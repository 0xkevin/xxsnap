#include "annotation/ShapeEditorController.h"
#include "annotation/TextAnnotationRenderer.h"
#include "annotation/AnnotationGeometry.h"

#include <algorithm>
#include <array>
#include <cwctype>
#include <utility>

namespace xxsnap::win {
namespace {

constexpr float pi = 3.14159265358979323846F;
constexpr float degreesToRadians = pi / 180.0F;

constexpr std::array shapeStrokeWidths{2.0F, 4.0F, 7.0F};

constexpr float minimum(float left, float right) noexcept
{
    return left < right ? left : right;
}

constexpr float maximum(float left, float right) noexcept
{
    return left > right ? left : right;
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

AnnotationPoint unrotatedPoint(
    AnnotationPoint point,
    const ShapeAnnotation& annotation) noexcept
{
    if (annotation.rotationDegrees == 0.0F) {
        return point;
    }
    const auto rect = standardized(annotation.rect);
    const AnnotationPoint center{
        rect.x + rect.width / 2.0F,
        rect.y + rect.height / 2.0F,
    };
    const auto radians = -annotation.rotationDegrees * degreesToRadians;
    const auto sine = approximateSine(radians);
    const auto cosine = approximateCosine(radians);
    const auto dx = point.x - center.x;
    const auto dy = point.y - center.y;
    return {
        center.x + dx * cosine - dy * sine,
        center.y + dx * sine + dy * cosine,
    };
}

bool containsRect(AnnotationRect rect, AnnotationPoint point) noexcept
{
    rect = standardized(rect);
    return point.x >= rect.x
        && point.y >= rect.y
        && point.x <= rect.x + rect.width
        && point.y <= rect.y + rect.height;
}

bool ellipseContains(
    AnnotationRect rect,
    AnnotationPoint point) noexcept
{
    rect = standardized(rect);
    if (rect.width <= 0.0F || rect.height <= 0.0F) {
        return false;
    }
    const auto rx = rect.width / 2.0F;
    const auto ry = rect.height / 2.0F;
    const auto dx = (point.x - rect.x - rx) / rx;
    const auto dy = (point.y - rect.y - ry) / ry;
    return dx * dx + dy * dy <= 1.0F;
}

bool shapeBorderContains(
    const ShapeAnnotation& annotation,
    AnnotationPoint point) noexcept
{
    constexpr float outset = 6.0F;
    point = unrotatedPoint(point, annotation);
    auto rect = standardized(annotation.rect);
    const AnnotationRect outer{
        rect.x - outset,
        rect.y - outset,
        rect.width + outset * 2.0F,
        rect.height + outset * 2.0F,
    };
    const AnnotationRect inner{
        rect.x + outset,
        rect.y + outset,
        maximum(0.0F, rect.width - outset * 2.0F),
        maximum(0.0F, rect.height - outset * 2.0F),
    };
    if (annotation.kind == AnnotationKind::ellipse) {
        return ellipseContains(outer, point)
            && (inner.width <= 0.0F
                || inner.height <= 0.0F
                || !ellipseContains(inner, point));
    }
    return containsRect(outer, point)
        && (inner.width <= 0.0F
            || inner.height <= 0.0F
            || !containsRect(inner, point));
}

AnnotationPoint clampedPoint(
    AnnotationPoint point,
    AnnotationRect bounds) noexcept
{
    bounds = standardized(bounds);
    point.x = (std::max)(bounds.x,
        (std::min)(bounds.x + bounds.width, point.x));
    point.y = (std::max)(bounds.y,
        (std::min)(bounds.y + bounds.height, point.y));
    return point;
}

ShapeCursorStyle cursorStyleForResizeHandle(
    ShapeResizeHandle handle) noexcept
{
    switch (handle) {
    case ShapeResizeHandle::left:
    case ShapeResizeHandle::right:
        return ShapeCursorStyle::resizeLeftRight;
    case ShapeResizeHandle::top:
    case ShapeResizeHandle::bottom:
        return ShapeCursorStyle::resizeUpDown;
    case ShapeResizeHandle::topLeft:
    case ShapeResizeHandle::bottomRight:
        return ShapeCursorStyle::resizeTopLeftBottomRight;
    case ShapeResizeHandle::topRight:
    case ShapeResizeHandle::bottomLeft:
        return ShapeCursorStyle::resizeTopRightBottomLeft;
    }
    return ShapeCursorStyle::arrow;
}

} // namespace

ShapeEditorController::ShapeEditorController(
    AnnotationRect canvasBounds) noexcept
    : interaction_(document_, canvasBounds),
      arrowInteraction_(document_, canvasBounds),
      brushInteraction_(document_, canvasBounds),
      markerInteraction_(document_, canvasBounds),
      mosaicInteraction_(document_, canvasBounds),
      canvasBounds_(standardized(canvasBounds))
{
    toolbarState_.setCapability(ToolbarAction::rectangle, true);
    toolbarState_.setCapability(ToolbarAction::polyline, true);
    toolbarState_.setCapability(ToolbarAction::pen, true);
    toolbarState_.setCapability(ToolbarAction::marker, true);
    toolbarState_.setCapability(ToolbarAction::eyedropper, true);
    toolbarState_.setCapability(ToolbarAction::mosaic, true);
    toolbarState_.setCapability(ToolbarAction::text, true);
    toolbarState_.setCapability(ToolbarAction::undo, true);
    toolbarState_.setCapability(ToolbarAction::redo, true);
    syncHistory();
}

void ShapeEditorController::setCanvasBounds(
    AnnotationRect canvasBounds) noexcept
{
    interaction_.setBounds(canvasBounds);
    arrowInteraction_.setBounds(canvasBounds);
    brushInteraction_.setBounds(canvasBounds);
    markerInteraction_.setBounds(canvasBounds);
    mosaicInteraction_.setBounds(canvasBounds);
    canvasBounds_ = standardized(canvasBounds);
}

const ToolbarState& ShapeEditorController::toolbarState() const noexcept
{
    return toolbarState_;
}

const ShapeOptionsState& ShapeEditorController::options() const noexcept
{
    return options_;
}

const ArrowLineOptionsState& ShapeEditorController::arrowLineOptions() const noexcept
{
    return arrowLineOptions_;
}

const BrushOptionsState& ShapeEditorController::brushOptions() const noexcept
{
    return brushOptions_;
}

const MarkerOptionsState& ShapeEditorController::markerOptions() const noexcept
{
    return markerOptions_;
}

const MosaicOptionsState& ShapeEditorController::mosaicOptions() const noexcept
{
    return mosaicOptions_;
}

const TextOptionsState& ShapeEditorController::textOptions() const noexcept
{
    return textOptions_;
}

const AnnotationDocument& ShapeEditorController::document() const noexcept
{
    return document_;
}

AnnotationDocument& ShapeEditorController::document() noexcept
{
    return document_;
}

std::uint64_t ShapeEditorController::interactionRevision() const noexcept
{
    return interactionRevision_;
}

const std::optional<ShapeAnnotation>& ShapeEditorController::preview() const noexcept
{
    if (mosaicInteraction_.preview().has_value()) {
        return mosaicInteraction_.preview();
    }
    if (brushInteraction_.preview().has_value()) {
        return brushInteraction_.preview();
    }
    if (markerInteraction_.preview().has_value()) {
        return markerInteraction_.preview();
    }
    return arrowInteraction_.preview().has_value()
        ? arrowInteraction_.preview()
        : interaction_.preview();
}

bool ShapeEditorController::isShapeToolActive() const noexcept
{
    return shapeToolActive_;
}

bool ShapeEditorController::isArrowLineToolActive() const noexcept
{
    return arrowLineToolActive_;
}

bool ShapeEditorController::isBrushToolActive() const noexcept
{
    return brushToolActive_;
}

bool ShapeEditorController::isMarkerToolActive() const noexcept
{
    return markerToolActive_;
}

bool ShapeEditorController::isEyedropperToolActive() const noexcept
{
    return toolbarState_.selectedAction() == ToolbarAction::eyedropper;
}

bool ShapeEditorController::isMosaicToolActive() const noexcept
{
    return toolbarState_.selectedAction() == ToolbarAction::mosaic;
}

bool ShapeEditorController::isTextToolActive() const noexcept
{
    return toolbarState_.selectedAction() == ToolbarAction::text;
}

bool ShapeEditorController::isEditingText() const noexcept
{
    return editingTextId_.has_value();
}

std::optional<TextPopupMenu>
ShapeEditorController::textPopupMenu() const noexcept
{
    return textPopupMenu_;
}

int ShapeEditorController::textPopupScrollOffset() const noexcept
{
    return textPopupScrollOffset_;
}

bool ShapeEditorController::strokePatternMenuVisible() const noexcept
{
    return strokePatternMenuVisible_;
}

bool ShapeEditorController::cornerRadiusPanelVisible() const noexcept
{
    return cornerRadiusPanelVisible_;
}

std::optional<ArrowEndpoint>
ShapeEditorController::arrowTypeMenuEndpoint() const noexcept
{
    return arrowTypeMenuEndpoint_;
}

bool ShapeEditorController::handleToolbarAction(ToolbarAction action)
{
    if (action != ToolbarAction::text && editingTextId_.has_value()) {
        commitTextEdit();
    }
    if (action == ToolbarAction::rectangle) {
        if (shapeToolActive_) {
            deactivateTool();
        } else {
            cancelInteraction();
            arrowLineToolActive_ = false;
            brushToolActive_ = false;
            markerToolActive_ = false;
            arrowTypeMenuEndpoint_.reset();
            shapeToolActive_ = toolbarState_.selectTool(action);
            if (shapeToolActive_) {
                ShapeOptionsState activated;
                options_ = activated;
                applyOptionsStyleToSelection();
            }
        }
        return true;
    }
    if (action == ToolbarAction::polyline) {
        if (arrowLineToolActive_) {
            deactivateTool();
        } else {
            cancelInteraction();
            shapeToolActive_ = false;
            brushToolActive_ = false;
            markerToolActive_ = false;
            arrowLineToolActive_ = toolbarState_.selectTool(action);
            if (arrowLineToolActive_) {
                ArrowLineOptionsState activated;
                arrowLineOptions_ = activated;
                applyArrowOptionsToSelection();
            }
        }
        return true;
    }
    if (action == ToolbarAction::pen) {
        if (brushToolActive_) {
            deactivateTool();
        } else {
            cancelInteraction();
            shapeToolActive_ = false;
            arrowLineToolActive_ = false;
            markerToolActive_ = false;
            brushToolActive_ = toolbarState_.selectTool(action);
            strokePatternMenuVisible_ = false;
            arrowTypeMenuEndpoint_.reset();
            if (brushToolActive_) {
                BrushOptionsState activated;
                brushOptions_ = activated;
            }
        }
        return true;
    }
    if (action == ToolbarAction::marker) {
        if (markerToolActive_) {
            deactivateTool();
        } else {
            cancelInteraction();
            shapeToolActive_ = false;
            arrowLineToolActive_ = false;
            brushToolActive_ = false;
            markerToolActive_ = toolbarState_.selectTool(action);
            dismissPopovers();
            if (markerToolActive_) {
                MarkerOptionsState activated;
                markerOptions_ = activated;
            }
        }
        return true;
    }
    if (action == ToolbarAction::mosaic) {
        if (isMosaicToolActive()) {
            deactivateTool();
        } else {
            cancelInteraction();
            shapeToolActive_ = false;
            arrowLineToolActive_ = false;
            brushToolActive_ = false;
            markerToolActive_ = false;
            const auto toolActivated = toolbarState_.selectTool(action);
            dismissPopovers();
            if (toolActivated) {
                MosaicOptionsState activated;
                mosaicOptions_ = activated;
                document_.clearSelection();
            }
        }
        return true;
    }
    if (action == ToolbarAction::text) {
        if (isTextToolActive()) {
            commitTextEdit();
            deactivateTool();
        } else {
            cancelInteraction();
            shapeToolActive_ = false;
            arrowLineToolActive_ = false;
            brushToolActive_ = false;
            markerToolActive_ = false;
            if (toolbarState_.selectTool(action)) {
                TextOptionsState activated;
                textOptions_ = std::move(activated);
                document_.clearSelection();
                dismissPopovers();
            }
        }
        return true;
    }
    if (action == ToolbarAction::eyedropper) {
        if (isEyedropperToolActive()) {
            deactivateTool();
        } else {
            cancelInteraction();
            shapeToolActive_ = false;
            arrowLineToolActive_ = false;
            brushToolActive_ = false;
            markerToolActive_ = false;
            if (toolbarState_.selectTool(action)) {
                document_.clearSelection();
                dismissPopovers();
            }
        }
        return true;
    }
    if (action == ToolbarAction::undo) {
        const auto changed = document_.undo();
        if (changed) {
            loadSelectedOptions();
            syncHistory();
        }
        return changed;
    }
    if (action == ToolbarAction::redo) {
        const auto changed = document_.redo();
        if (changed) {
            loadSelectedOptions();
            syncHistory();
        }
        return changed;
    }
    return false;
}

bool ShapeEditorController::applyArrowLineOptionHit(ArrowLineOptionHit hit)
{
    bool changed = false;
    switch (hit.control) {
    case ArrowLineOptionControl::strokeWidth: {
        const auto& widths = macArrowStrokeWidths();
        if (hit.index < widths.size()) {
            changed = arrowLineOptions_.setStrokeWidth(widths[hit.index]);
        }
        break;
    }
    case ArrowLineOptionControl::strokeStyle:
        strokePatternMenuVisible_ = !strokePatternMenuVisible_;
        arrowTypeMenuEndpoint_.reset();
        return true;
    case ArrowLineOptionControl::startArrowType:
    case ArrowLineOptionControl::endArrowType: {
        const auto endpoint = hit.control
            == ArrowLineOptionControl::startArrowType
            ? ArrowEndpoint::start
            : ArrowEndpoint::end;
        arrowTypeMenuEndpoint_ = arrowTypeMenuEndpoint_ == endpoint
            ? std::nullopt
            : std::optional<ArrowEndpoint>{endpoint};
        strokePatternMenuVisible_ = false;
        return true;
    }
    case ArrowLineOptionControl::customColor:
        return false;
    case ArrowLineOptionControl::palette:
        changed = arrowLineOptions_.selectPalette(hit.index);
        break;
    }
    if (!changed) {
        return false;
    }
    const auto applied = applyArrowOptionsToSelection();
    arrowTypeMenuEndpoint_.reset();
    syncHistory();
    return applied || !document_.selectedId().has_value();
}

bool ShapeEditorController::applyArrowType(
    ArrowEndpoint endpoint,
    std::size_t index)
{
    const auto& types = macArrowTypes();
    if (index >= types.size()) {
        return false;
    }
    const auto changed = arrowLineOptions_.selectArrowType(
        endpoint, types[index]);
    const auto applied = changed && applyArrowOptionsToSelection();
    arrowTypeMenuEndpoint_.reset();
    syncHistory();
    return applied || !document_.selectedId().has_value() || !changed;
}

bool ShapeEditorController::applyBrushOptionHit(BrushOptionHit hit)
{
    bool changed = false;
    switch (hit.control) {
    case BrushOptionControl::strokeWidth: {
        const auto& widths = macBrushStrokeWidths();
        if (hit.index < widths.size()) {
            changed = brushOptions_.setStrokeWidth(widths[hit.index]);
        }
        break;
    }
    case BrushOptionControl::strokeStyle:
        strokePatternMenuVisible_ = !strokePatternMenuVisible_;
        return true;
    case BrushOptionControl::palette:
        changed = brushOptions_.selectPalette(hit.index);
        break;
    case BrushOptionControl::customColor:
        return false;
    }
    return changed;
}

bool ShapeEditorController::applyMarkerOptionHit(MarkerOptionHit hit)
{
    bool changed = false;
    switch (hit.control) {
    case MarkerOptionControl::strokeWidth: {
        const auto& widths = macMarkerStrokeWidths();
        if (hit.index < widths.size()) {
            changed = markerOptions_.setStrokeWidth(widths[hit.index]);
        }
        break;
    }
    case MarkerOptionControl::palette:
        changed = markerOptions_.selectPalette(hit.index);
        break;
    case MarkerOptionControl::customColor:
        return false;
    }
    const auto selected = document_.selectedId();
    const auto* annotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    if (changed && annotation != nullptr && isMarkerAnnotation(*annotation)) {
        document_.updateStyle(*selected, markerOptions_.style());
        syncHistory();
    }
    return changed;
}

bool ShapeEditorController::applyMosaicOptionHit(MosaicOptionHit hit)
{
    bool changed = false;
    const auto previousKind = mosaicOptions_.kind();
    switch (hit.control) {
    case MosaicOptionControl::strokeWidth: {
        const auto& widths = macMosaicStrokeWidths();
        if (hit.index < widths.size()) {
            changed = mosaicOptions_.setStrokeWidth(widths[hit.index]);
        }
        break;
    }
    case MosaicOptionControl::rectangleMode:
        changed = mosaicOptions_.setKind(AnnotationKind::mosaicRectangle);
        break;
    case MosaicOptionControl::redactionType:
        changed = mosaicOptions_.toggleRedactionType();
        break;
    case MosaicOptionControl::redactionValue:
        return true;
    }
    const auto switchedDrawingMode = previousKind != mosaicOptions_.kind();
    if (switchedDrawingMode) {
        document_.clearSelection();
    }
    const auto selected = document_.selectedId();
    const auto* annotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    if (changed && annotation != nullptr && isMosaicAnnotation(*annotation)) {
        document_.updateStyle(*selected, mosaicOptions_.style());
        document_.updateMosaicRedaction(
            *selected, mosaicOptions_.redaction());
    }
    syncHistory();
    return changed;
}

bool ShapeEditorController::setMosaicRedactionValue(int value)
{
    if (!mosaicOptions_.setRedactionValue(value)) {
        return false;
    }
    const auto selected = document_.selectedId();
    const auto changed = selected.has_value()
        && document_.updateMosaicRedaction(
            *selected, mosaicOptions_.redaction());
    syncHistory();
    return changed || !selected.has_value();
}

void ShapeEditorController::beginMosaicRedactionEdit()
{
    document_.beginMosaicRedactionEdit();
}

void ShapeEditorController::endMosaicRedactionEdit()
{
    document_.endMosaicRedactionEdit();
    syncHistory();
}

bool ShapeEditorController::applyTextOptionHit(TextOptionHit hit)
{
    bool changed = false;
    switch (hit.control) {
    case TextOptionControl::bold:
        changed = textOptions_.toggleBold();
        break;
    case TextOptionControl::italic:
        changed = textOptions_.toggleItalic();
        break;
    case TextOptionControl::outline:
        changed = textOptions_.toggleOutline();
        break;
    case TextOptionControl::palette:
        changed = textOptions_.selectPalette(hit.index);
        break;
    case TextOptionControl::customColor:
    case TextOptionControl::fontFamily:
    case TextOptionControl::textSize:
        return false;
    }
    if (changed) {
        applyTextStyleToSelection();
    }
    return changed;
}

bool ShapeEditorController::setTextFontFamily(std::wstring family)
{
    const auto changed = textOptions_.setFontFamily(std::move(family));
    return changed && applyTextStyleToSelection();
}

bool ShapeEditorController::setTextSize(float size)
{
    const auto changed = textOptions_.setTextSize(size);
    return changed && applyTextStyleToSelection();
}

bool ShapeEditorController::toggleTextPopupMenu(
    TextPopupMenu menu) noexcept
{
    textPopupMenu_ = textPopupMenu_ == menu
        ? std::nullopt : std::optional<TextPopupMenu>{menu};
    textPopupScrollOffset_ = 0;
    strokePatternMenuVisible_ = false;
    cornerRadiusPanelVisible_ = false;
    arrowTypeMenuEndpoint_.reset();
    return true;
}

bool ShapeEditorController::scrollTextPopupMenu(int delta) noexcept
{
    if (!textPopupMenu_.has_value() || delta == 0) return false;
    textPopupScrollOffset_ = (std::max)(-10000,
        (std::min)(10000, textPopupScrollOffset_ + delta));
    return true;
}

bool ShapeEditorController::insertText(std::wstring text)
{
    if (!editingTextId_.has_value() || text.empty()) {
        return false;
    }
    const auto* annotation = document_.find(*editingTextId_);
    if (annotation == nullptr || !isTextAnnotation(*annotation)) {
        editingTextId_.reset();
        return false;
    }
    auto updated = *annotation->text;
    textCaretPosition_ = (std::min)(
        textCaretPosition_, updated.size());
    updated.insert(textCaretPosition_, text);
    textCaretPosition_ += text.size();
    const AnnotationPoint anchor{
        annotation->rect.x + textHorizontalPaddingDip,
        annotation->rect.y + annotation->rect.height / 2.0F,
    };
    ++interactionRevision_;
    return document_.updateText(*editingTextId_, updated,
        measuredTextRect(anchor, updated, annotation->style));
}

bool ShapeEditorController::deleteTextBackward()
{
    if (!editingTextId_.has_value()) {
        return false;
    }
    const auto* annotation = document_.find(*editingTextId_);
    if (annotation == nullptr || !isTextAnnotation(*annotation)) {
        return false;
    }
    auto updated = *annotation->text;
    textCaretPosition_ = (std::min)(
        textCaretPosition_, updated.size());
    if (updated.empty()) {
        return cancelTextEdit();
    }
    if (textCaretPosition_ == 0U) return false;
    auto eraseStart = textCaretPosition_ - 1U;
    if (eraseStart > 0U && updated[eraseStart] >= 0xDC00
        && updated[eraseStart] <= 0xDFFF
        && updated[eraseStart - 1U] >= 0xD800
        && updated[eraseStart - 1U] <= 0xDBFF) {
        --eraseStart;
    }
    updated.erase(eraseStart, textCaretPosition_ - eraseStart);
    textCaretPosition_ = eraseStart;
    const AnnotationPoint anchor{
        annotation->rect.x + textHorizontalPaddingDip,
        annotation->rect.y + annotation->rect.height / 2.0F,
    };
    ++interactionRevision_;
    return document_.updateText(*editingTextId_, updated,
        measuredTextRect(anchor, updated, annotation->style));
}

bool ShapeEditorController::deleteTextForward()
{
    if (!editingTextId_.has_value()) return false;
    const auto* annotation = document_.find(*editingTextId_);
    if (annotation == nullptr || !isTextAnnotation(*annotation)) return false;
    auto updated = *annotation->text;
    textCaretPosition_ = (std::min)(textCaretPosition_, updated.size());
    if (textCaretPosition_ >= updated.size()) return false;
    auto eraseCount = std::size_t{1U};
    if (updated[textCaretPosition_] >= 0xD800
        && updated[textCaretPosition_] <= 0xDBFF
        && textCaretPosition_ + 1U < updated.size()
        && updated[textCaretPosition_ + 1U] >= 0xDC00
        && updated[textCaretPosition_ + 1U] <= 0xDFFF) {
        eraseCount = 2U;
    }
    updated.erase(textCaretPosition_, eraseCount);
    const AnnotationPoint anchor{
        annotation->rect.x + textHorizontalPaddingDip,
        annotation->rect.y + annotation->rect.height / 2.0F,
    };
    ++interactionRevision_;
    return document_.updateText(*editingTextId_, updated,
        measuredTextRect(anchor, updated, annotation->style));
}

bool ShapeEditorController::commitTextEdit()
{
    if (!editingTextId_.has_value()) {
        return false;
    }
    const auto* annotation = document_.find(*editingTextId_);
    const auto keep = annotation != nullptr && isTextAnnotation(*annotation)
        && std::any_of(annotation->text->begin(), annotation->text->end(),
            [](wchar_t character) { return !std::iswspace(character); });
    document_.endTextEdit(keep);
    editingTextId_.reset();
    textCaretPosition_ = 0U;
    ++interactionRevision_;
    syncHistory();
    return true;
}

bool ShapeEditorController::cancelTextEdit()
{
    if (!editingTextId_.has_value()) {
        return false;
    }
    document_.endTextEdit(false);
    editingTextId_.reset();
    textCaretPosition_ = 0U;
    ++interactionRevision_;
    syncHistory();
    return true;
}

bool ShapeEditorController::beginTextEdit(AnnotationId id) noexcept
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isTextAnnotation(*annotation)) {
        return false;
    }
    if (editingTextId_ != id) {
        commitTextEdit();
        document_.beginTextEdit();
        editingTextId_ = id;
        textCaretPosition_ = annotation->text->size();
    }
    document_.select(id);
    textOptions_.load(annotation->style);
    ++interactionRevision_;
    return true;
}

