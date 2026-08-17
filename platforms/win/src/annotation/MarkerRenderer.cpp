#include "annotation/MarkerRenderer.h"
#include "annotation/MarkerMetrics.h"

#include <d2d1helper.h>
#include <wrl/client.h>

namespace xxsnap::win {

HRESULT drawMarkerLine(
    ID2D1RenderTarget* renderTarget,
    const ShapeAnnotation& annotation) noexcept
{
    if (renderTarget == nullptr || !isMarkerAnnotation(annotation)) {
        return E_INVALIDARG;
    }
    const auto color = annotation.style.strokeColor;
    Microsoft::WRL::ComPtr<ID2D1SolidColorBrush> brush;
    const auto result = renderTarget->CreateSolidColorBrush(
        D2D1::ColorF(
            static_cast<float>(color.red) / 255.0F,
            static_cast<float>(color.green) / 255.0F,
            static_cast<float>(color.blue) / 255.0F,
            markerMetrics::opacity),
        brush.ReleaseAndGetAddressOf());
    if (FAILED(result)) {
        return result;
    }
    const auto line = *annotation.markerLine;
    const auto dx = line.end.x - line.start.x;
    const auto dy = line.end.y - line.start.y;
    if (dx * dx + dy * dy < 0.25F) {
        const auto ellipse = D2D1::Ellipse(
            D2D1::Point2F(line.start.x, line.start.y),
            annotation.style.strokeWidthDip / 2.0F,
            annotation.style.strokeWidthDip / 2.0F);
        renderTarget->FillEllipse(&ellipse, brush.Get());
    } else {
        renderTarget->DrawLine(
            D2D1::Point2F(line.start.x, line.start.y),
            D2D1::Point2F(line.end.x, line.end.y),
            brush.Get(),
            annotation.style.strokeWidthDip);
        const auto radius = annotation.style.strokeWidthDip / 2.0F;
        const auto startCap = D2D1::Ellipse(
            D2D1::Point2F(line.start.x, line.start.y), radius, radius);
        const auto endCap = D2D1::Ellipse(
            D2D1::Point2F(line.end.x, line.end.y), radius, radius);
        renderTarget->FillEllipse(&startCap, brush.Get());
        renderTarget->FillEllipse(&endCap, brush.Get());
    }
    return S_OK;
}

} // namespace xxsnap::win
