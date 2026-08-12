#include "annotation/ShapeInteraction.h"

#include <array>

namespace xxsnap::win {
namespace {

constexpr float pi = 3.14159265358979323846F;
constexpr float radiansToDegrees = 180.0F / pi;
constexpr float degreesToRadians = pi / 180.0F;

constexpr float minimum(float left, float right) noexcept
{
    return left < right ? left : right;
}

constexpr float maximum(float left, float right) noexcept
{
    return left > right ? left : right;
}

constexpr float absoluteValue(float value) noexcept
{
    return value < 0.0F ? -value : value;
}

constexpr float clampValue(float value, float lower, float upper) noexcept
{
    return maximum(lower, minimum(value, upper));
}

float approximateAtan(float value) noexcept
{
    const auto magnitude = absoluteValue(value);
    const auto reduced = magnitude > 1.0F ? 1.0F / magnitude : magnitude;
    const auto radians = reduced / (1.0F + 0.28086F * reduced * reduced);
    const auto restored = magnitude > 1.0F ? pi / 2.0F - radians : radians;
    return value < 0.0F ? -restored : restored;
}

float approximateAtan2(float y, float x) noexcept
{
    if (x == 0.0F) {
        if (y > 0.0F) {
            return pi / 2.0F;
        }
        if (y < 0.0F) {
            return -pi / 2.0F;
        }
        return 0.0F;
    }

    auto angle = approximateAtan(y / x);
    if (x < 0.0F) {
        angle += y >= 0.0F ? pi : -pi;
    }
    return angle;
}

float normalizedRadians(float radians) noexcept
{
    while (radians > pi) {
        radians -= 2.0F * pi;
    }
    while (radians < -pi) {
        radians += 2.0F * pi;
    }
    return radians;
}

float normalizedDegrees(float degrees) noexcept
{
    while (degrees > 180.0F) {
        degrees -= 360.0F;
    }
    while (degrees < -180.0F) {
        degrees += 360.0F;
    }
    return degrees;
}

float approximateSine(float radians) noexcept
{
    const auto value = normalizedRadians(radians);
    const auto square = value * value;
    return value * (1.0F
        - square / 6.0F
        + square * square / 120.0F
        - square * square * square / 5040.0F
        + square * square * square * square / 362880.0F);
}

float approximateCosine(float radians) noexcept
{
    const auto value = normalizedRadians(radians);
    const auto square = value * value;
    return 1.0F
        - square / 2.0F
        + square * square / 24.0F
        - square * square * square / 720.0F
        + square * square * square * square / 40320.0F;
}

constexpr std::array allResizeHandles{
    ShapeResizeHandle::topLeft,
    ShapeResizeHandle::top,
    ShapeResizeHandle::topRight,
    ShapeResizeHandle::left,
    ShapeResizeHandle::right,
    ShapeResizeHandle::bottomLeft,
    ShapeResizeHandle::bottom,
    ShapeResizeHandle::bottomRight,
};

} // namespace

ShapeInteraction::ShapeInteraction(
    AnnotationDocument& document,
    AnnotationRect bounds) noexcept
    : document_(document), bounds_(standardized(bounds))
{
}

void ShapeInteraction::setBounds(AnnotationRect bounds) noexcept
{
    bounds_ = standardized(bounds);
    if (preview_.has_value()) {
        preview_->rect = clampRect(preview_->rect);
    }
}

bool ShapeInteraction::beginDrawing(
    AnnotationKind kind,
    AnnotationPoint point,
    AnnotationStyle style,
    float rotationDegrees) noexcept
{
    cancel();
    if (!isShapeKind(kind)
        || bounds_.width <= 0.0F
        || bounds_.height <= 0.0F) {
        return false;
    }

    startPoint_ = clampPoint(point);
    preview_ = ShapeAnnotation{
        invalidAnnotationId,
        kind,
        {startPoint_.x, startPoint_.y, 0.0F, 0.0F},
        style,
        rotationDegrees,
    };
    mode_ = ShapeInteractionMode::drawing;
    return true;
}

bool ShapeInteraction::beginMove(
    AnnotationId id,
    AnnotationPoint point) noexcept
{
    cancel();
    const auto* annotation = document_.find(id);
    if (annotation == nullptr) {
        return false;
    }

    document_.select(id);
    targetId_ = id;
    startRect_ = annotation->rect;
    moveOffset_ = {
        point.x - startRect_.x,
        point.y - startRect_.y,
    };
    preview_ = *annotation;
    mode_ = ShapeInteractionMode::moving;
    return true;
}

bool ShapeInteraction::beginResize(
    AnnotationId id,
    ShapeResizeHandle handle) noexcept
{
    cancel();
    const auto* annotation = document_.find(id);
    if (annotation == nullptr) {
        return false;
    }

    document_.select(id);
    targetId_ = id;
    startRect_ = annotation->rect;
    resizeHandle_ = handle;
    preview_ = *annotation;
    mode_ = ShapeInteractionMode::resizing;
    return true;
}

bool ShapeInteraction::beginRotation(
    AnnotationId id,
    AnnotationPoint point) noexcept
{
    cancel();
    const auto* annotation = document_.find(id);
    if (annotation == nullptr) {
        return false;
    }

    document_.select(id);
    targetId_ = id;
    startRect_ = annotation->rect;
    const AnnotationPoint center{
        startRect_.x + startRect_.width / 2.0F,
        startRect_.y + startRect_.height / 2.0F,
    };
    startPointerAngleDegrees_ = angleDegrees(center, clampPoint(point));
    startRotationDegrees_ = annotation->rotationDegrees;
    preview_ = *annotation;
    mode_ = ShapeInteractionMode::rotating;
    return true;
}

void ShapeInteraction::update(AnnotationPoint point) noexcept
{
    switch (mode_) {
    case ShapeInteractionMode::drawing:
        updateDrawing(point);
        break;
    case ShapeInteractionMode::moving:
        updateMoving(point);
        break;
    case ShapeInteractionMode::resizing:
        updateResizing(point);
        break;
    case ShapeInteractionMode::rotating:
        updateRotating(point);
        break;
    case ShapeInteractionMode::idle:
        break;
    }
}

bool ShapeInteraction::commit()
{
    if (!preview_.has_value()) {
        return false;
    }

    bool changed = false;
    switch (mode_) {
    case ShapeInteractionMode::drawing:
        if (preview_->rect.width >= minimumShapeSizeDip
            && preview_->rect.height >= minimumShapeSizeDip) {
            changed = document_.addShape(
                preview_->kind,
                preview_->rect,
                preview_->style,
                preview_->rotationDegrees) != invalidAnnotationId;
        }
        break;
    case ShapeInteractionMode::moving:
    case ShapeInteractionMode::resizing:
        changed = document_.updateRect(targetId_, preview_->rect);
        break;
    case ShapeInteractionMode::rotating:
        changed = document_.updateRotation(
            targetId_, preview_->rotationDegrees);
        break;
    case ShapeInteractionMode::idle:
        break;
    }

    cancel();
    return changed;
}

void ShapeInteraction::cancel() noexcept
{
    mode_ = ShapeInteractionMode::idle;
    preview_.reset();
    targetId_ = invalidAnnotationId;
    startPoint_ = {};
    moveOffset_ = {};
    startRect_ = {};
    startPointerAngleDegrees_ = 0.0F;
    startRotationDegrees_ = 0.0F;
}

ShapeInteractionMode ShapeInteraction::mode() const noexcept
{
    return mode_;
}

std::optional<ShapeResizeHandle>
ShapeInteraction::activeResizeHandle() const noexcept
{
    return mode_ == ShapeInteractionMode::resizing
        ? std::optional<ShapeResizeHandle>{resizeHandle_}
        : std::nullopt;
}

const std::optional<ShapeAnnotation>& ShapeInteraction::preview() const noexcept
{
    return preview_;
}

std::optional<AnnotationPoint> ShapeInteraction::resizeHandlePoint(
    AnnotationId id,
    ShapeResizeHandle handle) const noexcept
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr) {
        return std::nullopt;
    }
    return rotatedPoint(
        handlePoint(annotation->rect, handle),
        annotation->rect,
        annotation->rotationDegrees);
}

