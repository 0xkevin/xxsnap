#include "snipory/core/scroll/VerticalOverlapMatcher.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <thread>
#include <vector>

namespace snipory::core::scroll {
namespace {

constexpr std::array<int, 2> SignatureBinLimits{64, 127};
constexpr std::size_t RefinementCandidateThreshold = 16;
constexpr int MaximumFullResolutionCandidateLimit = 1'000'000;
constexpr int MaximumSignatureRows = 192;
constexpr int MaximumValidationColumns = 256;
constexpr int MaximumValidationRows = 384;
constexpr int NearWhiteLuminanceThreshold = 224;
constexpr int ChangedPixelLuminanceThreshold = 10;
constexpr double MaximumChangedPixelMismatchRatio = 0.30;
constexpr std::uint64_t MinimumForegroundValidationSamples = 256;
constexpr int MaximumMatchingHeight = 512;

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

struct ChangedPixelSource final
{
    int width = 0;
    int height = 0;
    std::vector<std::uint8_t> previous;
    std::vector<std::uint8_t> current;
    std::vector<std::uint8_t> difference;
};

template<typename Scorer>
[[nodiscard]] std::vector<ScoredAdvance> scoreAdvancesInParallel(
    const std::vector<int>& advances,
    Scorer scorer)
{
    if (advances.empty()) {
        return {};
    }
    std::vector<ScoredAdvance> scored(advances.size());
    const auto hardwareThreads = std::max(1U, std::thread::hardware_concurrency());
    const auto workerCount = std::min<std::size_t>(
        advances.size(), std::min<std::size_t>(hardwareThreads, 8U));
    const auto scoreRange = [&](std::size_t first, std::size_t last) {
        for (auto index = first; index < last; ++index) {
            scored[index] = {advances[index], scorer(advances[index])};
        }
    };
    std::vector<std::thread> workers;
    workers.reserve(workerCount > 0 ? workerCount - 1U : 0U);
    for (std::size_t worker = 1; worker < workerCount; ++worker) {
        const auto first = advances.size() * worker / workerCount;
        const auto last = advances.size() * (worker + 1U) / workerCount;
        workers.emplace_back(scoreRange, first, last);
    }
    scoreRange(0, advances.size() / workerCount);
    for (auto& worker : workers) {
        worker.join();
    }
    scored.erase(
        std::remove_if(
            scored.begin(), scored.end(),
            [](const ScoredAdvance& value) { return !std::isfinite(value.error); }),
        scored.end());
    return scored;
}

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

struct DifferenceBounds final
{
    int firstX = std::numeric_limits<int>::max();
    int firstY = std::numeric_limits<int>::max();
    int lastX = -1;
    int lastY = -1;

    [[nodiscard]] bool isValid() const
    {
        return firstX <= lastX && firstY <= lastY;
    }

    void include(int x, int y)
    {
        firstX = std::min(firstX, x);
        firstY = std::min(firstY, y);
        lastX = std::max(lastX, x);
        lastY = std::max(lastY, y);
    }

