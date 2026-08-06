#include "annotation/AnnotationDocument.h"

#include <algorithm>
#include <cstddef>
#include <utility>

namespace xxsnap::win {

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
    annotations_.push_back({id, kind, rect, style, rotationDegrees});
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