std::optional<ShapeResizeHandle> ShapeInteraction::hitTestResizeHandle(
    AnnotationId id,
    AnnotationPoint point) const noexcept
{
    constexpr auto hitRadiusSquared =
        resizeHandleHitRadiusDip * resizeHandleHitRadiusDip;
    for (const auto handle : allResizeHandles) {
        const auto center = resizeHandlePoint(id, handle);
        if (!center.has_value()) {
            return std::nullopt;
        }
        const auto dx = point.x - center->x;
        const auto dy = point.y - center->y;
        if (dx * dx + dy * dy <= hitRadiusSquared) {
            return handle;
        }
    }
    return std::nullopt;
}

std::optional<AnnotationPoint> ShapeInteraction::rotationHandlePoint(
    AnnotationId id) const noexcept
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr) {
        return std::nullopt;
    }
    const auto rect = standardized(annotation->rect);
    const AnnotationPoint point{
        rect.x + rect.width / 2.0F,
        rect.y - rotationHandleOffsetDip,
    };
    return rotatedPoint(point, rect, annotation->rotationDegrees);
}

bool ShapeInteraction::hitTestRotationHandle(
    AnnotationId id,
    AnnotationPoint point) const noexcept
{
    const auto center = rotationHandlePoint(id);
    if (!center.has_value()) {
        return false;
    }
    const auto dx = point.x - center->x;
    const auto dy = point.y - center->y;
    return dx * dx + dy * dy
        <= resizeHandleHitRadiusDip * resizeHandleHitRadiusDip;
}