bool ShapeEditorController::applyTextStyleToSelection()
{
    const auto selected = document_.selectedId();
    const auto* annotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    if (annotation == nullptr || !isTextAnnotation(*annotation)) {
        return true;
    }
    const auto text = *annotation->text;
    const AnnotationPoint anchor{
        annotation->rect.x + textHorizontalPaddingDip,
        annotation->rect.y + annotation->rect.height / 2.0F,
    };
    const auto style = textOptions_.style();
    const auto changed = document_.updateTextGeometry(
        *selected, measuredTextRect(anchor, text, style), style);
    syncHistory();
    return changed;
}

bool ShapeEditorController::applyOptionHit(ShapeOptionHit hit)
{
    bool changed = false;
    switch (hit.control) {
    case ShapeOptionControl::strokeWidth:
        if (hit.index < shapeStrokeWidths.size()) {
            changed = options_.setStrokeWidth(shapeStrokeWidths[hit.index]);
        }
        break;
    case ShapeOptionControl::fillToggle:
        changed = options_.toggleFill();
        break;
    case ShapeOptionControl::rectangleMode:
        changed = options_.setKind(AnnotationKind::rectangle);
        strokePatternMenuVisible_ = false;
        break;
    case ShapeOptionControl::cornerRadiusDisclosure:
        changed = options_.setKind(AnnotationKind::rectangle);
        strokePatternMenuVisible_ = false;
        cornerRadiusPanelVisible_ = !cornerRadiusPanelVisible_;
        if (changed) {
            if (const auto selected = document_.selectedId(); selected.has_value()) {
                document_.updateKind(*selected, options_.kind());
            }
            syncHistory();
        }
        return true;
        break;
    case ShapeOptionControl::ellipseMode:
        changed = options_.setKind(AnnotationKind::ellipse);
        cornerRadiusPanelVisible_ = false;
        break;
    case ShapeOptionControl::strokeStyle:
        strokePatternMenuVisible_ = !strokePatternMenuVisible_;
        cornerRadiusPanelVisible_ = false;
        return true;
    case ShapeOptionControl::palette:
        changed = options_.selectPalette(hit.index);
        break;
    case ShapeOptionControl::customColor:
        return false;
    }

    if (!changed) {
        return false;
    }
    if (const auto selected = document_.selectedId(); selected.has_value()) {
        if (hit.control == ShapeOptionControl::rectangleMode
            || hit.control == ShapeOptionControl::ellipseMode) {
            document_.updateKind(*selected, options_.kind());
        } else {
            document_.updateStyle(*selected, options_.style());
        }
    }
    syncHistory();
    return true;
}

