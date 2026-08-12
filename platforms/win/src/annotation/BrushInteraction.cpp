#include "annotation/BrushInteraction.h"

#include <algorithm>
#include <cmath>

namespace xxsnap::win {
namespace {

float distanceSquared(AnnotationPoint left, AnnotationPoint right) noexcept
{
    const auto dx = left.x - right.x;
    const auto dy = left.y - right.y;
    return dx * dx + dy * dy;
}

float distanceFromSegment(
    AnnotationPoint point,
    AnnotationPoint start,
    AnnotationPoint end) noexcept
{
    const auto dx = end.x - start.x;
    const auto dy = end.y - start.y;
    const auto lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 0.0001F) {
        return std::sqrt(distanceSquared(point, start));
    }
    const auto progress = (std::max)(0.0F, (std::min)(1.0F,
        ((point.x - start.x) * dx + (point.y - start.y) * dy)
            / lengthSquared));
    return std::sqrt(distanceSquared(point, {
        start.x + progress * dx,
        start.y + progress * dy,
    }));
}

AnnotationPoint insetEndpoint(
    AnnotationPoint endpoint,
    AnnotationPoint neighbour) noexcept
{
    constexpr float inset = 9.0F;
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

} // namespace

BrushInteraction::BrushInteraction(
    AnnotationDocument& document,
    AnnotationRect bounds) noexcept
    : document_(document), bounds_(standardized(bounds))
{
}

void BrushInteraction::setBounds(AnnotationRect bounds) noexcept
{
    bounds_ = standardized(bounds);
}

bool BrushInteraction::begin(
    AnnotationPoint point,
    AnnotationStyle style) noexcept
{
    cancel();
    if (bounds_.width <= 0.0F || bounds_.height <= 0.0F) {
        return false;
    }
    start_ = clampPoint(point);
    BrushPath path{{start_}};
    preview_ = ShapeAnnotation{
        invalidAnnotationId,
        AnnotationKind::brush,
        brushPathBounds(path),
        style,
        0.0F,
        std::nullopt,
        std::move(path),
    };
    mode_ = BrushInteractionMode::drawing;
    return true;
}

bool BrushInteraction::beginMove(
    AnnotationId id,
    AnnotationPoint point) noexcept
{
    cancel();
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isBrushAnnotation(*annotation)) {
        return false;
    }
    document_.select(id);
    targetId_ = id;
    originalPath_ = *annotation->brushPath;
    preview_ = *annotation;
    const auto rect = brushPathBounds(originalPath_);
    moveOffset_ = {point.x - rect.x, point.y - rect.y};
    mode_ = BrushInteractionMode::moving;
    return true;
}

bool BrushInteraction::beginRotate(
    AnnotationId id,
    BrushHandle handle) noexcept
{
    cancel();
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isBrushAnnotation(*annotation)
        || annotation->brushPath->points.size() < 2U) {
        return false;
    }
    document_.select(id);
    targetId_ = id;
    activeHandle_ = handle;
    originalPath_ = *annotation->brushPath;
    preview_ = *annotation;
    mode_ = BrushInteractionMode::rotating;
    return true;
}

void BrushInteraction::update(
    AnnotationPoint point,
    bool straightLine)
{
    if (!preview_.has_value() || !preview_->brushPath.has_value()) {
        return;
    }
    point = clampPoint(point);
    auto& path = *preview_->brushPath;
    if (mode_ == BrushInteractionMode::drawing) {
        if (straightLine) {
            path.points = {start_, point};
        } else if (path.points.empty()) {
            path.points = {start_, point};
        } else if (distanceSquared(path.points.back(), point) >= 2.25F) {
            path.points.push_back(point);
        }
    } else if (mode_ == BrushInteractionMode::moving) {
        const auto originalBounds = brushPathBounds(originalPath_);
        const auto maximumX = bounds_.x
            + (std::max)(0.0F, bounds_.width - originalBounds.width);
        const auto maximumY = bounds_.y
            + (std::max)(0.0F, bounds_.height - originalBounds.height);
        const AnnotationPoint desiredOrigin{
            (std::max)(bounds_.x, (std::min)(maximumX,
                point.x - moveOffset_.x)),
            (std::max)(bounds_.y, (std::min)(maximumY,
                point.y - moveOffset_.y)),
        };
        path = translated(originalPath_, {
            desiredOrigin.x - originalBounds.x,
            desiredOrigin.y - originalBounds.y,
        });
    } else if (mode_ == BrushInteractionMode::rotating) {
        const auto& points = originalPath_.points;
        const auto fixed = activeHandle_ == BrushHandle::start
            ? points.back()
            : points.front();
        const auto moving = activeHandle_ == BrushHandle::start
            ? points.front()
            : points.back();
        const AnnotationPoint source{moving.x - fixed.x, moving.y - fixed.y};
        const AnnotationPoint target{point.x - fixed.x, point.y - fixed.y};
        const auto sourceLengthSquared =
            source.x * source.x + source.y * source.y;
        if (sourceLengthSquared >= 0.001F) {
            const auto a = (target.x * source.x + target.y * source.y)
                / sourceLengthSquared;
            const auto b = (target.y * source.x - target.x * source.y)
                / sourceLengthSquared;
            path = originalPath_;
            for (auto& original : path.points) {
                const auto x = original.x - fixed.x;
                const auto y = original.y - fixed.y;
                original = {
                    fixed.x + a * x - b * y,
                    fixed.y + b * x + a * y,
                };
            }
        }
    }
    updatePreviewBounds();
}

