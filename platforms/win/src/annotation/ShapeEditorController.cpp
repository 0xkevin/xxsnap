#include "annotation/ShapeEditorController.h"
#include "annotation/NumberAnnotationRenderer.h"
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

AnnotationRect outsetRect(AnnotationRect rect, float amount) noexcept
{
    rect = standardized(rect);
    return {rect.x - amount, rect.y - amount,
        rect.width + amount * 2.0F, rect.height + amount * 2.0F};
}

bool rotatedRectIntersects(
    const ShapeAnnotation& annotation,
    AnnotationRect target) noexcept
{
    target = standardized(target);
    auto source = standardized(annotation.rect);
    const auto padding = (isArrowLineAnnotation(annotation)
            || isBrushAnnotation(annotation)
            || isMarkerAnnotation(annotation)
            || isMosaicStrokeAnnotation(annotation))
        ? annotation.style.strokeWidthDip / 2.0F : 0.0F;
    source = outsetRect(source, padding);
    const AnnotationPoint center{
        source.x + source.width / 2.0F,
        source.y + source.height / 2.0F,
    };
    const auto radians = annotation.rotationDegrees * degreesToRadians;
    const auto sine = approximateSine(radians);
    const auto cosine = approximateCosine(radians);
    auto corners = std::array<AnnotationPoint, 4>{
        AnnotationPoint{source.x, source.y},
        AnnotationPoint{source.x + source.width, source.y},
        AnnotationPoint{source.x + source.width, source.y + source.height},
        AnnotationPoint{source.x, source.y + source.height},
    };
    for (auto& corner : corners) {
        const auto dx = corner.x - center.x;
        const auto dy = corner.y - center.y;
        corner = {center.x + dx * cosine - dy * sine,
            center.y + dx * sine + dy * cosine};
    }
    const auto separatedOn = [&](AnnotationPoint axis) {
        auto polygonMin = corners[0].x * axis.x + corners[0].y * axis.y;
        auto polygonMax = polygonMin;
        for (std::size_t index = 1; index < corners.size(); ++index) {
            const auto value = corners[index].x * axis.x
                + corners[index].y * axis.y;
            polygonMin = minimum(polygonMin, value);
            polygonMax = maximum(polygonMax, value);
        }
        const std::array<AnnotationPoint, 4> targetCorners{
            AnnotationPoint{target.x, target.y},
            AnnotationPoint{target.x + target.width, target.y},
            AnnotationPoint{target.x + target.width, target.y + target.height},
            AnnotationPoint{target.x, target.y + target.height},
        };
        auto targetMin = targetCorners[0].x * axis.x
            + targetCorners[0].y * axis.y;
        auto targetMax = targetMin;
        for (std::size_t index = 1; index < targetCorners.size(); ++index) {
            const auto value = targetCorners[index].x * axis.x
                + targetCorners[index].y * axis.y;
            targetMin = minimum(targetMin, value);
            targetMax = maximum(targetMax, value);
        }
        return polygonMax < targetMin || targetMax < polygonMin;
    };
    if (separatedOn({1.0F, 0.0F}) || separatedOn({0.0F, 1.0F})) {
        return false;
    }
    for (std::size_t index = 0; index < corners.size(); ++index) {
        const auto edge = AnnotationPoint{
            corners[(index + 1U) % corners.size()].x - corners[index].x,
            corners[(index + 1U) % corners.size()].y - corners[index].y,
        };
        if (separatedOn({-edge.y, edge.x})) return false;
    }
    return true;
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
    toolbarState_.setCapability(ToolbarAction::number, true);
    toolbarState_.setCapability(ToolbarAction::magnifier, true);
    toolbarState_.setCapability(ToolbarAction::eraser, true);
    toolbarState_.setCapability(ToolbarAction::scroll, true);
    toolbarState_.setCapability(ToolbarAction::undo, true);
    toolbarState_.setCapability(ToolbarAction::redo, true);
    toolbarState_.setCapability(ToolbarAction::pin, true);
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

void ShapeEditorController::setTeachingPenMode(bool enabled) noexcept
{
    teachingPenMode_ = enabled;
    if (!enabled) return;
    options_.setCornerRadius(0.0F);
    if (textOptions_.style().textOutlineEnabled) {
        textOptions_.toggleOutline();
    }
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

const NumberOptionsState& ShapeEditorController::numberOptions() const noexcept
{
    return numberOptions_;
}

const MagnifierOptionsState&
ShapeEditorController::magnifierOptions() const noexcept
{
    return magnifierOptions_;
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

bool ShapeEditorController::isNumberToolActive() const noexcept
{
    return toolbarState_.selectedAction() == ToolbarAction::number;
}

bool ShapeEditorController::isMagnifierToolActive() const noexcept
{
    return toolbarState_.selectedAction() == ToolbarAction::magnifier;
}

bool ShapeEditorController::isEraserToolActive() const noexcept
{
    return toolbarState_.selectedAction() == ToolbarAction::eraser;
}

EraserMode ShapeEditorController::eraserMode() const noexcept
{
    return eraserMode_;
}

std::optional<AnnotationRect>
ShapeEditorController::eraserRectanglePreview() const noexcept
{
    if (!eraserRectangleStart_.has_value()
        || !eraserRectangleCurrent_.has_value()) {
        return std::nullopt;
    }
    return standardized({
        eraserRectangleStart_->x,
        eraserRectangleStart_->y,
        eraserRectangleCurrent_->x - eraserRectangleStart_->x,
        eraserRectangleCurrent_->y - eraserRectangleStart_->y,
    });
}

int ShapeEditorController::nextNumberSequenceValue() const noexcept
{
    return nextNumberValue(currentNumberGroupId_);
}

bool ShapeEditorController::isEditingInlineValue() const noexcept
{
    return editingTextId_.has_value() || editingNumberId_.has_value();
}

bool ShapeEditorController::isEditingNumber() const noexcept
{
    return editingNumberId_.has_value();
}

std::optional<TextPopupMenu>
ShapeEditorController::textPopupMenu() const noexcept
{
    return textPopupMenu_;
}

int ShapeEditorController::popupScrollOffset() const noexcept
{
    return popupScrollOffset_;
}

std::optional<NumberPopupMenu>
ShapeEditorController::numberPopupMenu() const noexcept
{
    return numberPopupMenu_;
}

bool ShapeEditorController::magnifierZoomMenuVisible() const noexcept
{
    return magnifierZoomMenuVisible_;
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
    if (action != ToolbarAction::number && editingNumberId_.has_value()) {
        commitNumberEdit();
    }
    if (action == ToolbarAction::clearAll) {
        return applyEraserOptionHit({EraserOptionControl::clearAll});
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
                if (teachingPenMode_) {
                    activated.setCornerRadius(0.0F);
                }
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
                if (teachingPenMode_
                    && activated.style().textOutlineEnabled) {
                    activated.toggleOutline();
                }
                textOptions_ = std::move(activated);
                document_.clearSelection();
                dismissPopovers();
            }
        }
        return true;
    }
    if (action == ToolbarAction::number) {
        if (isNumberToolActive()) {
            commitNumberEdit();
            deactivateTool();
        } else {
            cancelInteraction();
            shapeToolActive_ = false;
            arrowLineToolActive_ = false;
            brushToolActive_ = false;
            markerToolActive_ = false;
            if (toolbarState_.selectTool(action)) {
                NumberOptionsState activated;
                numberOptions_ = activated;
                currentNumberGroupId_ = nextNumberGroupId_++;
                numberTypeFollowerId_.reset();
                document_.clearSelection();
                dismissPopovers();
            }
        }
        return true;
    }
    if (action == ToolbarAction::magnifier) {
        return toggleStatelessTool(action);
    }
    if (action == ToolbarAction::eraser) {
        return toggleStatelessTool(action);
    }
    if (action == ToolbarAction::eyedropper) {
        return toggleStatelessTool(action);
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

bool ShapeEditorController::applyNumberOptionHit(NumberOptionHit hit)
{
    if (hit.control != NumberOptionControl::palette) {
        return false;
    }
    const auto changed = numberOptions_.selectPalette(hit.index);
    return changed && applyNumberStyleToSelection();
}

bool ShapeEditorController::applyMagnifierOptionHit(
    MagnifierOptionHit hit)
{
    bool changed = false;
    switch (hit.control) {
    case MagnifierOptionControl::strokeWidth: {
        const auto& widths = macMagnifierStrokeWidths();
        changed = hit.index < widths.size()
            && magnifierOptions_.setStrokeWidth(widths[hit.index]);
        break;
    }
    case MagnifierOptionControl::rectangleMode:
        changed = magnifierOptions_.setShape(MagnifierShape::rectangle);
        break;
    case MagnifierOptionControl::circleMode:
        changed = magnifierOptions_.setShape(MagnifierShape::circle);
        break;
    case MagnifierOptionControl::zoom:
        magnifierZoomMenuVisible_ = !magnifierZoomMenuVisible_;
        textPopupMenu_.reset();
        numberPopupMenu_.reset();
        return true;
    case MagnifierOptionControl::palette:
        changed = magnifierOptions_.selectPalette(hit.index);
        break;
    case MagnifierOptionControl::customColor:
        return false;
    }
    magnifierZoomMenuVisible_ = false;
    if (!changed) {
        return false;
    }
    const auto selected = document_.selectedId();
    const auto applied = applyMagnifierOptionsToSelection();
    if (applied) {
        syncHistory();
    }
    return applied || !selected.has_value();
}

bool ShapeEditorController::applyEraserOptionHit(EraserOptionHit hit)
{
    switch (hit.control) {
    case EraserOptionControl::pointMode:
        eraserMode_ = EraserMode::point;
        cancelInteraction();
        return true;
    case EraserOptionControl::rectangleMode:
        eraserMode_ = EraserMode::rectangle;
        cancelInteraction();
        return true;
    case EraserOptionControl::clearAll: {
        cancelInteraction();
        const auto changed = document_.clearAnnotationsAndMasks();
        syncHistory();
        return changed;
    }
    }
    return false;
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
    numberPopupMenu_.reset();
    magnifierZoomMenuVisible_ = false;
    popupScrollOffset_ = 0;
    strokePatternMenuVisible_ = false;
    cornerRadiusPanelVisible_ = false;
    arrowTypeMenuEndpoint_.reset();
    return true;
}

bool ShapeEditorController::scrollPopupMenu(int delta) noexcept
{
    if ((!textPopupMenu_.has_value() && !numberPopupMenu_.has_value())
        || delta == 0) return false;
    popupScrollOffset_ = (std::max)(-10000,
        (std::min)(10000, popupScrollOffset_ + delta));
    return true;
}

bool ShapeEditorController::toggleNumberPopupMenu(
    NumberPopupMenu menu) noexcept
{
    numberPopupMenu_ = numberPopupMenu_ == menu
        ? std::nullopt : std::optional<NumberPopupMenu>{menu};
    popupScrollOffset_ = 0;
    textPopupMenu_.reset();
    magnifierZoomMenuVisible_ = false;
    strokePatternMenuVisible_ = false;
    cornerRadiusPanelVisible_ = false;
    arrowTypeMenuEndpoint_.reset();
    return true;
}

bool ShapeEditorController::selectNumberType(NumberMarkType type)
{
    const auto optionChanged = numberOptions_.setType(type);
    const auto selected = document_.selectedId();
    const auto* annotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    if (annotation == nullptr || !isNumberAnnotation(*annotation)
        || numberTypeFollowerId_ != selected) {
        numberPopupMenu_.reset();
        return optionChanged;
    }
    const auto oldGroup = annotation->numberSequenceGroupId;
    const auto wasAutomatic = annotation->numberMarkType
        == NumberMarkType::number && !annotation->numberSequenceIsManual;
    document_.beginNumberEdit();
    bool changed = false;
    if (type == NumberMarkType::number) {
        if (currentNumberGroupId_ == 0) {
            currentNumberGroupId_ = nextNumberGroupId_++;
        }
        const auto manual = numberGroupIsManual(currentNumberGroupId_);
        changed = document_.updateNumberMark(
            *selected, type, nextNumberValue(currentNumberGroupId_), manual,
            currentNumberGroupId_);
    } else {
        changed = document_.updateNumberMark(
            *selected, type, std::nullopt, false, 0);
        if (wasAutomatic && oldGroup != 0) {
            renumberAutomaticGroup(oldGroup);
        }
    }
    changed = applyNumberStyleToSelection() || changed;
    document_.endNumberEdit(true);
    numberPopupMenu_.reset();
    syncHistory();
    return optionChanged || changed;
}

bool ShapeEditorController::setNumberSize(float size)
{
    const auto changed = numberOptions_.setSize(size);
    numberPopupMenu_.reset();
    return changed && applyNumberStyleToSelection();
}

bool ShapeEditorController::selectMagnifierZoom(float zoom)
{
    const auto changed = magnifierOptions_.setZoom(zoom);
    magnifierZoomMenuVisible_ = false;
    if (!changed) {
        return false;
    }
    const auto selected = document_.selectedId();
    const auto applied = applyMagnifierOptionsToSelection();
    if (applied) {
        syncHistory();
    }
    return applied || !selected.has_value();
}

bool ShapeEditorController::insertText(std::wstring text)
{
    if (editingNumberId_.has_value()) {
        text.erase(std::remove_if(text.begin(), text.end(),
            [](wchar_t character) {
                return character < L'0' || character > L'9';
            }), text.end());
        if (text.empty()) return false;
        return replaceEditingNumber(
            numberCaretPosition_, 0U, std::move(text));
    }
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
    if (editingNumberId_.has_value()) {
        if (numberCaretPosition_ == 0U) return false;
        return replaceEditingNumber(
            numberCaretPosition_ - 1U, 1U, L"");
    }
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
    if (editingNumberId_.has_value()) {
        if (numberCaretPosition_ >= numberEditBuffer_.size()) return false;
        return replaceEditingNumber(numberCaretPosition_, 1U, L"");
    }
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
    const auto selected = document_.selectedId();
    const auto* selectedAnnotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    if (completedAnnotationsLocked_
        && (selectedAnnotation == nullptr
            || !canEditCompletedAnnotation(*selectedAnnotation))) {
        document_.clearSelection();
    }
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

bool ShapeEditorController::commitNumberEdit()
{
    if (!editingNumberId_.has_value()) return false;
    const auto id = *editingNumberId_;
    const auto* annotation = document_.find(id);
    if (annotation != nullptr && isNumberAnnotation(*annotation)
        && numberEditBuffer_.empty()) {
        markNumberGroupManual(annotation->numberSequenceGroupId);
        document_.updateNumberMark(id, NumberMarkType::number, 1, true,
            annotation->numberSequenceGroupId);
    }
    document_.endNumberEdit(true);
    editingNumberId_.reset();
    numberEditBuffer_.clear();
    numberCaretPosition_ = 0U;
    if (completedAnnotationsLocked_) document_.clearSelection();
    ++interactionRevision_;
    syncHistory();
    return true;
}

bool ShapeEditorController::cancelNumberEdit()
{
    if (!editingNumberId_.has_value()) return false;
    document_.endNumberEdit(false);
    editingNumberId_.reset();
    numberEditBuffer_.clear();
    numberCaretPosition_ = 0U;
    ++interactionRevision_;
    syncHistory();
    return true;
}

bool ShapeEditorController::replaceEditingNumber(
    std::size_t start,
    std::size_t length,
    std::wstring replacement)
{
    if (!editingNumberId_.has_value()) return false;
    if (std::any_of(replacement.begin(), replacement.end(),
            [](wchar_t character) {
                return character < L'0' || character > L'9';
            })) {
        return false;
    }
    start = (std::min)(start, numberEditBuffer_.size());
    length = (std::min)(length, numberEditBuffer_.size() - start);
    if (numberEditBuffer_.size() - length + replacement.size() > 3U) {
        return false;
    }
    auto updated = numberEditBuffer_;
    updated.replace(start, length, replacement);
    if (updated == numberEditBuffer_) return false;
    const auto id = *editingNumberId_;
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isNumberAnnotation(*annotation)
        || annotation->numberMarkType != NumberMarkType::number) {
        return false;
    }
    const auto groupId = annotation->numberSequenceGroupId;
    numberEditBuffer_ = std::move(updated);
    numberCaretPosition_ = start + replacement.size();
    if (!annotation->numberSequenceIsManual) {
        markNumberGroupManual(groupId);
    }
    if (!numberEditBuffer_.empty()) {
        auto value = 0;
        for (const auto digit : numberEditBuffer_) {
            value = value * 10 + static_cast<int>(digit - L'0');
        }
        value = clampedNumberValue(value);
        numberEditBuffer_ = std::to_wstring(value);
        numberCaretPosition_ = (std::min)(
            numberCaretPosition_, numberEditBuffer_.size());
        document_.updateNumberMark(
            id, NumberMarkType::number, value, true, groupId);
    }
    ++interactionRevision_;
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

bool ShapeEditorController::beginNumberEdit(AnnotationId id) noexcept
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isNumberAnnotation(*annotation)
        || annotation->numberMarkType != NumberMarkType::number) {
        return false;
    }
    if (editingNumberId_ != id) {
        commitNumberEdit();
        document_.beginNumberEdit();
        editingNumberId_ = id;
        numberEditBuffer_ = std::to_wstring(clampedNumberValue(
            annotation->numberSequenceIndex.value_or(1)));
        numberCaretPosition_ = numberEditBuffer_.size();
    }
    document_.select(id);
    numberOptions_.load(*annotation);
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

bool ShapeEditorController::applyNumberStyleToSelection()
{
    const auto selected = document_.selectedId();
    const auto* annotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    if (annotation == nullptr || !isNumberAnnotation(*annotation)) {
        return true;
    }
    const auto rect = standardized(annotation->rect);
    const AnnotationPoint center{
        rect.x + rect.width / 2.0F,
        rect.y + rect.height / 2.0F,
    };
    const auto changed = document_.updateNumberGeometry(
        *selected,
        numberMarkRect(center, numberOptions_.style().textSize),
        numberOptions_.style());
    syncHistory();
    return changed;
}

void ShapeEditorController::markNumberGroupManual(std::uint64_t groupId)
{
    if (groupId == 0) return;
    std::vector<AnnotationId> ids;
    for (const auto& annotation : document_.annotations()) {
        if (isNumberAnnotation(annotation)
            && annotation.numberMarkType == NumberMarkType::number
            && annotation.numberSequenceGroupId == groupId) {
            ids.push_back(annotation.id);
        }
    }
    for (const auto id : ids) {
        const auto* annotation = document_.find(id);
        if (annotation != nullptr) {
            document_.updateNumberMark(id, NumberMarkType::number,
                annotation->numberSequenceIndex, true, groupId);
        }
    }
}

bool ShapeEditorController::numberGroupIsManual(
    std::uint64_t groupId) const noexcept
{
    return groupId != 0 && std::any_of(
        document_.annotations().begin(), document_.annotations().end(),
        [groupId](const auto& annotation) {
            return isNumberAnnotation(annotation)
                && annotation.numberMarkType == NumberMarkType::number
                && annotation.numberSequenceGroupId == groupId
                && annotation.numberSequenceIsManual;
        });
}

void ShapeEditorController::renumberAutomaticGroup(std::uint64_t groupId)
{
    if (groupId == 0) return;
    int value = numberMinimumValue;
    std::vector<AnnotationId> ids;
    for (const auto& annotation : document_.annotations()) {
        if (isNumberAnnotation(annotation)
            && annotation.numberMarkType == NumberMarkType::number
            && annotation.numberSequenceGroupId == groupId
            && !annotation.numberSequenceIsManual) {
            ids.push_back(annotation.id);
        }
    }
    for (const auto id : ids) {
        document_.updateNumberMark(
            id, NumberMarkType::number, value++, false, groupId);
    }
}

int ShapeEditorController::nextNumberValue(
    std::uint64_t groupId) const noexcept
{
    int maximumValue = 0;
    for (const auto& annotation : document_.annotations()) {
        if (isNumberAnnotation(annotation)
            && annotation.numberMarkType == NumberMarkType::number
            && annotation.numberSequenceGroupId == groupId) {
            maximumValue = (std::max)(maximumValue,
                annotation.numberSequenceIndex.value_or(0));
        }
    }
    return clampedNumberValue(maximumValue + 1);
}

bool ShapeEditorController::removeNumberAndRenumber(AnnotationId id)
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !isNumberAnnotation(*annotation)) {
        return false;
    }
    const auto groupId = annotation->numberSequenceGroupId;
    const auto automatic = annotation->numberMarkType == NumberMarkType::number
        && !numberGroupIsManual(groupId);
    document_.beginNumberEdit();
    const auto removed = document_.remove(id);
    if (removed && automatic) renumberAutomaticGroup(groupId);
    document_.endNumberEdit(true);
    syncHistory();
    return removed;
}

bool ShapeEditorController::adjustSelectedNumber(int delta)
{
    const auto selected = document_.selectedId();
    const auto* selectedAnnotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    if (selectedAnnotation == nullptr
        || selectedAnnotation->numberMarkType != NumberMarkType::number) {
        return false;
    }
    const auto current = selectedAnnotation->numberSequenceIndex.value_or(1);
    const auto candidate = clampedNumberValue(current + delta);
    if (candidate == current) return false;
    const auto groupId = selectedAnnotation->numberSequenceGroupId;
    const auto manual = numberGroupIsManual(groupId);
    std::optional<AnnotationId> collision;
    for (const auto& annotation : document_.annotations()) {
        if (annotation.id != *selected
            && isNumberAnnotation(annotation)
            && annotation.numberMarkType == NumberMarkType::number
            && annotation.numberSequenceGroupId == groupId
            && annotation.numberSequenceIndex == candidate) {
            collision = annotation.id;
            break;
        }
    }
    if (!manual && !collision.has_value()) return false;
    document_.beginNumberEdit();
    if (collision.has_value()) {
        document_.updateNumberMark(*collision, NumberMarkType::number,
            current, manual, groupId);
    }
    document_.updateNumberMark(*selected, NumberMarkType::number,
        candidate, manual, groupId);
    document_.endNumberEdit(true);
    syncHistory();
    ++interactionRevision_;
    return true;
}

bool ShapeEditorController::resetSelectedNumber()
{
    const auto selected = document_.selectedId();
    const auto* annotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    if (annotation == nullptr
        || annotation->numberMarkType != NumberMarkType::number
        || annotation->numberSequenceIndex.value_or(1) <= 1) {
        return false;
    }
    const auto oldGroup = annotation->numberSequenceGroupId;
    const auto automatic = !numberGroupIsManual(oldGroup);
    const auto newGroup = nextNumberGroupId_++;
    document_.beginNumberEdit();
    document_.updateNumberMark(*selected, NumberMarkType::number,
        1, false, newGroup);
    if (automatic) renumberAutomaticGroup(oldGroup);
    document_.endNumberEdit(true);
    currentNumberGroupId_ = newGroup;
    syncHistory();
    ++interactionRevision_;
    return true;
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
    const auto activeAction = toolbarState_.selectedAction().value_or(
        ToolbarAction::rectangle);
    bool optionChanged = false;
    switch (activeAction) {
    case ToolbarAction::polyline:
        optionChanged = arrowLineOptions_.selectCustomColor(color);
        break;
    case ToolbarAction::pen:
        optionChanged = brushOptions_.selectCustomColor(color);
        break;
    case ToolbarAction::marker:
        optionChanged = markerOptions_.selectCustomColor(color);
        break;
    case ToolbarAction::text:
        optionChanged = textOptions_.selectCustomColor(color);
        break;
    case ToolbarAction::number:
        optionChanged = numberOptions_.selectCustomColor(color);
        break;
    case ToolbarAction::magnifier:
        optionChanged = magnifierOptions_.selectCustomColor(color);
        break;
    default:
        optionChanged = options_.selectCustomColor(color);
        break;
    }
    if (!optionChanged) {
        return false;
    }
    auto changed = false;
    switch (activeAction) {
    case ToolbarAction::magnifier:
        changed = applyMagnifierOptionsToSelection();
        break;
    case ToolbarAction::number:
        changed = applyNumberStyleToSelection();
        break;
    case ToolbarAction::text:
        changed = applyTextStyleToSelection();
        break;
    case ToolbarAction::marker: {
        const auto selected = document_.selectedId();
        const auto* annotation = selected.has_value()
            ? document_.find(*selected) : nullptr;
        changed = annotation != nullptr && isMarkerAnnotation(*annotation)
            && document_.updateStyle(*selected, markerOptions_.style());
        break;
    }
    case ToolbarAction::polyline:
        changed = applyArrowOptionsToSelection();
        break;
    case ToolbarAction::pen:
        break;
    default:
        changed = applyOptionsStyleToSelection();
        break;
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
    popupScrollOffset_ = 0;
    numberPopupMenu_.reset();
    magnifierZoomMenuVisible_ = false;
}

void ShapeEditorController::setCompletedAnnotationsLocked(bool enabled) noexcept
{
    completedAnnotationsLocked_ = enabled;
    const auto selected = document_.selectedId();
    const auto* annotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    if (enabled && !editingTextId_.has_value()
        && !editingNumberId_.has_value()
        && (annotation == nullptr
            || !canEditCompletedAnnotation(*annotation))) {
        document_.clearSelection();
    }
}

bool ShapeEditorController::canEditCompletedAnnotation(
    const ShapeAnnotation& annotation) const noexcept
{
    return !completedAnnotationsLocked_
        || isArrowLineAnnotation(annotation)
        || isShapeKind(annotation.kind)
        || isTextAnnotation(annotation)
        || isNumberAnnotation(annotation)
        || isMagnifierAnnotation(annotation);
}

bool ShapeEditorController::pointerDown(
    AnnotationPoint point,
    bool shift,
    int clickCount) noexcept
{
    ++interactionRevision_;
    static_cast<void>(shift);
    if (interaction_.mode() != ShapeInteractionMode::idle
        || arrowInteraction_.mode() != ArrowLineInteractionMode::idle
        || brushInteraction_.active()
        || markerInteraction_.mode() != MarkerInteractionMode::idle
        || mosaicInteraction_.mode() != MosaicInteractionMode::idle
        || eraserPointInteractionActive_
        || eraserRectangleStart_.has_value()) {
        return false;
    }
    if (isEraserToolActive()) {
        point = clampedPoint(point, canvasBounds_);
        document_.clearSelection();
        if (eraserMode_ == EraserMode::point) {
            eraserPointInteractionActive_ = true;
            if (const auto hit = annotationAtEraserPoint(point)) {
                document_.remove(*hit);
                syncHistory();
            }
        } else {
            eraserRectangleStart_ = point;
            eraserRectangleCurrent_ = point;
        }
        return true;
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
    if (editingNumberId_.has_value()) {
        const auto* editing = document_.find(*editingNumberId_);
        if (editing != nullptr
            && containsRect(standardized(editing->rect), point)) {
            const auto rect = standardized(editing->rect);
            const auto progress = rect.width <= 0.0F ? 1.0F
                : (std::max)(0.0F, (std::min)(1.0F,
                    (point.x - rect.x) / rect.width));
            numberCaretPosition_ = (std::min)(numberEditBuffer_.size(),
                static_cast<std::size_t>(progress
                    * static_cast<float>(numberEditBuffer_.size()) + 0.5F));
            return true;
        }
        commitNumberEdit();
    }
    if (const auto selected = document_.selectedId(); selected.has_value()) {
        const auto* annotation = document_.find(*selected);
        if (annotation != nullptr
            && canEditCompletedAnnotation(*annotation)) {
            if (isNumberAnnotation(*annotation)) {
                for (const auto kind : {
                        NumberHandleKind::deleteHandle,
                        NumberHandleKind::resize,
                        NumberHandleKind::increment,
                        NumberHandleKind::decrement,
                        NumberHandleKind::reset}) {
                    const auto handle = numberHandleRect(*annotation, kind);
                    if (!handle.has_value() || !containsRect(*handle, point)) {
                        continue;
                    }
                    numberTypeFollowerId_ = *selected;
                    if (kind == NumberHandleKind::deleteHandle) {
                        return removeNumberAndRenumber(*selected);
                    }
                    if (kind == NumberHandleKind::resize) {
                        return interaction_.beginResize(
                            *selected, ShapeResizeHandle::bottomRight);
                    }
                    if (kind == NumberHandleKind::increment) {
                        adjustSelectedNumber(1);
                        return true;
                    }
                    if (kind == NumberHandleKind::decrement) {
                        adjustSelectedNumber(-1);
                        return true;
                    }
                    resetSelectedNumber();
                    return true;
                }
            }
            if (isTextAnnotation(*annotation)) {
                if (const auto handle = textDeleteHandlePoint(*selected);
                    handle.has_value()
                    && annotationDistanceSquared(point, *handle) <= 100.0F) {
                    const auto removed = document_.remove(*selected);
                    syncHistory();
                    return removed;
                }
            }
            if (annotation->arrowLine.has_value()) {
                if (const auto handle = arrowInteraction_.hitTestHandle(
                        *selected, point)) {
                    return arrowInteraction_.beginEdit(*selected, *handle);
                }
            } else if (isBrushAnnotation(*annotation)) {
                if (!brushToolActive_) {
                    if (const auto handle = brushInteraction_.hitTestHandle(
                            *selected, point)) {
                        return brushInteraction_.beginRotate(*selected, *handle);
                    }
                }
            } else if (isMarkerAnnotation(*annotation)) {
                if (const auto handle = markerInteraction_.hitTestHandle(
                        *annotation, point)) {
                    return markerInteraction_.beginResize(*selected, *handle);
                }
            } else if (isNumberAnnotation(*annotation)) {
                // Number marks expose only the dedicated bottom-right size handle.
            } else if (isMagnifierAnnotation(*annotation)) {
                if (const auto handle = interaction_.hitTestResizeHandle(
                        *selected, point); handle.has_value()) {
                    return interaction_.beginResize(*selected, *handle);
                }
            } else if (!isMosaicStrokeAnnotation(*annotation)) {
                if (interaction_.hitTestRotationHandle(*selected, point)) {
                    return interaction_.beginRotation(*selected, point);
                }
                if (const auto handle = interaction_.hitTestResizeHandle(
                        *selected, point); handle.has_value()) {
                    return interaction_.beginResize(*selected, *handle);
                }
            }
        }
    }
    if (!containsRect(canvasBounds_, point)) {
        document_.clearSelection();
        numberTypeFollowerId_.reset();
        return false;
    }
    if (brushToolActive_) {
        document_.clearSelection();
        return brushInteraction_.begin(point, brushOptions_.style());
    }
    if (isTextToolActive()) {
        if (const auto text = textAnnotationAt(point)) {
            const auto* existing = document_.find(*text);
            if (existing != nullptr
                && canEditCompletedAnnotation(*existing)) {
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
    if (isNumberToolActive()) {
        if (const auto number = numberAnnotationAt(point)) {
            document_.select(*number);
            numberTypeFollowerId_ = *number;
            loadSelectedOptions();
            if (clickCount >= 2) {
                return beginNumberEdit(*number);
            }
            return interaction_.beginMove(*number, point);
        }
        document_.clearSelection();
        numberTypeFollowerId_.reset();
        if (currentNumberGroupId_ == 0) {
            currentNumberGroupId_ = nextNumberGroupId_++;
        }
        const auto type = numberOptions_.type();
        const auto value = type == NumberMarkType::number
            ? std::optional<int>{nextNumberValue(currentNumberGroupId_)}
            : std::nullopt;
        const auto manual = type == NumberMarkType::number
            && numberGroupIsManual(currentNumberGroupId_);
        const auto id = document_.addNumberMark(
            numberMarkRect(point, numberOptions_.style().textSize),
            type, value, manual,
            type == NumberMarkType::number ? currentNumberGroupId_ : 0,
            numberOptions_.style());
        syncHistory();
        return id != invalidAnnotationId;
    }
    if (isMosaicToolActive()) {
        if (!completedAnnotationsLocked_) {
            if (const auto hit = annotationAtBorder(point)) {
                const auto* annotation = document_.find(*hit);
                if (annotation != nullptr && isMosaicAnnotation(*annotation)) {
                    document_.select(*hit);
                    loadSelectedOptions();
                    return isMosaicStrokeAnnotation(*annotation)
                        ? mosaicInteraction_.beginMove(*hit, point)
                        : interaction_.beginMove(*hit, point);
                }
            }
        }
        document_.clearSelection();
        if (mosaicOptions_.kind() == AnnotationKind::mosaicRectangle) {
            return interaction_.beginMosaicRectangleDrawing(
                point, mosaicOptions_.style(), mosaicOptions_.redaction());
        }
        return mosaicInteraction_.beginDrawing(
            point, mosaicOptions_.style(), mosaicOptions_.redaction());
    }
    if (const auto hit = annotationAtBorder(point); hit.has_value()) {
        const auto* annotation = document_.find(*hit);
        if (annotation != nullptr
            && canEditCompletedAnnotation(*annotation)) {
            document_.select(*hit);
            if (isMagnifierAnnotation(*annotation)) {
                shapeToolActive_ = false;
                arrowLineToolActive_ = false;
                brushToolActive_ = false;
                markerToolActive_ = false;
                toolbarState_.selectTool(ToolbarAction::magnifier);
                dismissPopovers();
            }
            loadSelectedOptions();
            if (annotation->arrowLine.has_value()) {
                return arrowInteraction_.beginMove(*hit, point);
            }
            if (isBrushAnnotation(*annotation)) {
                return brushInteraction_.beginMove(*hit, point);
            }
            if (isMarkerAnnotation(*annotation)) {
                return markerInteraction_.beginMove(*hit, point);
            }
            if (isMosaicStrokeAnnotation(*annotation)) {
                return mosaicInteraction_.beginMove(*hit, point);
            }
            return interaction_.beginMove(*hit, point);
        }
    }
    if (isMagnifierToolActive()) {
        document_.clearSelection();
        return interaction_.beginMagnifierDrawing(
            point,
            magnifierOptions_.shape(),
            magnifierOptions_.zoom(),
            magnifierOptions_.style());
    }
    if (arrowLineToolActive_) {
        document_.clearSelection();
        const auto started = arrowInteraction_.beginDrawing(
            point,
            arrowLineOptions_.style(),
            arrowLineOptions_.startArrowType(),
            arrowLineOptions_.endArrowType());
        arrowDrawingMoveCount_ = 0U;
        return started;
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
    if (eraserRectangleStart_.has_value()) {
        point = clampedPoint(point, canvasBounds_);
        if (!eraserRectangleCurrent_.has_value()
            || !(*eraserRectangleCurrent_ == point)) {
            eraserRectangleCurrent_ = point;
            ++interactionRevision_;
        }
        return;
    }
    if (eraserPointInteractionActive_) return;
    point = clampedPoint(point, canvasBounds_);
    if (brushInteraction_.active()) {
        ++interactionRevision_;
        brushInteraction_.update(point, shift);
    } else if (mosaicInteraction_.mode() != MosaicInteractionMode::idle) {
        ++interactionRevision_;
        mosaicInteraction_.update(point, shift);
    } else if (markerInteraction_.mode() != MarkerInteractionMode::idle) {
        ++interactionRevision_;
        markerInteraction_.update(point, shift);
    } else if (arrowInteraction_.mode() != ArrowLineInteractionMode::idle) {
        if (arrowInteraction_.mode() == ArrowLineInteractionMode::drawing) {
            ++arrowDrawingMoveCount_;
        }
        ++interactionRevision_;
        arrowInteraction_.update(point);
    } else if (interaction_.mode() != ShapeInteractionMode::idle) {
        const auto previous = interaction_.preview();
        interaction_.update(point, shift);
        if (interaction_.preview() != previous) {
            ++interactionRevision_;
        }
    }
}

bool ShapeEditorController::pointerUp(
    AnnotationPoint point,
    bool shift)
{
    if (eraserPointInteractionActive_) {
        eraserPointInteractionActive_ = false;
        ++interactionRevision_;
        return true;
    }
    if (eraserRectangleStart_.has_value()) {
        point = clampedPoint(point, canvasBounds_);
        eraserRectangleCurrent_ = point;
        const auto rect = eraserRectanglePreview().value_or(AnnotationRect{});
        eraserRectangleStart_.reset();
        eraserRectangleCurrent_.reset();
        ++interactionRevision_;
        if (rect.width >= 3.0F && rect.height >= 3.0F) {
            document_.addEraserMask(
                rect, annotationsIntersectingEraserRect(rect));
            syncHistory();
        }
        return true;
    }
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
        arrowDrawingMoveCount_ = 0U;
    } else {
        interaction_.update(point, shift);
        interaction_.commit();
    }
    const auto selected = document_.selectedId();
    const auto* annotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    if (annotation != nullptr
        && canEditCompletedAnnotation(*annotation)) {
        loadSelectedOptions();
    } else if (completedAnnotationsLocked_) {
        document_.clearSelection();
    }
    syncHistory();
    return true;
}

void ShapeEditorController::cancelInteraction() noexcept
{
    ++interactionRevision_;
    interaction_.cancel();
    arrowInteraction_.cancel();
    arrowDrawingMoveCount_ = 0U;
    brushInteraction_.cancel();
    markerInteraction_.cancel();
    mosaicInteraction_.cancel();
    eraserPointInteractionActive_ = false;
    eraserRectangleStart_.reset();
    eraserRectangleCurrent_.reset();
}

ShapeCursorStyle ShapeEditorController::cursorStyleAt(
    AnnotationPoint point) const noexcept
{
    if (isEraserToolActive()) {
        return eraserMode_ == EraserMode::rectangle
            ? ShapeCursorStyle::crosshair : ShapeCursorStyle::eraser;
    }
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

    if (brushToolActive_) {
        return ShapeCursorStyle::brush;
    }
    if (markerToolActive_) {
        return ShapeCursorStyle::marker;
    }

    if (const auto selected = document_.selectedId(); selected.has_value()) {
        const auto* annotation = document_.find(*selected);
        if (annotation != nullptr
            && canEditCompletedAnnotation(*annotation)) {
            if (isNumberAnnotation(*annotation)) {
                for (const auto kind : {
                        NumberHandleKind::deleteHandle,
                        NumberHandleKind::resize,
                        NumberHandleKind::increment,
                        NumberHandleKind::decrement,
                        NumberHandleKind::reset}) {
                    const auto handle = numberHandleRect(*annotation, kind);
                    if (handle.has_value() && containsRect(*handle, point)) {
                        return kind == NumberHandleKind::resize
                            ? ShapeCursorStyle::resizeTopLeftBottomRight
                            : ShapeCursorStyle::arrow;
                    }
                }
            } else if (annotation->arrowLine.has_value()) {
                if (arrowInteraction_.hitTestHandle(*selected, point)) {
                    return ShapeCursorStyle::move;
                }
            } else if (isBrushAnnotation(*annotation)) {
                if (brushInteraction_.hitTestHandle(*selected, point)) {
                    return ShapeCursorStyle::rotation;
                }
            } else if (isMarkerAnnotation(*annotation)) {
                if (markerInteraction_.hitTestHandle(*annotation, point)) {
                    return ShapeCursorStyle::resizeUpDown;
                }
            } else if (isMagnifierAnnotation(*annotation)) {
                if (const auto handle = interaction_.hitTestResizeHandle(
                        *selected, point)) {
                    return cursorStyleForResizeHandle(*handle);
                }
            } else if (!isMosaicStrokeAnnotation(*annotation)) {
                if (interaction_.hitTestRotationHandle(*selected, point)) {
                    return ShapeCursorStyle::rotation;
                }
                if (const auto handle = interaction_.hitTestResizeHandle(
                        *selected, point)) {
                    return cursorStyleForResizeHandle(*handle);
                }
            }
        }
    }
    if (const auto hit = annotationAtBorder(point); hit.has_value()) {
        const auto* annotation = document_.find(*hit);
        if (annotation != nullptr
            && canEditCompletedAnnotation(*annotation)) {
            return ShapeCursorStyle::move;
        }
    }
    if (const auto selected = document_.selectedId(); selected.has_value()) {
        const auto* annotation = document_.find(*selected);
        if (annotation != nullptr
            && canEditCompletedAnnotation(*annotation)) {
            if (const auto handle = textDeleteHandlePoint(*selected);
                handle.has_value()
                && annotationDistanceSquared(point, *handle) <= 100.0F) {
                return ShapeCursorStyle::arrow;
            }
        }
    }
    if (isTextToolActive()) {
        if (const auto text = textAnnotationAt(point); text.has_value()) {
            const auto* annotation = document_.find(*text);
            if (annotation != nullptr
                && canEditCompletedAnnotation(*annotation)) {
                return ShapeCursorStyle::textInput;
            }
        }
    }
    if (isMosaicToolActive()) {
        return mosaicOptions_.kind() == AnnotationKind::mosaicStroke
            ? ShapeCursorStyle::mosaic : ShapeCursorStyle::crosshair;
    }
    if (isNumberToolActive()) {
        switch (numberOptions_.type()) {
        case NumberMarkType::number:
            return ShapeCursorStyle::numberMark;
        case NumberMarkType::check:
            return ShapeCursorStyle::numberCheck;
        case NumberMarkType::cross:
            return ShapeCursorStyle::numberCross;
        }
    }
    if (isTextToolActive()) {
        return ShapeCursorStyle::textInput;
    }
    return shapeToolActive_ || arrowLineToolActive_
        || isMagnifierToolActive()
        ? ShapeCursorStyle::crosshair : ShapeCursorStyle::arrow;
}

ShapeEditorKeyResult ShapeEditorController::handleKey(
    ShapeEditorKey key,
    bool control,
    bool shift)
{
    if (editingNumberId_.has_value()) {
        if (key == ShapeEditorKey::escapeKey) {
            cancelNumberEdit();
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
            commitNumberEdit();
            return ShapeEditorKeyResult::consumed;
        }
        if (!control && key == ShapeEditorKey::left) {
            if (numberCaretPosition_ > 0U) --numberCaretPosition_;
            ++interactionRevision_;
            return ShapeEditorKeyResult::consumed;
        }
        if (!control && key == ShapeEditorKey::right) {
            if (numberCaretPosition_ < numberEditBuffer_.size()) {
                ++numberCaretPosition_;
            }
            ++interactionRevision_;
            return ShapeEditorKeyResult::consumed;
        }
    }
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
    if (!control && key == ShapeEditorKey::rectangle) {
        handleToolbarAction(ToolbarAction::rectangle);
        return ShapeEditorKeyResult::consumed;
    }
    if (!control && key == ShapeEditorKey::polyline) {
        handleToolbarAction(ToolbarAction::polyline);
        return ShapeEditorKeyResult::consumed;
    }
    if (!control && key == ShapeEditorKey::pen) {
        handleToolbarAction(ToolbarAction::pen);
        return ShapeEditorKeyResult::consumed;
    }
    if (!control && key == ShapeEditorKey::marker) {
        handleToolbarAction(ToolbarAction::marker);
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
    if (!control && key == ShapeEditorKey::number) {
        handleToolbarAction(ToolbarAction::number);
        return ShapeEditorKeyResult::consumed;
    }
    if (!control && key == ShapeEditorKey::magnifier) {
        handleToolbarAction(ToolbarAction::magnifier);
        return ShapeEditorKeyResult::consumed;
    }
    if (!control && key == ShapeEditorKey::eraser) {
        handleToolbarAction(ToolbarAction::eraser);
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
            || isTextToolActive() || isNumberToolActive()
            || isMagnifierToolActive()
            || isEraserToolActive()
            || isEyedropperToolActive()) {
            deactivateTool();
            return ShapeEditorKeyResult::consumed;
        }
        return ShapeEditorKeyResult::requestCancel;
    }
    if (key == ShapeEditorKey::deleteKey) {
        const auto selected = document_.selectedId();
        if (!selected.has_value()) {
            return ShapeEditorKeyResult::ignored;
        }
        const auto* annotation = document_.find(*selected);
        const auto removed = annotation != nullptr
            && isNumberAnnotation(*annotation)
            ? removeNumberAndRenumber(*selected)
            : document_.remove(*selected);
        if (!removed) return ShapeEditorKeyResult::ignored;
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
    if (control && !shift && key == ShapeEditorKey::pin) {
        return ShapeEditorKeyResult::requestPin;
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

std::optional<AnnotationRect> ShapeEditorController::numberHandle(
    AnnotationId id,
    NumberHandleKind kind) const noexcept
{
    const auto* annotation = document_.find(id);
    return annotation == nullptr
        ? std::nullopt : numberHandleRect(*annotation, kind);
}

AnnotationRenderPlan ShapeEditorController::renderPlan(
    AnnotationPoint selectionOriginDip,
    bool showEditingAffordances) const
{
    auto currentPreview = preview();
    if (currentPreview.has_value()
        && arrowInteraction_.mode() == ArrowLineInteractionMode::drawing
        && currentPreview->arrowLine.has_value()
        && (arrowDrawingMoveCount_ < 2U
            || annotationDistanceSquared(
                currentPreview->arrowLine->start,
                currentPreview->arrowLine->end)
                < ArrowLineInteraction::minimumLineLengthDip
                    * ArrowLineInteraction::minimumLineLengthDip)) {
        currentPreview.reset();
    }
    const auto selected = document_.selectedId();
    const auto* selectedAnnotation = selected.has_value()
        ? document_.find(*selected) : nullptr;
    const auto canShowEditingAffordances
        = !completedAnnotationsLocked_
        || (selectedAnnotation != nullptr
            && canEditCompletedAnnotation(*selectedAnnotation))
        || (currentPreview.has_value()
            && canEditCompletedAnnotation(*currentPreview));
    auto plan = buildAnnotationRenderPlan(
        document_, currentPreview, selectionOriginDip,
        showEditingAffordances && canShowEditingAffordances,
        editingTextId_.has_value()
            ? std::optional<AnnotationEditingState>{{
                *editingTextId_, textCaretPosition_}}
            : editingNumberId_.has_value()
                ? std::optional<AnnotationEditingState>{{
                    *editingNumberId_, numberCaretPosition_,
                    numberEditBuffer_}}
                : std::nullopt);
    if (const auto preview = eraserRectanglePreview()) {
        plan.eraserPreview = translated(*preview, selectionOriginDip);
    }
    return plan;
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
        } else if (isNumberAnnotation(*iterator)) {
            contains = ellipseContains(iterator->rect, point);
        } else if (isMagnifierAnnotation(*iterator)) {
            contains = containsRect(standardized(iterator->rect), point);
        } else {
            contains = shapeBorderContains(*iterator, point);
        }
        if (contains) {
            return iterator->id;
        }
    }
    return std::nullopt;
}

std::optional<AnnotationId>
ShapeEditorController::annotationAtEraserPoint(AnnotationPoint point) const noexcept
{
    const auto& annotations = document_.annotations();
    for (auto iterator = annotations.rbegin(); iterator != annotations.rend();
         ++iterator) {
        bool hit = false;
        if (isArrowLineAnnotation(*iterator)) {
            hit = arrowInteraction_.hitTestLine(iterator->id, point);
        } else if (isBrushAnnotation(*iterator)) {
            hit = brushInteraction_.hitTestPath(iterator->id, point);
        } else if (isMarkerAnnotation(*iterator)) {
            hit = markerInteraction_.hitTestLine(*iterator, point);
        } else if (isMosaicStrokeAnnotation(*iterator)) {
            hit = mosaicInteraction_.hitTestStroke(iterator->id, point);
        } else if (isShapeKind(iterator->kind)) {
            hit = containsRect(outsetRect(iterator->rect, 4.0F), point);
        } else if (isNumberAnnotation(*iterator)) {
            hit = containsRect(outsetRect(iterator->rect, 6.0F), point);
        } else {
            hit = containsRect(outsetRect(iterator->rect, 6.0F),
                unrotatedPoint(point, *iterator));
        }
        if (hit) return iterator->id;
    }
    return std::nullopt;
}

std::vector<AnnotationId>
ShapeEditorController::annotationsIntersectingEraserRect(
    AnnotationRect rect) const
{
    std::vector<AnnotationId> result;
    rect = standardized(rect);
    for (const auto& annotation : document_.annotations()) {
        if (rotatedRectIntersects(annotation, rect)) {
            result.push_back(annotation.id);
        }
    }
    return result;
}

std::optional<AnnotationId> ShapeEditorController::numberAnnotationAt(
    AnnotationPoint point) const noexcept
{
    const auto& annotations = document_.annotations();
    for (auto iterator = annotations.rbegin(); iterator != annotations.rend();
         ++iterator) {
        if (isNumberAnnotation(*iterator)
            && ellipseContains(iterator->rect, point)) {
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
        } else if (isNumberAnnotation(*annotation)) {
            numberOptions_.load(*annotation);
            if (annotation->numberMarkType == NumberMarkType::number
                && annotation->numberSequenceGroupId != 0) {
                currentNumberGroupId_ = annotation->numberSequenceGroupId;
                nextNumberGroupId_ = (std::max)(nextNumberGroupId_,
                    currentNumberGroupId_ + 1U);
            }
        } else if (isMagnifierAnnotation(*annotation)) {
            magnifierOptions_.load(*annotation);
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

bool ShapeEditorController::applyMagnifierOptionsToSelection()
{
    const auto selected = document_.selectedId();
    if (!selected.has_value()) {
        return false;
    }
    const auto* annotation = document_.find(*selected);
    return annotation != nullptr && isMagnifierAnnotation(*annotation)
        && document_.updateMagnifier(
            *selected,
            magnifierOptions_.shape(),
            magnifierOptions_.zoom(),
            magnifierOptions_.style());
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

bool ShapeEditorController::toggleStatelessTool(ToolbarAction action)
{
    if (toolbarState_.selectedAction() == action) {
        deactivateTool();
        return true;
    }
    cancelInteraction();
    shapeToolActive_ = false;
    arrowLineToolActive_ = false;
    brushToolActive_ = false;
    markerToolActive_ = false;
    if (toolbarState_.selectTool(action)) {
        document_.clearSelection();
        dismissPopovers();
    }
    return true;
}

void ShapeEditorController::deactivateTool()
{
    if (editingTextId_.has_value()) {
        commitTextEdit();
    }
    if (editingNumberId_.has_value()) {
        commitNumberEdit();
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
    popupScrollOffset_ = 0;
    numberPopupMenu_.reset();
    numberTypeFollowerId_.reset();
    magnifierZoomMenuVisible_ = false;
}

} // namespace xxsnap::win