bool ShapeEditorController::applyStrokePattern(std::size_t index)
{
    const auto& shapePatterns = macShapeStrokePatterns();
    const auto& brushPatterns = macBrushStrokePatterns();
    if (brushToolActive_) {
        if (index >= brushPatterns.size()
            || !brushOptions_.setStrokePattern(brushPatterns[index])) {
            return false;
        }
        strokePatternMenuVisible_ = false;
        return true;
    }
    const auto& patterns = shapePatterns;
    if (index >= patterns.size()) {
        return false;
    }
    const auto optionChanged = arrowLineToolActive_
        ? arrowLineOptions_.setStrokePattern(patterns[index])
        : options_.setStrokePattern(patterns[index]);
    if (!optionChanged) {
        return false;
    }
    strokePatternMenuVisible_ = false;
    const auto changed = arrowLineToolActive_
        ? applyArrowOptionsToSelection()
        : applyOptionsStyleToSelection();
    syncHistory();
    return changed || !document_.selectedId().has_value();
}

bool ShapeEditorController::setCornerRadius(float cornerRadiusDip)
{
    if (!options_.setCornerRadius(cornerRadiusDip)) {
        return false;
    }
    const auto changed = applyOptionsStyleToSelection();
    syncHistory();
    return changed || !document_.selectedId().has_value();
}