bool BrushInteraction::commit()
{
    if (!preview_.has_value() || !preview_->brushPath.has_value()) {
        cancel();
        return false;
    }
    const auto changed = mode_ == BrushInteractionMode::drawing
        ? document_.addBrushPath(*preview_->brushPath, preview_->style)
            != invalidAnnotationId
        : document_.updateBrushPath(targetId_, *preview_->brushPath);
    cancel();
    return changed;
}

void BrushInteraction::cancel() noexcept
{
    preview_.reset();
    originalPath_.points.clear();
    targetId_ = invalidAnnotationId;
    moveOffset_ = {};
    mode_ = BrushInteractionMode::idle;
}

bool BrushInteraction::active() const noexcept
{
    return preview_.has_value();
}

BrushInteractionMode BrushInteraction::mode() const noexcept
{
    return mode_;
}

std::optional<BrushHandle> BrushInteraction::hitTestHandle(
    AnnotationId id,
    AnnotationPoint point) const noexcept
{
    constexpr float hitRadiusSquared = 12.0F * 12.0F;
    for (const auto handle : {BrushHandle::start, BrushHandle::end}) {
        const auto center = handlePoint(id, handle);
        if (center.has_value()
            && distanceSquared(point, *center) <= hitRadiusSquared) {
            return handle;
        }
    }
    return std::nullopt;
}

bool BrushInteraction::hitTestPath(
    AnnotationId id,
    AnnotationPoint point) const noexcept
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isBrushAnnotation(*annotation)) {
        return false;
    }
    const auto& points = annotation->brushPath->points;
    const auto hitOutset = (std::max)(
        8.0F, annotation->style.strokeWidthDip / 2.0F + 4.0F);
    for (std::size_t index = 1; index < points.size(); ++index) {
        if (distanceFromSegment(point, points[index - 1U], points[index])
            <= hitOutset) {
            return true;
        }
    }
    return points.size() == 1U
        && std::sqrt(distanceSquared(point, points.front())) <= hitOutset;
}

std::optional<AnnotationPoint> BrushInteraction::handlePoint(
    AnnotationId id,
    BrushHandle handle) const noexcept
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isBrushAnnotation(*annotation)
        || annotation->brushPath->points.size() < 2U) {
        return std::nullopt;
    }
    const auto& points = annotation->brushPath->points;
    return handle == BrushHandle::start
        ? std::optional<AnnotationPoint>{insetEndpoint(points[0], points[1])}
        : std::optional<AnnotationPoint>{insetEndpoint(
            points.back(), points[points.size() - 2U])};
}

const std::optional<ShapeAnnotation>& BrushInteraction::preview() const noexcept
{
    return preview_;
}

AnnotationPoint BrushInteraction::clampPoint(
    AnnotationPoint point) const noexcept
{
    point.x = (std::max)(bounds_.x,
        (std::min)(bounds_.x + bounds_.width, point.x));
    point.y = (std::max)(bounds_.y,
        (std::min)(bounds_.y + bounds_.height, point.y));
    return point;
}

void BrushInteraction::updatePreviewBounds() noexcept
{
    preview_->rect = brushPathBounds(*preview_->brushPath);
}

} // namespace xxsnap::win
