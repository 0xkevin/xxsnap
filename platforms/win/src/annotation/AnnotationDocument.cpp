#include "annotation/AnnotationDocument.h"
#include "annotation/NumberAnnotationMetrics.h"

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

AnnotationId AnnotationDocument::addText(
    AnnotationRect rect,
    std::wstring text,
    AnnotationStyle style,
    float rotationDegrees)
{
    rect = standardized(rect);
    if (rect.width <= 0.0F || rect.height <= 0.0F
        || nextId_ == invalidAnnotationId) {
        return invalidAnnotationId;
    }
    style.strokeWidthDip = 0.0F;
    style.strokePattern = AnnotationStrokePattern::solid;
    style.fillEnabled = false;
    style.textSize = clampedTextSize(style.textSize);
    auto before = snapshot();
    const auto id = nextId_++;
    annotations_.push_back({
        id, AnnotationKind::text, rect, std::move(style), rotationDegrees,
        std::nullopt, std::nullopt, std::nullopt, std::nullopt,
        std::nullopt, std::move(text),
    });
    selectedId_ = id;
    if (textEditBefore_.has_value()) {
        textEditChanged_ = true;
        ++revision_;
        return id;
    }
    commit(std::move(before));
    return id;
}

AnnotationId AnnotationDocument::addNumberMark(
    AnnotationRect rect,
    NumberMarkType type,
    std::optional<int> sequenceIndex,
    bool manualSequence,
    std::uint64_t groupId,
    AnnotationStyle style)
{
    rect = standardized(rect);
    if (rect.width <= 0.0F || rect.height <= 0.0F
        || nextId_ == invalidAnnotationId) {
        return invalidAnnotationId;
    }
    if (type == NumberMarkType::number) {
        sequenceIndex = clampedNumberValue(sequenceIndex.value_or(1));
    } else {
        sequenceIndex.reset();
        manualSequence = false;
        groupId = 0;
    }
    style.strokeWidthDip = 0.0F;
    style.strokePattern = AnnotationStrokePattern::solid;
    style.fillEnabled = false;
    style.textSize = clampedNumberSize(style.textSize);
    auto before = snapshot();
    const auto id = nextId_++;
    ShapeAnnotation annotation;
    annotation.id = id;
    annotation.kind = AnnotationKind::numberSequence;
    annotation.rect = rect;
    annotation.style = std::move(style);
    annotation.numberMarkType = type;
    annotation.numberSequenceIndex = sequenceIndex;
    annotation.numberSequenceIsManual = manualSequence;
    annotation.numberSequenceGroupId = groupId;
    annotations_.push_back(std::move(annotation));
    selectedId_ = id;
    if (numberEditBefore_.has_value()) {
        numberEditChanged_ = true;
        ++revision_;
        return id;
    }
    commit(std::move(before));
    return id;
}

AnnotationId AnnotationDocument::addMagnifier(
    AnnotationRect rect,
    MagnifierShape shape,
    float zoom,
    AnnotationStyle style)
{
    rect = standardized(rect);
    if (rect.width <= 0.0F || rect.height <= 0.0F
        || nextId_ == invalidAnnotationId) {
        return invalidAnnotationId;
    }
    style.strokePattern = AnnotationStrokePattern::solid;
    style.fillEnabled = false;
    auto before = snapshot();
    const auto id = nextId_++;
    ShapeAnnotation annotation;
    annotation.id = id;
    annotation.kind = AnnotationKind::magnifier;
    annotation.rect = rect;
    annotation.style = style;
    annotation.magnifierShape = shape;
    annotation.magnifierZoom = normalizedMagnifierZoom(zoom);
    annotations_.push_back(std::move(annotation));
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
    std::optional<Snapshot> before;
    if (!numberEditBefore_.has_value()) before = snapshot();
    annotations_.erase(annotations_.begin() + static_cast<std::ptrdiff_t>(*index));
    if (selectedId_ == id) {
        selectedId_ = annotations_.empty()
            ? std::nullopt
            : std::optional<AnnotationId>{annotations_.back().id};
    }
    if (numberEditBefore_.has_value()) {
        numberEditChanged_ = true;
        ++revision_;
    } else {
        commit(std::move(*before));
    }
    return true;
}

