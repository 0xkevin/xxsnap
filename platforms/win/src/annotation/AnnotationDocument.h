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
    AnnotationId addArrowLine(
        ArrowLine line,
        AnnotationStyle style = {});
    AnnotationId addBrushPath(
        BrushPath path,
        AnnotationStyle style = {});
    AnnotationId addMarkerLine(
        MarkerLine line,
        AnnotationStyle style = {});
    AnnotationId addMosaicStroke(
        MosaicStroke stroke,
        MosaicRedaction redaction,
        AnnotationStyle style = {});
    AnnotationId addMosaicRectangle(
        AnnotationRect rect,
        MosaicRedaction redaction,
        AnnotationStyle style = {},
        float rotationDegrees = 0.0F);
    AnnotationId addText(
        AnnotationRect rect,
        std::wstring text,
        AnnotationStyle style = {},
        float rotationDegrees = 0.0F);
    AnnotationId addNumberMark(
        AnnotationRect rect,
        NumberMarkType type,
        std::optional<int> sequenceIndex,
        bool manualSequence,
        std::uint64_t groupId,
        AnnotationStyle style = {});
    AnnotationId addMagnifier(
        AnnotationRect rect,
        MagnifierShape shape,
        float zoom,
        AnnotationStyle style = {});
    bool addEraserMask(
        AnnotationRect rect,
        std::vector<AnnotationId> affectedAnnotationIds);
    bool clearAnnotationsAndMasks();

    bool remove(AnnotationId id);
    bool updateRect(AnnotationId id, AnnotationRect rect);
    bool move(AnnotationId id, AnnotationPoint offset);
    bool updateKind(AnnotationId id, AnnotationKind kind);
    bool updateRotation(AnnotationId id, float rotationDegrees);
    bool updateStyle(AnnotationId id, AnnotationStyle style);
    bool updateArrowLine(AnnotationId id, ArrowLine line);
    bool updateBrushPath(AnnotationId id, BrushPath path);
    bool updateMarkerLine(AnnotationId id, MarkerLine line);
    bool updateMosaicStroke(AnnotationId id, MosaicStroke stroke);
    bool updateMosaicRedaction(AnnotationId id, MosaicRedaction redaction);
    bool updateText(
        AnnotationId id,
        std::wstring text,
        AnnotationRect rect);
    bool updateTextGeometry(
        AnnotationId id,
        AnnotationRect rect,
        AnnotationStyle style);
    bool updateNumberMark(
        AnnotationId id,
        NumberMarkType type,
        std::optional<int> sequenceIndex,
        bool manualSequence,
        std::uint64_t groupId);
    bool updateNumberGeometry(
        AnnotationId id,
        AnnotationRect rect,
        AnnotationStyle style);
    bool updateMagnifier(
        AnnotationId id,
        MagnifierShape shape,
        float zoom,
        AnnotationStyle style);
    void beginMosaicRedactionEdit();
    void endMosaicRedactionEdit();
    void beginTextEdit();
    void endTextEdit(bool keepChanges);
    void beginNumberEdit();
    void endNumberEdit(bool keepChanges = true);

    bool select(AnnotationId id) noexcept;
    void clearSelection() noexcept;
    std::optional<AnnotationId> selectedId() const noexcept;

    const ShapeAnnotation* find(AnnotationId id) const noexcept;
    const std::vector<ShapeAnnotation>& annotations() const noexcept;
    const std::vector<EraserMask>& eraserMasks() const noexcept;

    bool canUndo() const noexcept;
    bool canRedo() const noexcept;
    bool undo();
    bool redo();
    std::uint64_t revision() const noexcept;

private:
    struct Snapshot {
        std::vector<ShapeAnnotation> annotations;
        std::vector<EraserMask> eraserMasks;
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
    std::vector<EraserMask> eraserMasks_;
    std::optional<AnnotationId> selectedId_;
    std::vector<HistoryEntry> undoHistory_;
    std::vector<HistoryEntry> redoHistory_;
    std::optional<Snapshot> mosaicRedactionEditBefore_;
    bool mosaicRedactionEditChanged_ = false;
    std::optional<Snapshot> textEditBefore_;
    bool textEditChanged_ = false;
    std::optional<Snapshot> numberEditBefore_;
    bool numberEditChanged_ = false;
    AnnotationId nextId_ = 1;
    std::uint64_t revision_ = 0;
};

} // namespace xxsnap::win
