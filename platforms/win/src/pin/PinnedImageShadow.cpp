#include "pin/PinnedImageShadow.h"

#include <algorithm>
#include <cmath>

namespace xxsnap::win {
namespace {

struct PremultipliedColor final {
    double blue = 0.0;
    double green = 0.0;
    double red = 0.0;
    double alpha = 0.0;
};

double outsideDistanceSquared(PixelPoint point, PixelRect rect) noexcept
{
    const auto right = rect.x + rect.width;
    const auto bottom = rect.y + rect.height;
    const auto dx = point.x < rect.x
        ? static_cast<double>(rect.x - point.x)
        : point.x >= right
            ? static_cast<double>(point.x - right + 1)
            : 0.0;
    const auto dy = point.y < rect.y
        ? static_cast<double>(rect.y - point.y)
        : point.y >= bottom
            ? static_cast<double>(point.y - bottom + 1)
            : 0.0;
    return dx * dx + dy * dy;
}

void compositeOver(
    PremultipliedColor& destination,
    double red,
    double green,
    double blue,
    double alpha) noexcept
{
    alpha = std::clamp(alpha, 0.0, 1.0);
    const auto remaining = 1.0 - alpha;
    destination.red = red * alpha + destination.red * remaining;
    destination.green = green * alpha + destination.green * remaining;
    destination.blue = blue * alpha + destination.blue * remaining;
    destination.alpha = alpha + destination.alpha * remaining;
}

double shadowAlpha(
    double distanceSquared,
    double opacity,
    double blur) noexcept
{
    const auto sigma = blur / 2.0;
    return opacity * std::exp(-0.5 * distanceSquared / (sigma * sigma));
}

std::uint8_t byteValue(double value) noexcept
{
    return static_cast<std::uint8_t>(std::llround(
        std::clamp(value, 0.0, 1.0) * 255.0));
}

} // namespace

PinnedImageShadowPixel pinnedImageShadowPixel(
    PixelPoint point,
    PixelRect imageRect) noexcept
{
    imageRect = snipory::core::portable::standardized(imageRect);
    const auto primaryDistanceSquared =
        outsideDistanceSquared(point, imageRect);
    auto lowerLayerRect = imageRect;
    ++lowerLayerRect.y;
    const auto lowerDistanceSquared =
        outsideDistanceSquared(point, lowerLayerRect);

    PremultipliedColor result;
    compositeOver(result,
        0.12, 0.45, 0.82,
        shadowAlpha(primaryDistanceSquared, 0.42, 16.0));
    compositeOver(result,
        0.28, 0.64, 1.0,
        shadowAlpha(lowerDistanceSquared, 0.34, 7.0));
    if (primaryDistanceSquared <= 1.0) {
        compositeOver(result, 0.36, 0.65, 0.92, 0.28);
    }
    return {
        byteValue(result.blue),
        byteValue(result.green),
        byteValue(result.red),
        byteValue(result.alpha),
    };
}

} // namespace xxsnap::win
