#include "snipory/core/scroll/VerticalOverlapMatcher.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

namespace snipory::core::scroll {
namespace {

constexpr std::array<int, 2> SignatureBinLimits{64, 127};
constexpr std::size_t RefinementCandidateThreshold = 16;
constexpr int MaximumFullResolutionCandidateLimit = 1'000'000;
constexpr int MaximumSignatureRows = 192;
constexpr int MaximumValidationColumns = 256;
constexpr int MaximumValidationRows = 384;

struct LuminanceImage final
{
    int width = 0;
    int height = 0;
    std::vector<std::uint8_t> pixels;
};

struct ScoredAdvance final
{
    int advance = 0;
    double error = std::numeric_limits<double>::infinity();
};

struct RowSignatures final
{
    int height = 0;
    int binCount = 0;
    std::vector<int> binWidths;
    std::vector<std::uint64_t> sums;
    std::vector<std::int64_t> alternatingSums;
};

struct WideAccumulator final
{
    std::uint64_t high = 0;
    std::uint64_t low = 0;

    void add(std::uint64_t value)
    {
        const auto previous = low;
        low += value;
        high += low < previous ? 1U : 0U;
    }

    [[nodiscard]] long double value() const
    {
        constexpr long double TwoTo64 = 18'446'744'073'709'551'616.0L;
        return static_cast<long double>(high) * TwoTo64 + static_cast<long double>(low);
    }
};

struct EvaluationBudget final
{
    int remaining = 0;
    bool exhausted = false;
};

[[nodiscard]] bool validConfig(const OverlapConfig& config)
{
    return std::isfinite(config.minimumOverlapRatio)
        && std::isfinite(config.maximumAdvanceRatio)
        && std::isfinite(config.maximumNormalizedError)
        && std::isfinite(config.minimumWinnerMargin)
        && config.minimumOverlapRatio > 0.0
        && config.minimumOverlapRatio <= 1.0
        && config.maximumAdvanceRatio >= 0.0
        && config.maximumAdvanceRatio <= 1.0
        && config.maximumNormalizedError >= 0.0
        && config.minimumWinnerMargin >= 0.0
        && config.maximumFullResolutionCandidates > 0
        && config.maximumFullResolutionCandidates <= MaximumFullResolutionCandidateLimit
        && config.excludedBands.left >= 0
        && config.excludedBands.right >= 0
        && config.excludedBands.top >= 0
        && config.excludedBands.bottom >= 0;
}

[[nodiscard]] std::uint8_t luminanceAt(const ScrollFrame& frame, int x, int y)
{
    const auto offset = static_cast<std::size_t>(y)
            * static_cast<std::size_t>(frame.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    const auto blue = static_cast<std::uint32_t>(frame.pixels[offset]);
    const auto green = static_cast<std::uint32_t>(frame.pixels[offset + 1U]);
    const auto red = static_cast<std::uint32_t>(frame.pixels[offset + 2U]);
    return static_cast<std::uint8_t>((29U * blue + 150U * green + 77U * red + 128U) >> 8U);
}

[[nodiscard]] LuminanceImage makeLuminance(const ScrollFrame& frame)
{
    LuminanceImage result;
    result.width = frame.width;
    result.height = frame.height;
    result.pixels.resize(
        static_cast<std::size_t>(frame.width) * static_cast<std::size_t>(frame.height));
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            const auto destination = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(frame.width)
                + static_cast<std::size_t>(x);
            result.pixels[destination] = luminanceAt(frame, x, y);
        }
    }
    return result;
}

[[nodiscard]] RowSignatures makeRowSignatures(
    const LuminanceImage& image,
    const PixelCrop& excludedBands,
    int binLimit)
{
    RowSignatures result;
    result.height = image.height;
    const int scoringWidth = image.width - excludedBands.left - excludedBands.right;
    result.binCount = std::min(binLimit, scoringWidth);
    result.binWidths.resize(static_cast<std::size_t>(result.binCount));
    result.sums.resize(
        static_cast<std::size_t>(image.height) * static_cast<std::size_t>(result.binCount));
    result.alternatingSums.resize(result.sums.size());

    for (int bin = 0; bin < result.binCount; ++bin) {
        const auto first = static_cast<std::size_t>(excludedBands.left)
            + static_cast<std::size_t>(scoringWidth) * static_cast<std::size_t>(bin)
                / static_cast<std::size_t>(result.binCount);
        const auto last = static_cast<std::size_t>(excludedBands.left)
            + static_cast<std::size_t>(scoringWidth) * static_cast<std::size_t>(bin + 1)
                / static_cast<std::size_t>(result.binCount);
        result.binWidths[static_cast<std::size_t>(bin)] = static_cast<int>(last - first);
        for (int y = 0; y < image.height; ++y) {
            const auto row = static_cast<std::size_t>(y) * static_cast<std::size_t>(image.width);
            std::uint64_t sum = 0;
            std::int64_t alternatingSum = 0;
            for (auto x = first; x < last; ++x) {
                const auto value = image.pixels[row + x];
                sum += value;
                const auto signedValue = static_cast<std::int64_t>(value);
                alternatingSum += (x & 1U) == 0U ? signedValue : -signedValue;
            }
            const auto destination = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(result.binCount)
                + static_cast<std::size_t>(bin);
            result.sums[destination] = sum;
            result.alternatingSums[destination] = alternatingSum;
        }
    }
    return result;
}

[[nodiscard]] double signatureError(
    const RowSignatures& previous,
    const RowSignatures& current,
    int advance,
    const PixelCrop& excludedBands)
{
    const int firstY = excludedBands.top;
    const int lastY = previous.height - excludedBands.bottom - advance;
    if (firstY >= lastY) {
        return std::numeric_limits<double>::infinity();
    }
    WideAccumulator difference;
    std::uint64_t count = 0;
    const int rowStep = std::max(1, (lastY - firstY + MaximumSignatureRows - 1) / MaximumSignatureRows);
    for (int currentY = firstY; currentY < lastY; currentY += rowStep) {
        const auto previousRow = static_cast<std::size_t>(currentY + advance)
            * static_cast<std::size_t>(previous.binCount);
        const auto currentRow = static_cast<std::size_t>(currentY)
            * static_cast<std::size_t>(current.binCount);
        for (int bin = 0; bin < previous.binCount; ++bin) {
            const auto index = static_cast<std::size_t>(bin);
            const auto width = static_cast<std::uint64_t>(previous.binWidths[index]);
            const auto previousSum = previous.sums[previousRow + index];
            const auto currentSum = current.sums[currentRow + index];
            const auto meanDifference = previousSum >= currentSum
                ? previousSum - currentSum
                : currentSum - previousSum;
            const auto alternatingDelta = previous.alternatingSums[previousRow + index]
                - current.alternatingSums[currentRow + index];
            const auto alternatingDifference = static_cast<std::uint64_t>(
                alternatingDelta >= 0 ? alternatingDelta : -alternatingDelta);
            // Both projections are lower bounds for this bin's absolute pixel error.
            difference.add(std::max(meanDifference, alternatingDifference));
            count += width;
        }
    }
    if (difference.high == 0 && difference.low == 0) {
        return 0.0;
    }
    const auto normalized = static_cast<double>(
        difference.value() / (static_cast<long double>(count) * 255.0L));
    return std::nextafter(normalized, -std::numeric_limits<double>::infinity());
}

[[nodiscard]] double fullResolutionError(
    const LuminanceImage& previous,
    const LuminanceImage& current,
    int advance,
    const PixelCrop& excludedBands)
{
    const int firstX = excludedBands.left;
    const int lastX = previous.width - excludedBands.right;
    const int firstY = excludedBands.top;
    const int lastY = previous.height - excludedBands.bottom - advance;
    if (firstX >= lastX || firstY >= lastY) {
        return std::numeric_limits<double>::infinity();
    }

    double difference = 0;
    std::uint64_t count = 0;
    const auto columnStep = static_cast<std::size_t>(lastY - firstY <= MaximumValidationRows
        ? 1
        : std::max(
            1,
            (lastX - firstX + MaximumValidationColumns - 1) / MaximumValidationColumns));
    const auto rowStep = static_cast<std::size_t>(std::max(
        1,
        (lastY - firstY + MaximumValidationRows - 1) / MaximumValidationRows));
    for (auto currentY = static_cast<std::size_t>(firstY);
         currentY < static_cast<std::size_t>(lastY);
         currentY += rowStep) {
        const auto previousRow = (currentY + static_cast<std::size_t>(advance))
            * static_cast<std::size_t>(previous.width);
        const auto currentRow = currentY * static_cast<std::size_t>(current.width);
        for (auto column = static_cast<std::size_t>(firstX);
             column < static_cast<std::size_t>(lastX);
             column += columnStep) {
            const int previousValue = previous.pixels[previousRow + column];
            const int currentValue = current.pixels[currentRow + column];
            difference += static_cast<double>(std::abs(previousValue - currentValue));
            ++count;
        }
    }
    return difference / (static_cast<double>(count) * 255.0);
}

void sortByError(std::vector<ScoredAdvance>& scores)
{
    std::sort(scores.begin(), scores.end(), [](const auto& left, const auto& right) {
        const bool leftFinite = std::isfinite(left.error);
        const bool rightFinite = std::isfinite(right.error);
        if (leftFinite != rightFinite) {
            return leftFinite;
        }
        if (!leftFinite) {
            return left.advance < right.advance;
        }
        if (left.error == right.error) {
            return left.advance < right.advance;
        }
        return left.error < right.error;
    });
}

[[nodiscard]] bool canCompete(double lowerBound, double bestError, double winnerMargin)
{
    if (!std::isfinite(lowerBound)) {
        return false;
    }
    if (!std::isfinite(bestError)) {
        return true;
    }
    const double cutoff = std::nextafter(
        bestError + winnerMargin,
        std::numeric_limits<double>::infinity());
    return lowerBound < cutoff;
}

[[nodiscard]] std::optional<double> cachedFullResolutionError(
    int advance,
    const LuminanceImage& previous,
    const LuminanceImage& current,
    const PixelCrop& excludedBands,
    std::vector<double>& fullErrors,
    std::vector<bool>& evaluated,
    EvaluationBudget& budget)
{
    const auto index = static_cast<std::size_t>(advance);
    if (evaluated[index]) {
        return fullErrors[index];
    }
    if (budget.remaining == 0) {
        budget.exhausted = true;
        return std::nullopt;
    }
    --budget.remaining;
    fullErrors[index] = fullResolutionError(previous, current, advance, excludedBands);
    evaluated[index] = true;
    return fullErrors[index];
}

[[nodiscard]] bool independentBasins(
    const ScoredAdvance& left,
    const ScoredAdvance& right,
    const std::vector<ScoredAdvance>& lowerBounds,
    double minimumWinnerMargin,
    const LuminanceImage& previous,
    const LuminanceImage& current,
    const PixelCrop& excludedBands,
    std::vector<double>& fullErrors,
    std::vector<bool>& evaluated,
    EvaluationBudget& budget)
{
    if (left.advance == right.advance) {
        return false;
    }
    if (left.error == 0.0 && right.error == 0.0) {
        return true;
    }
    const int first = std::min(left.advance, right.advance);
    const int last = std::max(left.advance, right.advance);
    if (last - first <= 1) {
        return false;
    }
    const double endpointMaximum = std::max(left.error, right.error);
    const double minimumRise = std::max(1e-12, std::min(minimumWinnerMargin, 1.0 / 255.0));
    const double barrierThreshold = std::nextafter(
        endpointMaximum + minimumRise,
        std::numeric_limits<double>::infinity());
    for (int advance = first + 1; advance < last; ++advance) {
        // A lower bound can prove a barrier exists. It cannot prove its absence,
        // so inconclusive points are evaluated at full resolution.
        if (lowerBounds[static_cast<std::size_t>(advance)].error > barrierThreshold) {
            return true;
        }
        const auto fullError = cachedFullResolutionError(
                advance,
                previous,
                current,
                excludedBands,
                fullErrors,
                evaluated,
                budget);
        if (!fullError.has_value()) {
            return false;
        }
        if (*fullError > barrierThreshold) {
            return true;
        }
    }
    return false;
}

} // namespace

