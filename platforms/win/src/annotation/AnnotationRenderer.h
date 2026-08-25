#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "annotation/AnnotationDocument.h"
#include "annotation/NumberAnnotationMetrics.h"

#include <Windows.h>
#include <d2d1.h>
#include <dwrite.h>

#include <optional>
#include <utility>
#include <vector>

namespace xxsnap::win {

struct AnnotationRenderItem {
    ShapeAnnotation annotation{};
    bool isPreview = false;
    std::optional<std::wstring> numberDraft;
};

struct AnnotationRenderPlan {
    std::vector<AnnotationRenderItem> items;
    std::vector<AnnotationPoint> resizeHandles;
    std::vector<AnnotationPoint> lineHandles;
    std::optional<AnnotationPoint> rotationHandle;
    std::optional<AnnotationRect> textCaret;
    float textCaretRotationDegrees = 0.0F;
    std::optional<AnnotationPoint> textCaretRotationCenter;
    std::optional<AnnotationPoint> textDeleteHandle;
    std::optional<AnnotationRect> textEditingOutline;
    float textEditingOutlineRotationDegrees = 0.0F;
    std::optional<AnnotationRect> numberOutline;
    std::vector<std::pair<NumberHandleKind, AnnotationRect>> numberHandles;
    bool numberIncrementEnabled = false;
    bool numberDecrementEnabled = false;
    std::optional<AnnotationRect> numberCaret;
    std::optional<AnnotationRect> eraserPreview;
    std::optional<AnnotationRect> mosaicPreviewOutline;
};

struct AnnotationEditingState {
    AnnotationId id = invalidAnnotationId;
    std::size_t caretPosition = 0U;
    std::optional<std::wstring> draftText;
};

AnnotationRenderPlan buildAnnotationRenderPlan(
    const AnnotationDocument& document,
    const std::optional<ShapeAnnotation>& preview,
    AnnotationPoint selectionOriginDip,
    bool showEditingAffordances,
    std::optional<AnnotationEditingState> editingState = std::nullopt);

std::vector<float> strokeDashPattern(
    AnnotationStrokePattern pattern,
    float strokeWidthDip);

std::vector<float> normalizedStrokeDashPattern(
    AnnotationStrokePattern pattern,
    float strokeWidthDip);

std::vector<AnnotationPoint> sketchStrokeSamplePoints(
    AnnotationPoint start,
    AnnotationPoint end,
    float lineWidthDip);

class AnnotationRenderer final {
public:
    explicit AnnotationRenderer(ID2D1Factory* factory) noexcept;
    ~AnnotationRenderer();

    AnnotationRenderer(const AnnotationRenderer&) = delete;
    AnnotationRenderer& operator=(const AnnotationRenderer&) = delete;

    HRESULT draw(
        ID2D1RenderTarget* renderTarget,
        const AnnotationRenderPlan& plan) const noexcept;

private:
    ID2D1Factory* factory_ = nullptr;
    IDWriteFactory* dwriteFactory_ = nullptr;
};

} // namespace xxsnap::win
