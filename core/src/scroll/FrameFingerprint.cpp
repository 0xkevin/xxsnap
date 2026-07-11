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
        const int sourceTop = targetY * frame.height / size.height;
        const int sourceBottom = std::max(
            sourceTop + 1,
            static_cast<int>(std::ceil(static_cast<double>(targetY + 1) * frame.height / size.height)));

        for (int targetX = 0; targetX < size.width; ++targetX) {
            const int sourceLeft = targetX * frame.width / size.width;
            const int sourceRight = std::max(
                sourceLeft + 1,
                static_cast<int>(std::ceil(static_cast<double>(targetX + 1) * frame.width / size.width)));

            std::uint64_t sum = 0;
            std::uint64_t samples = 0;
            for (int sourceY = sourceTop; sourceY < sourceBottom; ++sourceY) {
                const auto rowOffset = static_cast<std::size_t>(sourceY)
                    * static_cast<std::size_t>(frame.bytesPerRow);
                for (int sourceX = sourceLeft; sourceX < sourceRight; ++sourceX) {
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
