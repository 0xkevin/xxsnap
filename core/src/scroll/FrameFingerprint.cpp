#include "snipory/core/scroll/FrameFingerprint.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace snipory::core::scroll {
namespace {

std::optional<std::size_t> elementCount(FingerprintSize size)
{
    if (size.width <= 0 || size.height <= 0) {
        return std::nullopt;
    }

    const auto width = static_cast<std::size_t>(size.width);
    const auto height = static_cast<std::size_t>(size.height);
    if (width > std::numeric_limits<std::size_t>::max() / height) {
        return std::nullopt;
    }
    return width * height;
}

std::uint8_t luminance(const std::uint8_t* bgra)
{
    const auto weighted = 29U * bgra[0] + 150U * bgra[1] + 77U * bgra[2] + 128U;
    return static_cast<std::uint8_t>(weighted >> 8U);
}

bool isValid(const Fingerprint& fingerprint)
{
    const auto count = elementCount(fingerprint.size);
    return count.has_value() && fingerprint.luminance.size() == *count;
}

struct SampleRange final
{
    int begin;
    int end;
};

SampleRange sampleRange(int targetIndex, int sourceExtent, int targetExtent)
{
    const auto index = static_cast<std::uint64_t>(targetIndex);
    const auto source = static_cast<std::uint64_t>(sourceExtent);
    const auto target = static_cast<std::uint64_t>(targetExtent);
    const auto begin = std::min(index * source / target, source - 1U);
    const auto endNumerator = (index + 1U) * source;
    const auto roundedEnd = endNumerator / target + (endNumerator % target != 0U ? 1U : 0U);
    const auto end = std::min(source, std::max(begin + 1U, roundedEnd));
    return {static_cast<int>(begin), static_cast<int>(end)};
}

} // namespace

Fingerprint FrameFingerprint::make(const ScrollFrame& frame, FingerprintSize size)
{
    Fingerprint result{size, {}};
    const auto count = elementCount(size);
    if (!frame.isValid() || !count.has_value()) {
        return result;
    }

    result.luminance.resize(*count);
    for (int targetY = 0; targetY < size.height; ++targetY) {
        const auto verticalRange = sampleRange(targetY, frame.height, size.height);

        for (int targetX = 0; targetX < size.width; ++targetX) {
            const auto horizontalRange = sampleRange(targetX, frame.width, size.width);

            std::uint64_t sum = 0;
            std::uint64_t samples = 0;
            constexpr int MaximumSamplesPerAxis = 4;
            const int verticalStep = std::max(
                1,
                (verticalRange.end - verticalRange.begin + MaximumSamplesPerAxis - 1)
                    / MaximumSamplesPerAxis);
            const int horizontalStep = std::max(
                1,
                (horizontalRange.end - horizontalRange.begin + MaximumSamplesPerAxis - 1)
                    / MaximumSamplesPerAxis);
            for (int sourceY = verticalRange.begin;
                 sourceY < verticalRange.end;
                 sourceY += verticalStep) {
                const auto rowOffset = static_cast<std::size_t>(sourceY)
                    * static_cast<std::size_t>(frame.bytesPerRow);
                for (int sourceX = horizontalRange.begin;
                     sourceX < horizontalRange.end;
                     sourceX += horizontalStep) {
                    const auto pixelOffset = rowOffset + static_cast<std::size_t>(sourceX) * 4U;
                    sum += luminance(frame.pixels.data() + pixelOffset);
                    ++samples;
                }
            }

            const auto targetOffset = static_cast<std::size_t>(targetY)
                * static_cast<std::size_t>(size.width) + static_cast<std::size_t>(targetX);
            result.luminance[targetOffset] = static_cast<std::uint8_t>((sum + samples / 2U) / samples);
        }
    }
    return result;
}

std::optional<double> FrameFingerprint::meanAbsoluteDistance(
    const Fingerprint& left,
    const Fingerprint& right)
{
    if (!isValid(left) || !isValid(right)
        || left.size.width != right.size.width || left.size.height != right.size.height) {
        return std::nullopt;
    }

    double sum = 0.0;
    for (std::size_t index = 0; index < left.luminance.size(); ++index) {
        sum += std::abs(
            static_cast<int>(left.luminance[index]) - static_cast<int>(right.luminance[index]))
            / 255.0;
    }
    return sum / static_cast<double>(left.luminance.size());
}

} // namespace snipory::core::scroll
