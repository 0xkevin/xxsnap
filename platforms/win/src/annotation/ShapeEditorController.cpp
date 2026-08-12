#include "annotation/ShapeEditorController.h"

#include <array>
#include <cmath>

namespace xxsnap::win {
namespace {

constexpr float pi = 3.14159265358979323846F;
constexpr float degreesToRadians = pi / 180.0F;

constexpr std::array shapeStrokeWidths{2.0F, 4.0F, 7.0F};
constexpr std::array arrowStrokeWidths{3.0F, 4.0F, 6.0F};

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

float squaredDistance(AnnotationPoint left, AnnotationPoint right) noexcept
{
    const auto dx = left.x - right.x;
    const auto dy = left.y - right.y;
    return dx * dx + dy * dy;
}

AnnotationPoint quadraticPoint(const ArrowLine& line, float progress) noexcept
{
    const auto remaining = 1.0F - progress;
    return {
        remaining * remaining * line.start.x
            + 2.0F * remaining * progress * line.control.x
            + progress * progress * line.end.x,
        remaining * remaining * line.start.y
            + 2.0F * remaining * progress * line.control.y
            + progress * progress * line.end.y,
    };
}

float distanceToSegmentSquared(
    AnnotationPoint point,
    AnnotationPoint start,
    AnnotationPoint end) noexcept
{
    const auto dx = end.x - start.x;
    const auto dy = end.y - start.y;
    const auto lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 0.0F) {
        return squaredDistance(point, start);
    }
    const auto projection = ((point.x - start.x) * dx
        + (point.y - start.y) * dy) / lengthSquared;
    const auto progress = (std::max)(0.0F, (std::min)(1.0F, projection));
    return squaredDistance(point, {
        start.x + dx * progress,
        start.y + dy * progress,
    });
}

bool arrowLineContains(const ArrowLine& line, AnnotationPoint point) noexcept
{
    constexpr float hitRadiusSquared = 49.0F;
    auto previous = line.start;
    for (int index = 1; index <= 32; ++index) {
        const auto current = quadraticPoint(
            line, static_cast<float>(index) / 32.0F);
        if (distanceToSegmentSquared(point, previous, current)
            <= hitRadiusSquared) {
            return true;
        }
        previous = current;
    }
    return false;
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
    : interaction_(document_, canvasBounds), canvasBounds_(standardized(canvasBounds))
{
    toolbarState_.setCapability(ToolbarAction::rectangle, true);
    toolbarState_.setCapability(ToolbarAction::polyline, true);
    toolbarState_.setCapability(ToolbarAction::undo, true);
    toolbarState_.setCapability(ToolbarAction::redo, true);
    syncHistory();
}

void ShapeEditorController::setCanvasBounds(
    AnnotationRect canvasBounds) noexcept
{
    interaction_.setBounds(canvasBounds);
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

const AnnotationDocument& ShapeEditorController::document() const noexcept
{
    return document_;
}

AnnotationDocument& ShapeEditorController::document() noexcept
{
    return document_;
}

const std::optional<ShapeAnnotation>& ShapeEditorController::preview() const noexcept
{
    return arrowPreview_.has_value() ? arrowPreview_ : interaction_.preview();
}

bool ShapeEditorController::isShapeToolActive() const noexcept
{
    return shapeToolActive_;
}

bool ShapeEditorController::isArrowLineToolActive() const noexcept
{
    return arrowLineToolActive_;
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
    if (action == ToolbarAction::rectangle) {
        if (shapeToolActive_) {
            deactivateTool();
        } else {
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
            arrowLineToolActive_ = toolbarState_.selectTool(action);
            if (arrowLineToolActive_) {
                ArrowLineOptionsState activated;
                arrowLineOptions_ = activated;
                applyArrowOptionsToSelection();
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
    case ArrowLineOptionControl::strokeWidth:
        if (hit.index < arrowStrokeWidths.size()) {
            changed = arrowLineOptions_.setStrokeWidth(arrowStrokeWidths[hit.index]);
        }
        break;
    case ArrowLineOptionControl::strokeStyle:
        strokePatternMenuVisible_ = !strokePatternMenuVisible_;
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
    if (index >= types.size()
        || !arrowLineOptions_.selectArrowType(endpoint, types[index])) {
        return false;
    }
    const auto applied = applyArrowOptionsToSelection();
    syncHistory();
    return applied || !document_.selectedId().has_value();
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
    const auto& patterns = macShapeStrokePatterns();
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
    const auto optionChanged = arrowLineToolActive_
        ? arrowLineOptions_.selectCustomColor(color)
        : options_.selectCustomColor(color);
    if (!optionChanged) {
        return false;
    }
    const auto changed = arrowLineToolActive_
        ? applyArrowOptionsToSelection()
        : applyOptionsStyleToSelection();
    syncHistory();
    return changed || !document_.selectedId().has_value();
}

void ShapeEditorController::dismissPopovers() noexcept
{
    strokePatternMenuVisible_ = false;
    cornerRadiusPanelVisible_ = false;
    arrowTypeMenuEndpoint_.reset();
}

bool ShapeEditorController::pointerDown(AnnotationPoint point) noexcept
{
    point = clampedPoint(point, canvasBounds_);
    if (interaction_.mode() != ShapeInteractionMode::idle
        || arrowInteractionMode_ != ArrowInteractionMode::idle) {
        return false;
    }
    if (const auto selected = document_.selectedId(); selected.has_value()) {
        const auto* annotation = document_.find(*selected);
        if (annotation != nullptr && annotation->arrowLine.has_value()) {
            constexpr float handleRadiusSquared = 49.0F;
            if (squaredDistance(point, annotation->arrowLine->start)
                <= handleRadiusSquared) {
                return beginArrowInteraction(
                    *selected, ArrowInteractionMode::editingStart, point);
            }
            if (squaredDistance(point, annotation->arrowLine->end)
                <= handleRadiusSquared) {
                return beginArrowInteraction(
                    *selected, ArrowInteractionMode::editingEnd, point);
            }
            if (squaredDistance(point, annotation->arrowLine->control)
                <= handleRadiusSquared) {
                return beginArrowInteraction(
                    *selected, ArrowInteractionMode::editingControl, point);
            }
        } else {
            if (interaction_.hitTestRotationHandle(*selected, point)) {
                return interaction_.beginRotation(*selected, point);
            }
            if (const auto handle = interaction_.hitTestResizeHandle(
                    *selected, point); handle.has_value()) {
                return interaction_.beginResize(*selected, *handle);
            }
        }
    }
    if (const auto hit = annotationAtBorder(point); hit.has_value()) {
        document_.select(*hit);
        loadSelectedOptions();
        if (const auto* annotation = document_.find(*hit);
            annotation != nullptr && annotation->arrowLine.has_value()) {
            return beginArrowInteraction(
                *hit, ArrowInteractionMode::moving, point);
        }
        return interaction_.beginMove(*hit, point);
    }
    if (arrowLineToolActive_) {
        document_.clearSelection();
        arrowInteractionMode_ = ArrowInteractionMode::drawing;
        arrowAnchorPoint_ = point;
        ArrowLine line{
            point,
            point,
            point,
            arrowLineOptions_.startArrowType(),
            arrowLineOptions_.endArrowType(),
        };
        arrowPreview_ = ShapeAnnotation{
            invalidAnnotationId,
            AnnotationKind::arrowLine,
            {point.x, point.y, 0.0F, 0.0F},
            arrowLineOptions_.style(),
            0.0F,
            line,
        };
        return true;
    }
    if (shapeToolActive_) {
        document_.clearSelection();
        return interaction_.beginDrawing(
            options_.kind(), point, options_.style());
    }
    document_.clearSelection();
    return false;
}

void ShapeEditorController::pointerMove(AnnotationPoint point) noexcept
{
    point = clampedPoint(point, canvasBounds_);
    if (arrowInteractionMode_ != ArrowInteractionMode::idle) {
        updateArrowInteraction(point);
    } else {
        interaction_.update(point);
    }
}

bool ShapeEditorController::pointerUp(AnnotationPoint point)
{
    if (interaction_.mode() == ShapeInteractionMode::idle
        && arrowInteractionMode_ == ArrowInteractionMode::idle) {
        return false;
    }
    point = clampedPoint(point, canvasBounds_);
    if (arrowInteractionMode_ != ArrowInteractionMode::idle) {
        updateArrowInteraction(point);
        commitArrowInteraction();
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
    interaction_.cancel();
    cancelArrowInteraction();
}

ShapeCursorStyle ShapeEditorController::cursorStyleAt(
    AnnotationPoint point) const noexcept
{
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

    if (arrowInteractionMode_ == ArrowInteractionMode::drawing) {
        return ShapeCursorStyle::crosshair;
    }
    if (arrowInteractionMode_ != ArrowInteractionMode::idle) {
        return ShapeCursorStyle::move;
    }

    if (const auto selected = document_.selectedId(); selected.has_value()) {
        if (interaction_.hitTestRotationHandle(*selected, point)) {
            return ShapeCursorStyle::rotation;
        }
        if (const auto handle = interaction_.hitTestResizeHandle(
                *selected, point)) {
            return cursorStyleForResizeHandle(*handle);
        }
    }
    if (annotationAtBorder(point).has_value()) {
        return ShapeCursorStyle::move;
    }
    return shapeToolActive_ || arrowLineToolActive_
        ? ShapeCursorStyle::crosshair
        : ShapeCursorStyle::arrow;
}

ShapeEditorKeyResult ShapeEditorController::handleKey(
    ShapeEditorKey key,
    bool control,
    bool shift)
{
    if (key == ShapeEditorKey::escapeKey) {
        if (interaction_.mode() != ShapeInteractionMode::idle
            || arrowInteractionMode_ != ArrowInteractionMode::idle) {
            cancelInteraction();
            return ShapeEditorKeyResult::consumed;
        }
        if (shapeToolActive_ || arrowLineToolActive_) {
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

AnnotationRenderPlan ShapeEditorController::renderPlan(
    AnnotationPoint selectionOriginDip,
    bool showEditingAffordances) const
{
    return buildAnnotationRenderPlan(
        document_, preview(), selectionOriginDip,
        showEditingAffordances);
}

std::optional<AnnotationId> ShapeEditorController::annotationAtBorder(
    AnnotationPoint point) const noexcept
{
    const auto& annotations = document_.annotations();
    for (auto iterator = annotations.rbegin(); iterator != annotations.rend(); ++iterator) {
        if (iterator->arrowLine.has_value()
            ? arrowLineContains(*iterator->arrowLine, point)
            : shapeBorderContains(*iterator, point)) {
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
        if (annotation->arrowLine.has_value()) {
            arrowLineOptions_.load(annotation->style, *annotation->arrowLine);
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
    if (annotation == nullptr || !annotation->arrowLine.has_value()) {
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

bool ShapeEditorController::beginArrowInteraction(
    AnnotationId id,
    ArrowInteractionMode mode,
    AnnotationPoint point) noexcept
{
    const auto* annotation = document_.find(id);
    if (annotation == nullptr || !annotation->arrowLine.has_value()) {
        return false;
    }
    arrowInteractionMode_ = mode;
    arrowInteractionId_ = id;
    arrowAnchorPoint_ = point;
    arrowOriginal_ = *annotation->arrowLine;
    arrowPreview_ = *annotation;
    return true;
}

void ShapeEditorController::updateArrowInteraction(AnnotationPoint point) noexcept
{
    if (!arrowPreview_.has_value() || !arrowPreview_->arrowLine.has_value()) {
        return;
    }
    auto line = arrowOriginal_;
    switch (arrowInteractionMode_) {
    case ArrowInteractionMode::drawing:
        line = *arrowPreview_->arrowLine;
        line.end = point;
        line.control = {
            (line.start.x + line.end.x) / 2.0F,
            (line.start.y + line.end.y) / 2.0F,
        };
        break;
    case ArrowInteractionMode::moving: {
        const AnnotationPoint offset{
            point.x - arrowAnchorPoint_.x,
            point.y - arrowAnchorPoint_.y,
        };
        line.start = translated(line.start, offset);
        line.end = translated(line.end, offset);
        line.control = translated(line.control, offset);
        break;
    }
    case ArrowInteractionMode::editingStart:
        line.start = point;
        break;
    case ArrowInteractionMode::editingEnd:
        line.end = point;
        break;
    case ArrowInteractionMode::editingControl:
        line.control = point;
        break;
    case ArrowInteractionMode::idle:
        return;
    }
    arrowPreview_->arrowLine = line;
    const auto left = (std::min)({line.start.x, line.end.x, line.control.x});
    const auto top = (std::min)({line.start.y, line.end.y, line.control.y});
    const auto right = (std::max)({line.start.x, line.end.x, line.control.x});
    const auto bottom = (std::max)({line.start.y, line.end.y, line.control.y});
    arrowPreview_->rect = {left, top, right - left, bottom - top};
}

void ShapeEditorController::commitArrowInteraction()
{
    if (!arrowPreview_.has_value() || !arrowPreview_->arrowLine.has_value()) {
        cancelArrowInteraction();
        return;
    }
    const auto line = *arrowPreview_->arrowLine;
    if (arrowInteractionMode_ == ArrowInteractionMode::drawing) {
        document_.addArrowLine(line, arrowPreview_->style);
    } else {
        document_.updateArrowLine(arrowInteractionId_, line);
    }
    cancelArrowInteraction();
}

void ShapeEditorController::cancelArrowInteraction() noexcept
{
    arrowInteractionMode_ = ArrowInteractionMode::idle;
    arrowInteractionId_ = invalidAnnotationId;
    arrowPreview_.reset();
}

void ShapeEditorController::syncHistory() noexcept
{
    toolbarState_.setHistoryAvailability(
        document_.canUndo(), document_.canRedo());
}

void ShapeEditorController::deactivateTool() noexcept
{
    cancelInteraction();
    shapeToolActive_ = false;
    arrowLineToolActive_ = false;
    toolbarState_.clearSelectedTool();
    strokePatternMenuVisible_ = false;
    cornerRadiusPanelVisible_ = false;
    arrowTypeMenuEndpoint_.reset();
}

} // namespace xxsnap::win
