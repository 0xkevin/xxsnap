#include "snipory/core/scroll/VerticalOverlapMatcher.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

namespace snipory::core::scroll {
namespace {

constexpr int CoarseScale = 4;
constexpr std::size_t CoarseCandidateCount = 8;

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

[[nodiscard]] constexpr int ceilDivide(int value, int divisor)
{
    return value / divisor + (value % divisor == 0 ? 0 : 1);
}

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

[[nodiscard]] LuminanceImage quarterScaleLuminance(const ScrollFrame& frame)
{
    LuminanceImage result;
    result.width = ceilDivide(frame.width, CoarseScale);
    result.height = ceilDivide(frame.height, CoarseScale);
    result.pixels.resize(
        static_cast<std::size_t>(result.width) * static_cast<std::size_t>(result.height));

    for (int coarseY = 0; coarseY < result.height; ++coarseY) {
        const int firstY = coarseY * CoarseScale;
        const int lastY = std::min(firstY + CoarseScale, frame.height);
        for (int coarseX = 0; coarseX < result.width; ++coarseX) {
            const int firstX = coarseX * CoarseScale;
            const int lastX = std::min(firstX + CoarseScale, frame.width);
            std::uint32_t sum = 0;
            std::uint32_t count = 0;
            for (int y = firstY; y < lastY; ++y) {
                for (int x = firstX; x < lastX; ++x) {
                    sum += luminanceAt(frame, x, y);
                    ++count;
                }
            }
            const auto destination = static_cast<std::size_t>(coarseY)
                    * static_cast<std::size_t>(result.width)
                + static_cast<std::size_t>(coarseX);
            result.pixels[destination] = static_cast<std::uint8_t>((sum + count / 2U) / count);
        }
    }
    return result;
}

template<typename PixelAt>
[[nodiscard]] double normalizedError(
    int width,
    int height,
    int advance,
    const PixelCrop& excludedBands,
    int scale,
    PixelAt pixelAt)
{
    const int firstX = ceilDivide(excludedBands.left, scale);
    const int lastX = (width - excludedBands.right) / scale;
    const int firstCurrentY = ceilDivide(excludedBands.top, scale);
    const int lastCurrentY = (height - advance - excludedBands.bottom) / scale;
    const int previousTop = excludedBands.top > advance
        ? ceilDivide(excludedBands.top - advance, scale)
        : 0;
    const int firstPreviousY = std::max(firstCurrentY, previousTop);
    const int lastPreviousY = std::min(lastCurrentY, (height - excludedBands.bottom - advance) / scale);
    if (firstX >= lastX || firstPreviousY >= lastPreviousY) {
        return std::numeric_limits<double>::infinity();
    }

    long double difference = 0;
    std::uint64_t count = 0;
    const int scaledAdvance = advance / scale;
    for (int currentY = firstPreviousY; currentY < lastPreviousY; ++currentY) {
        for (int x = firstX; x < lastX; ++x) {
            const int previousValue = pixelAt(0, x, currentY + scaledAdvance);
            const int currentValue = pixelAt(1, x, currentY);
            difference += static_cast<long double>(std::abs(previousValue - currentValue));
            ++count;
        }
    }
    return static_cast<double>(difference / (static_cast<long double>(count) * 255.0L));
}

[[nodiscard]] double fullResolutionError(
    const ScrollFrame& previous,
    const ScrollFrame& current,
    int advance,
    const PixelCrop& excludedBands)
{
    return normalizedError(
        previous.width,
        previous.height,
        advance,
        excludedBands,
        1,
        [&](int image, int x, int y) {
            return luminanceAt(image == 0 ? previous : current, x, y);
        });
}

[[nodiscard]] double coarseError(
    const LuminanceImage& previous,
    const LuminanceImage& current,
    int advance,
    const PixelCrop& excludedBands,
    int fullWidth,
    int fullHeight)
{
    return normalizedError(
        fullWidth,
        fullHeight,
        advance,
        excludedBands,
        CoarseScale,
        [&](int image, int x, int y) {
            const auto& source = image == 0 ? previous : current;
            const auto offset = static_cast<std::size_t>(y) * static_cast<std::size_t>(source.width)
                + static_cast<std::size_t>(x);
            return source.pixels[offset];
        });
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

    const auto coarsePrevious = quarterScaleLuminance(previous);
    const auto coarseCurrent = quarterScaleLuminance(current);
    std::vector<ScoredAdvance> coarseScores;
    coarseScores.reserve(static_cast<std::size_t>(maximumAdvance / CoarseScale + 1));
    for (int advance = 0; advance <= maximumAdvance; advance += CoarseScale) {
        coarseScores.push_back({advance, coarseError(
            coarsePrevious,
            coarseCurrent,
            advance,
            config.excludedBands,
            previous.width,
            height)});
    }
    std::sort(coarseScores.begin(), coarseScores.end(), [](const auto& left, const auto& right) {
        return left.error < right.error;
    });

    std::vector<int> fullResolutionAdvances;
    const auto candidateCount = std::min(CoarseCandidateCount, coarseScores.size());
    fullResolutionAdvances.reserve(candidateCount * (2U * CoarseScale - 1U));
    for (std::size_t index = 0; index < candidateCount; ++index) {
        for (int delta = -(CoarseScale - 1); delta < CoarseScale; ++delta) {
            const int advance = coarseScores[index].advance + delta;
            if (advance >= 0 && advance <= maximumAdvance) {
                fullResolutionAdvances.push_back(advance);
            }
        }
    }
    if (maximumAdvance % CoarseScale != 0) {
        fullResolutionAdvances.push_back(maximumAdvance);
    }
    std::sort(fullResolutionAdvances.begin(), fullResolutionAdvances.end());
    fullResolutionAdvances.erase(
        std::unique(fullResolutionAdvances.begin(), fullResolutionAdvances.end()),
        fullResolutionAdvances.end());

    std::vector<ScoredAdvance> fullScores;
    fullScores.reserve(fullResolutionAdvances.size());
    for (const int advance : fullResolutionAdvances) {
        fullScores.push_back({advance, fullResolutionError(
            previous,
            current,
            advance,
            config.excludedBands)});
    }
    std::sort(fullScores.begin(), fullScores.end(), [](const auto& left, const auto& right) {
        return left.error < right.error;
    });
    if (fullScores.empty() || !std::isfinite(fullScores.front().error)) {
        return result;
    }

    const auto& best = fullScores.front();
    result.verticalAdvance = best.advance;
    result.overlapHeight = height - best.advance;
    result.normalizedError = best.error;
    if (best.error > config.maximumNormalizedError) {
        return result;
    }

    const double runnerUpError = fullScores.size() > 1U
        ? fullScores[1].error
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