bool ShapeEditorController::adjustCornerRadius(float deltaDip)
{
    if (!options_.adjustCornerRadius(deltaDip)) {
        return false;
    }
    const auto changed = applyOptionsStyleToSelection();
    syncHistory();
    return changed || !document_.selectedId().has_value();
}

bool ShapeEditorController::selectCustomColor(AnnotationColor color)
{
    const auto optionChanged = isTextToolActive()
        ? textOptions_.selectCustomColor(color)
        : markerToolActive_
        ? markerOptions_.selectCustomColor(color)
        : brushToolActive_
            ? brushOptions_.selectCustomColor(color)
            : arrowLineToolActive_
                ? arrowLineOptions_.selectCustomColor(color)
                : options_.selectCustomColor(color);
    if (!optionChanged) {
        return false;
    }
    auto changed = false;
    if (isTextToolActive()) {
        changed = applyTextStyleToSelection();
    } else if (markerToolActive_) {
        const auto selected = document_.selectedId();
        const auto* annotation = selected.has_value()
            ? document_.find(*selected) : nullptr;
        changed = annotation != nullptr && isMarkerAnnotation(*annotation)
            && document_.updateStyle(*selected, markerOptions_.style());
    } else if (arrowLineToolActive_) {
        changed = applyArrowOptionsToSelection();
    } else if (!brushToolActive_) {
        changed = applyOptionsStyleToSelection();
    }
    syncHistory();
    return changed || !document_.selectedId().has_value();
}

