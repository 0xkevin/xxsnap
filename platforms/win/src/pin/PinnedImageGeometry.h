#pragma once

#include "snipory/core/portable/Geometry.h"

namespace xxsnap::win {

using snipory::core::portable::PixelRect;

struct PinnedImageSize {
    std::int64_t width = 0;
    std::int64_t height = 0;
};

inline constexpr double pinnedImageMaximumScreenFraction = 0.8;
inline constexpr std::int64_t pinnedImageMinimumLongSide = 96;
inline constexpr std::int64_t pinnedImageShadowOutset = 18;

PinnedImageSize fittedPinnedImageSize(
    PinnedImageSize imageSize,
    PixelRect visibleFrame) noexcept;

PinnedImageSize scaledPinnedImageSize(
    PinnedImageSize currentSize,
    double aspectRatio,
    double scaleFactor,
    PixelRect visibleFrame) noexcept;

PixelRect initialPinnedImageRect(
    PinnedImageSize imageSize,
    PixelRect requestedRect,
    PixelRect visibleFrame) noexcept;

} // namespace xxsnap::win
