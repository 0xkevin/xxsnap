#include "annotation/ArrowLineInteraction.h"

#include <algorithm>

namespace xxsnap::win {
namespace {

constexpr float minimum(float left, float right) noexcept
{
    return left < right ? left : right;
}

constexpr float maximum(float left, float right) noexcept
{
    return left > right ? left : right;
}

constexpr float clampValue(float value, float lower, float upper) noexcept
{
    return maximum(lower, minimum(value, upper));
}

float squaredDistance(AnnotationPoint left, AnnotationPoint right) noexcept
{
    const auto dx = left.x - right.x;
    const auto dy = left.y - right.y;
    return dx * dx + dy * dy;
}

AnnotationPoint quadraticPoint(const ArrowLine& line, float progress) noexcept
{
    const auto remaining = 1.0F - progress;
    return {
        remaining * remaining * line.start.x
            + 2.0F * remaining * progress * line.control.x
            + progress * progress * line.end.x,
        remaining * remaining * line.start.y
            + 2.0F * remaining * progress * line.control.y
            + progress * progress * line.end.y,
    };
}

float distanceToSegmentSquared(
    AnnotationPoint point,
    AnnotationPoint start,
    AnnotationPoint end) noexcept
{
    const auto dx = end.x - start.x;
    const auto dy = end.y - start.y;
    const auto lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 0.0F) {
        return squaredDistance(point, start);
    }
    const auto projection = ((point.x - start.x) * dx
        + (point.y - start.y) * dy) / lengthSquared;
    const auto progress = (std::max)(0.0F, (std::min)(1.0F, projection));
    return squaredDistance(point, {
        start.x + dx * progress,
        start.y + dy * progress,
    });
}

bool curveContains(const ArrowLine& line, AnnotationPoint point) noexcept
{
    constexpr float hitRadiusSquared
        = ArrowLineInteraction::handleHitRadiusDip
        * ArrowLineInteraction::handleHitRadiusDip;
    constexpr float hitOutset = ArrowLineInteraction::handleHitRadiusDip;
    const auto bounds = standardized(arrowLineBounds(line));
    if (point.x < bounds.x - hitOutset
        || point.y < bounds.y - hitOutset
        || point.x > bounds.x + bounds.width + hitOutset
        || point.y > bounds.y + bounds.height + hitOutset) {
        return false;
    }
    auto previous = line.start;
    for (int index = 1; index <= 32; ++index) {
        const auto current = quadraticPoint(
            line, static_cast<float>(index) / 32.0F);
        if (distanceToSegmentSquared(point, previous, current)
            <= hitRadiusSquared) {
            return true;
        }
        previous = current;
    }
    return false;
}

} // namespace

ArrowLineInteraction::ArrowLineInteraction(
    AnnotationDocument& document,
    AnnotationRect bounds) noexcept
    : document_(document), bounds_(standardized(bounds))
{
}

void ArrowLineInteraction::setBounds(AnnotationRect bounds) noexcept
{
    bounds_ = standardized(bounds);
    if (preview_.has_value() && preview_->arrowLine.has_value()) {
        auto line = *preview_->arrowLine;
        const auto offset = clampTranslation(line, {});
        line = translated(line, offset);
        preview_->arrowLine = line;
        preview_->rect = arrowLineBounds(line);
    }
}

bool ArrowLineInteraction::beginDrawing(
    AnnotationPoint point,
    AnnotationStyle style,
    ArrowType startArrowType,
    ArrowType endArrowType) noexcept
{
    cancel();
    if (bounds_.width <= 0.0F || bounds_.height <= 0.0F) {
        return false;
    }
    point = clampPoint(point);
    const ArrowLine line{
        point,
        point,
        point,
        startArrowType,
        endArrowType,
    };
    preview_ = ShapeAnnotation{
        invalidAnnotationId,
        AnnotationKind::arrowLine,
        {point.x, point.y, 0.0F, 0.0F},
        style,
        0.0F,
        line,
    };
    original_ = line;
    anchorPoint_ = point;
    mode_ = ArrowLineInteractionMode::drawing;
    return true;
}

bool ArrowLineInteraction::beginMove(
    AnnotationId id,
    AnnotationPoint point) noexcept
{
    cancel();
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isArrowLineAnnotation(*annotation)) {
        return false;
    }
    document_.select(id);
    targetId_ = id;
    anchorPoint_ = clampPoint(point);
    original_ = *annotation->arrowLine;
    preview_ = *annotation;
    mode_ = ArrowLineInteractionMode::moving;
    return true;
}