void ShapeEditorController::dismissPopovers() noexcept
{
    strokePatternMenuVisible_ = false;
    cornerRadiusPanelVisible_ = false;
    arrowTypeMenuEndpoint_.reset();
    textPopupMenu_.reset();
    textPopupScrollOffset_ = 0;
}

bool ShapeEditorController::pointerDown(
    AnnotationPoint point,
    bool shift) noexcept
{
    ++interactionRevision_;
    static_cast<void>(shift);
    if (interaction_.mode() != ShapeInteractionMode::idle
        || arrowInteraction_.mode() != ArrowLineInteractionMode::idle
        || brushInteraction_.active()
        || markerInteraction_.mode() != MarkerInteractionMode::idle
        || mosaicInteraction_.mode() != MosaicInteractionMode::idle) {
        return false;
    }
    if (editingTextId_.has_value()) {
        const auto* editing = document_.find(*editingTextId_);
        const auto deleteHandle = textDeleteHandlePoint(*editingTextId_);
        if (deleteHandle.has_value()
            && annotationDistanceSquared(point, *deleteHandle) <= 100.0F) {
            const auto id = *editingTextId_;
            commitTextEdit();
            const auto removed = document_.remove(id);
            syncHistory();
            return removed;
        }
        if (editing != nullptr
            && containsRect(standardized(editing->rect),
                unrotatedPoint(point, *editing))) {
            if (const auto position = textPositionAtPoint(
                    *editing, unrotatedPoint(point, *editing))) {
                textCaretPosition_ = *position;
            }
            return true;
        }
        commitTextEdit();
    }
    if (const auto selected = document_.selectedId(); selected.has_value()) {
        const auto* annotation = document_.find(*selected);
        if (annotation != nullptr && isTextAnnotation(*annotation)) {
            if (const auto handle = textDeleteHandlePoint(*selected);
                handle.has_value()
                && annotationDistanceSquared(point, *handle) <= 100.0F) {
                const auto removed = document_.remove(*selected);
                syncHistory();
                return removed;
            }
        }
        if (annotation != nullptr && annotation->arrowLine.has_value()) {
            if (const auto handle = arrowInteraction_.hitTestHandle(
                    *selected, point)) {
                return arrowInteraction_.beginEdit(*selected, *handle);
            }
        } else if (annotation != nullptr && isBrushAnnotation(*annotation)) {
            if (!brushToolActive_) {
                if (const auto handle = brushInteraction_.hitTestHandle(
                        *selected, point)) {
                    return brushInteraction_.beginRotate(*selected, *handle);
                }
            }
        } else if (annotation != nullptr && isMarkerAnnotation(*annotation)) {
            if (const auto handle = markerInteraction_.hitTestHandle(
                    *annotation, point)) {
                return markerInteraction_.beginResize(*selected, *handle);
            }
        } else if (annotation != nullptr
            && !isMosaicStrokeAnnotation(*annotation)) {
            if (interaction_.hitTestRotationHandle(*selected, point)) {
                return interaction_.beginRotation(*selected, point);
            }
            if (const auto handle = interaction_.hitTestResizeHandle(
                    *selected, point); handle.has_value()) {
                return interaction_.beginResize(*selected, *handle);
            }
        }
    }
    if (!containsRect(canvasBounds_, point)) {
        document_.clearSelection();
        return false;
    }
    if (brushToolActive_) {
        document_.clearSelection();
        return brushInteraction_.begin(point, brushOptions_.style());
    }
    if (isTextToolActive()) {
        if (const auto text = textAnnotationAt(point)) {
            if (!beginTextEdit(*text)) return false;
            const auto* annotation = document_.find(*text);
            if (annotation != nullptr) {
                if (const auto position = textPositionAtPoint(
                        *annotation, unrotatedPoint(point, *annotation))) {
                    textCaretPosition_ = *position;
                }
            }
            return true;
        }
    }
    if (const auto hit = annotationAtBorder(point); hit.has_value()) {
        document_.select(*hit);
        loadSelectedOptions();
        if (const auto* annotation = document_.find(*hit);
            annotation != nullptr && annotation->arrowLine.has_value()) {
            return arrowInteraction_.beginMove(*hit, point);
        }
        if (const auto* annotation = document_.find(*hit);
            annotation != nullptr && isBrushAnnotation(*annotation)) {
            return brushInteraction_.beginMove(*hit, point);
        }
        if (const auto* annotation = document_.find(*hit);
            annotation != nullptr && isMarkerAnnotation(*annotation)) {
            return markerInteraction_.beginMove(*hit, point);
        }
        if (const auto* annotation = document_.find(*hit);
            annotation != nullptr && isMosaicStrokeAnnotation(*annotation)) {
            return mosaicInteraction_.beginMove(*hit, point);
        }
        return interaction_.beginMove(*hit, point);
    }
    if (isMosaicToolActive()) {
        document_.clearSelection();
        if (mosaicOptions_.kind() == AnnotationKind::mosaicRectangle) {
            return interaction_.beginMosaicRectangleDrawing(
                point, mosaicOptions_.style(), mosaicOptions_.redaction());
        }
        return mosaicInteraction_.beginDrawing(
            point, mosaicOptions_.style(), mosaicOptions_.redaction());
    }
    if (isTextToolActive()) {
        document_.clearSelection();
        document_.beginTextEdit();
        const auto rect = measuredTextRect(
            point, L"", textOptions_.style());
        const auto id = document_.addText(
            rect, L"", textOptions_.style());
        if (id == invalidAnnotationId) {
            document_.endTextEdit(false);
            return false;
        }
        editingTextId_ = id;
        textCaretPosition_ = 0U;
        return true;
    }
    if (arrowLineToolActive_) {
        document_.clearSelection();
        return arrowInteraction_.beginDrawing(
            point,
            arrowLineOptions_.style(),
            arrowLineOptions_.startArrowType(),
            arrowLineOptions_.endArrowType());
    }
    if (markerToolActive_) {
        document_.clearSelection();
        return markerInteraction_.beginDrawing(point, markerOptions_.style());
    }
    if (shapeToolActive_) {
        document_.clearSelection();
        return interaction_.beginDrawing(
            options_.kind(), point, options_.style());
    }
    document_.clearSelection();
    return false;
}

