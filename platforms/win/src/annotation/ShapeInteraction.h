#pragma once

#include "annotation/AnnotationDocument.h"

#include <cstdint>
#include <optional>

namespace xxsnap::win {

enum class ShapeResizeHandle : std::uint8_t {
    topLeft,
    top,
    topRight,
    left,
    right,
    bottomLeft,
    bottom,
    bottomRight,
};

enum class ShapeInteractionMode : std::uint8_t {
    idle,
    drawing,
    moving,
    resizing,
    rotating,
};

class ShapeInteraction {
public:
    static constexpr float minimumShapeSizeDip = 8.0F;
    static constexpr float resizeHandleHitRadiusDip = 7.0F;
    static constexpr float rotationHandleOffsetDip = 14.0F;

    ShapeInteraction(
        AnnotationDocument& document,
        AnnotationRect bounds) noexcept;

    void setBounds(AnnotationRect bounds) noexcept;

    bool beginDrawing(
        AnnotationKind kind,
        AnnotationPoint point,
        AnnotationStyle style = {},
        float rotationDegrees = 0.0F) noexcept;
    bool beginMove(AnnotationId id, AnnotationPoint point) noexcept;
    bool beginResize(AnnotationId id, ShapeResizeHandle handle) noexcept;
    bool beginRotation(AnnotationId id, AnnotationPoint point) noexcept;

    void update(AnnotationPoint point) noexcept;
    bool commit();
    void cancel() noexcept;

    ShapeInteractionMode mode() const noexcept;
    const std::optional<ShapeAnnotation>& preview() const noexcept;

    std::optional<AnnotationPoint> resizeHandlePoint(
        AnnotationId id,
        ShapeResizeHandle handle) const noexcept;
    std::optional<ShapeResizeHandle> hitTestResizeHandle(
        AnnotationId id,
        AnnotationPoint point) const noexcept;
    std::optional<AnnotationPoint> rotationHandlePoint(
        AnnotationId id) const noexcept;
    bool hitTestRotationHandle(
        AnnotationId id,
        AnnotationPoint point) const noexcept;

private:
    static AnnotationPoint handlePoint(
        AnnotationRect rect,
        ShapeResizeHandle handle) noexcept;
    static AnnotationPoint rotatedPoint(
        AnnotationPoint point,
        AnnotationRect rect,
        float rotationDegrees) noexcept;
    static float angleDegrees(
        AnnotationPoint center,
        AnnotationPoint point) noexcept;

    AnnotationPoint clampPoint(AnnotationPoint point) const noexcept;
    AnnotationRect clampRect(AnnotationRect rect) const noexcept;
    void updateDrawing(AnnotationPoint point) noexcept;
    void updateMoving(AnnotationPoint point) noexcept;
    void updateResizing(AnnotationPoint point) noexcept;
    void updateRotating(AnnotationPoint point) noexcept;

    AnnotationDocument& document_;
    AnnotationRect bounds_;
    ShapeInteractionMode mode_ = ShapeInteractionMode::idle;
    std::optional<ShapeAnnotation> preview_;
    AnnotationId targetId_ = invalidAnnotationId;
    AnnotationPoint startPoint_{};
    AnnotationPoint moveOffset_{};
    AnnotationRect startRect_{};
    ShapeResizeHandle resizeHandle_ = ShapeResizeHandle::bottomRight;
    float startPointerAngleDegrees_ = 0.0F;
    float startRotationDegrees_ = 0.0F;
};

} // namespace xxsnap::win
