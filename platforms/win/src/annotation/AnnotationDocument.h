#pragma once

#include "annotation/AnnotationTypes.h"

#include <cstdint>
#include <optional>
#include <vector>

namespace xxsnap::win {

class AnnotationDocument {
public:
    AnnotationId addShape(
        AnnotationKind kind,
        AnnotationRect rect,
        AnnotationStyle style = {},
        float rotationDegrees = 0.0F);

    bool remove(AnnotationId id);
    bool updateRect(AnnotationId id, AnnotationRect rect);
    bool move(AnnotationId id, AnnotationPoint offset);
    bool updateRotation(AnnotationId id, float rotationDegrees);
    bool updateStyle(AnnotationId id, AnnotationStyle style);

    bool select(AnnotationId id) noexcept;
    void clearSelection() noexcept;
    std::optional<AnnotationId> selectedId() const noexcept;

    const ShapeAnnotation* find(AnnotationId id) const noexcept;
    const std::vector<ShapeAnnotation>& annotations() const noexcept;

    bool canUndo() const noexcept;
    bool canRedo() const noexcept;
    bool undo();
    bool redo();
    std::uint64_t revision() const noexcept;

private:
    struct Snapshot {
        std::vector<ShapeAnnotation> annotations;
        std::optional<AnnotationId> selectedId;
    };

    struct HistoryEntry {
        Snapshot before;
        Snapshot after;
    };

    std::optional<std::size_t> indexOf(AnnotationId id) const noexcept;
    ShapeAnnotation* findMutable(AnnotationId id) noexcept;
    Snapshot snapshot() const;
    void commit(Snapshot before);
    void restore(const Snapshot& snapshot);

    std::vector<ShapeAnnotation> annotations_;
    std::optional<AnnotationId> selectedId_;
    std::vector<HistoryEntry> undoHistory_;
    std::vector<HistoryEntry> redoHistory_;
    AnnotationId nextId_ = 1;
    std::uint64_t revision_ = 0;
};

} // namespace xxsnap::win