void ShapeEditorController::pointerMove(
    AnnotationPoint point,
    bool shift)
{
    ++interactionRevision_;
    point = clampedPoint(point, canvasBounds_);
    if (brushInteraction_.active()) {
        brushInteraction_.update(point, shift);
    } else if (mosaicInteraction_.mode() != MosaicInteractionMode::idle) {
        mosaicInteraction_.update(point, shift);
    } else if (markerInteraction_.mode() != MarkerInteractionMode::idle) {
        markerInteraction_.update(point, shift);
    } else if (arrowInteraction_.mode() != ArrowLineInteractionMode::idle) {
        arrowInteraction_.update(point);
    } else {
        interaction_.update(point);
    }
}

bool ShapeEditorController::pointerUp(
    AnnotationPoint point,
    bool shift)
{
    if (interaction_.mode() == ShapeInteractionMode::idle
        && arrowInteraction_.mode() == ArrowLineInteractionMode::idle
        && !brushInteraction_.active()
        && markerInteraction_.mode() == MarkerInteractionMode::idle
        && mosaicInteraction_.mode() == MosaicInteractionMode::idle) {
        return false;
    }
    ++interactionRevision_;
    point = clampedPoint(point, canvasBounds_);
    if (brushInteraction_.active()) {
        brushInteraction_.update(point, shift);
        brushInteraction_.commit();
    } else if (mosaicInteraction_.mode() != MosaicInteractionMode::idle) {
        mosaicInteraction_.update(point, shift);
        mosaicInteraction_.commit();
    } else if (markerInteraction_.mode() != MarkerInteractionMode::idle) {
        markerInteraction_.update(point, shift);
        markerInteraction_.commit();
    } else if (arrowInteraction_.mode() != ArrowLineInteractionMode::idle) {
        arrowInteraction_.update(point);
        arrowInteraction_.commit();
    } else {
        interaction_.update(point);
        interaction_.commit();
    }
    loadSelectedOptions();
    syncHistory();
    return true;
}

void ShapeEditorController::cancelInteraction() noexcept
{
    ++interactionRevision_;
    interaction_.cancel();
    arrowInteraction_.cancel();
    brushInteraction_.cancel();
    markerInteraction_.cancel();
    mosaicInteraction_.cancel();
}

