#include "pin/PinnedImageGeometry.h"

#include <algorithm>
#include <cmath>

namespace xxsnap::win {
namespace {

PinnedImageSize scaled(PinnedImageSize value, double factor) noexcept
{
    return {
        (std::max)(1LL, static_cast<std::int64_t>(std::llround(
            static_cast<double>(value.width) * factor))),
        (std::max)(1LL, static_cast<std::int64_t>(std::llround(
            static_cast<double>(value.height) * factor))),
    };
}

} // namespace

PinnedImageSize fittedPinnedImageSize(
    PinnedImageSize imageSize,
    PixelRect visibleFrame) noexcept
{
    visibleFrame = snipory::core::portable::standardized(visibleFrame);
    if (imageSize.width <= 0 || imageSize.height <= 0) {
        return {pinnedImageMinimumLongSide, pinnedImageMinimumLongSide};
    }
    const auto maximumWidth = (std::max)(
        static_cast<double>(pinnedImageMinimumLongSide),
        static_cast<double>(visibleFrame.width)
            * pinnedImageMaximumScreenFraction);
    const auto maximumHeight = (std::max)(
        static_cast<double>(pinnedImageMinimumLongSide),
        static_cast<double>(visibleFrame.height)
            * pinnedImageMaximumScreenFraction);
    const auto fitFactor = (std::min)({
        1.0,
        maximumWidth / static_cast<double>(imageSize.width),
        maximumHeight / static_cast<double>(imageSize.height),
    });
    const auto minimumFactor = static_cast<double>(pinnedImageMinimumLongSide)
        / static_cast<double>((std::max)(imageSize.width, imageSize.height));
    return scaled(imageSize, (std::max)(fitFactor, minimumFactor));
}

PinnedImageSize scaledPinnedImageSize(
    PinnedImageSize currentSize,
    double aspectRatio,
    double scaleFactor,
    PixelRect visibleFrame) noexcept
{
    visibleFrame = snipory::core::portable::standardized(visibleFrame);
    if (currentSize.width <= 0 || currentSize.height <= 0
        || aspectRatio <= 0.0 || scaleFactor <= 0.0) {
        return currentSize;
    }
    const auto maximumWidth = (std::max)(
        static_cast<double>(pinnedImageMinimumLongSide),
        static_cast<double>(visibleFrame.width)
            * pinnedImageMaximumScreenFraction);
    const auto maximumHeight = (std::max)(
        static_cast<double>(pinnedImageMinimumLongSide),
        static_cast<double>(visibleFrame.height)
            * pinnedImageMaximumScreenFraction);
    const auto maximumFactor = (std::min)(
        maximumWidth / static_cast<double>(currentSize.width),
        maximumHeight / static_cast<double>(currentSize.height));
    const auto minimumFactor = static_cast<double>(pinnedImageMinimumLongSide)
        / static_cast<double>((std::max)(currentSize.width, currentSize.height));
    const auto factor = (std::min)(
        (std::max)(scaleFactor, minimumFactor), maximumFactor);
    const auto width = (std::max)(1LL, static_cast<std::int64_t>(std::llround(
        static_cast<double>(currentSize.width) * factor)));
    return {
        width,
        (std::max)(1LL, static_cast<std::int64_t>(std::llround(
            static_cast<double>(width) / aspectRatio))),
    };
}

PixelRect initialPinnedImageRect(
    PinnedImageSize imageSize,
    PixelRect requestedRect,
    PixelRect visibleFrame) noexcept
{
    requestedRect = snipory::core::portable::standardized(requestedRect);
    visibleFrame = snipory::core::portable::standardized(visibleFrame);
    const auto requestedFits = requestedRect.width > 0
        && requestedRect.height > 0
        && requestedRect.width + pinnedImageShadowOutset * 2
            <= visibleFrame.width
        && requestedRect.height + pinnedImageShadowOutset * 2
            <= visibleFrame.height;
    if (requestedFits) return requestedRect;

    const auto fitted = fittedPinnedImageSize(imageSize, {
        visibleFrame.x,
        visibleFrame.y,
        static_cast<std::int64_t>(std::llround(
            static_cast<double>(visibleFrame.width) * 0.875)),
        static_cast<std::int64_t>(std::llround(
            static_cast<double>(visibleFrame.height) * 0.875)),
    });
    return {
        visibleFrame.x + (visibleFrame.width - fitted.width) / 2,
        visibleFrame.y + (visibleFrame.height - fitted.height) / 2,
        fitted.width,
        fitted.height,
    };
}

} // namespace xxsnap::win
