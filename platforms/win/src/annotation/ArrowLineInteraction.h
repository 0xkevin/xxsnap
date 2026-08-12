#pragma once

#include "annotation/AnnotationDocument.h"

#include <cstdint>
#include <optional>

namespace xxsnap::win {

enum class ArrowLineHandle : std::uint8_t {
    start,
    end,
    control,
};

enum class ArrowLineInteractionMode : std::uint8_t {
    idle,
    drawing,
    moving,
    editingStart,
    editingEnd,
    editingControl,
};

class ArrowLineInteraction final {
public:
    static constexpr float minimumLineLengthDip = 8.0F;
    static constexpr float handleHitRadiusDip = 7.0F;

    ArrowLineInteraction(
        AnnotationDocument& document,
        AnnotationRect bounds) noexcept;

    void setBounds(AnnotationRect bounds) noexcept;
    bool beginDrawing(
        AnnotationPoint point,
        AnnotationStyle style,
        ArrowType startArrowType,
        ArrowType endArrowType) noexcept;
    bool beginMove(AnnotationId id, AnnotationPoint point) noexcept;
    bool beginEdit(AnnotationId id, ArrowLineHandle handle) noexcept;

    void update(AnnotationPoint point) noexcept;
    bool commit();
    void cancel() noexcept;

    ArrowLineInteractionMode mode() const noexcept;
    const std::optional<ShapeAnnotation>& preview() const noexcept;
    std::optional<ArrowLineHandle> hitTestHandle(
        AnnotationId id,
        AnnotationPoint point) const noexcept;
    bool hitTestLine(AnnotationId id, AnnotationPoint point) const noexcept;

private:
    AnnotationPoint clampPoint(AnnotationPoint point) const noexcept;
    AnnotationPoint clampTranslation(
        const ArrowLine& line,
        AnnotationPoint offset) const noexcept;

    AnnotationDocument& document_;
    AnnotationRect bounds_{};
    ArrowLineInteractionMode mode_ = ArrowLineInteractionMode::idle;
    AnnotationId targetId_ = invalidAnnotationId;
    AnnotationPoint anchorPoint_{};
    ArrowLine original_{};
    std::optional<ShapeAnnotation> preview_;
};

} // namespace xxsnap::win
