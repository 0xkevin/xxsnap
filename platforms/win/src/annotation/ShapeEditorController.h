#pragma once

#include "annotation/AnnotationRenderer.h"
#include "annotation/ArrowLineInteraction.h"
#include "annotation/BrushInteraction.h"
#include "annotation/MarkerInteraction.h"
#include "annotation/MosaicInteraction.h"
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
    backspace,
    enter,
    left,
    right,
    home,
    end,
    z,
    save,
    copy,
    eyedropper,
    mosaic,
    text,
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
    brush,
    marker,
    mosaic,
    textInput,
    eyedropper,
};

enum class TextPopupMenu : std::uint8_t {
    fontFamily,
    textSize,
};

class ShapeEditorController final {
public:
    explicit ShapeEditorController(AnnotationRect canvasBounds) noexcept;

    void setCanvasBounds(AnnotationRect canvasBounds) noexcept;
    const ToolbarState& toolbarState() const noexcept;
    const ShapeOptionsState& options() const noexcept;
    const ArrowLineOptionsState& arrowLineOptions() const noexcept;
    const BrushOptionsState& brushOptions() const noexcept;
    const MarkerOptionsState& markerOptions() const noexcept;
    const MosaicOptionsState& mosaicOptions() const noexcept;
    const TextOptionsState& textOptions() const noexcept;
    const AnnotationDocument& document() const noexcept;
    AnnotationDocument& document() noexcept;
    std::uint64_t interactionRevision() const noexcept;
    const std::optional<ShapeAnnotation>& preview() const noexcept;

    bool isShapeToolActive() const noexcept;
    bool isArrowLineToolActive() const noexcept;
    bool isBrushToolActive() const noexcept;
    bool isMarkerToolActive() const noexcept;
    bool isEyedropperToolActive() const noexcept;
    bool isMosaicToolActive() const noexcept;
    bool isTextToolActive() const noexcept;
    bool isEditingText() const noexcept;
    std::optional<TextPopupMenu> textPopupMenu() const noexcept;
    int textPopupScrollOffset() const noexcept;
    bool strokePatternMenuVisible() const noexcept;
    bool cornerRadiusPanelVisible() const noexcept;
    std::optional<ArrowEndpoint> arrowTypeMenuEndpoint() const noexcept;
    bool handleToolbarAction(ToolbarAction action);
    bool applyOptionHit(ShapeOptionHit hit);
    bool applyArrowLineOptionHit(ArrowLineOptionHit hit);
    bool applyBrushOptionHit(BrushOptionHit hit);
    bool applyMarkerOptionHit(MarkerOptionHit hit);
    bool applyMosaicOptionHit(MosaicOptionHit hit);
    bool applyTextOptionHit(TextOptionHit hit);
    bool setTextFontFamily(std::wstring family);
    bool setTextSize(float size);
    bool toggleTextPopupMenu(TextPopupMenu menu) noexcept;
    bool scrollTextPopupMenu(int delta) noexcept;
    bool insertText(std::wstring text);
    bool deleteTextBackward();
    bool deleteTextForward();
    bool commitTextEdit();
    bool cancelTextEdit();
    void beginMosaicRedactionEdit();
    void endMosaicRedactionEdit();
    bool setMosaicRedactionValue(int value);
    bool applyArrowType(ArrowEndpoint endpoint, std::size_t index);
    bool applyStrokePattern(std::size_t index);
    bool setCornerRadius(float cornerRadiusDip);
    bool adjustCornerRadius(float deltaDip);
    bool selectCustomColor(AnnotationColor color);
    void dismissPopovers() noexcept;

    bool pointerDown(
        AnnotationPoint point,
        bool shift = false) noexcept;
    void pointerMove(
        AnnotationPoint point,
        bool shift = false);
    bool pointerUp(
        AnnotationPoint point,
        bool shift = false);
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
    std::optional<AnnotationPoint> textDeleteHandlePoint(
        AnnotationId id) const noexcept;
    AnnotationRenderPlan renderPlan(
        AnnotationPoint selectionOriginDip,
        bool showEditingAffordances = true) const;

private:
    std::optional<AnnotationId> annotationAtBorder(
        AnnotationPoint point) const noexcept;
    std::optional<AnnotationId> textAnnotationAt(
        AnnotationPoint point) const noexcept;
    bool beginTextEdit(AnnotationId id) noexcept;
    bool applyTextStyleToSelection();
    bool applyArrowOptionsToSelection();
    void loadSelectedOptions() noexcept;
    bool applyOptionsStyleToSelection();
    void syncHistory() noexcept;
    void deactivateTool();

    AnnotationDocument document_;
    ShapeOptionsState options_;
    ArrowLineOptionsState arrowLineOptions_;
    BrushOptionsState brushOptions_;
    MarkerOptionsState markerOptions_;
    MosaicOptionsState mosaicOptions_;
    TextOptionsState textOptions_;
    ShapeInteraction interaction_;
    ArrowLineInteraction arrowInteraction_;
    BrushInteraction brushInteraction_;
    MarkerInteraction markerInteraction_;
    MosaicInteraction mosaicInteraction_;
    AnnotationRect canvasBounds_{};
    ToolbarState toolbarState_;
    bool shapeToolActive_ = false;
    bool arrowLineToolActive_ = false;
    bool brushToolActive_ = false;
    bool markerToolActive_ = false;
    bool strokePatternMenuVisible_ = false;
    bool cornerRadiusPanelVisible_ = false;
    std::uint64_t interactionRevision_ = 0;
    std::optional<ArrowEndpoint> arrowTypeMenuEndpoint_;
    std::optional<AnnotationId> editingTextId_;
    std::size_t textCaretPosition_ = 0U;
    std::optional<TextPopupMenu> textPopupMenu_;
    int textPopupScrollOffset_ = 0;
};

} // namespace xxsnap::win
