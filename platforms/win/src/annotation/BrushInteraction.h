#pragma once

#include "annotation/AnnotationDocument.h"

#include <optional>

namespace xxsnap::win {

enum class BrushHandle : std::uint8_t {
    start,
    end,
};

enum class BrushInteractionMode : std::uint8_t {
    idle,
    drawing,
    moving,
    rotating,
};

class BrushInteraction final {
public:
    BrushInteraction(
        AnnotationDocument& document,
        AnnotationRect bounds) noexcept;

    void setBounds(AnnotationRect bounds) noexcept;
    bool begin(AnnotationPoint point, AnnotationStyle style) noexcept;
    bool beginMove(AnnotationId id, AnnotationPoint point) noexcept;
    bool beginRotate(AnnotationId id, BrushHandle handle) noexcept;
    void update(AnnotationPoint point, bool straightLine = false);
    bool commit();
    void cancel() noexcept;
    bool active() const noexcept;
    BrushInteractionMode mode() const noexcept;
    std::optional<BrushHandle> hitTestHandle(
        AnnotationId id, AnnotationPoint point) const noexcept;
    bool hitTestPath(AnnotationId id, AnnotationPoint point) const noexcept;
    std::optional<AnnotationPoint> handlePoint(
        AnnotationId id, BrushHandle handle) const noexcept;
    const std::optional<ShapeAnnotation>& preview() const noexcept;

private:
    AnnotationPoint clampPoint(AnnotationPoint point) const noexcept;
    void updatePreviewBounds() noexcept;

    AnnotationDocument& document_;
    AnnotationRect bounds_{};
    AnnotationPoint start_{};
    AnnotationPoint moveOffset_{};
    BrushPath originalPath_{};
    AnnotationId targetId_ = invalidAnnotationId;
    BrushHandle activeHandle_ = BrushHandle::end;
    BrushInteractionMode mode_ = BrushInteractionMode::idle;
    std::optional<ShapeAnnotation> preview_;
};

} // namespace xxsnap::win
