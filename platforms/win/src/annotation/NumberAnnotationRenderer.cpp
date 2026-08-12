#include "annotation/NumberAnnotationRenderer.h"

#include <d2d1helper.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <string>

namespace xxsnap::win {
namespace {

using Microsoft::WRL::ComPtr;

D2D1_COLOR_F color(AnnotationColor value) noexcept
{
    return D2D1::ColorF(
        static_cast<float>(value.red) / 255.0F,
        static_cast<float>(value.green) / 255.0F,
        static_cast<float>(value.blue) / 255.0F,
        static_cast<float>(value.alpha) / 255.0F);
}

HRESULT createCenteredLayout(
    IDWriteFactory* factory,
    const wchar_t* family,
    float fontSize,
    const std::wstring& text,
    AnnotationRect rect,
    IDWriteTextLayout** destination) noexcept
{
    ComPtr<IDWriteTextFormat> format;
    auto result = factory->CreateTextFormat(
        family, nullptr, DWRITE_FONT_WEIGHT_BOLD,
        DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
        fontSize, L"", format.ReleaseAndGetAddressOf());
    if (FAILED(result)) return result;
    result = format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
    if (FAILED(result)) return result;
    result = format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
    if (FAILED(result)) return result;
    result = format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    if (FAILED(result)) return result;
    return factory->CreateTextLayout(
        text.data(), static_cast<UINT32>(text.size()), format.Get(),
        rect.width, rect.height, destination);
}

HRESULT fittedNumberLayout(
    IDWriteFactory* factory,
    const std::wstring& text,
    const ShapeAnnotation& annotation,
    IDWriteTextLayout** destination) noexcept
{
    const auto rect = standardized(annotation.rect);
    const auto maximumSize = numberMarkTextSize(annotation.style.textSize);
    ComPtr<IDWriteTextLayout> layout;
    auto result = createCenteredLayout(
        factory, L"Consolas", maximumSize, text, rect,
        layout.ReleaseAndGetAddressOf());
    if (FAILED(result)) return result;
    DWRITE_TEXT_METRICS metrics{};
    result = layout->GetMetrics(&metrics);
    if (FAILED(result)) return result;
    const auto widthLimit = rect.width * 0.78F;
    const auto heightLimit = rect.height * 0.78F;
    if (metrics.width <= widthLimit && metrics.height <= heightLimit) {
        *destination = layout.Detach();
        return S_OK;
    }
    const auto widthScale = metrics.width > 0.0F
        ? widthLimit / metrics.width : 1.0F;
    const auto heightScale = metrics.height > 0.0F
        ? heightLimit / metrics.height : 1.0F;
    const auto fittedSize = (std::max)(6.0F,
        std::floor(maximumSize * (std::min)(widthScale, heightScale)));
    return createCenteredLayout(
        factory, L"Consolas", fittedSize, text, rect, destination);
}

} // namespace

AnnotationColor readableNumberForeground(
    AnnotationColor background) noexcept
{
    const auto luminance = 0.2126F * static_cast<float>(background.red) / 255.0F
        + 0.7152F * static_cast<float>(background.green) / 255.0F
        + 0.0722F * static_cast<float>(background.blue) / 255.0F;
    return luminance > 0.68F
        ? AnnotationColor{0, 0, 0, 219}
        : AnnotationColor{255, 255, 255, 255};
}

AnnotationRect numberCaretRect(
    const ShapeAnnotation& annotation,
    std::size_t caretPosition,
    const std::optional<std::wstring>& draftText) noexcept
{
    const auto rect = standardized(annotation.rect);
    const auto value = clampedNumberValue(
        annotation.numberSequenceIndex.value_or(1));
    const auto text = draftText.value_or(std::to_wstring(value));
    caretPosition = (std::min)(caretPosition, text.size());
    auto fontSize = numberMarkTextSize(annotation.style.textSize);
    if (text.size() == 2U) fontSize *= 0.88F;
    if (text.size() >= 3U) fontSize *= 0.68F;
    const auto textWidth = (std::min)(
        rect.width * 0.78F,
        fontSize * 0.62F * static_cast<float>(text.size()));
    const auto height = (std::min)(rect.height * 0.82F,
        (std::max)(8.0F, fontSize * 0.88F));
    const auto x = rect.x + rect.width / 2.0F - textWidth / 2.0F
        + textWidth * static_cast<float>(caretPosition)
            / static_cast<float>((std::max)(std::size_t{1U}, text.size()));
    return {x, rect.y + (rect.height - height) / 2.0F, 1.5F, height};
}

HRESULT drawNumberAnnotation(
    IDWriteFactory* factory,
    ID2D1RenderTarget* renderTarget,
    const ShapeAnnotation& annotation,
    const std::optional<std::wstring>& draftText) noexcept
{
    if (factory == nullptr || renderTarget == nullptr
        || !isNumberAnnotation(annotation)) {
        return E_INVALIDARG;
    }
    const auto rect = standardized(annotation.rect);
    ComPtr<ID2D1SolidColorBrush> markBrush;
    auto result = renderTarget->CreateSolidColorBrush(
        color(annotation.style.strokeColor),
        markBrush.ReleaseAndGetAddressOf());
    if (FAILED(result)) return result;
    std::wstring text;
    const wchar_t* family = L"Microsoft YaHei";
    auto fontSize = rect.height;
    ComPtr<ID2D1SolidColorBrush> textBrush;
    ComPtr<IDWriteTextLayout> layout;
    if (annotation.numberMarkType == NumberMarkType::number) {
        const auto circle = D2D1::Ellipse(
            D2D1::Point2F(rect.x + rect.width / 2.0F,
                rect.y + rect.height / 2.0F),
            rect.width / 2.0F, rect.height / 2.0F);
        renderTarget->FillEllipse(&circle, markBrush.Get());
        text = draftText.value_or(std::to_wstring(clampedNumberValue(
            annotation.numberSequenceIndex.value_or(1))));
        result = fittedNumberLayout(factory, text, annotation,
            layout.ReleaseAndGetAddressOf());
        if (FAILED(result)) return result;
        result = renderTarget->CreateSolidColorBrush(
            color(readableNumberForeground(annotation.style.strokeColor)),
            textBrush.ReleaseAndGetAddressOf());
    } else {
        text = annotation.numberMarkType == NumberMarkType::check
            ? L"✓" : L"×";
        result = createCenteredLayout(
            factory, family, fontSize, text, rect,
            layout.ReleaseAndGetAddressOf());
        if (FAILED(result)) return result;
        textBrush = markBrush;
    }
    if (FAILED(result)) return result;
    renderTarget->DrawTextLayout(
        D2D1::Point2F(rect.x, rect.y), layout.Get(), textBrush.Get(),
        D2D1_DRAW_TEXT_OPTIONS_CLIP);
    return S_OK;
}

} // namespace xxsnap::win
