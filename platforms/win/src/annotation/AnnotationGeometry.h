#pragma once

#include "annotation/AnnotationTypes.h"

#include <algorithm>
#include <cmath>

namespace xxsnap::win {

inline float annotationDistanceSquared(
    AnnotationPoint left,
    AnnotationPoint right) noexcept
{
    const auto dx = left.x - right.x;
    const auto dy = left.y - right.y;
    return dx * dx + dy * dy;
}

inline float annotationDistanceFromSegment(
    AnnotationPoint point,
    AnnotationPoint start,
    AnnotationPoint end) noexcept
{
    const auto dx = end.x - start.x;
    const auto dy = end.y - start.y;
    const auto lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 0.0001F) {
        return std::sqrt(annotationDistanceSquared(point, start));
    }
    const auto progress = (std::max)(0.0F, (std::min)(1.0F,
        ((point.x - start.x) * dx + (point.y - start.y) * dy)
            / lengthSquared));
    return std::sqrt(annotationDistanceSquared(point, {
        start.x + progress * dx,
        start.y + progress * dy,
    }));
}

inline AnnotationPoint insetAnnotationEndpoint(
    AnnotationPoint endpoint,
    AnnotationPoint neighbour,
    float inset) noexcept
{
    const auto dx = neighbour.x - endpoint.x;
    const auto dy = neighbour.y - endpoint.y;
    const auto length = std::sqrt(dx * dx + dy * dy);
    if (length <= 0.001F) {
        return endpoint;
    }
    const auto distance = (std::min)(inset, length / 2.0F);
    return {
        endpoint.x + dx / length * distance,
        endpoint.y + dy / length * distance,
    };
}

} // namespace xxsnap::win
