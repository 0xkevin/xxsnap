#include "snipory/core/scroll/VerticalOverlapMatcher.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

namespace snipory::core::scroll {
namespace {

constexpr int CoarseScale = 4;
constexpr int PeakSuppressionRadius = CoarseScale - 1;
constexpr std::size_t CoarseCandidateCount = 8;
constexpr int MaximumCoarseColumns = 64;

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

[[nodiscard]] double normalizedError(
    const LuminanceImage& previous,
    const LuminanceImage& current,
    int advance,
    const PixelCrop& excludedBands,
    int rowStep,
    int columnStep)
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
    const auto unsignedRowStep = static_cast<std::size_t>(rowStep);
    const auto unsignedColumnStep = static_cast<std::size_t>(columnStep);
    for (auto currentY = static_cast<std::size_t>(firstY);
         currentY < static_cast<std::size_t>(lastY);
         currentY += unsignedRowStep) {
        const auto previousRow = (currentY + static_cast<std::size_t>(advance))
            * static_cast<std::size_t>(previous.width);
        const auto currentRow = currentY * static_cast<std::size_t>(current.width);
        for (auto column = static_cast<std::size_t>(firstX);
             column < static_cast<std::size_t>(lastX);
             column += unsignedColumnStep) {
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

[[nodiscard]] std::vector<int> selectCoarsePeaks(std::vector<ScoredAdvance> scores)
{
    sortByError(scores);
    std::vector<int> peaks;
    peaks.reserve(CoarseCandidateCount);
    for (const auto& score : scores) {
        if (!std::isfinite(score.error)) {
            break;
        }
        const bool nearSelectedPeak = std::any_of(peaks.cbegin(), peaks.cend(), [&](int selected) {
            return std::abs(selected - score.advance) <= PeakSuppressionRadius;
        });
        if (!nearSelectedPeak) {
            peaks.push_back(score.advance);
            if (peaks.size() == CoarseCandidateCount) {
                break;
            }
        }
    }
    return peaks;
}

[[nodiscard]] std::vector<ScoredAdvance> scoreFullResolution(
    const LuminanceImage& previous,
    const LuminanceImage& current,
    const PixelCrop& excludedBands,
    const std::vector<int>& advances)
{
    std::vector<ScoredAdvance> scores;
    scores.reserve(advances.size());
    for (const int advance : advances) {
        scores.push_back({advance, normalizedError(previous, current, advance, excludedBands, 1, 1)});
    }
    sortByError(scores);
    return scores;
}

[[nodiscard]] std::vector<int> allAdvances(int maximumAdvance)
{
    std::vector<int> advances;
    advances.reserve(static_cast<std::size_t>(maximumAdvance) + 1U);
    for (int advance = 0; advance <= maximumAdvance; ++advance) {
        advances.push_back(advance);
    }
    return advances;
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
    const int scoringWidth = previous.width
        - config.excludedBands.left
        - config.excludedBands.right;
    const int coarseColumnStep = std::max(
        CoarseScale,
        scoringWidth / MaximumCoarseColumns
            + (scoringWidth % MaximumCoarseColumns == 0 ? 0 : 1));
    std::vector<ScoredAdvance> coarseScores;
    coarseScores.reserve(static_cast<std::size_t>(maximumAdvance) + 1U);
    for (int advance = 0; advance <= maximumAdvance; ++advance) {
        coarseScores.push_back({advance, normalizedError(
            previousLuminance,
            currentLuminance,
            advance,
            config.excludedBands,
            CoarseScale,
            coarseColumnStep)});
    }
    const auto coarsePeaks = selectCoarsePeaks(coarseScores);
    if (coarsePeaks.empty()) {
        return result;
    }

    auto fullScores = scoreFullResolution(
        previousLuminance,
        currentLuminance,
        config.excludedBands,
        coarsePeaks);
    if (fullScores.empty() || !std::isfinite(fullScores.front().error)) {
        return result;
    }

    // A zero-error coarse sample cannot lead to a non-zero full-resolution winner
    // unless sampling aliases hid the exact placement. Recover with a bounded full scan.
    const auto coarseBest = std::min_element(coarseScores.cbegin(), coarseScores.cend(), [](const auto& left, const auto& right) {
        return left.error < right.error;
    });
    if (coarseBest != coarseScores.cend() && coarseBest->error == 0.0
        && fullScores.front().error != 0.0) {
        fullScores = scoreFullResolution(
            previousLuminance,
            currentLuminance,
            config.excludedBands,
            allAdvances(maximumAdvance));
    }

    const auto& best = fullScores.front();
    result.verticalAdvance = best.advance;
    result.overlapHeight = height - best.advance;
    result.normalizedError = best.error;
    if (best.error > config.maximumNormalizedError) {
        return result;
    }

    const auto runnerUp = std::find_if(fullScores.cbegin() + 1, fullScores.cend(), [&](const auto& candidate) {
        return std::abs(candidate.advance - best.advance) > PeakSuppressionRadius;
    });
    const double runnerUpError = runnerUp != fullScores.cend()
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
    result.kind = winnerMargin < config.minimumWinnerMargin
        ? OverlapKind::Ambiguous
        : OverlapKind::Reliable;
    return result;
}

} // namespace snipory::core::scroll