ShapeCursorStyle ShapeEditorController::cursorStyleAt(
    AnnotationPoint point) const noexcept
{
    if (isEyedropperToolActive()) {
        return ShapeCursorStyle::eyedropper;
    }
    switch (interaction_.mode()) {
    case ShapeInteractionMode::drawing:
        return ShapeCursorStyle::crosshair;
    case ShapeInteractionMode::moving:
        return ShapeCursorStyle::move;
    case ShapeInteractionMode::resizing:
        if (const auto handle = interaction_.activeResizeHandle()) {
            return cursorStyleForResizeHandle(*handle);
        }
        return ShapeCursorStyle::arrow;
    case ShapeInteractionMode::rotating:
        return ShapeCursorStyle::rotation;
    case ShapeInteractionMode::idle:
        break;
    }

    if (arrowInteraction_.mode() == ArrowLineInteractionMode::drawing) {
        return ShapeCursorStyle::crosshair;
    }
    if (arrowInteraction_.mode() != ArrowLineInteractionMode::idle) {
        return ShapeCursorStyle::move;
    }
    if (brushInteraction_.active()) {
        return ShapeCursorStyle::brush;
    }
    if (mosaicInteraction_.mode() == MosaicInteractionMode::drawing) {
        return ShapeCursorStyle::mosaic;
    }
    if (mosaicInteraction_.mode() == MosaicInteractionMode::moving) {
        return ShapeCursorStyle::move;
    }
    if (markerInteraction_.mode() == MarkerInteractionMode::drawing) {
        return ShapeCursorStyle::marker;
    }
    if (markerInteraction_.mode() == MarkerInteractionMode::resizing) {
        return ShapeCursorStyle::resizeUpDown;
    }
    if (markerInteraction_.mode() == MarkerInteractionMode::moving) {
        return ShapeCursorStyle::move;
    }

    if (const auto selected = document_.selectedId(); selected.has_value()) {
        const auto* annotation = document_.find(*selected);
        if (annotation != nullptr && annotation->arrowLine.has_value()) {
            if (arrowInteraction_.hitTestHandle(*selected, point)) {
                return ShapeCursorStyle::move;
            }
        } else if (annotation != nullptr && isBrushAnnotation(*annotation)) {
            if (brushInteraction_.hitTestHandle(*selected, point)) {
                return ShapeCursorStyle::rotation;
            }
        } else if (annotation != nullptr && isMarkerAnnotation(*annotation)) {
            if (markerInteraction_.hitTestHandle(*annotation, point)) {
                return ShapeCursorStyle::resizeUpDown;
            }
        } else if (annotation != nullptr
            && !isMosaicStrokeAnnotation(*annotation)) {
            if (interaction_.hitTestRotationHandle(*selected, point)) {
                return ShapeCursorStyle::rotation;
            }
            if (const auto handle = interaction_.hitTestResizeHandle(
                    *selected, point)) {
                return cursorStyleForResizeHandle(*handle);
            }
        }
    }
    if (annotationAtBorder(point).has_value()) {
        return ShapeCursorStyle::move;
    }
    if (const auto selected = document_.selectedId(); selected.has_value()) {
        if (const auto handle = textDeleteHandlePoint(*selected);
            handle.has_value()
            && annotationDistanceSquared(point, *handle) <= 100.0F) {
            return ShapeCursorStyle::arrow;
        }
    }
    if (isTextToolActive() && textAnnotationAt(point).has_value()) {
        return ShapeCursorStyle::textInput;
    }
    if (brushToolActive_) {
        return ShapeCursorStyle::brush;
    }
    if (markerToolActive_) {
        return ShapeCursorStyle::marker;
    }
    if (isMosaicToolActive()) {
        return mosaicOptions_.kind() == AnnotationKind::mosaicStroke
            ? ShapeCursorStyle::mosaic : ShapeCursorStyle::crosshair;
    }
    return shapeToolActive_ || arrowLineToolActive_ || isTextToolActive()
        ? ShapeCursorStyle::crosshair : ShapeCursorStyle::arrow;
}

ShapeEditorKeyResult ShapeEditorController::handleKey(
    ShapeEditorKey key,
    bool control,
    bool shift)
{
    if (editingTextId_.has_value()) {
        if (key == ShapeEditorKey::escapeKey) {
            cancelTextEdit();
            return ShapeEditorKeyResult::consumed;
        }
        if (!control && key == ShapeEditorKey::backspace) {
            deleteTextBackward();
            return ShapeEditorKeyResult::consumed;
        }
        if (!control && key == ShapeEditorKey::deleteKey) {
            deleteTextForward();
            return ShapeEditorKeyResult::consumed;
        }
        if (!control && key == ShapeEditorKey::enter) {
            insertText(L"\n");
            return ShapeEditorKeyResult::consumed;
        }
        const auto* annotation = document_.find(*editingTextId_);
        const auto textLength = annotation != nullptr && annotation->text.has_value()
            ? annotation->text->size() : 0U;
        if (!control && key == ShapeEditorKey::left) {
            if (textCaretPosition_ > 0U) {
                --textCaretPosition_;
                if (annotation != nullptr && textCaretPosition_ > 0U
                    && (*annotation->text)[textCaretPosition_] >= 0xDC00
                    && (*annotation->text)[textCaretPosition_] <= 0xDFFF) {
                    --textCaretPosition_;
                }
            }
            ++interactionRevision_;
            return ShapeEditorKeyResult::consumed;
        }
        if (!control && key == ShapeEditorKey::right) {
            if (textCaretPosition_ < textLength) {
                if (annotation != nullptr
                    && (*annotation->text)[textCaretPosition_] >= 0xD800
                    && (*annotation->text)[textCaretPosition_] <= 0xDBFF
                    && textCaretPosition_ + 1U < textLength) {
                    ++textCaretPosition_;
                }
                ++textCaretPosition_;
            }
            ++interactionRevision_;
            return ShapeEditorKeyResult::consumed;
        }
        if (!control && key == ShapeEditorKey::home) {
            const std::wstring text = annotation != nullptr
                ? *annotation->text : std::wstring{};
            const auto newline = text.rfind(L'\n',
                textCaretPosition_ == 0U ? 0U : textCaretPosition_ - 1U);
            textCaretPosition_ = newline == std::wstring::npos
                ? 0U : newline + 1U;
            ++interactionRevision_;
            return ShapeEditorKeyResult::consumed;
        }
        if (!control && key == ShapeEditorKey::end) {
            const std::wstring text = annotation != nullptr
                ? *annotation->text : std::wstring{};
            const auto newline = text.find(L'\n', textCaretPosition_);
            textCaretPosition_ = newline == std::wstring::npos
                ? text.size() : newline;
            ++interactionRevision_;
            return ShapeEditorKeyResult::consumed;
        }
    }
    if (!control && key == ShapeEditorKey::eyedropper) {
        handleToolbarAction(ToolbarAction::eyedropper);
        return ShapeEditorKeyResult::consumed;
    }
    if (!control && key == ShapeEditorKey::mosaic) {
        handleToolbarAction(ToolbarAction::mosaic);
        return ShapeEditorKeyResult::consumed;
    }
    if (!control && key == ShapeEditorKey::text) {
        handleToolbarAction(ToolbarAction::text);
        return ShapeEditorKeyResult::consumed;
    }
    if (key == ShapeEditorKey::escapeKey) {
        if (interaction_.mode() != ShapeInteractionMode::idle
            || arrowInteraction_.mode() != ArrowLineInteractionMode::idle
            || brushInteraction_.active()
            || markerInteraction_.mode() != MarkerInteractionMode::idle
            || mosaicInteraction_.mode() != MosaicInteractionMode::idle) {
            cancelInteraction();
            return ShapeEditorKeyResult::consumed;
        }
        if (shapeToolActive_ || arrowLineToolActive_ || brushToolActive_
            || markerToolActive_ || isMosaicToolActive()
            || isTextToolActive() || isEyedropperToolActive()) {
            deactivateTool();
            return ShapeEditorKeyResult::consumed;
        }
        return ShapeEditorKeyResult::requestCancel;
    }
    if (key == ShapeEditorKey::deleteKey) {
        const auto selected = document_.selectedId();
        if (!selected.has_value() || !document_.remove(*selected)) {
            return ShapeEditorKeyResult::ignored;
        }
        syncHistory();
        return ShapeEditorKeyResult::consumed;
    }
    if (control && key == ShapeEditorKey::z) {
        const auto changed = shift ? document_.redo() : document_.undo();
        if (changed) {
            loadSelectedOptions();
            syncHistory();
        }
        return changed
            ? ShapeEditorKeyResult::consumed
            : ShapeEditorKeyResult::ignored;
    }
    if (control && !shift && key == ShapeEditorKey::copy) {
        return ShapeEditorKeyResult::requestCopy;
    }
    if (control && !shift && key == ShapeEditorKey::save) {
        return ShapeEditorKeyResult::requestSave;
    }
    return ShapeEditorKeyResult::ignored;
}

