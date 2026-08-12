#pragma once

#include "annotation/AnnotationDocument.h"

#include <cstdint>
#include <optional>

namespace xxsnap::win {

enum class MarkerHandle : std::uint8_t {
    start,
    end,
};

enum class MarkerInteractionMode : std::uint8_t {
    idle,
    drawing,
    moving,
    resizing,
};

class MarkerInteraction final {
public:
    MarkerInteraction(
        AnnotationDocument& document,
        AnnotationRect bounds) noexcept;

    void setBounds(AnnotationRect bounds) noexcept;
    bool beginDrawing(AnnotationPoint point, AnnotationStyle style) noexcept;
    bool beginMove(AnnotationId id, AnnotationPoint point) noexcept;
    bool beginResize(AnnotationId id, MarkerHandle handle) noexcept;
    void update(AnnotationPoint point, bool snapDirection = false) noexcept;
    bool commit();
    void cancel() noexcept;

    MarkerInteractionMode mode() const noexcept;
    const std::optional<ShapeAnnotation>& preview() const noexcept;
    bool hitTestLine(
        const ShapeAnnotation& annotation,
        AnnotationPoint point) const noexcept;
    std::optional<MarkerHandle> hitTestHandle(
        const ShapeAnnotation& annotation,
        AnnotationPoint point) const noexcept;
    std::optional<AnnotationPoint> handlePoint(
        const ShapeAnnotation& annotation,
        MarkerHandle handle) const noexcept;

private:
    AnnotationPoint clampPoint(AnnotationPoint point) const noexcept;
    void updateBounds() noexcept;

    AnnotationDocument& document_;
    AnnotationRect bounds_{};
    MarkerInteractionMode mode_ = MarkerInteractionMode::idle;
    AnnotationId targetId_ = invalidAnnotationId;
    MarkerHandle activeHandle_ = MarkerHandle::end;
    AnnotationPoint start_{};
    AnnotationPoint moveOffset_{};
    MarkerLine originalLine_{};
    std::optional<ShapeAnnotation> preview_;
};

} // namespace xxsnap::win
