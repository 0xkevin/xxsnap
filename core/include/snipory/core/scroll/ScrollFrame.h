#pragma once

#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

namespace snipory::core::scroll {

struct PixelCrop final
{
    int left = 0;
    int right = 0;
    int top = 0;
    int bottom = 0;
};

// A bridge-safe image buffer with four bytes per pixel in BGRA byte order.
struct ScrollFrame final
{
    int width = 0;
    int height = 0;
    int bytesPerRow = 0;
    std::vector<std::uint8_t> pixels;

    ScrollFrame() = default;

    ScrollFrame(int frameWidth, int frameHeight)
        : width(frameWidth)
        , height(frameHeight)
    {
        if (frameWidth <= 0 || frameHeight <= 0) {
            return;
        }

        const auto unsignedWidth = static_cast<std::size_t>(frameWidth);
        if (unsignedWidth > static_cast<std::size_t>(std::numeric_limits<int>::max()) / 4U) {
            return;
        }

        const auto rowSize = unsignedWidth * 4U;
        const auto unsignedHeight = static_cast<std::size_t>(frameHeight);
        if (unsignedHeight > pixels.max_size() / rowSize) {
            return;
        }

        try {
            pixels.assign(rowSize * unsignedHeight, 0);
        } catch (...) {
            pixels.clear();
            return;
        }
        bytesPerRow = static_cast<int>(rowSize);
    }

    [[nodiscard]] bool isValid() const noexcept
    {
        if (width <= 0 || height <= 0 || bytesPerRow <= 0) {
            return false;
        }

        const auto unsignedWidth = static_cast<std::size_t>(width);
        if (unsignedWidth > std::numeric_limits<std::size_t>::max() / 4U) {
            return false;
        }

        const auto requiredRowSize = unsignedWidth * 4U;
        const auto rowSize = static_cast<std::size_t>(bytesPerRow);
        if (rowSize < requiredRowSize) {
            return false;
        }

        const auto unsignedHeight = static_cast<std::size_t>(height);
        if (unsignedHeight > std::numeric_limits<std::size_t>::max() / rowSize) {
            return false;
        }
        return pixels.size() >= rowSize * unsignedHeight;
    }
};

} // namespace snipory::core::scroll