std::optional<AnnotationPoint> ShapeEditorController::resizeHandlePoint(
    AnnotationId id,
    ShapeResizeHandle handle) const noexcept
{
    return interaction_.resizeHandlePoint(id, handle);
}

std::optional<AnnotationPoint> ShapeEditorController::rotationHandlePoint(
    AnnotationId id) const noexcept
{
    return interaction_.rotationHandlePoint(id);
}

std::optional<AnnotationPoint> ShapeEditorController::textDeleteHandlePoint(
    AnnotationId id) const noexcept
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isTextAnnotation(*annotation)) {
        return std::nullopt;
    }
    return interaction_.resizeHandlePoint(id, ShapeResizeHandle::topRight);
}

AnnotationRenderPlan ShapeEditorController::renderPlan(
    AnnotationPoint selectionOriginDip,
    bool showEditingAffordances) const
{
    return buildAnnotationRenderPlan(
        document_, preview(), selectionOriginDip,
        showEditingAffordances, editingTextId_, textCaretPosition_);
}

std::optional<AnnotationId> ShapeEditorController::annotationAtBorder(
    AnnotationPoint point) const noexcept
{
    const auto& annotations = document_.annotations();
    for (auto iterator = annotations.rbegin(); iterator != annotations.rend(); ++iterator) {
        bool contains = false;
        if (isArrowLineAnnotation(*iterator)) {
            contains = arrowInteraction_.hitTestLine(iterator->id, point);
        } else if (isBrushAnnotation(*iterator)) {
            contains = brushInteraction_.hitTestPath(iterator->id, point);
        } else if (isMarkerAnnotation(*iterator)) {
            contains = markerInteraction_.hitTestLine(*iterator, point);
        } else if (isMosaicStrokeAnnotation(*iterator)) {
            contains = mosaicInteraction_.hitTestStroke(iterator->id, point);
        } else {
            contains = shapeBorderContains(*iterator, point);
        }
        if (contains) {
            return iterator->id;
        }
    }
    return std::nullopt;
}

std::optional<AnnotationId> ShapeEditorController::textAnnotationAt(
    AnnotationPoint point) const noexcept
{
    const auto& annotations = document_.annotations();
    for (auto iterator = annotations.rbegin(); iterator != annotations.rend();
         ++iterator) {
        if (!isTextAnnotation(*iterator)) {
            continue;
        }
        const auto local = unrotatedPoint(point, *iterator);
        const auto rect = standardized(iterator->rect);
        constexpr float border = 6.0F;
        const AnnotationRect interior{
            rect.x + border,
            rect.y + border,
            maximum(0.0F, rect.width - border * 2.0F),
            maximum(0.0F, rect.height - border * 2.0F),
        };
        if (containsRect(interior, local)) {
            return iterator->id;
        }
    }
    return std::nullopt;
}

void ShapeEditorController::loadSelectedOptions() noexcept
{
    const auto selected = document_.selectedId();
    if (!selected.has_value()) {
        return;
    }
    if (const auto* annotation = document_.find(*selected)) {
        if (isArrowLineAnnotation(*annotation)) {
            arrowLineOptions_.load(annotation->style, *annotation->arrowLine);
        } else if (isBrushAnnotation(*annotation)) {
            brushOptions_.load(annotation->style);
        } else if (isMarkerAnnotation(*annotation)) {
            markerOptions_.load(annotation->style);
        } else if (isMosaicAnnotation(*annotation)) {
            mosaicOptions_.load(*annotation);
        } else if (isTextAnnotation(*annotation)) {
            textOptions_.load(annotation->style);
        } else {
            options_.load(annotation->kind, annotation->style);
        }
    }
}

bool ShapeEditorController::applyOptionsStyleToSelection()
{
    const auto selected = document_.selectedId();
    return selected.has_value()
        && document_.updateStyle(*selected, options_.style());
}

bool ShapeEditorController::applyArrowOptionsToSelection()
{
    const auto selected = document_.selectedId();
    if (!selected.has_value()) {
        return false;
    }
    const auto* annotation = document_.find(*selected);
    if (annotation == nullptr || !isArrowLineAnnotation(*annotation)) {
        return false;
    }
    auto line = *annotation->arrowLine;
    line.startArrowType = arrowLineOptions_.startArrowType();
    line.endArrowType = arrowLineOptions_.endArrowType();
    const auto lineChanged = document_.updateArrowLine(*selected, line);
    const auto styleChanged = document_.updateStyle(
        *selected, arrowLineOptions_.style());
    return lineChanged || styleChanged;
}

void ShapeEditorController::syncHistory() noexcept
{
    toolbarState_.setHistoryAvailability(
        document_.canUndo(), document_.canRedo());
}

void ShapeEditorController::deactivateTool()
{
    if (editingTextId_.has_value()) {
        commitTextEdit();
    }
    cancelInteraction();
    shapeToolActive_ = false;
    arrowLineToolActive_ = false;
    brushToolActive_ = false;
    markerToolActive_ = false;
    toolbarState_.clearSelectedTool();
    strokePatternMenuVisible_ = false;
    cornerRadiusPanelVisible_ = false;
    arrowTypeMenuEndpoint_.reset();
    textPopupMenu_.reset();
    textPopupScrollOffset_ = 0;
}

} // namespace xxsnap::win
