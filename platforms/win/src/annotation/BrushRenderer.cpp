#include "annotation/BrushRenderer.h"

#include "annotation/AnnotationRenderer.h"

#include <d2d1helper.h>

#include <utility>

namespace xxsnap::win {
namespace {

template<typename Interface>
class ComPtr final {
public:
    ComPtr() noexcept = default;
    ~ComPtr() { reset(); }

    Interface* get() const noexcept { return value_; }
    Interface* operator->() const noexcept { return value_; }
    Interface** put() noexcept
    {
        reset();
        return &value_;
    }
    void reset() noexcept
    {
        if (value_ != nullptr) {
            std::exchange(value_, nullptr)->Release();
        }
    }

private:
    Interface* value_ = nullptr;
};

D2D1_COLOR_F d2dColor(AnnotationColor value) noexcept
{
    return D2D1::ColorF(
        static_cast<float>(value.red) / 255.0F,
        static_cast<float>(value.green) / 255.0F,
        static_cast<float>(value.blue) / 255.0F,
        static_cast<float>(value.alpha) / 255.0F);
}

} // namespace

HRESULT drawBrushPath(
    ID2D1Factory* factory,
    ID2D1RenderTarget* renderTarget,
    const ShapeAnnotation& annotation) noexcept
{
    if (factory == nullptr || renderTarget == nullptr
        || !isBrushAnnotation(annotation)
        || annotation.brushPath->points.empty()) {
        return E_INVALIDARG;
    }
    ComPtr<ID2D1SolidColorBrush> brush;
    auto result = renderTarget->CreateSolidColorBrush(
        d2dColor(annotation.style.strokeColor), brush.put());
    if (FAILED(result)) {
        return result;
    }
    const auto dashes = normalizedStrokeDashPattern(
        annotation.style.strokePattern,
        annotation.style.strokeWidthDip);
    const D2D1_STROKE_STYLE_PROPERTIES properties{
        D2D1_CAP_STYLE_ROUND,
        D2D1_CAP_STYLE_ROUND,
        D2D1_CAP_STYLE_ROUND,
        D2D1_LINE_JOIN_ROUND,
        10.0F,
        dashes.empty() ? D2D1_DASH_STYLE_SOLID : D2D1_DASH_STYLE_CUSTOM,
        0.0F,
    };
    ComPtr<ID2D1StrokeStyle> strokeStyle;
    result = factory->CreateStrokeStyle(
        properties,
        dashes.empty() ? nullptr : dashes.data(),
        static_cast<UINT32>(dashes.size()),
        strokeStyle.put());
    if (FAILED(result)) {
        return result;
    }
    ComPtr<ID2D1PathGeometry> geometry;
    result = factory->CreatePathGeometry(geometry.put());
    if (FAILED(result)) {
        return result;
    }
    ComPtr<ID2D1GeometrySink> sink;
    result = geometry->Open(sink.put());
    if (FAILED(result)) {
        return result;
    }
    const auto& points = annotation.brushPath->points;
    sink->BeginFigure(
        D2D1::Point2F(points.front().x, points.front().y),
        D2D1_FIGURE_BEGIN_HOLLOW);
    if (points.size() == 1U) {
        sink->AddLine(D2D1::Point2F(
            points.front().x + 0.01F,
            points.front().y + 0.01F));
    } else {
        for (std::size_t index = 1; index < points.size(); ++index) {
            sink->AddLine(D2D1::Point2F(points[index].x, points[index].y));
        }
    }
    sink->EndFigure(D2D1_FIGURE_END_OPEN);
    result = sink->Close();
    if (FAILED(result)) {
        return result;
    }
    renderTarget->DrawGeometry(
        geometry.get(),
        brush.get(),
        annotation.style.strokeWidthDip,
        strokeStyle.get());
    return S_OK;
}

} // namespace xxsnap::win
