#include "annotation/ShapeEditorController.h"

#include <array>

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

} // namespace

ShapeEditorController::ShapeEditorController(
    AnnotationRect canvasBounds) noexcept
    : interaction_(document_, canvasBounds)
{
    toolbarState_.setCapability(ToolbarAction::rectangle, true);
    toolbarState_.setCapability(ToolbarAction::undo, true);
    toolbarState_.setCapability(ToolbarAction::redo, true);
    syncHistory();
}

void ShapeEditorController::setCanvasBounds(
    AnnotationRect canvasBounds) noexcept
{
    interaction_.setBounds(canvasBounds);
}

const ToolbarState& ShapeEditorController::toolbarState() const noexcept
{
    return toolbarState_;
}

const ShapeOptionsState& ShapeEditorController::options() const noexcept
{
    return options_;
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
    return interaction_.preview();
}

bool ShapeEditorController::isShapeToolActive() const noexcept
{
    return shapeToolActive_;
}

bool ShapeEditorController::strokePatternMenuVisible() const noexcept
{
    return strokePatternMenuVisible_;
}

bool ShapeEditorController::cornerRadiusPanelVisible() const noexcept
{
    return cornerRadiusPanelVisible_;
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
        cornerRadiusPanelVisible_ = false;
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
    if (index >= patterns.size()
        || !options_.setStrokePattern(patterns[index])) {
        return false;
    }
    strokePatternMenuVisible_ = false;
    const auto changed = applyOptionsStyleToSelection();
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

bool ShapeEditorController::selectCustomColor(AnnotationColor color)
{
    if (!options_.selectCustomColor(color)) {
        return false;
    }
    const auto changed = applyOptionsStyleToSelection();
    syncHistory();
    return changed || !document_.selectedId().has_value();
}

bool ShapeEditorController::pointerDown(AnnotationPoint point) noexcept
{
    if (interaction_.mode() != ShapeInteractionMode::idle) {
        return false;
    }
    if (const auto selected = document_.selectedId(); selected.has_value()) {
        if (interaction_.hitTestRotationHandle(*selected, point)) {
            return interaction_.beginRotation(*selected, point);
        }
        if (const auto handle = interaction_.hitTestResizeHandle(
                *selected, point); handle.has_value()) {
            return interaction_.beginResize(*selected, *handle);
        }
    }
    if (const auto hit = annotationAtBorder(point); hit.has_value()) {
        document_.select(*hit);
        loadSelectedOptions();
        return interaction_.beginMove(*hit, point);
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
    interaction_.update(point);
}

bool ShapeEditorController::pointerUp(AnnotationPoint point)
{
    if (interaction_.mode() == ShapeInteractionMode::idle) {
        return false;
    }
    interaction_.update(point);
    interaction_.commit();
    loadSelectedOptions();
    syncHistory();
    return true;
}

void ShapeEditorController::cancelInteraction() noexcept
{
    interaction_.cancel();
}

ShapeEditorKeyResult ShapeEditorController::handleKey(
    ShapeEditorKey key,
    bool control,
    bool shift)
{
    if (key == ShapeEditorKey::escapeKey) {
        if (interaction_.mode() != ShapeInteractionMode::idle) {
            interaction_.cancel();
            return ShapeEditorKeyResult::consumed;
        }
        if (shapeToolActive_) {
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
        document_, interaction_.preview(), selectionOriginDip,
        showEditingAffordances);
}

std::optional<AnnotationId> ShapeEditorController::annotationAtBorder(
    AnnotationPoint point) const noexcept
{
    const auto& annotations = document_.annotations();
    for (auto iterator = annotations.rbegin(); iterator != annotations.rend(); ++iterator) {
        if (shapeBorderContains(*iterator, point)) {
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
        options_.load(annotation->kind, annotation->style);
    }
}

bool ShapeEditorController::applyOptionsStyleToSelection()
{
    const auto selected = document_.selectedId();
    return selected.has_value()
        && document_.updateStyle(*selected, options_.style());
}

void ShapeEditorController::syncHistory() noexcept
{
    toolbarState_.setHistoryAvailability(
        document_.canUndo(), document_.canRedo());
}

void ShapeEditorController::deactivateTool() noexcept
{
    interaction_.cancel();
    shapeToolActive_ = false;
    toolbarState_.clearSelectedTool();
    strokePatternMenuVisible_ = false;
    cornerRadiusPanelVisible_ = false;
}

} // namespace xxsnap::win