AnnotationPoint ShapeInteraction::handlePoint(
    AnnotationRect rect,
    ShapeResizeHandle handle) noexcept
{
    rect = standardized(rect);
    const auto left = rect.x;
    const auto centerX = rect.x + rect.width / 2.0F;
    const auto right = rect.x + rect.width;
    const auto top = rect.y;
    const auto centerY = rect.y + rect.height / 2.0F;
    const auto bottom = rect.y + rect.height;

    switch (handle) {
    case ShapeResizeHandle::topLeft:
        return {left, top};
    case ShapeResizeHandle::top:
        return {centerX, top};
    case ShapeResizeHandle::topRight:
        return {right, top};
    case ShapeResizeHandle::left:
        return {left, centerY};
    case ShapeResizeHandle::right:
        return {right, centerY};
    case ShapeResizeHandle::bottomLeft:
        return {left, bottom};
    case ShapeResizeHandle::bottom:
        return {centerX, bottom};
    case ShapeResizeHandle::bottomRight:
        return {right, bottom};
    }
    return {};
}

AnnotationPoint ShapeInteraction::rotatedPoint(
    AnnotationPoint point,
    AnnotationRect rect,
    float rotationDegrees) noexcept
{
    if (rotationDegrees == 0.0F) {
        return point;
    }
    rect = standardized(rect);
    const AnnotationPoint center{
        rect.x + rect.width / 2.0F,
        rect.y + rect.height / 2.0F,
    };
    const auto radians = rotationDegrees * degreesToRadians;
    const auto sine = approximateSine(radians);
    const auto cosine = approximateCosine(radians);
    const auto dx = point.x - center.x;
    const auto dy = point.y - center.y;
    return {
        center.x + dx * cosine - dy * sine,
        center.y + dx * sine + dy * cosine,
    };
}

float ShapeInteraction::angleDegrees(
    AnnotationPoint center,
    AnnotationPoint point) noexcept
{
    return approximateAtan2(point.y - center.y, point.x - center.x)
        * radiansToDegrees;
}

AnnotationPoint ShapeInteraction::clampPoint(
    AnnotationPoint point) const noexcept
{
    return {
        clampValue(point.x, bounds_.x, bounds_.x + bounds_.width),
        clampValue(point.y, bounds_.y, bounds_.y + bounds_.height),
    };
}

AnnotationRect ShapeInteraction::clampRect(AnnotationRect rect) const noexcept
{
    rect = standardized(rect);
    const auto maximumX = bounds_.x + maximum(0.0F, bounds_.width - rect.width);
    const auto maximumY = bounds_.y + maximum(0.0F, bounds_.height - rect.height);
    rect.x = clampValue(rect.x, bounds_.x, maximumX);
    rect.y = clampValue(rect.y, bounds_.y, maximumY);
    return rect;
}

void ShapeInteraction::updateDrawing(AnnotationPoint point) noexcept
{
    if (!preview_.has_value()) {
        return;
    }
    point = clampPoint(point);
    preview_->rect = standardized({
        startPoint_.x,
        startPoint_.y,
        point.x - startPoint_.x,
        point.y - startPoint_.y,
    });
}

void ShapeInteraction::updateMoving(AnnotationPoint point) noexcept
{
    if (!preview_.has_value()) {
        return;
    }
    preview_->rect = clampRect({
        point.x - moveOffset_.x,
        point.y - moveOffset_.y,
        startRect_.width,
        startRect_.height,
    });
}

void ShapeInteraction::updateResizing(AnnotationPoint point) noexcept
{
    if (!preview_.has_value()) {
        return;
    }
    point = clampPoint(point);
    auto left = startRect_.x;
    auto right = startRect_.x + startRect_.width;
    auto top = startRect_.y;
    auto bottom = startRect_.y + startRect_.height;

    switch (resizeHandle_) {
    case ShapeResizeHandle::topLeft:
        left = point.x;
        top = point.y;
        break;
    case ShapeResizeHandle::top:
        top = point.y;
        break;
    case ShapeResizeHandle::topRight:
        right = point.x;
        top = point.y;
        break;
    case ShapeResizeHandle::left:
        left = point.x;
        break;
    case ShapeResizeHandle::right:
        right = point.x;
        break;
    case ShapeResizeHandle::bottomLeft:
        left = point.x;
        bottom = point.y;
        break;
    case ShapeResizeHandle::bottom:
        bottom = point.y;
        break;
    case ShapeResizeHandle::bottomRight:
        right = point.x;
        bottom = point.y;
        break;
    }

    const auto resized = standardized({left, top, right - left, bottom - top});
    if (resized.width >= minimumShapeSizeDip
        && resized.height >= minimumShapeSizeDip) {
        preview_->rect = resized;
    }
}

void ShapeInteraction::updateRotating(AnnotationPoint point) noexcept
{
    if (!preview_.has_value()) {
        return;
    }
    const AnnotationPoint center{
        startRect_.x + startRect_.width / 2.0F,
        startRect_.y + startRect_.height / 2.0F,
    };
    const auto delta = normalizedDegrees(
        angleDegrees(center, clampPoint(point))
        - startPointerAngleDegrees_);
    preview_->rotationDegrees = startRotationDegrees_ + delta;
}

} // namespace xxsnap::win
