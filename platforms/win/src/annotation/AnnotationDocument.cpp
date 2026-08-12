#include "annotation/AnnotationDocument.h"

#include <algorithm>
#include <cstddef>
#include <cmath>
#include <utility>

namespace xxsnap::win {
namespace {

bool hasUsableArrowLine(const ArrowLine& line) noexcept
{
    return std::hypot(
        static_cast<double>(line.end.x - line.start.x),
        static_cast<double>(line.end.y - line.start.y)) >= 8.0;
}

} // namespace

AnnotationId AnnotationDocument::addShape(
    AnnotationKind kind,
    AnnotationRect rect,
    AnnotationStyle style,
    float rotationDegrees)
{
    rect = standardized(rect);
    if (!isShapeKind(kind)
        || rect.width <= 0.0F
        || rect.height <= 0.0F
        || nextId_ == invalidAnnotationId) {
        return invalidAnnotationId;
    }

    auto before = snapshot();
    const auto id = nextId_++;
    annotations_.push_back({id, kind, rect, style, rotationDegrees, std::nullopt});
    selectedId_ = id;
    commit(std::move(before));
    return id;
}

AnnotationId AnnotationDocument::addArrowLine(
    ArrowLine line,
    AnnotationStyle style)
{
    if (!hasUsableArrowLine(line) || nextId_ == invalidAnnotationId) {
        return invalidAnnotationId;
    }
    auto before = snapshot();
    const auto id = nextId_++;
    annotations_.push_back({
        id,
        AnnotationKind::arrowLine,
        arrowLineBounds(line),
        style,
        0.0F,
        line,
    });
    selectedId_ = id;
    commit(std::move(before));
    return id;
}

AnnotationId AnnotationDocument::addBrushPath(
    BrushPath path,
    AnnotationStyle style)
{
    if (path.points.size() < 2U || nextId_ == invalidAnnotationId) {
        return invalidAnnotationId;
    }
    auto before = snapshot();
    const auto id = nextId_++;
    annotations_.push_back({
        id,
        AnnotationKind::brush,
        brushPathBounds(path),
        style,
        0.0F,
        std::nullopt,
        std::move(path),
    });
    selectedId_.reset();
    commit(std::move(before));
    return id;
}

AnnotationId AnnotationDocument::addMarkerLine(
    MarkerLine line,
    AnnotationStyle style)
{
    if (nextId_ == invalidAnnotationId) {
        return invalidAnnotationId;
    }
    auto before = snapshot();
    const auto id = nextId_++;
    annotations_.push_back({
        id,
        AnnotationKind::marker,
        markerLineBounds(line),
        style,
        0.0F,
        std::nullopt,
        std::nullopt,
        line,
    });
    selectedId_ = id;
    commit(std::move(before));
    return id;
}

AnnotationId AnnotationDocument::addMosaicStroke(
    MosaicStroke stroke,
    MosaicRedaction redaction,
    AnnotationStyle style)
{
    if (stroke.points.empty() || nextId_ == invalidAnnotationId) {
        return invalidAnnotationId;
    }
    redaction.value = (std::max)(1, redaction.value);
    style.fillEnabled = false;
    style.strokePattern = AnnotationStrokePattern::solid;
    auto before = snapshot();
    const auto id = nextId_++;
    annotations_.push_back({
        id, AnnotationKind::mosaicStroke, brushPathBounds(stroke), style,
        0.0F, std::nullopt, std::nullopt, std::nullopt,
        std::move(stroke), redaction,
    });
    selectedId_ = id;
    commit(std::move(before));
    return id;
}

AnnotationId AnnotationDocument::addMosaicRectangle(
    AnnotationRect rect,
    MosaicRedaction redaction,
    AnnotationStyle style,
    float rotationDegrees)
{
    rect = standardized(rect);
    if (rect.width <= 0.0F || rect.height <= 0.0F
        || nextId_ == invalidAnnotationId) {
        return invalidAnnotationId;
    }
    redaction.value = (std::max)(1, redaction.value);
    style.fillEnabled = false;
    style.strokePattern = AnnotationStrokePattern::solid;
    auto before = snapshot();
    const auto id = nextId_++;
    annotations_.push_back({
        id, AnnotationKind::mosaicRectangle, rect, style, rotationDegrees,
        std::nullopt, std::nullopt, std::nullopt, std::nullopt, redaction,
    });
    selectedId_ = id;
    commit(std::move(before));
    return id;
}

bool AnnotationDocument::remove(AnnotationId id)
{
    const auto index = indexOf(id);
    if (!index.has_value()) {
        return false;
    }
    auto before = snapshot();
    annotations_.erase(annotations_.begin() + static_cast<std::ptrdiff_t>(*index));
    if (selectedId_ == id) {
        selectedId_ = annotations_.empty()
            ? std::nullopt
            : std::optional<AnnotationId>{annotations_.back().id};
    }
    commit(std::move(before));
    return true;
}

bool AnnotationDocument::updateRect(AnnotationId id, AnnotationRect rect)
{
    auto* annotation = findMutable(id);
    rect = standardized(rect);
    if (annotation == nullptr
        || (!isShapeKind(annotation->kind)
            && annotation->kind != AnnotationKind::mosaicRectangle)
        || rect.width <= 0.0F
        || rect.height <= 0.0F
        || annotation->rect == rect) {
        return false;
    }
    auto before = snapshot();
    annotation->rect = rect;
    commit(std::move(before));
    return true;
}

bool AnnotationDocument::move(AnnotationId id, AnnotationPoint offset)
{
    const auto* annotation = find(id);
    if (annotation == nullptr || offset == AnnotationPoint{}) {
        return false;
    }
    if (isArrowLineAnnotation(*annotation)) {
        return updateArrowLine(id, translated(*annotation->arrowLine, offset));
    }
    if (isBrushAnnotation(*annotation)) {
        return updateBrushPath(id, translated(*annotation->brushPath, offset));
    }
    if (isMarkerAnnotation(*annotation)) {
        return updateMarkerLine(id, translated(*annotation->markerLine, offset));
    }
    if (isMosaicStrokeAnnotation(*annotation)) {
        return updateMosaicStroke(
            id, translated(*annotation->mosaicStroke, offset));
    }
    return updateRect(id, translated(annotation->rect, offset));
}

bool AnnotationDocument::updateKind(AnnotationId id, AnnotationKind kind)
{
    auto* annotation = findMutable(id);
    if (annotation == nullptr
        || !isShapeKind(kind)
        || annotation->kind == kind) {
        return false;
    }
    auto before = snapshot();
    annotation->kind = kind;
    commit(std::move(before));
    return true;
}

bool AnnotationDocument::updateRotation(
    AnnotationId id,
    float rotationDegrees)
{
    auto* annotation = findMutable(id);
    if (annotation == nullptr
        || annotation->rotationDegrees == rotationDegrees) {
        return false;
    }
    auto before = snapshot();
    annotation->rotationDegrees = rotationDegrees;
    commit(std::move(before));
    return true;
}

bool AnnotationDocument::updateStyle(AnnotationId id, AnnotationStyle style)
{
    auto* annotation = findMutable(id);
    if (annotation == nullptr || annotation->style == style) {
        return false;
    }
    auto before = snapshot();
    annotation->style = style;
    commit(std::move(before));
    return true;
}

bool AnnotationDocument::updateArrowLine(AnnotationId id, ArrowLine line)
{
    auto* annotation = findMutable(id);
    if (annotation == nullptr
        || !isArrowLineAnnotation(*annotation)
        || !hasUsableArrowLine(line)
        || *annotation->arrowLine == line) {
        return false;
    }
    auto before = snapshot();
    annotation->arrowLine = line;
    annotation->rect = arrowLineBounds(line);
    commit(std::move(before));
    return true;
}

bool AnnotationDocument::updateBrushPath(AnnotationId id, BrushPath path)
{
    auto* annotation = findMutable(id);
    if (annotation == nullptr
        || !isBrushAnnotation(*annotation)
        || path.points.size() < 2U
        || *annotation->brushPath == path) {
        return false;
    }
    auto before = snapshot();
    annotation->brushPath = std::move(path);
    annotation->rect = brushPathBounds(*annotation->brushPath);
    commit(std::move(before));
    return true;
}

bool AnnotationDocument::updateMarkerLine(AnnotationId id, MarkerLine line)
{
    auto* annotation = findMutable(id);
    if (annotation == nullptr
        || !isMarkerAnnotation(*annotation)
        || *annotation->markerLine == line) {
        return false;
    }
    auto before = snapshot();
    annotation->markerLine = line;
    annotation->rect = markerLineBounds(line);
    commit(std::move(before));
    return true;
}

bool AnnotationDocument::updateMosaicStroke(
    AnnotationId id,
    MosaicStroke stroke)
{
    auto* annotation = findMutable(id);
    if (annotation == nullptr || !isMosaicStrokeAnnotation(*annotation)
        || stroke.points.empty() || *annotation->mosaicStroke == stroke) {
        return false;
    }
    auto before = snapshot();
    annotation->mosaicStroke = std::move(stroke);
    annotation->rect = brushPathBounds(*annotation->mosaicStroke);
    commit(std::move(before));
    return true;
}

bool AnnotationDocument::updateMosaicRedaction(
    AnnotationId id,
    MosaicRedaction redaction)
{
    auto* annotation = findMutable(id);
    redaction.value = clampedMosaicRedactionValue(redaction.value);
    if (annotation == nullptr || !isMosaicAnnotation(*annotation)
        || annotation->mosaicRedaction == redaction) {
        return false;
    }
    auto before = snapshot();
    annotation->mosaicRedaction = redaction;
    if (mosaicRedactionEditBefore_.has_value()) {
        mosaicRedactionEditChanged_ = true;
        ++revision_;
        return true;
    }
    commit(std::move(before));
    return true;
}

void AnnotationDocument::beginMosaicRedactionEdit()
{
    if (!mosaicRedactionEditBefore_.has_value()) {
        mosaicRedactionEditBefore_ = snapshot();
        mosaicRedactionEditChanged_ = false;
    }
}

void AnnotationDocument::endMosaicRedactionEdit()
{
    if (!mosaicRedactionEditBefore_.has_value()) {
        return;
    }
    if (mosaicRedactionEditChanged_) {
        undoHistory_.push_back({
            std::move(*mosaicRedactionEditBefore_), snapshot()});
        redoHistory_.clear();
    }
    mosaicRedactionEditBefore_.reset();
    mosaicRedactionEditChanged_ = false;
}

bool AnnotationDocument::select(AnnotationId id) noexcept
{
    if (find(id) == nullptr) {
        return false;
    }
    selectedId_ = id;
    return true;
}

void AnnotationDocument::clearSelection() noexcept
{
    selectedId_.reset();
}

std::optional<AnnotationId> AnnotationDocument::selectedId() const noexcept
{
    return selectedId_;
}

const ShapeAnnotation* AnnotationDocument::find(AnnotationId id) const noexcept
{
    const auto index = indexOf(id);
    return index.has_value() ? &annotations_[*index] : nullptr;
}

const std::vector<ShapeAnnotation>& AnnotationDocument::annotations() const noexcept
{
    return annotations_;
}

bool AnnotationDocument::canUndo() const noexcept
{
    return !undoHistory_.empty();
}

bool AnnotationDocument::canRedo() const noexcept
{
    return !redoHistory_.empty();
}

bool AnnotationDocument::undo()
{
    if (undoHistory_.empty()) {
        return false;
    }
    auto entry = std::move(undoHistory_.back());
    undoHistory_.pop_back();
    restore(entry.before);
    redoHistory_.push_back(std::move(entry));
    ++revision_;
    return true;
}

bool AnnotationDocument::redo()
{
    if (redoHistory_.empty()) {
        return false;
    }
    auto entry = std::move(redoHistory_.back());
    redoHistory_.pop_back();
    restore(entry.after);
    undoHistory_.push_back(std::move(entry));
    ++revision_;
    return true;
}

std::uint64_t AnnotationDocument::revision() const noexcept
{
    return revision_;
}

std::optional<std::size_t> AnnotationDocument::indexOf(
    AnnotationId id) const noexcept
{
    const auto found = std::find_if(
        annotations_.begin(),
        annotations_.end(),
        [id](const ShapeAnnotation& annotation) { return annotation.id == id; });
    if (found == annotations_.end()) {
        return std::nullopt;
    }
    return static_cast<std::size_t>(found - annotations_.begin());
}

ShapeAnnotation* AnnotationDocument::findMutable(AnnotationId id) noexcept
{
    const auto index = indexOf(id);
    return index.has_value() ? &annotations_[*index] : nullptr;
}

AnnotationDocument::Snapshot AnnotationDocument::snapshot() const
{
    return {annotations_, selectedId_};
}

void AnnotationDocument::commit(Snapshot before)
{
    undoHistory_.push_back({std::move(before), snapshot()});
    redoHistory_.clear();
    ++revision_;
}

void AnnotationDocument::restore(const Snapshot& state)
{
    annotations_ = state.annotations;
    selectedId_ = state.selectedId;
}

} // namespace xxsnap::win