OverlapResult VerticalOverlapMatcher::match(
    const ScrollFrame& previous,
    const ScrollFrame& current,
    const OverlapConfig& config) const
{
    OverlapResult result;
    if (!previous.isValid() || !current.isValid() || !validConfig(config)
        || previous.width != current.width || previous.height != current.height
        || config.excludedBands.left >= previous.width - config.excludedBands.right
        || config.excludedBands.top >= previous.height - config.excludedBands.bottom) {
        return result;
    }

    const int height = previous.height;
    const int minimumOverlap = static_cast<int>(
        std::ceil(static_cast<double>(height) * config.minimumOverlapRatio));
    const int ratioMaximumAdvance = static_cast<int>(
        std::floor(static_cast<double>(height) * config.maximumAdvanceRatio));
    const int maximumAdvance = std::min(height - minimumOverlap, ratioMaximumAdvance);
    if (maximumAdvance < 0) {
        return result;
    }

    const auto previousLuminance = makeLuminance(previous);
    const auto currentLuminance = makeLuminance(current);
    std::vector<ScoredAdvance> lowerBounds;
    lowerBounds.reserve(static_cast<std::size_t>(maximumAdvance) + 1U);
    for (int advance = 0; advance <= maximumAdvance; ++advance) {
        lowerBounds.push_back({advance, 0.0});
    }

    std::vector<double> fullErrors(static_cast<std::size_t>(maximumAdvance) + 1U, 1.0);
    std::vector<bool> fullEvaluated(static_cast<std::size_t>(maximumAdvance) + 1U, false);
    EvaluationBudget evaluationBudget{config.maximumFullResolutionCandidates, false};
    double bestFullError = std::numeric_limits<double>::infinity();
    for (std::size_t level = 0; level < SignatureBinLimits.size(); ++level) {
        // Finer partitions monotonically tighten the lower bound without dropping
        // any placement that could still win or fall inside the winner margin.
        const auto previousSignatures = makeRowSignatures(
            previousLuminance,
            config.excludedBands,
            SignatureBinLimits[level]);
        const auto currentSignatures = makeRowSignatures(
            currentLuminance,
            config.excludedBands,
            SignatureBinLimits[level]);
        std::size_t competitiveCount = 0;
        for (auto& candidate : lowerBounds) {
            if (!canCompete(candidate.error, bestFullError, config.minimumWinnerMargin)) {
                continue;
            }
            const double refinedBound = signatureError(
                previousSignatures,
                currentSignatures,
                candidate.advance,
                config.excludedBands);
            candidate.error = std::isfinite(refinedBound)
                ? std::max(candidate.error, refinedBound)
                : std::numeric_limits<double>::infinity();
            if (canCompete(candidate.error, bestFullError, config.minimumWinnerMargin)) {
                ++competitiveCount;
            }
        }

        auto orderedAtLevel = lowerBounds;
        sortByError(orderedAtLevel);
        const auto firstUnevaluated = std::find_if(orderedAtLevel.cbegin(), orderedAtLevel.cend(), [&](const auto& candidate) {
            return canCompete(candidate.error, bestFullError, config.minimumWinnerMargin)
                && !fullEvaluated[static_cast<std::size_t>(candidate.advance)];
        });
        if (firstUnevaluated != orderedAtLevel.cend()) {
            const auto fullError = cachedFullResolutionError(
                firstUnevaluated->advance,
                previousLuminance,
                currentLuminance,
                config.excludedBands,
                fullErrors,
                fullEvaluated,
                evaluationBudget);
            if (!fullError.has_value()) {
                break;
            }
            bestFullError = std::min(bestFullError, *fullError);
        }
        const auto nextUnevaluated = std::find_if(orderedAtLevel.cbegin(), orderedAtLevel.cend(), [&](const auto& candidate) {
            return canCompete(candidate.error, bestFullError, config.minimumWinnerMargin)
                && !fullEvaluated[static_cast<std::size_t>(candidate.advance)];
        });
        const bool bestIsGloballyBounded = nextUnevaluated == orderedAtLevel.cend()
            || bestFullError <= std::nextafter(
                nextUnevaluated->error,
                std::numeric_limits<double>::infinity());
        if (competitiveCount <= RefinementCandidateThreshold || bestIsGloballyBounded) {
            break;
        }
    }

    auto orderedCandidates = lowerBounds;
    sortByError(orderedCandidates);
    bool certifiedAmbiguity = false;
    for (std::size_t candidateIndex = 0; candidateIndex < orderedCandidates.size(); ++candidateIndex) {
        const auto& candidate = orderedCandidates[candidateIndex];
        if (!canCompete(candidate.error, bestFullError, config.minimumWinnerMargin)) {
            break;
        }
        const auto fullError = cachedFullResolutionError(
            candidate.advance,
            previousLuminance,
            currentLuminance,
            config.excludedBands,
            fullErrors,
            fullEvaluated,
            evaluationBudget);
        if (!fullError.has_value()) {
            break;
        }
        bestFullError = std::min(bestFullError, *fullError);

        std::vector<ScoredAdvance> evaluatedSoFar;
        for (int advance = 0; advance <= maximumAdvance; ++advance) {
            const auto index = static_cast<std::size_t>(advance);
            if (fullEvaluated[index]) {
                evaluatedSoFar.push_back({advance, fullErrors[index]});
            }
        }
        sortByError(evaluatedSoFar);
        if (evaluatedSoFar.size() > 1U && config.minimumWinnerMargin > 0.0) {
            const auto& provisionalBest = evaluatedSoFar.front();
            const double nextLowerBound = candidateIndex + 1U < orderedCandidates.size()
                ? orderedCandidates[candidateIndex + 1U].error
                : std::numeric_limits<double>::infinity();
            const bool bestIsCertified = provisionalBest.error <= std::nextafter(
                    nextLowerBound,
                    std::numeric_limits<double>::infinity());
            if (bestIsCertified) {
                const auto provisionalRunner = std::find_if(
                    evaluatedSoFar.cbegin() + 1,
                    evaluatedSoFar.cend(),
                    [&](const auto& possibleRunner) {
                        return possibleRunner.error - provisionalBest.error < config.minimumWinnerMargin
                            && independentBasins(
                                provisionalBest,
                                possibleRunner,
                                lowerBounds,
                                config.minimumWinnerMargin,
                                previousLuminance,
                                currentLuminance,
                                config.excludedBands,
                                fullErrors,
                                fullEvaluated,
                                evaluationBudget);
                    });
                if (provisionalRunner != evaluatedSoFar.cend()) {
                    certifiedAmbiguity = true;
                    break;
                }
            }
        }
    }

    std::vector<ScoredAdvance> evaluated;
    for (int advance = 0; advance <= maximumAdvance; ++advance) {
        const auto index = static_cast<std::size_t>(advance);
        if (fullEvaluated[index]) {
            evaluated.push_back({advance, fullErrors[index]});
        }
    }
    sortByError(evaluated);
    if (evaluated.empty() || !std::isfinite(evaluated.front().error)) {
        return result;
    }

    const auto& best = evaluated.front();
    result.verticalAdvance = best.advance;
    result.overlapHeight = height - best.advance;
    result.normalizedError = best.error;
    if (evaluationBudget.exhausted) {
        result.kind = OverlapKind::Ambiguous;
        result.confidence = 0.0;
        return result;
    }
    if (best.error > config.maximumNormalizedError) {
        return result;
    }

    const auto runnerUp = std::find_if(evaluated.cbegin() + 1, evaluated.cend(), [&](const auto& candidate) {
        return independentBasins(
            best,
            candidate,
            lowerBounds,
            config.minimumWinnerMargin,
            previousLuminance,
            currentLuminance,
            config.excludedBands,
            fullErrors,
            fullEvaluated,
            evaluationBudget);
    });
    const double runnerUpError = runnerUp != evaluated.cend()
        ? runnerUp->error
        : std::numeric_limits<double>::infinity();
    const double winnerMargin = runnerUpError - best.error;
    if (evaluationBudget.exhausted) {
        result.kind = OverlapKind::Ambiguous;
        result.confidence = 0.0;
        return result;
    }
    const double errorConfidence = config.maximumNormalizedError > 0.0
        ? std::clamp(1.0 - best.error / config.maximumNormalizedError, 0.0, 1.0)
        : (best.error == 0.0 ? 1.0 : 0.0);
    const double marginConfidence = config.minimumWinnerMargin > 0.0
        ? std::clamp(winnerMargin / config.minimumWinnerMargin, 0.0, 1.0)
        : 1.0;
    result.confidence = errorConfidence * marginConfidence;
    result.kind = certifiedAmbiguity || winnerMargin < config.minimumWinnerMargin
        ? OverlapKind::Ambiguous
        : OverlapKind::Reliable;
    return result;
}

} // namespace snipory::core::scroll
