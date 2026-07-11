#include "snipory/core/scroll/VerticalOverlapMatcher.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

namespace snipory::core::scroll {
namespace {

constexpr int MaximumSignatureBins = 64;

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
    std::vector<double> means;
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
    const PixelCrop& excludedBands)
{
    RowSignatures result;
    result.height = image.height;
    const int scoringWidth = image.width - excludedBands.left - excludedBands.right;
    result.binCount = std::min(MaximumSignatureBins, scoringWidth);
    result.binWidths.resize(static_cast<std::size_t>(result.binCount));
    result.means.resize(
        static_cast<std::size_t>(image.height) * static_cast<std::size_t>(result.binCount));

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
            for (auto x = first; x < last; ++x) {
                sum += image.pixels[row + x];
            }
            const auto destination = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(result.binCount)
                + static_cast<std::size_t>(bin);
            result.means[destination] = static_cast<double>(sum)
                / static_cast<double>(last - first);
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
    double difference = 0;
    std::uint64_t count = 0;
    for (int currentY = firstY; currentY < lastY; ++currentY) {
        const auto previousRow = static_cast<std::size_t>(currentY + advance)
            * static_cast<std::size_t>(previous.binCount);
        const auto currentRow = static_cast<std::size_t>(currentY)
            * static_cast<std::size_t>(current.binCount);
        for (int bin = 0; bin < previous.binCount; ++bin) {
            const auto index = static_cast<std::size_t>(bin);
            const auto width = static_cast<std::uint64_t>(previous.binWidths[index]);
            difference += std::abs(previous.means[previousRow + index] - current.means[currentRow + index])
                * static_cast<double>(width);
            count += width;
        }
    }
    return difference / (static_cast<double>(count) * 255.0);
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
    for (auto currentY = static_cast<std::size_t>(firstY);
         currentY < static_cast<std::size_t>(lastY);
         ++currentY) {
        const auto previousRow = (currentY + static_cast<std::size_t>(advance))
            * static_cast<std::size_t>(previous.width);
        const auto currentRow = currentY * static_cast<std::size_t>(current.width);
        for (auto column = static_cast<std::size_t>(firstX);
             column < static_cast<std::size_t>(lastX);
             ++column) {
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
        if (left.error == right.error) {
            return left.advance < right.advance;
        }
        return left.error < right.error;
    });
}

[[nodiscard]] bool independentBasins(
    const ScoredAdvance& left,
    const ScoredAdvance& right,
    const std::vector<ScoredAdvance>& coarseByAdvance,
    double minimumWinnerMargin)
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
    const double endpointMaximum = std::max(
        coarseByAdvance[static_cast<std::size_t>(first)].error,
        coarseByAdvance[static_cast<std::size_t>(last)].error);
    const double minimumRise = std::max(1e-12, std::min(minimumWinnerMargin, 1.0 / 255.0));
    for (int advance = first + 1; advance < last; ++advance) {
        if (coarseByAdvance[static_cast<std::size_t>(advance)].error
            > endpointMaximum + minimumRise) {
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
    const auto previousSignatures = makeRowSignatures(previousLuminance, config.excludedBands);
    const auto currentSignatures = makeRowSignatures(currentLuminance, config.excludedBands);
    std::vector<ScoredAdvance> coarseByAdvance;
    coarseByAdvance.reserve(static_cast<std::size_t>(maximumAdvance) + 1U);
    for (int advance = 0; advance <= maximumAdvance; ++advance) {
        coarseByAdvance.push_back({advance, signatureError(
            previousSignatures,
            currentSignatures,
            advance,
            config.excludedBands)});
    }
    auto orderedCandidates = coarseByAdvance;
    sortByError(orderedCandidates);
    std::vector<ScoredAdvance> evaluated;
    evaluated.reserve(orderedCandidates.size());
    double bestFullError = std::numeric_limits<double>::infinity();
    bool exactAmbiguity = false;
    for (const auto& candidate : orderedCandidates) {
        if (std::isfinite(bestFullError)
            && candidate.error >= bestFullError + config.minimumWinnerMargin) {
            break;
        }
        const ScoredAdvance fullScore{
            candidate.advance,
            fullResolutionError(
                previousLuminance,
                currentLuminance,
                candidate.advance,
                config.excludedBands)};
        evaluated.push_back(fullScore);
        bestFullError = std::min(bestFullError, fullScore.error);
        if (fullScore.error == 0.0 && config.minimumWinnerMargin > 0.0) {
            const auto otherExact = std::find_if(evaluated.cbegin(), evaluated.cend() - 1, [&](const auto& other) {
                return other.error == 0.0 && independentBasins(
                    other,
                    fullScore,
                    coarseByAdvance,
                    config.minimumWinnerMargin);
            });
            if (otherExact != evaluated.cend() - 1) {
                exactAmbiguity = true;
                break;
            }
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
    if (best.error > config.maximumNormalizedError) {
        return result;
    }

    const auto runnerUp = std::find_if(evaluated.cbegin() + 1, evaluated.cend(), [&](const auto& candidate) {
        return independentBasins(
            best,
            candidate,
            coarseByAdvance,
            config.minimumWinnerMargin);
    });
    const double runnerUpError = runnerUp != evaluated.cend()
        ? runnerUp->error
        : std::numeric_limits<double>::infinity();
    const double winnerMargin = runnerUpError - best.error;
    const double errorConfidence = config.maximumNormalizedError > 0.0
        ? std::clamp(1.0 - best.error / config.maximumNormalizedError, 0.0, 1.0)
        : (best.error == 0.0 ? 1.0 : 0.0);
    const double marginConfidence = config.minimumWinnerMargin > 0.0
        ? std::clamp(winnerMargin / config.minimumWinnerMargin, 0.0, 1.0)
        : 1.0;
    result.confidence = errorConfidence * marginConfidence;
    result.kind = exactAmbiguity || winnerMargin < config.minimumWinnerMargin
        ? OverlapKind::Ambiguous
        : OverlapKind::Reliable;
    return result;
}

} // namespace snipory::core::scroll
