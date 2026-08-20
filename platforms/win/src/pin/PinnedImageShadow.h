#pragma once

#include "snipory/core/portable/Geometry.h"

#include <cstdint>

namespace xxsnap::win {

using snipory::core::portable::PixelPoint;
using snipory::core::portable::PixelRect;

struct PinnedImageShadowPixel final {
    std::uint8_t blue = 0U;
    std::uint8_t green = 0U;
    std::uint8_t red = 0U;
    std::uint8_t alpha = 0U;
};

PinnedImageShadowPixel pinnedImageShadowPixel(
    PixelPoint point,
    PixelRect imageRect) noexcept;

} // namespace xxsnap::win
