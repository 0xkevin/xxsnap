#pragma once

#include "annotation/AnnotationTypes.h"

#include <algorithm>
#include <array>
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

inline AnnotationPoint snappedAnnotationEnd(
    AnnotationPoint start,
    AnnotationPoint end) noexcept
{
    constexpr float diagonal = 0.7071067811865475F;
    constexpr std::array directions{
        AnnotationPoint{1, 0}, AnnotationPoint{diagonal, diagonal},
        AnnotationPoint{0, 1}, AnnotationPoint{-diagonal, diagonal},
        AnnotationPoint{-1, 0}, AnnotationPoint{-diagonal, -diagonal},
        AnnotationPoint{0, -1}, AnnotationPoint{diagonal, -diagonal},
    };
    const auto dx = end.x - start.x;
    const auto dy = end.y - start.y;
    if (dx * dx + dy * dy < 0.000001F) {
        return end;
    }
    auto best = directions.front();
    auto bestProjection = dx * best.x + dy * best.y;
    for (const auto direction : directions) {
        const auto projection = dx * direction.x + dy * direction.y;
        if (projection > bestProjection) {
            best = direction;
            bestProjection = projection;
        }
    }
    return {
        start.x + best.x * bestProjection,
        start.y + best.y * bestProjection,
    };
}

} // namespace xxsnap::win