    void include(const DifferenceBounds& other)
    {
        if (!other.isValid()) {
            return;
        }
        include(other.firstX, other.firstY);
        include(other.lastX, other.lastY);
    }
};

[[nodiscard]] DifferenceBounds findDifferenceBounds(
    const ScrollFrame& previous,
    const ScrollFrame& current,
    const PixelCrop& excludedBands)
{
    constexpr int ChannelDifferenceThreshold = 10;
    const int firstX = excludedBands.left;
    const int lastX = previous.width - excludedBands.right;
    const int firstY = excludedBands.top;
    const int lastY = previous.height - excludedBands.bottom;
    const int availableRows = lastY - firstY;
    const auto hardwareThreads = std::max(1U, std::thread::hardware_concurrency());
    const int workerCount = std::min(availableRows, static_cast<int>(hardwareThreads));
    std::vector<DifferenceBounds> partials(static_cast<std::size_t>(workerCount));
    const auto scanRows = [&](int worker) {
        const int workerFirstY = firstY + availableRows * worker / workerCount;
        const int workerLastY = firstY + availableRows * (worker + 1) / workerCount;
        auto& bounds = partials[static_cast<std::size_t>(worker)];
        for (int y = workerFirstY; y < workerLastY; ++y) {
            const auto rowOffset = static_cast<std::size_t>(y)
                * static_cast<std::size_t>(previous.bytesPerRow);
            for (int x = firstX; x < lastX; ++x) {
                const auto offset = rowOffset + static_cast<std::size_t>(x) * 4U;
                const int blueDifference = std::abs(
                    static_cast<int>(previous.pixels[offset])
                    - static_cast<int>(current.pixels[offset]));
                const int greenDifference = std::abs(
                    static_cast<int>(previous.pixels[offset + 1U])
                    - static_cast<int>(current.pixels[offset + 1U]));
                const int redDifference = std::abs(
                    static_cast<int>(previous.pixels[offset + 2U])
                    - static_cast<int>(current.pixels[offset + 2U]));
                if (std::max({blueDifference, greenDifference, redDifference})
                    > ChannelDifferenceThreshold) {
                    bounds.include(x, y);
                }
            }
        }
    };
    std::vector<std::thread> workers;
    workers.reserve(static_cast<std::size_t>(std::max(0, workerCount - 1)));
    for (int worker = 1; worker < workerCount; ++worker) {
        workers.emplace_back(scanRows, worker);
    }
    scanRows(0);
    for (auto& worker : workers) {
        worker.join();
    }
    DifferenceBounds bounds;
    for (const auto& partial : partials) {
        bounds.include(partial);
    }
    return bounds;
}

[[nodiscard]] bool validConfig(const OverlapConfig& config)
{
    return std::isfinite(config.minimumOverlapRatio)
        && std::isfinite(config.maximumAdvanceRatio)
        && std::isfinite(config.maximumReliableAdvanceRatio)
        && std::isfinite(config.maximumNormalizedError)
        && std::isfinite(config.minimumWinnerMargin)
        && std::isfinite(config.minimumReliableConfidence)
        && config.minimumOverlapRatio > 0.0
        && config.minimumOverlapRatio <= 1.0
        && config.maximumAdvanceRatio >= 0.0
        && config.maximumAdvanceRatio <= 1.0
        && config.maximumReliableAdvanceRatio >= 0.0
        && config.maximumReliableAdvanceRatio <= 1.0
        && config.maximumNormalizedError >= 0.0
        && config.minimumWinnerMargin >= 0.0
        && config.minimumReliableConfidence >= 0.0
        && config.minimumReliableConfidence <= 1.0
        && config.expectedAdvance >= 0
        && config.expectedAdvanceTolerance >= 0
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

[[nodiscard]] ScrollFrame scaledFrame(
    const ScrollFrame& source,
    int targetHeight)
{
    if (!source.isValid() || targetHeight <= 0) {
        return {};
    }
    ScrollFrame result(source.width, targetHeight);
    if (!result.isValid()) {
        return {};
    }
    const double sourceRowsPerTarget = static_cast<double>(source.height)
        / static_cast<double>(targetHeight);
    const auto luminance = [](const std::uint8_t* pixel) {
        return (29U * static_cast<std::uint32_t>(pixel[0])
                + 150U * static_cast<std::uint32_t>(pixel[1])
                + 77U * static_cast<std::uint32_t>(pixel[2])
                + 128U)
            >> 8U;
    };
    const auto scaleRows = [&](int firstTargetY, int lastTargetY) {
        for (int targetY = firstTargetY; targetY < lastTargetY; ++targetY) {
            const double sourcePosition = (static_cast<double>(targetY) + 0.5)
                    * sourceRowsPerTarget
                - 0.5;
            const int firstSourceY = std::clamp(
                static_cast<int>(std::floor(sourcePosition)), 0, source.height - 1);
            const int secondSourceY = std::min(source.height - 1, firstSourceY + 1);
            const int secondWeight = std::clamp(
                static_cast<int>(std::lround(std::clamp(
                    sourcePosition - static_cast<double>(firstSourceY), 0.0, 1.0) * 256.0)),
                0,
                256);
            const int firstWeight = 256 - secondWeight;
            const auto firstOffset = static_cast<std::size_t>(firstSourceY)
                * static_cast<std::size_t>(source.bytesPerRow);
            const auto secondOffset = static_cast<std::size_t>(secondSourceY)
                * static_cast<std::size_t>(source.bytesPerRow);
            const auto destinationOffset = static_cast<std::size_t>(targetY)
                * static_cast<std::size_t>(result.bytesPerRow);
            for (int targetX = 0; targetX < source.width; ++targetX) {
                const auto targetIndex = static_cast<std::size_t>(targetX);
                const auto sourceByte = targetIndex * 4U;
                const auto topValue = luminance(
                    source.pixels.data() + firstOffset + sourceByte);
                const auto bottomValue = luminance(
                    source.pixels.data() + secondOffset + sourceByte);
                const auto value = static_cast<std::uint8_t>(
                    (topValue * static_cast<std::uint32_t>(firstWeight)
                        + bottomValue * static_cast<std::uint32_t>(secondWeight)
                        + 128U) >> 8U);
                const auto destination = destinationOffset + targetIndex * 4U;
                result.pixels[destination] = value;
                result.pixels[destination + 1U] = value;
                result.pixels[destination + 2U] = value;
                result.pixels[destination + 3U] = 255;
            }
        }
    };
    const auto hardwareThreads = std::max(1U, std::thread::hardware_concurrency());
    const int workerCount = std::min(targetHeight, static_cast<int>(hardwareThreads));
    std::vector<std::thread> workers;
    workers.reserve(static_cast<std::size_t>(std::max(0, workerCount - 1)));
    for (int worker = 1; worker < workerCount; ++worker) {
        const int first = targetHeight * worker / workerCount;
        const int last = targetHeight * (worker + 1) / workerCount;
        workers.emplace_back(scaleRows, first, last);
    }
    scaleRows(0, targetHeight / workerCount);
    for (auto& worker : workers) {
        worker.join();
    }
    return result;
}

[[nodiscard]] int scaledPixels(int value, double scale)
{
    if (value <= 0) {
        return 0;
    }
    return std::max(1, static_cast<int>(std::lround(static_cast<double>(value) * scale)));
}

[[nodiscard]] double sampledFrameError(
    const ScrollFrame& previous,
    const ScrollFrame& current,
    int advance,
    const PixelCrop& excludedBands,
    bool suppressNearWhite,
    int maximumColumns = MaximumValidationColumns,
    int maximumRows = MaximumValidationRows,
    std::uint64_t minimumForegroundSamples = MinimumForegroundValidationSamples)
{
    const int firstX = excludedBands.left;
    const int lastX = previous.width - excludedBands.right;
    const int firstY = excludedBands.top;
    const int lastY = previous.height - excludedBands.bottom - advance;
    if (firstX >= lastX || firstY >= lastY) {
        return std::numeric_limits<double>::infinity();
    }
    const int columnStep = std::max(
        1, (lastX - firstX + maximumColumns - 1) / maximumColumns);
    const int rowStep = std::max(
        1, (lastY - firstY + maximumRows - 1) / maximumRows);
    double difference = 0;
    std::uint64_t count = 0;
    for (int currentY = firstY; currentY < lastY; currentY += rowStep) {
        for (int x = firstX; x < lastX; x += columnStep) {
            const int previousValue = luminanceAt(previous, x, currentY + advance);
            const int currentValue = luminanceAt(current, x, currentY);
            if (suppressNearWhite
                && previousValue >= NearWhiteLuminanceThreshold
                && currentValue >= NearWhiteLuminanceThreshold) {
                continue;
            }
            difference += static_cast<double>(std::abs(previousValue - currentValue));
            ++count;
        }
    }
    if (count == 0 || (suppressNearWhite && count < minimumForegroundSamples)) {
        return std::numeric_limits<double>::infinity();
    }
    return difference / (static_cast<double>(count) * 255.0);
}

[[nodiscard]] std::vector<ScoredAdvance> scoreChangedPixelAdvances(
    const ScrollFrame& previous,
    const ScrollFrame& current,
    const std::vector<int>& advances,
    const PixelCrop& excludedBands,
    int targetColumns)
{
    const int sourceWidth = previous.width - excludedBands.left - excludedBands.right;
    const int reducedWidth = std::clamp(targetColumns, 1, sourceWidth);
    const auto pixelCount = static_cast<std::size_t>(reducedWidth)
        * static_cast<std::size_t>(previous.height);
    std::vector<std::uint8_t> reducedPrevious(pixelCount);
    std::vector<std::uint8_t> reducedCurrent(pixelCount);
    std::vector<std::uint8_t> changed(pixelCount);

    const auto reduceRows = [&](int firstY, int lastY) {
        for (int y = firstY; y < lastY; ++y) {
            const auto row = static_cast<std::size_t>(y)
                * static_cast<std::size_t>(reducedWidth);
            for (int reducedX = 0; reducedX < reducedWidth; ++reducedX) {
                const double sourcePosition = (static_cast<double>(reducedX) + 0.5)
                        * static_cast<double>(sourceWidth)
                        / static_cast<double>(reducedWidth)
                    - 0.5;
                const int firstRelativeX = std::clamp(
                    static_cast<int>(std::floor(sourcePosition)), 0, sourceWidth - 1);
                const int secondRelativeX = std::min(sourceWidth - 1, firstRelativeX + 1);
                const int secondWeight = std::clamp(
                    static_cast<int>(std::lround(std::clamp(
                        sourcePosition - static_cast<double>(firstRelativeX), 0.0, 1.0)
                        * 256.0)),
                    0,
                    256);
                const int firstWeight = 256 - secondWeight;
                const int firstX = excludedBands.left + firstRelativeX;
                const int secondX = excludedBands.left + secondRelativeX;
                const auto previousFirst = luminanceAt(previous, firstX, y);
                const auto previousSecond = luminanceAt(previous, secondX, y);
                const auto currentFirst = luminanceAt(current, firstX, y);
                const auto currentSecond = luminanceAt(current, secondX, y);
                const auto destination = row + static_cast<std::size_t>(reducedX);
                reducedPrevious[destination] = static_cast<std::uint8_t>(
                    (static_cast<int>(previousFirst) * firstWeight
                        + static_cast<int>(previousSecond) * secondWeight
                        + 128) >> 8);
                reducedCurrent[destination] = static_cast<std::uint8_t>(
                    (static_cast<int>(currentFirst) * firstWeight
                        + static_cast<int>(currentSecond) * secondWeight
                        + 128) >> 8);
                const int changedFirst = std::abs(
                    static_cast<int>(previousFirst) - static_cast<int>(currentFirst));
                const int changedSecond = std::abs(
                    static_cast<int>(previousSecond) - static_cast<int>(currentSecond));
                changed[destination] = ((changedFirst * firstWeight
                            + changedSecond * secondWeight
                            + 128) >> 8)
                        > ChangedPixelLuminanceThreshold
                    ? 1U
                    : 0U;
            }
        }
    };
    const auto hardwareThreads = std::max(1U, std::thread::hardware_concurrency());
    const int workerCount = std::min(previous.height, static_cast<int>(hardwareThreads));
    std::vector<std::thread> workers;
    workers.reserve(static_cast<std::size_t>(std::max(0, workerCount - 1)));
    for (int worker = 1; worker < workerCount; ++worker) {
        workers.emplace_back(
            reduceRows,
            previous.height * worker / workerCount,
            previous.height * (worker + 1) / workerCount);
    }
    reduceRows(0, previous.height / workerCount);
    for (auto& worker : workers) {
        worker.join();
    }

    return scoreAdvancesInParallel(advances, [&](int advance) {
        const int firstY = excludedBands.top;
        const int lastY = previous.height - excludedBands.bottom - advance;
        if (advance <= 0 || firstY >= lastY) {
            return std::numeric_limits<double>::infinity();
        }
        std::uint64_t mismatched = 0;
        std::uint64_t count = 0;
        for (int currentY = firstY; currentY < lastY; ++currentY) {
            const auto currentRow = static_cast<std::size_t>(currentY)
                * static_cast<std::size_t>(reducedWidth);
            const auto previousRow = static_cast<std::size_t>(currentY + advance)
                * static_cast<std::size_t>(reducedWidth);
            for (int x = 0; x < reducedWidth; ++x) {
                const auto currentIndex = currentRow + static_cast<std::size_t>(x);
                const auto previousIndex = previousRow + static_cast<std::size_t>(x);
                if (changed[currentIndex] == 0U && changed[previousIndex] == 0U) {
                    continue;
                }
                if (std::abs(
                        static_cast<int>(reducedPrevious[previousIndex])
                        - static_cast<int>(reducedCurrent[currentIndex]))
                    > ChangedPixelLuminanceThreshold) {
                    ++mismatched;
                }
                ++count;
            }
        }
        return count > 0
            ? static_cast<double>(mismatched) / static_cast<double>(count)
            : std::numeric_limits<double>::infinity();
    });
}

[[nodiscard]] ChangedPixelSource makeChangedPixelSource(
    const ScrollFrame& previous,
    const ScrollFrame& current,
    const PixelCrop& excludedBands)
{
    ChangedPixelSource source;
    source.width = previous.width - excludedBands.left - excludedBands.right;
    source.height = previous.height;
    const auto pixelCount = static_cast<std::size_t>(source.width)
        * static_cast<std::size_t>(source.height);
    source.previous.resize(pixelCount);
    source.current.resize(pixelCount);
    source.difference.resize(pixelCount);
    const auto convertRows = [&](int firstY, int lastY) {
        for (int y = firstY; y < lastY; ++y) {
            const auto row = static_cast<std::size_t>(y)
                * static_cast<std::size_t>(source.width);
            for (int relativeX = 0; relativeX < source.width; ++relativeX) {
                const int x = excludedBands.left + relativeX;
                const auto previousValue = luminanceAt(previous, x, y);
                const auto currentValue = luminanceAt(current, x, y);
                const auto destination = row + static_cast<std::size_t>(relativeX);
                source.previous[destination] = previousValue;
                source.current[destination] = currentValue;
                source.difference[destination] = static_cast<std::uint8_t>(std::abs(
                    static_cast<int>(previousValue) - static_cast<int>(currentValue)));
            }
        }
    };
    const auto hardwareThreads = std::max(1U, std::thread::hardware_concurrency());
    const int workerCount = std::min(source.height, static_cast<int>(hardwareThreads));
    std::vector<std::thread> workers;
    workers.reserve(static_cast<std::size_t>(std::max(0, workerCount - 1)));
    for (int worker = 1; worker < workerCount; ++worker) {
        workers.emplace_back(
            convertRows,
            source.height * worker / workerCount,
            source.height * (worker + 1) / workerCount);
    }
    convertRows(0, source.height / workerCount);
    for (auto& worker : workers) {
        worker.join();
    }
    return source;
}

[[nodiscard]] std::vector<ScoredAdvance> scoreChangedPixelAdvances(
    const ChangedPixelSource& source,
    const std::vector<int>& advances,
    const PixelCrop& excludedBands,
    int targetColumns)
{
    const int reducedWidth = std::clamp(targetColumns, 1, source.width);
    const auto pixelCount = static_cast<std::size_t>(reducedWidth)
        * static_cast<std::size_t>(source.height);
    std::vector<std::uint8_t> reducedPrevious(pixelCount);
    std::vector<std::uint8_t> reducedCurrent(pixelCount);
    std::vector<std::uint8_t> changed(pixelCount);
    const auto reduceRows = [&](int firstY, int lastY) {
        for (int y = firstY; y < lastY; ++y) {
            const auto sourceRow = static_cast<std::size_t>(y)
                * static_cast<std::size_t>(source.width);
            const auto destinationRow = static_cast<std::size_t>(y)
                * static_cast<std::size_t>(reducedWidth);
            for (int reducedX = 0; reducedX < reducedWidth; ++reducedX) {
                const double sourcePosition = (static_cast<double>(reducedX) + 0.5)
                        * static_cast<double>(source.width)
                        / static_cast<double>(reducedWidth)
                    - 0.5;
                const int firstX = std::clamp(
                    static_cast<int>(std::floor(sourcePosition)), 0, source.width - 1);
                const int secondX = std::min(source.width - 1, firstX + 1);
                const int secondWeight = std::clamp(
                    static_cast<int>(std::lround(std::clamp(
                        sourcePosition - static_cast<double>(firstX), 0.0, 1.0)
                        * 256.0)),
                    0,
                    256);
                const int firstWeight = 256 - secondWeight;
                const auto first = sourceRow + static_cast<std::size_t>(firstX);
                const auto second = sourceRow + static_cast<std::size_t>(secondX);
                const auto destination = destinationRow + static_cast<std::size_t>(reducedX);
                const auto interpolate = [&](const std::vector<std::uint8_t>& pixels) {
                    return (static_cast<int>(pixels[first]) * firstWeight
                            + static_cast<int>(pixels[second]) * secondWeight
                            + 128) >> 8;
                };
                reducedPrevious[destination] = static_cast<std::uint8_t>(
                    interpolate(source.previous));
                reducedCurrent[destination] = static_cast<std::uint8_t>(
                    interpolate(source.current));
                changed[destination] = interpolate(source.difference)
                        > ChangedPixelLuminanceThreshold
                    ? 1U
                    : 0U;
            }
        }
    };
    const auto hardwareThreads = std::max(1U, std::thread::hardware_concurrency());
    const int workerCount = std::min(source.height, static_cast<int>(hardwareThreads));
    std::vector<std::thread> workers;
    workers.reserve(static_cast<std::size_t>(std::max(0, workerCount - 1)));
    for (int worker = 1; worker < workerCount; ++worker) {
        workers.emplace_back(
            reduceRows,
            source.height * worker / workerCount,
            source.height * (worker + 1) / workerCount);
    }
    reduceRows(0, source.height / workerCount);
    for (auto& worker : workers) {
        worker.join();
    }
    return scoreAdvancesInParallel(advances, [&](int advance) {
        const int firstY = excludedBands.top;
        const int lastY = source.height - excludedBands.bottom - advance;
        if (advance <= 0 || firstY >= lastY) {
            return std::numeric_limits<double>::infinity();
        }
        std::uint64_t mismatched = 0;
        std::uint64_t count = 0;
        for (int currentY = firstY; currentY < lastY; ++currentY) {
            const auto currentRow = static_cast<std::size_t>(currentY)
                * static_cast<std::size_t>(reducedWidth);
            const auto previousRow = static_cast<std::size_t>(currentY + advance)
                * static_cast<std::size_t>(reducedWidth);
            for (int x = 0; x < reducedWidth; ++x) {
                const auto currentIndex = currentRow + static_cast<std::size_t>(x);
                const auto previousIndex = previousRow + static_cast<std::size_t>(x);
                if (changed[currentIndex] == 0U && changed[previousIndex] == 0U) {
                    continue;
                }
                if (std::abs(
                        static_cast<int>(reducedPrevious[previousIndex])
                        - static_cast<int>(reducedCurrent[currentIndex]))
                    > ChangedPixelLuminanceThreshold) {
                    ++mismatched;
                }
                ++count;
            }
        }
        return count > 0
            ? static_cast<double>(mismatched) / static_cast<double>(count)
            : std::numeric_limits<double>::infinity();
    });
}

[[nodiscard]] std::optional<OverlapResult> changedPixelDisplacementCandidate(
    const ScrollFrame& previous,
    const ScrollFrame& current,
    const OverlapConfig& config,
    std::vector<ScoredAdvance>* orderedCandidates = nullptr)
{
    const int scoringHeight = previous.height
        - config.excludedBands.top - config.excludedBands.bottom;
    const int minimumOverlap = static_cast<int>(
        std::ceil(static_cast<double>(scoringHeight) * config.minimumOverlapRatio));
    const int maximumAdvance = std::min({
        scoringHeight - minimumOverlap,
        static_cast<int>(std::floor(
            static_cast<double>(previous.height) * config.maximumAdvanceRatio)),
        static_cast<int>(std::floor(
            static_cast<double>(scoringHeight) * config.maximumReliableAdvanceRatio)),
    });
    if (maximumAdvance < 1) {
        return std::nullopt;
    }

    std::vector<int> advances;
    advances.reserve(static_cast<std::size_t>(maximumAdvance));
    for (int advance = 1; advance <= maximumAdvance; ++advance) {
        advances.push_back(advance);
    }
    const int scoringWidth = previous.width
        - config.excludedBands.left - config.excludedBands.right;
    int maximumColumns = std::max(1, scoringWidth / 32);
    const auto scoringSource = makeChangedPixelSource(
        previous, current, config.excludedBands);
    std::vector<ScoredAdvance> candidates;
    while (!advances.empty()) {
        candidates = scoreChangedPixelAdvances(
            scoringSource, advances, config.excludedBands, maximumColumns);
        if (candidates.empty()) {
            return std::nullopt;
        }
        std::sort(candidates.begin(), candidates.end(), [](const auto& left, const auto& right) {
            return left.error < right.error
                || (left.error == right.error && left.advance < right.advance);
        });
        if (maximumColumns >= scoringWidth) {
            break;
        }
        advances.clear();
        const auto survivorCount = std::max<std::size_t>(1, (candidates.size() + 1U) / 2U);
        advances.reserve(survivorCount);
        for (std::size_t index = 0; index < survivorCount; ++index) {
            advances.push_back(candidates[index].advance);
        }
        maximumColumns = std::min(scoringWidth, maximumColumns * 2);
    }
    if (orderedCandidates != nullptr) {
        *orderedCandidates = candidates;
    }
    const auto& best = candidates.front();
    const double errorConfidence = std::clamp(
        1.0 - best.error / MaximumChangedPixelMismatchRatio, 0.0, 1.0);
    OverlapResult result;
    result.verticalAdvance = best.advance;
    result.overlapHeight = previous.height - best.advance;
    result.normalizedError = best.error;
    result.confidence = errorConfidence;
    result.usedChangedPixelMask = true;
    if (best.error >= MaximumChangedPixelMismatchRatio) {
        result.kind = OverlapKind::Insufficient;
    } else {
        result.kind = OverlapKind::Reliable;
    }
    return result;
}

[[nodiscard]] std::optional<OverlapResult> foregroundDisplacementCandidate(
    const ScrollFrame& previous,
    const ScrollFrame& current,
    const OverlapConfig& config,
    std::vector<ScoredAdvance>* orderedCandidates = nullptr)
{
    const int minimumOverlap = static_cast<int>(
        std::ceil(static_cast<double>(previous.height) * config.minimumOverlapRatio));
    const int maximumAdvance = std::min({
        previous.height - minimumOverlap,
        static_cast<int>(std::floor(
            static_cast<double>(previous.height) * config.maximumAdvanceRatio)),
        static_cast<int>(std::floor(
            static_cast<double>(previous.height) * config.maximumReliableAdvanceRatio)),
    });
    if (maximumAdvance < 1) {
        return std::nullopt;
    }

    std::vector<ScoredAdvance> candidates;
    candidates.reserve(static_cast<std::size_t>(maximumAdvance));
    for (int advance = 1; advance <= maximumAdvance; ++advance) {
        const double error = sampledFrameError(
            previous, current, advance, config.excludedBands, true, 64, 64, 16);
        if (std::isfinite(error)) {
            candidates.push_back({advance, error});
        }
    }
    if (candidates.empty()) {
        return std::nullopt;
    }
    std::sort(candidates.begin(), candidates.end(), [](const auto& left, const auto& right) {
        return left.error < right.error
            || (left.error == right.error && left.advance < right.advance);
    });
    if (orderedCandidates != nullptr) {
        *orderedCandidates = candidates;
    }
    const auto& best = candidates.front();
    const int independentDistance = std::max(2, previous.height / 128);
    const auto runner = std::find_if(
        candidates.cbegin() + 1,
        candidates.cend(),
        [&](const ScoredAdvance& candidate) {
            return std::abs(candidate.advance - best.advance) > independentDistance;
        });
    const double runnerError = runner != candidates.cend()
        ? runner->error
        : std::numeric_limits<double>::infinity();
    const double winnerMargin = runnerError - best.error;
    const double errorConfidence = config.maximumNormalizedError > 0.0
        ? std::clamp(1.0 - best.error / config.maximumNormalizedError, 0.0, 1.0)
        : (best.error == 0.0 ? 1.0 : 0.0);
    const double marginConfidence = config.minimumWinnerMargin > 0.0
        ? std::clamp(winnerMargin / config.minimumWinnerMargin, 0.0, 1.0)
        : 1.0;

    OverlapResult result;
    result.verticalAdvance = best.advance;
    result.overlapHeight = previous.height - best.advance;
    result.normalizedError = best.error;
    result.confidence = errorConfidence * marginConfidence;
    if (winnerMargin < config.minimumWinnerMargin) {
        result.kind = OverlapKind::Ambiguous;
    } else if (best.error > config.maximumNormalizedError
        || result.confidence < config.minimumReliableConfidence) {
        result.kind = OverlapKind::Insufficient;
    } else {
        result.kind = OverlapKind::Reliable;
    }
    return result;
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

    // Preserve the hinted fast path before reducing a Retina-sized viewport.
    // A real pixel displacement becomes fractional after vertical scaling, which
    // can turn an exact original-resolution match into an ambiguous scaled one.
    if (config.expectedAdvance > 0) {
        const int minimumOverlap = static_cast<int>(
            std::ceil(static_cast<double>(previous.height) * config.minimumOverlapRatio));
        const int maximumExpectedAdvance = std::min({
            previous.height - minimumOverlap,
            static_cast<int>(std::floor(
                static_cast<double>(previous.height) * config.maximumAdvanceRatio)),
            static_cast<int>(std::floor(
                static_cast<double>(previous.height)
                * config.maximumReliableAdvanceRatio)),
        });
        if (config.expectedAdvance <= maximumExpectedAdvance) {
            const double maximumExpectedError = std::min(
                config.maximumNormalizedError, 0.03);
            const double exactError = sampledFrameError(
                previous,
                current,
                config.expectedAdvance,
                config.excludedBands,
                false);
            if (std::isfinite(exactError)
                && exactError <= std::min(maximumExpectedError, 0.005)) {
                const double confidence = maximumExpectedError > 0.0
                    ? std::clamp(
                        1.0 - exactError / maximumExpectedError, 0.0, 1.0)
                    : (exactError == 0.0 ? 1.0 : 0.0);
                if (confidence >= config.minimumReliableConfidence) {
                    result.kind = OverlapKind::Reliable;
                    result.verticalAdvance = config.expectedAdvance;
                    result.overlapHeight = previous.height - config.expectedAdvance;
                    result.normalizedError = exactError;
                    result.confidence = confidence;
                    return result;
                }
            }
        }
    }

    if (previous.height > MaximumMatchingHeight) {
        const double scale = static_cast<double>(MaximumMatchingHeight)
            / static_cast<double>(previous.height);
        auto scaledConfig = config;
        scaledConfig.expectedAdvance = scaledPixels(config.expectedAdvance, scale);
        scaledConfig.expectedAdvanceTolerance = scaledPixels(
            config.expectedAdvanceTolerance, scale);
        scaledConfig.excludedBands.left = config.excludedBands.left;
        scaledConfig.excludedBands.right = config.excludedBands.right;
        scaledConfig.excludedBands.top = scaledPixels(config.excludedBands.top, scale);
        scaledConfig.excludedBands.bottom = scaledPixels(config.excludedBands.bottom, scale);
        const auto scaledPrevious = scaledFrame(previous, MaximumMatchingHeight);
        const auto scaledCurrent = scaledFrame(current, MaximumMatchingHeight);
        if (!scaledPrevious.isValid() || !scaledCurrent.isValid()) {
            return result;
        }

        std::vector<ScoredAdvance> scaledCandidates;
        result = match(scaledPrevious, scaledCurrent, scaledConfig);
        if (!result.usedChangedPixelMask) {
            (void)foregroundDisplacementCandidate(
                scaledPrevious, scaledCurrent, scaledConfig, &scaledCandidates);
        }
        const auto scaledKind = result.kind;
        const double scaledError = result.normalizedError;
        const int scaledAdvance = result.verticalAdvance;
        result.verticalAdvance = static_cast<int>(std::lround(
            static_cast<double>(scaledAdvance) / scale));
        result.verticalAdvance = std::clamp(result.verticalAdvance, 0, previous.height);
        result.overlapHeight = previous.height - result.verticalAdvance;
        if (scaledAdvance <= 0) {
            return result;
        }

        const int minimumOverlap = static_cast<int>(
            std::ceil(static_cast<double>(previous.height) * config.minimumOverlapRatio));
        const int maximumAdvance = std::min(
            previous.height - minimumOverlap,
            static_cast<int>(std::floor(
                static_cast<double>(previous.height) * config.maximumAdvanceRatio)));
        const int maximumReliableAdvance = static_cast<int>(std::floor(
            static_cast<double>(previous.height)
            * std::min(config.maximumAdvanceRatio, config.maximumReliableAdvanceRatio)));
        const int refinementRadius = std::max(
            2, static_cast<int>(std::ceil(2.0 / scale)));
        constexpr std::size_t MaximumScaledCandidatesToRefine = 16;
        std::vector<bool> evaluated(
            static_cast<std::size_t>(maximumReliableAdvance) + 1U, false);
        std::vector<int> refinementAdvances;
        const auto refineAround = [&](int center) {
            const int first = std::max(1, center - refinementRadius);
            const int last = std::min({
                maximumAdvance,
                maximumReliableAdvance,
                center + refinementRadius,
            });
            for (int advance = first; advance <= last; ++advance) {
                const auto index = static_cast<std::size_t>(advance);
                if (evaluated[index]) {
                    continue;
                }
                evaluated[index] = true;
                refinementAdvances.push_back(advance);
            }
        };
        refineAround(result.verticalAdvance);
        const auto candidateCount = std::min(
            scaledCandidates.size(), MaximumScaledCandidatesToRefine);
        for (std::size_t index = 0; index < candidateCount; ++index) {
            refineAround(static_cast<int>(std::lround(
                static_cast<double>(scaledCandidates[index].advance) / scale)));
        }
        auto refinedCandidates = result.usedChangedPixelMask
            ? scoreChangedPixelAdvances(
                previous, current, refinementAdvances, config.excludedBands, 128)
            : scoreAdvancesInParallel(
                refinementAdvances,
                [&](int advance) {
                    const double foregroundError = sampledFrameError(
                        previous,
                        current,
                        advance,
                        config.excludedBands,
                        true,
                        128,
                        128,
                        64);
                    return std::isfinite(foregroundError)
                        ? foregroundError
                        : sampledFrameError(
                            previous,
                            current,
                            advance,
                            config.excludedBands,
                            false,
                            128,
                            128,
                            0);
                });
        std::sort(
            refinedCandidates.begin(),
            refinedCandidates.end(),
            [](const auto& left, const auto& right) {
                return left.error < right.error
                    || (left.error == right.error && left.advance < right.advance);
            });
        constexpr std::size_t MaximumOriginalCandidatesToValidate = 8;
        const auto validationCount = std::min(
            refinedCandidates.size(), MaximumOriginalCandidatesToValidate);
        std::vector<int> validationAdvances;
        validationAdvances.reserve(validationCount);
        for (std::size_t index = 0; index < validationCount; ++index) {
            validationAdvances.push_back(refinedCandidates[index].advance);
        }
        std::vector<ScoredAdvance> validatedCandidates;
        if (result.usedChangedPixelMask
            && !refinedCandidates.empty()
            && refinedCandidates.front().error == 0.0) {
            validatedCandidates.push_back(refinedCandidates.front());
        } else if (result.usedChangedPixelMask) {
            validatedCandidates = scoreChangedPixelAdvances(
                previous,
                current,
                validationAdvances,
                config.excludedBands,
                MaximumValidationColumns);
        } else {
            validatedCandidates = scoreAdvancesInParallel(
                validationAdvances,
                [&](int advance) {
                    const double foregroundError = sampledFrameError(
                        previous,
                        current,
                        advance,
                        config.excludedBands,
                        true,
                        MaximumValidationColumns,
                        MaximumValidationRows,
                        MinimumForegroundValidationSamples);
                    return std::isfinite(foregroundError)
                        ? foregroundError
                        : sampledFrameError(
                            previous, current, advance, config.excludedBands, false);
                });
        }
        std::sort(
            validatedCandidates.begin(),
            validatedCandidates.end(),
            [](const auto& left, const auto& right) {
                    return left.error < right.error
                        || (left.error == right.error && left.advance < right.advance);
                });
        if (!validatedCandidates.empty()) {
            const auto& refined = validatedCandidates.front();
            result.verticalAdvance = refined.advance;
            result.overlapHeight = previous.height - refined.advance;
            result.normalizedError = refined.error;
            const double effectiveMaximumError = result.usedChangedPixelMask
                ? MaximumChangedPixelMismatchRatio
                : config.maximumNormalizedError;
            const double errorConfidence = effectiveMaximumError > 0.0
                ? std::clamp(
                    1.0 - refined.error / effectiveMaximumError, 0.0, 1.0)
                : (refined.error == 0.0 ? 1.0 : 0.0);
            const int independentDistance = std::max(2, previous.height / 512);
            const auto runner = std::find_if(
                validatedCandidates.cbegin() + 1,
                validatedCandidates.cend(),
                [&](const ScoredAdvance& candidate) {
                    return std::abs(candidate.advance - refined.advance)
                        > independentDistance;
                });
            const double runnerError = runner != validatedCandidates.cend()
                ? runner->error
                : std::numeric_limits<double>::infinity();
            const double winnerMargin = runnerError - refined.error;
            const double marginConfidence = config.minimumWinnerMargin > 0.0
                ? std::clamp(winnerMargin / config.minimumWinnerMargin, 0.0, 1.0)
                : 1.0;
            result.confidence = result.usedChangedPixelMask
                ? errorConfidence
                : errorConfidence * marginConfidence;
            const bool refinedMatchIsAmbiguous = winnerMargin < config.minimumWinnerMargin;
            const bool scaledMatchWasGenuinelyAmbiguous = scaledCandidates.empty()
                && scaledKind == OverlapKind::Ambiguous
                && scaledError <= config.maximumNormalizedError;
            if ((refinedMatchIsAmbiguous
                    && !result.usedChangedPixelMask)
                || scaledMatchWasGenuinelyAmbiguous) {
                result.kind = OverlapKind::Ambiguous;
            } else if (refined.error < effectiveMaximumError
                && (result.usedChangedPixelMask
                    || result.confidence >= config.minimumReliableConfidence)) {
                result.kind = OverlapKind::Reliable;
            } else {
                result.kind = OverlapKind::Insufficient;
            }
        }
        return result;
    }

    if (config.isolateChangedRegion) {
        auto adjustedConfig = config;
        adjustedConfig.isolateChangedRegion = false;
        bool isolatedOuterBands = false;
        const auto bounds = findDifferenceBounds(
            previous, current, config.excludedBands);
        if (bounds.isValid()) {
            const auto changedBoundsArea = static_cast<std::uint64_t>(
                bounds.lastX - bounds.firstX + 1)
                * static_cast<std::uint64_t>(bounds.lastY - bounds.firstY + 1);
            const auto availableArea = static_cast<std::uint64_t>(
                previous.width - config.excludedBands.left - config.excludedBands.right)
                * static_cast<std::uint64_t>(
                    previous.height - config.excludedBands.top - config.excludedBands.bottom);
            if (availableArea < 512U * 512U) {
                return match(previous, current, adjustedConfig);
            }
            if (changedBoundsArea * 10U < availableArea * 3U
                && config.expectedAdvance == 0) {
                result.kind = OverlapKind::Ambiguous;
                result.normalizedError = 0.0;
                return result;
            }
            if (changedBoundsArea * 10U < availableArea * 3U) {
                return match(previous, current, adjustedConfig);
            }
            adjustedConfig.excludedBands.left = std::max(
                config.excludedBands.left, bounds.firstX);
            adjustedConfig.excludedBands.right = std::max(
                config.excludedBands.right, previous.width - bounds.lastX - 1);
            adjustedConfig.excludedBands.top = std::max(
                config.excludedBands.top, bounds.firstY);
            adjustedConfig.excludedBands.bottom = std::max(
                config.excludedBands.bottom, previous.height - bounds.lastY - 1);
            isolatedOuterBands = adjustedConfig.excludedBands.left != config.excludedBands.left
                || adjustedConfig.excludedBands.right != config.excludedBands.right
                || adjustedConfig.excludedBands.top != config.excludedBands.top
                || adjustedConfig.excludedBands.bottom != config.excludedBands.bottom;
        }
        if (config.expectedAdvance == 0) {
            if (config.allowChangedPixelFallback || isolatedOuterBands) {
                const auto changedCandidate = changedPixelDisplacementCandidate(
                    previous, current, adjustedConfig);
                if (changedCandidate.has_value()
                    && (changedCandidate->kind == OverlapKind::Reliable
                        || (changedCandidate->kind == OverlapKind::Ambiguous
                            && changedCandidate->confidence >= 0.80))) {
                    return *changedCandidate;
                }
            }
            const auto baseline = match(previous, current, adjustedConfig);
            if (baseline.kind == OverlapKind::Reliable && baseline.verticalAdvance > 0) {
                return baseline;
            }
            if (!config.allowChangedPixelFallback && !isolatedOuterBands) {
                return baseline;
            }
            const auto legacyForegroundCandidate = foregroundDisplacementCandidate(
                previous, current, adjustedConfig);
            if (legacyForegroundCandidate.has_value()
                && (legacyForegroundCandidate->kind == OverlapKind::Reliable
                    || (legacyForegroundCandidate->kind == OverlapKind::Ambiguous
                        && legacyForegroundCandidate->confidence >= 0.80))) {
                return *legacyForegroundCandidate;
            }
            return baseline;
        }
        return match(previous, current, adjustedConfig);
    }

    const int height = previous.height;
    const int minimumOverlap = static_cast<int>(
        std::ceil(static_cast<double>(height) * config.minimumOverlapRatio));
    const int ratioMaximumAdvance = static_cast<int>(
        std::floor(static_cast<double>(height) * config.maximumAdvanceRatio));
    const int maximumReliableAdvance = static_cast<int>(
        std::floor(static_cast<double>(height)
            * std::min(config.maximumAdvanceRatio, config.maximumReliableAdvanceRatio)));
    const int maximumAdvance = std::min(height - minimumOverlap, ratioMaximumAdvance);
    if (maximumAdvance < 0) {
        return result;
    }

    const auto expectedResult = [&]() -> std::optional<OverlapResult> {
        if (config.expectedAdvance <= 0) {
            return std::nullopt;
        }
        const int first = std::max(1, config.expectedAdvance - config.expectedAdvanceTolerance);
        const int last = std::min({
            maximumAdvance,
            maximumReliableAdvance,
            config.expectedAdvance + config.expectedAdvanceTolerance,
        });
        if (first > last) {
            return std::nullopt;
        }

        const double maximumExpectedError = std::min(
            config.maximumNormalizedError, 0.03);
        const auto resolvedResult = [&](int advance, double error)
            -> std::optional<OverlapResult> {
            OverlapResult resolved;
            resolved.kind = OverlapKind::Reliable;
            resolved.verticalAdvance = advance;
            resolved.overlapHeight = height - advance;
            resolved.normalizedError = error;
            resolved.confidence = maximumExpectedError > 0.0
                ? std::clamp(1.0 - error / maximumExpectedError, 0.0, 1.0)
                : (error == 0.0 ? 1.0 : 0.0);
            if (resolved.confidence < config.minimumReliableConfidence) {
                return std::nullopt;
            }
            return resolved;
        };
        const double exactError = sampledFrameError(
            previous, current, config.expectedAdvance, config.excludedBands, false);
        if (std::isfinite(exactError)
            && exactError <= std::min(maximumExpectedError, 0.005)) {
            return resolvedResult(config.expectedAdvance, exactError);
        }

        const auto bestExpectedAdvance = [&](bool suppressNearWhite) {
            ScoredAdvance expectedBest;
            for (int advance = first; advance <= last; ++advance) {
                const double error = suppressNearWhite
                    ? sampledFrameError(
                        previous, current, advance, config.excludedBands, true)
                    : sampledFrameError(
                        previous, current, advance, config.excludedBands, false);
                if (error < expectedBest.error
                    || (error == expectedBest.error
                        && std::abs(advance - config.expectedAdvance)
                            < std::abs(expectedBest.advance - config.expectedAdvance))) {
                    expectedBest = {advance, error};
                }
            }
            return expectedBest;
        };
        auto expectedBest = bestExpectedAdvance(false);
        const auto foregroundBest = bestExpectedAdvance(true);
        if (std::isfinite(foregroundBest.error)) {
            expectedBest = foregroundBest;
        }
        if (!std::isfinite(expectedBest.error) || expectedBest.error > maximumExpectedError) {
            return std::nullopt;
        }

        return resolvedResult(expectedBest.advance, expectedBest.error);
    };
    // Wheel/trackpad input gives us a narrow, visual-motion search window. When
    // that window contains a pixel-valid match, avoid the exhaustive full-height
    // search; this keeps stitching ahead of the live capture stream instead of
    // letting the overlap disappear while a previous frame is still matching.
    if (const auto expected = expectedResult(); expected.has_value()) {
        return *expected;
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
        if (const auto expected = expectedResult(); expected.has_value()) {
            return *expected;
        }
        return result;
    }

    const auto& best = evaluated.front();
    result.verticalAdvance = best.advance;
    result.overlapHeight = height - best.advance;
    result.normalizedError = best.error;
    if (evaluationBudget.exhausted) {
        if (const auto expected = expectedResult(); expected.has_value()) {
            return *expected;
        }
        result.kind = OverlapKind::Ambiguous;
        result.confidence = 0.0;
        return result;
    }
    if (best.error > config.maximumNormalizedError) {
        if (const auto expected = expectedResult(); expected.has_value()) {
            return *expected;
        }
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
        if (const auto expected = expectedResult(); expected.has_value()) {
            return *expected;
        }
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
    if (certifiedAmbiguity || winnerMargin < config.minimumWinnerMargin) {
        result.kind = OverlapKind::Ambiguous;
    } else if (best.advance > maximumReliableAdvance) {
        result.kind = OverlapKind::Insufficient;
    } else if (result.confidence < config.minimumReliableConfidence) {
        result.kind = OverlapKind::Insufficient;
    } else {
        result.kind = OverlapKind::Reliable;
    }
    if ((result.kind != OverlapKind::Reliable
            || result.verticalAdvance == 0
            || std::abs(result.verticalAdvance - config.expectedAdvance)
                > config.expectedAdvanceTolerance)
        && config.expectedAdvance > 0) {
        if (const auto expected = expectedResult(); expected.has_value()) {
            return *expected;
        }
    }
    return result;
}

} // namespace snipory::core::scroll
