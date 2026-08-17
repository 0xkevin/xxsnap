#pragma once

#include "annotation/AnnotationDocument.h"

#include <optional>

namespace xxsnap::win {

enum class MosaicInteractionMode : std::uint8_t {
    idle,
    drawing,
    moving,
};

class MosaicInteraction final {
public:
    MosaicInteraction(
        AnnotationDocument& document,
        AnnotationRect bounds) noexcept;

    void setBounds(AnnotationRect bounds) noexcept;
    bool beginDrawing(
        AnnotationPoint point,
        AnnotationStyle style,
        MosaicRedaction redaction) noexcept;
    bool beginMove(AnnotationId id, AnnotationPoint point) noexcept;
    void update(AnnotationPoint point, bool axisLocked = false);
    bool commit();
    void cancel() noexcept;
    MosaicInteractionMode mode() const noexcept;
    bool hitTestStroke(AnnotationId id, AnnotationPoint point) const noexcept;
    const std::optional<ShapeAnnotation>& preview() const noexcept;

private:
    AnnotationPoint clampPoint(AnnotationPoint point) const noexcept;
    AnnotationPoint axisLockedPoint(AnnotationPoint point) const noexcept;
    void expandPreviewBounds(AnnotationPoint point) noexcept;

    AnnotationDocument& document_;
    AnnotationRect bounds_{};
    AnnotationPoint start_{};
    AnnotationPoint moveOffset_{};
    AnnotationRect originalBounds_{};
    MosaicStroke originalStroke_{};
    AnnotationId targetId_ = invalidAnnotationId;
    MosaicInteractionMode mode_ = MosaicInteractionMode::idle;
    std::optional<ShapeAnnotation> preview_;
};

} // namespace xxsnap::win
