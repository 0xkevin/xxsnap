#include "annotation/MarkerInteraction.h"
#include "annotation/AnnotationGeometry.h"
#include "annotation/MarkerMetrics.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace xxsnap::win {
namespace {

float lineLength(const MarkerLine& line) noexcept
{
    return std::sqrt(annotationDistanceSquared(line.start, line.end));
}

AnnotationPoint snappedEnd(
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

} // namespace

MarkerInteraction::MarkerInteraction(
    AnnotationDocument& document,
    AnnotationRect bounds) noexcept
    : document_(document), bounds_(standardized(bounds))
{
}

void MarkerInteraction::setBounds(AnnotationRect bounds) noexcept
{
    bounds_ = standardized(bounds);
}

bool MarkerInteraction::beginDrawing(
    AnnotationPoint point,
    AnnotationStyle style) noexcept
{
    cancel();
    if (bounds_.width <= 0.0F || bounds_.height <= 0.0F) {
        return false;
    }
    start_ = clampPoint(point);
    const MarkerLine line{start_, start_};
    preview_ = ShapeAnnotation{
        invalidAnnotationId,
        AnnotationKind::marker,
        markerLineBounds(line),
        style,
        0.0F,
        std::nullopt,
        std::nullopt,
        line,
    };
    mode_ = MarkerInteractionMode::drawing;
    return true;
}

bool MarkerInteraction::beginMove(
    AnnotationId id,
    AnnotationPoint point) noexcept
{
    cancel();
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isMarkerAnnotation(*annotation)) {
        return false;
    }
    document_.select(id);
    targetId_ = id;
    originalLine_ = *annotation->markerLine;
    preview_ = *annotation;
    const auto rect = markerLineBounds(originalLine_);
    moveOffset_ = {point.x - rect.x, point.y - rect.y};
    mode_ = MarkerInteractionMode::moving;
    return true;
}

bool MarkerInteraction::beginResize(
    AnnotationId id,
    MarkerHandle handle) noexcept
{
    cancel();
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isMarkerAnnotation(*annotation)
        || lineLength(*annotation->markerLine) < markerMetrics::dotThresholdDip) {
        return false;
    }
    document_.select(id);
    targetId_ = id;
    activeHandle_ = handle;
    originalLine_ = *annotation->markerLine;
    preview_ = *annotation;
    mode_ = MarkerInteractionMode::resizing;
    return true;
}

void MarkerInteraction::update(
    AnnotationPoint point,
    bool snapDirection) noexcept
{
    if (!preview_.has_value() || !preview_->markerLine.has_value()) {
        return;
    }
    point = clampPoint(point);
    auto line = *preview_->markerLine;
    if (mode_ == MarkerInteractionMode::drawing) {
        line.end = snapDirection ? snappedEnd(start_, point) : point;
        line.end = clampPoint(line.end);
    } else if (mode_ == MarkerInteractionMode::moving) {
        const auto originalBounds = markerLineBounds(originalLine_);
        const auto maximumX = bounds_.x
            + (std::max)(0.0F, bounds_.width - originalBounds.width);
        const auto maximumY = bounds_.y
            + (std::max)(0.0F, bounds_.height - originalBounds.height);
        const AnnotationPoint origin{
            (std::max)(bounds_.x, (std::min)(maximumX,
                point.x - moveOffset_.x)),
            (std::max)(bounds_.y, (std::min)(maximumY,
                point.y - moveOffset_.y)),
        };
        line = translated(originalLine_, {
            origin.x - originalBounds.x,
            origin.y - originalBounds.y,
        });
    } else if (mode_ == MarkerInteractionMode::resizing) {
        auto candidate = originalLine_;
        if (activeHandle_ == MarkerHandle::start) {
            candidate.start = point;
        } else {
            candidate.end = point;
        }
        if (lineLength(candidate) >= markerMetrics::minimumLengthDip) {
            line = candidate;
        }
    }
    preview_->markerLine = line;
    updateBounds();
}

bool MarkerInteraction::commit()
{
    if (!preview_.has_value() || !preview_->markerLine.has_value()) {
        return false;
    }
    const auto length = lineLength(*preview_->markerLine);
    bool changed = false;
    if (mode_ == MarkerInteractionMode::drawing) {
        if (length < markerMetrics::dotThresholdDip
            || length >= markerMetrics::minimumLengthDip) {
            changed = document_.addMarkerLine(
                *preview_->markerLine, preview_->style) != invalidAnnotationId;
        }
    } else {
        changed = document_.updateMarkerLine(
            targetId_, *preview_->markerLine);
    }
    cancel();
    return changed;
}

void MarkerInteraction::cancel() noexcept
{
    mode_ = MarkerInteractionMode::idle;
    targetId_ = invalidAnnotationId;
    start_ = {};
    moveOffset_ = {};
    originalLine_ = {};
    preview_.reset();
}

MarkerInteractionMode MarkerInteraction::mode() const noexcept
{
    return mode_;
}

const std::optional<ShapeAnnotation>& MarkerInteraction::preview() const noexcept
{
    return preview_;
}

bool MarkerInteraction::hitTestLine(
    const ShapeAnnotation& annotation,
    AnnotationPoint point) const noexcept
{
    return isMarkerAnnotation(annotation)
        && annotationDistanceFromSegment(point,
            annotation.markerLine->start,
            annotation.markerLine->end)
            <= (std::max)(
                8.0F, annotation.style.strokeWidthDip / 2.0F + 4.0F);
}

std::optional<MarkerHandle> MarkerInteraction::hitTestHandle(
    const ShapeAnnotation& annotation,
    AnnotationPoint point) const noexcept
{
    constexpr float hitRadiusSquared = markerMetrics::handleHitRadiusDip
        * markerMetrics::handleHitRadiusDip;
    for (const auto handle : {MarkerHandle::start, MarkerHandle::end}) {
        const auto center = handlePoint(annotation, handle);
        if (center.has_value()
            && annotationDistanceSquared(point, *center) <= hitRadiusSquared) {
            return handle;
        }
    }
    return std::nullopt;
}

std::optional<AnnotationPoint> MarkerInteraction::handlePoint(
    const ShapeAnnotation& annotation,
    MarkerHandle handle) const noexcept
{
    if (!isMarkerAnnotation(annotation)
        || lineLength(*annotation.markerLine)
            < markerMetrics::dotThresholdDip) {
        return std::nullopt;
    }
    const auto line = *annotation.markerLine;
    return handle == MarkerHandle::start
        ? std::optional<AnnotationPoint>{insetAnnotationEndpoint(
            line.start, line.end, markerMetrics::endpointInsetDip)}
        : std::optional<AnnotationPoint>{insetAnnotationEndpoint(
            line.end, line.start, markerMetrics::endpointInsetDip)};
}

AnnotationPoint MarkerInteraction::clampPoint(
    AnnotationPoint point) const noexcept
{
    return {
        (std::max)(bounds_.x,
            (std::min)(bounds_.x + bounds_.width, point.x)),
        (std::max)(bounds_.y,
            (std::min)(bounds_.y + bounds_.height, point.y)),
    };
}

void MarkerInteraction::updateBounds() noexcept
{
    preview_->rect = markerLineBounds(*preview_->markerLine);
}

} // namespace xxsnap::win
