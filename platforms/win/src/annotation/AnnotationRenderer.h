#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "annotation/AnnotationDocument.h"

#include <Windows.h>
#include <d2d1.h>

#include <optional>
#include <vector>

namespace xxsnap::win {

struct AnnotationRenderItem {
    ShapeAnnotation annotation{};
    bool isPreview = false;
};

struct AnnotationRenderPlan {
    std::vector<AnnotationRenderItem> items;
    std::vector<AnnotationPoint> resizeHandles;
    std::optional<AnnotationPoint> rotationHandle;
};

AnnotationRenderPlan buildAnnotationRenderPlan(
    const AnnotationDocument& document,
    const std::optional<ShapeAnnotation>& preview,
    AnnotationPoint selectionOriginDip,
    bool showEditingAffordances);

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
};

} // namespace xxsnap::win
