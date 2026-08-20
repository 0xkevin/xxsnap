#pragma once

#include "annotation/AnnotationTypes.h"

#include <algorithm>
#include <cmath>
#include <optional>

namespace xxsnap::win {

struct MagnifierGeometry {
    float sourceLeft = 0.0F;
    float sourceTop = 0.0F;
    float sourceRight = 0.0F;
    float sourceBottom = 0.0F;
    float drawLeft = 0.0F;
    float drawTop = 0.0F;
    float drawWidth = 0.0F;
    float drawHeight = 0.0F;
};

inline std::optional<MagnifierGeometry> magnifierGeometry(
    AnnotationRect destination,
    float zoom,
    float sourceWidth,
    float sourceHeight,
    float contentXOffset,
    float contentYOffset) noexcept
{
    destination = standardized(destination);
    if (destination.width <= 0.0F || destination.height <= 0.0F
        || sourceWidth <= 0.0F || sourceHeight <= 0.0F) {
        return std::nullopt;
    }
    zoom = normalizedMagnifierZoom(zoom);
    const auto requestedWidth = destination.width / zoom;
    const auto requestedHeight = destination.height / zoom;
    const auto centeredLeft = destination.x
        + destination.width / 2.0F - requestedWidth / 2.0F;
    const auto shiftedLeft = centeredLeft - contentXOffset / zoom;
    const auto shiftedFits = shiftedLeft >= 0.0F
        && shiftedLeft + requestedWidth <= sourceWidth
        && destination.x > 0.0F
        && destination.x + destination.width < sourceWidth;
    const auto requestedLeft = shiftedFits ? shiftedLeft : centeredLeft;
    const auto requestedTop = destination.y
        + destination.height / 2.0F - requestedHeight / 2.0F;
    const auto sourceLeft = (std::max)(0.0F, std::floor(requestedLeft));
    const auto sourceTop = (std::max)(0.0F, std::floor(requestedTop));
    const auto sourceRight = (std::min)(sourceWidth,
        std::ceil(requestedLeft + requestedWidth));
    const auto sourceBottom = (std::min)(sourceHeight,
        std::ceil(requestedTop + requestedHeight));
    if (sourceLeft >= sourceRight || sourceTop >= sourceBottom) {
        return std::nullopt;
    }
    const auto xScale = destination.width / (std::max)(requestedWidth, 1.0F);
    const auto yScale = destination.height / (std::max)(requestedHeight, 1.0F);
    const auto drawWidth = (sourceRight - sourceLeft) * xScale;
    const auto drawHeight = (sourceBottom - sourceTop) * yScale;
    const auto visibleLeft = (std::max)(0.0F, destination.x);
    const auto visibleTop = (std::max)(0.0F, destination.y);
    const auto visibleRight = (std::min)(sourceWidth,
        destination.x + destination.width);
    const auto visibleBottom = (std::min)(sourceHeight,
        destination.y + destination.height);
    const auto drawLeft = sourceLeft <= 0.0F && requestedLeft < 0.0F
        ? visibleLeft
        : sourceRight >= sourceWidth
            && requestedLeft + requestedWidth > sourceWidth
        ? visibleRight - drawWidth
        : destination.x + (sourceLeft - requestedLeft) * xScale;
    const auto drawTop = sourceTop <= 0.0F && requestedTop < 0.0F
        ? visibleTop
        : sourceBottom >= sourceHeight
            && requestedTop + requestedHeight > sourceHeight
        ? visibleBottom - drawHeight
        : destination.y + (sourceTop - requestedTop) * yScale;
    return MagnifierGeometry{
        sourceLeft, sourceTop, sourceRight, sourceBottom,
        drawLeft, drawTop - contentYOffset, drawWidth, drawHeight};
}

} // namespace xxsnap::win