bool ArrowLineInteraction::beginEdit(
    AnnotationId id,
    ArrowLineHandle handle) noexcept
{
    cancel();
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isArrowLineAnnotation(*annotation)) {
        return false;
    }
    document_.select(id);
    targetId_ = id;
    original_ = *annotation->arrowLine;
    preview_ = *annotation;
    switch (handle) {
    case ArrowLineHandle::start:
        mode_ = ArrowLineInteractionMode::editingStart;
        break;
    case ArrowLineHandle::end:
        mode_ = ArrowLineInteractionMode::editingEnd;
        break;
    case ArrowLineHandle::control:
        mode_ = ArrowLineInteractionMode::editingControl;
        break;
    }
    return true;
}

void ArrowLineInteraction::update(AnnotationPoint point) noexcept
{
    if (!preview_.has_value() || !preview_->arrowLine.has_value()) {
        return;
    }
    point = clampPoint(point);
    auto line = original_;
    switch (mode_) {
    case ArrowLineInteractionMode::drawing:
        line.end = point;
        line.control = {
            (line.start.x + line.end.x) / 2.0F,
            (line.start.y + line.end.y) / 2.0F,
        };
        break;
    case ArrowLineInteractionMode::moving: {
        auto offset = AnnotationPoint{
            point.x - anchorPoint_.x,
            point.y - anchorPoint_.y,
        };
        offset = clampTranslation(original_, offset);
        line = translated(original_, offset);
        break;
    }
    case ArrowLineInteractionMode::editingStart:
        line.start = point;
        break;
    case ArrowLineInteractionMode::editingEnd:
        line.end = point;
        break;
    case ArrowLineInteractionMode::editingControl:
        line.control = point;
        break;
    case ArrowLineInteractionMode::idle:
        return;
    }
    preview_->arrowLine = line;
    preview_->rect = arrowLineBounds(line);
}

bool ArrowLineInteraction::commit()
{
    if (!preview_.has_value() || !preview_->arrowLine.has_value()) {
        cancel();
        return false;
    }
    const auto line = *preview_->arrowLine;
    bool changed = false;
    if (mode_ == ArrowLineInteractionMode::drawing) {
        if (squaredDistance(line.start, line.end)
            >= minimumLineLengthDip * minimumLineLengthDip) {
            changed = document_.addArrowLine(line, preview_->style)
                != invalidAnnotationId;
        }
    } else if (mode_ != ArrowLineInteractionMode::idle) {
        changed = document_.updateArrowLine(targetId_, line);
    }
    cancel();
    return changed;
}

void ArrowLineInteraction::cancel() noexcept
{
    mode_ = ArrowLineInteractionMode::idle;
    targetId_ = invalidAnnotationId;
    preview_.reset();
}

ArrowLineInteractionMode ArrowLineInteraction::mode() const noexcept
{
    return mode_;
}

const std::optional<ShapeAnnotation>& ArrowLineInteraction::preview() const noexcept
{
    return preview_;
}

std::optional<ArrowLineHandle> ArrowLineInteraction::hitTestHandle(
    AnnotationId id,
    AnnotationPoint point) const noexcept
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isArrowLineAnnotation(*annotation)) {
        return std::nullopt;
    }
    constexpr float radiusSquared = handleHitRadiusDip * handleHitRadiusDip;
    const auto& line = *annotation->arrowLine;
    if (squaredDistance(point, line.start) <= radiusSquared) {
        return ArrowLineHandle::start;
    }
    if (squaredDistance(point, line.end) <= radiusSquared) {
        return ArrowLineHandle::end;
    }
    if (squaredDistance(point, line.control) <= radiusSquared) {
        return ArrowLineHandle::control;
    }
    return std::nullopt;
}

bool ArrowLineInteraction::hitTestLine(
    AnnotationId id,
    AnnotationPoint point) const noexcept
{
    const auto* annotation = document_.find(id);
    return annotation != nullptr
        && isArrowLineAnnotation(*annotation)
        && curveContains(*annotation->arrowLine, point);
}

AnnotationPoint ArrowLineInteraction::clampPoint(
    AnnotationPoint point) const noexcept
{
    return {
        clampValue(point.x, bounds_.x, bounds_.x + bounds_.width),
        clampValue(point.y, bounds_.y, bounds_.y + bounds_.height),
    };
}

AnnotationPoint ArrowLineInteraction::clampTranslation(
    const ArrowLine& line,
    AnnotationPoint offset) const noexcept
{
    const auto minimumX = minimum(line.start.x,
        minimum(line.end.x, line.control.x));
    const auto maximumX = maximum(line.start.x,
        maximum(line.end.x, line.control.x));
    const auto minimumY = minimum(line.start.y,
        minimum(line.end.y, line.control.y));
    const auto maximumY = maximum(line.start.y,
        maximum(line.end.y, line.control.y));
    return {
        clampValue(offset.x,
            bounds_.x - minimumX,
            bounds_.x + bounds_.width - maximumX),
        clampValue(offset.y,
            bounds_.y - minimumY,
            bounds_.y + bounds_.height - maximumY),
    };
}

} // namespace xxsnap::win
