#pragma once

#include <cstddef>
#include <cstdint>
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
        , bytesPerRow(frameWidth * 4)
        , pixels(static_cast<std::size_t>(bytesPerRow * frameHeight), 0)
    {
    }

    [[nodiscard]] bool isValid() const noexcept
    {
        return width > 0 && height > 0 && bytesPerRow >= width * 4
            && pixels.size() >= static_cast<std::size_t>(bytesPerRow * height);
    }
};

} // namespace snipory::core::scroll
