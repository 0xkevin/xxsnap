#pragma once

#include "annotation/AnnotationRenderer.h"
#include "annotation/ShapeInteraction.h"
#include "annotation/ShapeOptions.h"
#include "toolbar/ToolbarState.h"

#include <cstddef>
#include <cstdint>
#include <optional>

namespace xxsnap::win {

enum class ShapeEditorKey : std::uint8_t {
    escapeKey,
    deleteKey,
    z,
    save,
    copy,
};

enum class ShapeEditorKeyResult : std::uint8_t {
    ignored,
    consumed,
    requestCancel,
    requestSave,
    requestCopy,
};

class ShapeEditorController final {
public:
    explicit ShapeEditorController(AnnotationRect canvasBounds) noexcept;

    void setCanvasBounds(AnnotationRect canvasBounds) noexcept;
    const ToolbarState& toolbarState() const noexcept;
    const ShapeOptionsState& options() const noexcept;
    const AnnotationDocument& document() const noexcept;
    AnnotationDocument& document() noexcept;
    const std::optional<ShapeAnnotation>& preview() const noexcept;

    bool isShapeToolActive() const noexcept;
    bool strokePatternMenuVisible() const noexcept;
    bool cornerRadiusPanelVisible() const noexcept;
    bool handleToolbarAction(ToolbarAction action);
    bool applyOptionHit(ShapeOptionHit hit);
    bool applyStrokePattern(std::size_t index);
    bool setCornerRadius(float cornerRadiusDip);
    bool selectCustomColor(AnnotationColor color);

    bool pointerDown(AnnotationPoint point) noexcept;
    void pointerMove(AnnotationPoint point) noexcept;
    bool pointerUp(AnnotationPoint point);
    void cancelInteraction() noexcept;

    ShapeEditorKeyResult handleKey(
        ShapeEditorKey key,
        bool control,
        bool shift);

    std::optional<AnnotationPoint> resizeHandlePoint(
        AnnotationId id,
        ShapeResizeHandle handle) const noexcept;
    std::optional<AnnotationPoint> rotationHandlePoint(
        AnnotationId id) const noexcept;
    AnnotationRenderPlan renderPlan(
        AnnotationPoint selectionOriginDip,
        bool showEditingAffordances = true) const;

private:
    std::optional<AnnotationId> annotationAtBorder(
        AnnotationPoint point) const noexcept;
    void loadSelectedOptions() noexcept;
    bool applyOptionsStyleToSelection();
    void syncHistory() noexcept;
    void deactivateTool() noexcept;

    AnnotationDocument document_;
    ShapeOptionsState options_;
    ShapeInteraction interaction_;
    ToolbarState toolbarState_;
    bool shapeToolActive_ = false;
    bool strokePatternMenuVisible_ = false;
    bool cornerRadiusPanelVisible_ = false;
};

} // namespace xxsnap::win