bool AnnotationDocument::updateRect(AnnotationId id, AnnotationRect rect)
{
    auto* annotation = findMutable(id);
    rect = standardized(rect);
    if (annotation == nullptr
        || (!isShapeKind(annotation->kind)
            && annotation->kind != AnnotationKind::mosaicRectangle
            && annotation->kind != AnnotationKind::text
            && annotation->kind != AnnotationKind::numberSequence
            && annotation->kind != AnnotationKind::magnifier)
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

bool AnnotationDocument::updateText(
    AnnotationId id,
    std::wstring text,
    AnnotationRect rect)
{
    auto* annotation = findMutable(id);
    rect = standardized(rect);
    if (annotation == nullptr || !isTextAnnotation(*annotation)
        || rect.width <= 0.0F || rect.height <= 0.0F
        || (*annotation->text == text && annotation->rect == rect)) {
        return false;
    }
    std::optional<Snapshot> before;
    if (!textEditBefore_.has_value()) before = snapshot();
    annotation->text = std::move(text);
    annotation->rect = rect;
    if (textEditBefore_.has_value()) {
        textEditChanged_ = true;
        ++revision_;
        return true;
    }
    commit(std::move(*before));
    return true;
}

bool AnnotationDocument::updateTextGeometry(
    AnnotationId id,
    AnnotationRect rect,
    AnnotationStyle style)
{
    auto* annotation = findMutable(id);
    rect = standardized(rect);
    if (annotation == nullptr || !isTextAnnotation(*annotation)
        || rect.width <= 0.0F || rect.height <= 0.0F
        || (annotation->rect == rect && annotation->style == style)) {
        return false;
    }
    std::optional<Snapshot> before;
    if (!textEditBefore_.has_value()) before = snapshot();
    annotation->rect = rect;
    annotation->style = std::move(style);
    if (textEditBefore_.has_value()) {
        textEditChanged_ = true;
        ++revision_;
        return true;
    }
    commit(std::move(*before));
    return true;
}

bool AnnotationDocument::updateNumberMark(
    AnnotationId id,
    NumberMarkType type,
    std::optional<int> sequenceIndex,
    bool manualSequence,
    std::uint64_t groupId)
{
    auto* annotation = findMutable(id);
    if (annotation == nullptr || !isNumberAnnotation(*annotation)) {
        return false;
    }
    if (type == NumberMarkType::number) {
        sequenceIndex = clampedNumberValue(sequenceIndex.value_or(1));
    } else {
        sequenceIndex.reset();
        manualSequence = false;
        groupId = 0;
    }
    if (annotation->numberMarkType == type
        && annotation->numberSequenceIndex == sequenceIndex
        && annotation->numberSequenceIsManual == manualSequence
        && annotation->numberSequenceGroupId == groupId) {
        return false;
    }
    std::optional<Snapshot> before;
    if (!numberEditBefore_.has_value()) before = snapshot();
    annotation->numberMarkType = type;
    annotation->numberSequenceIndex = sequenceIndex;
    annotation->numberSequenceIsManual = manualSequence;
    annotation->numberSequenceGroupId = groupId;
    if (numberEditBefore_.has_value()) {
        numberEditChanged_ = true;
        ++revision_;
    } else {
        commit(std::move(*before));
    }
    return true;
}

bool AnnotationDocument::updateNumberGeometry(
    AnnotationId id,
    AnnotationRect rect,
    AnnotationStyle style)
{
    auto* annotation = findMutable(id);
    rect = standardized(rect);
    style.textSize = clampedNumberSize(style.textSize);
    style.strokeWidthDip = 0.0F;
    style.strokePattern = AnnotationStrokePattern::solid;
    style.fillEnabled = false;
    if (annotation == nullptr || !isNumberAnnotation(*annotation)
        || rect.width <= 0.0F || rect.height <= 0.0F
        || (annotation->rect == rect && annotation->style == style)) {
        return false;
    }
    std::optional<Snapshot> before;
    if (!numberEditBefore_.has_value()) before = snapshot();
    annotation->rect = rect;
    annotation->style = std::move(style);
    if (numberEditBefore_.has_value()) {
        numberEditChanged_ = true;
        ++revision_;
    } else {
        commit(std::move(*before));
    }
    return true;
}

bool AnnotationDocument::updateMagnifier(
    AnnotationId id,
    MagnifierShape shape,
    float zoom,
    AnnotationStyle style)
{
    auto* annotation = findMutable(id);
    zoom = normalizedMagnifierZoom(zoom);
    style.strokePattern = AnnotationStrokePattern::solid;
    style.fillEnabled = false;
    if (annotation == nullptr || !isMagnifierAnnotation(*annotation)
        || (annotation->magnifierShape == shape
            && annotation->magnifierZoom == zoom
            && annotation->style == style)) {
        return false;
    }
    auto before = snapshot();
    annotation->magnifierShape = shape;
    annotation->magnifierZoom = zoom;
    annotation->style = style;
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

void AnnotationDocument::beginTextEdit()
{
    if (!textEditBefore_.has_value()) {
        textEditBefore_ = snapshot();
        textEditChanged_ = false;
    }
}

void AnnotationDocument::endTextEdit(bool keepChanges)
{
    if (!textEditBefore_.has_value()) {
        return;
    }
    if (!keepChanges) {
        restore(*textEditBefore_);
        ++revision_;
    } else if (textEditChanged_) {
        undoHistory_.push_back({std::move(*textEditBefore_), snapshot()});
        redoHistory_.clear();
    }
    textEditBefore_.reset();
    textEditChanged_ = false;
}

void AnnotationDocument::beginNumberEdit()
{
    if (!numberEditBefore_.has_value()) {
        numberEditBefore_ = snapshot();
        numberEditChanged_ = false;
    }
}

void AnnotationDocument::endNumberEdit(bool keepChanges)
{
    if (!numberEditBefore_.has_value()) {
        return;
    }
    if (!keepChanges) {
        restore(*numberEditBefore_);
        ++revision_;
    } else if (numberEditChanged_) {
        undoHistory_.push_back({std::move(*numberEditBefore_), snapshot()});
        redoHistory_.clear();
    }
    numberEditBefore_.reset();
    numberEditChanged_ = false;
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
