#include "annotation/MosaicInteraction.h"
#include "annotation/AnnotationGeometry.h"

#include <algorithm>
#include <cmath>

namespace xxsnap::win {

MosaicInteraction::MosaicInteraction(
    AnnotationDocument& document,
    AnnotationRect bounds) noexcept
    : document_(document), bounds_(standardized(bounds))
{
}

void MosaicInteraction::setBounds(AnnotationRect bounds) noexcept
{
    bounds_ = standardized(bounds);
}

bool MosaicInteraction::beginDrawing(
    AnnotationPoint point,
    AnnotationStyle style,
    MosaicRedaction redaction) noexcept
{
    cancel();
    if (bounds_.width <= 0.0F || bounds_.height <= 0.0F) {
        return false;
    }
    start_ = clampPoint(point);
    MosaicStroke stroke{{start_}};
    preview_ = ShapeAnnotation{
        invalidAnnotationId,
        AnnotationKind::mosaicStroke,
        brushPathBounds(stroke),
        style,
        0.0F,
        std::nullopt,
        std::nullopt,
        std::nullopt,
        std::move(stroke),
        redaction,
    };
    mode_ = MosaicInteractionMode::drawing;
    return true;
}

bool MosaicInteraction::beginMove(
    AnnotationId id,
    AnnotationPoint point) noexcept
{
    cancel();
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isMosaicStrokeAnnotation(*annotation)) {
        return false;
    }
    document_.select(id);
    targetId_ = id;
    originalStroke_ = *annotation->mosaicStroke;
    preview_ = *annotation;
    originalBounds_ = brushPathBounds(originalStroke_);
    moveOffset_ = {
        point.x - originalBounds_.x,
        point.y - originalBounds_.y,
    };
    mode_ = MosaicInteractionMode::moving;
    return true;
}

void MosaicInteraction::update(AnnotationPoint point, bool axisLocked)
{
    if (!preview_.has_value() || !preview_->mosaicStroke.has_value()) {
        return;
    }
    point = clampPoint(point);
    auto& stroke = *preview_->mosaicStroke;
    auto boundsNeedRecalculation = false;
    if (mode_ == MosaicInteractionMode::drawing) {
        if (axisLocked) {
            stroke.points = {start_, axisLockedPoint(point)};
            boundsNeedRecalculation = true;
        } else if (stroke.points.empty()) {
            stroke.points = {start_, point};
            boundsNeedRecalculation = true;
        } else if (annotationDistanceSquared(stroke.points.back(), point)
            >= 2.25F) {
            stroke.points.push_back(point);
            expandPreviewBounds(point);
        }
    } else if (mode_ == MosaicInteractionMode::moving) {
        const auto maximumX = bounds_.x
            + (std::max)(0.0F, bounds_.width - originalBounds_.width);
        const auto maximumY = bounds_.y
            + (std::max)(0.0F, bounds_.height - originalBounds_.height);
        const AnnotationPoint desiredOrigin{
            (std::max)(bounds_.x, (std::min)(maximumX,
                point.x - moveOffset_.x)),
            (std::max)(bounds_.y, (std::min)(maximumY,
                point.y - moveOffset_.y)),
        };
        stroke = translated(originalStroke_, {
            desiredOrigin.x - originalBounds_.x,
            desiredOrigin.y - originalBounds_.y,
        });
        preview_->rect = translated(originalBounds_, {
            desiredOrigin.x - originalBounds_.x,
            desiredOrigin.y - originalBounds_.y,
        });
    }
    if (boundsNeedRecalculation) {
        preview_->rect = brushPathBounds(stroke);
    }
}

bool MosaicInteraction::commit()
{
    if (!preview_.has_value() || !preview_->mosaicStroke.has_value()
        || !preview_->mosaicRedaction.has_value()) {
        cancel();
        return false;
    }
    const auto changed = mode_ == MosaicInteractionMode::drawing
        ? document_.addMosaicStroke(
            *preview_->mosaicStroke,
            *preview_->mosaicRedaction,
            preview_->style) != invalidAnnotationId
        : document_.updateMosaicStroke(
            targetId_, *preview_->mosaicStroke);
    cancel();
    return changed;
}

void MosaicInteraction::cancel() noexcept
{
    preview_.reset();
    originalStroke_.points.clear();
    originalBounds_ = {};
    targetId_ = invalidAnnotationId;
    moveOffset_ = {};
    mode_ = MosaicInteractionMode::idle;
}

MosaicInteractionMode MosaicInteraction::mode() const noexcept
{
    return mode_;
}

bool MosaicInteraction::hitTestStroke(
    AnnotationId id,
    AnnotationPoint point) const noexcept
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isMosaicStrokeAnnotation(*annotation)) {
        return false;
    }
    const auto& points = annotation->mosaicStroke->points;
    const auto hitOutset = (std::max)(
        8.0F, annotation->style.strokeWidthDip / 2.0F + 4.0F);
    for (std::size_t index = 1; index < points.size(); ++index) {
        if (annotationDistanceFromSegment(
                point, points[index - 1U], points[index]) <= hitOutset) {
            return true;
        }
    }
    return points.size() == 1U
        && std::sqrt(annotationDistanceSquared(point, points.front()))
            <= hitOutset;
}

const std::optional<ShapeAnnotation>& MosaicInteraction::preview() const noexcept
{
    return preview_;
}

AnnotationPoint MosaicInteraction::clampPoint(AnnotationPoint point) const noexcept
{
    point.x = (std::max)(bounds_.x,
        (std::min)(bounds_.x + bounds_.width, point.x));
    point.y = (std::max)(bounds_.y,
        (std::min)(bounds_.y + bounds_.height, point.y));
    return point;
}

AnnotationPoint MosaicInteraction::axisLockedPoint(
    AnnotationPoint point) const noexcept
{
    const auto dx = point.x - start_.x;
    const auto dy = point.y - start_.y;
    return std::abs(dx) >= std::abs(dy)
        ? AnnotationPoint{point.x, start_.y}
        : AnnotationPoint{start_.x, point.y};
}

void MosaicInteraction::expandPreviewBounds(AnnotationPoint point) noexcept
{
    const auto left = (std::min)(preview_->rect.x, point.x);
    const auto top = (std::min)(preview_->rect.y, point.y);
    const auto right = (std::max)(
        preview_->rect.x + preview_->rect.width, point.x);
    const auto bottom = (std::max)(
        preview_->rect.y + preview_->rect.height, point.y);
    preview_->rect = {left, top, right - left, bottom - top};
}

} // namespace xxsnap::win
