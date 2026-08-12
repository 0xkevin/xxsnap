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

enum class ShapeCursorStyle : std::uint8_t {
    arrow,
    crosshair,
    move,
    resizeLeftRight,
    resizeUpDown,
    resizeTopLeftBottomRight,
    resizeTopRightBottomLeft,
    rotation,
};

class ShapeEditorController final {
public:
    explicit ShapeEditorController(AnnotationRect canvasBounds) noexcept;

    void setCanvasBounds(AnnotationRect canvasBounds) noexcept;
    const ToolbarState& toolbarState() const noexcept;
    const ShapeOptionsState& options() const noexcept;
    const ArrowLineOptionsState& arrowLineOptions() const noexcept;
    const AnnotationDocument& document() const noexcept;
    AnnotationDocument& document() noexcept;
    const std::optional<ShapeAnnotation>& preview() const noexcept;

    bool isShapeToolActive() const noexcept;
    bool isArrowLineToolActive() const noexcept;
    bool strokePatternMenuVisible() const noexcept;
    bool cornerRadiusPanelVisible() const noexcept;
    std::optional<ArrowEndpoint> arrowTypeMenuEndpoint() const noexcept;
    bool handleToolbarAction(ToolbarAction action);
    bool applyOptionHit(ShapeOptionHit hit);
    bool applyArrowLineOptionHit(ArrowLineOptionHit hit);
    bool applyArrowType(ArrowEndpoint endpoint, std::size_t index);
    bool applyStrokePattern(std::size_t index);
    bool setCornerRadius(float cornerRadiusDip);
    bool adjustCornerRadius(float deltaDip);
    bool selectCustomColor(AnnotationColor color);
    void dismissPopovers() noexcept;

    bool pointerDown(AnnotationPoint point) noexcept;
    void pointerMove(AnnotationPoint point) noexcept;
    bool pointerUp(AnnotationPoint point);
    void cancelInteraction() noexcept;
    ShapeCursorStyle cursorStyleAt(AnnotationPoint point) const noexcept;

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
    enum class ArrowInteractionMode : std::uint8_t {
        idle,
        drawing,
        moving,
        editingStart,
        editingEnd,
        editingControl,
    };

    std::optional<AnnotationId> annotationAtBorder(
        AnnotationPoint point) const noexcept;
    bool beginArrowInteraction(
        AnnotationId id,
        ArrowInteractionMode mode,
        AnnotationPoint point) noexcept;
    void updateArrowInteraction(AnnotationPoint point) noexcept;
    void commitArrowInteraction();
    void cancelArrowInteraction() noexcept;
    bool applyArrowOptionsToSelection();
    void loadSelectedOptions() noexcept;
    bool applyOptionsStyleToSelection();
    void syncHistory() noexcept;
    void deactivateTool() noexcept;

    AnnotationDocument document_;
    ShapeOptionsState options_;
    ArrowLineOptionsState arrowLineOptions_;
    ShapeInteraction interaction_;
    AnnotationRect canvasBounds_{};
    ToolbarState toolbarState_;
    bool shapeToolActive_ = false;
    bool arrowLineToolActive_ = false;
    ArrowInteractionMode arrowInteractionMode_ = ArrowInteractionMode::idle;
    AnnotationId arrowInteractionId_ = invalidAnnotationId;
    AnnotationPoint arrowAnchorPoint_{};
    ArrowLine arrowOriginal_{};
    std::optional<ShapeAnnotation> arrowPreview_;
    bool strokePatternMenuVisible_ = false;
    bool cornerRadiusPanelVisible_ = false;
    std::optional<ArrowEndpoint> arrowTypeMenuEndpoint_;
};

} // namespace xxsnap::win
