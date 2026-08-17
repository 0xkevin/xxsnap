#include "annotation/TextAnnotationRenderer.h"

#include <d2d1helper.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <new>
#include <utility>

namespace xxsnap::win {
namespace {

template<typename Interface>
class ComPtr final {
public:
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

D2D1_COLOR_F d2dColor(AnnotationColor color) noexcept
{
    return D2D1::ColorF(
        static_cast<float>(color.red) / 255.0F,
        static_cast<float>(color.green) / 255.0F,
        static_cast<float>(color.blue) / 255.0F,
        static_cast<float>(color.alpha) / 255.0F);
}

HRESULT createTextFormat(
    IDWriteFactory* factory,
    const AnnotationStyle& style,
    IDWriteTextFormat** result) noexcept
{
    if (factory == nullptr || result == nullptr) {
        return E_INVALIDARG;
    }
    const auto family = style.textFontFamily.empty()
        ? textDefaultFontFamily : style.textFontFamily.c_str();
    const auto weight = style.textBold
        ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_MEDIUM;
    const auto fontStyle = style.textItalic
        ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL;
    auto status = factory->CreateTextFormat(
        family, nullptr, weight, fontStyle, DWRITE_FONT_STRETCH_NORMAL,
        clampedTextSize(style.textSize) * textDisplayScale,
        L"zh-CN", result);
    if (FAILED(status)) {
        status = factory->CreateTextFormat(
            textDefaultFontFamily, nullptr, weight, fontStyle,
            DWRITE_FONT_STRETCH_NORMAL,
            clampedTextSize(style.textSize) * textDisplayScale,
            L"zh-CN", result);
    }
    if (SUCCEEDED(status)) {
        status = (*result)->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    }
    return status;
}

class GlyphRenderer final : public IDWriteTextRenderer {
public:
    GlyphRenderer(
        ID2D1Factory* factory,
        ID2D1RenderTarget* target,
        ID2D1Brush* fill,
        ID2D1Brush* outline,
        float outlineWidth) noexcept
        : factory_(factory), target_(target), fill_(fill), outline_(outline),
          outlineWidth_(outlineWidth)
    {
        if (factory_) factory_->AddRef();
        if (target_) target_->AddRef();
        if (fill_) fill_->AddRef();
        if (outline_) outline_->AddRef();
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(
        REFIID iid, void** object) noexcept override
    {
        if (object == nullptr) return E_POINTER;
        *object = nullptr;
        if (iid == __uuidof(IUnknown)
            || iid == __uuidof(IDWritePixelSnapping)
            || iid == __uuidof(IDWriteTextRenderer)) {
            *object = static_cast<IDWriteTextRenderer*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() noexcept override
    {
        return ++references_;
    }

    ULONG STDMETHODCALLTYPE Release() noexcept override
    {
        const auto remaining = --references_;
        if (remaining == 0U) delete this;
        return remaining;
    }

    HRESULT STDMETHODCALLTYPE IsPixelSnappingDisabled(
        void*, BOOL* disabled) noexcept override
    {
        if (disabled == nullptr) return E_POINTER;
        *disabled = FALSE;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE GetCurrentTransform(
        void*, DWRITE_MATRIX* matrix) noexcept override
    {
        if (matrix == nullptr) return E_POINTER;
        D2D1_MATRIX_3X2_F transform{};
        target_->GetTransform(&transform);
        matrix->m11 = transform._11;
        matrix->m12 = transform._12;
        matrix->m21 = transform._21;
        matrix->m22 = transform._22;
        matrix->dx = transform._31;
        matrix->dy = transform._32;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE GetPixelsPerDip(
        void*, FLOAT* pixelsPerDip) noexcept override
    {
        if (pixelsPerDip == nullptr) return E_POINTER;
        FLOAT dpiX = 96.0F, dpiY = 96.0F;
        target_->GetDpi(&dpiX, &dpiY);
        *pixelsPerDip = dpiX / 96.0F;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DrawGlyphRun(
        void*, FLOAT baselineX, FLOAT baselineY,
        DWRITE_MEASURING_MODE,
        const DWRITE_GLYPH_RUN* run,
        const DWRITE_GLYPH_RUN_DESCRIPTION*,
        IUnknown*) noexcept override
    {
        if (run == nullptr || run->fontFace == nullptr) return E_INVALIDARG;
        ComPtr<ID2D1PathGeometry> path;
        auto status = factory_->CreatePathGeometry(path.put());
        if (FAILED(status)) return status;
        ComPtr<ID2D1GeometrySink> sink;
        status = path->Open(sink.put());
        if (FAILED(status)) return status;
        status = run->fontFace->GetGlyphRunOutline(
            run->fontEmSize, run->glyphIndices, run->glyphAdvances,
            run->glyphOffsets, run->glyphCount, run->isSideways,
            (run->bidiLevel & 1U) != 0U, sink.get());
        if (SUCCEEDED(status)) status = sink->Close();
        if (FAILED(status)) return status;
        ComPtr<ID2D1TransformedGeometry> positioned;
        status = factory_->CreateTransformedGeometry(
            path.get(), D2D1::Matrix3x2F::Translation(baselineX, baselineY),
            positioned.put());
        if (FAILED(status)) return status;
        if (outline_ != nullptr && outlineWidth_ > 0.0F) {
            target_->DrawGeometry(
                positioned.get(), outline_, outlineWidth_);
        }
        target_->FillGeometry(positioned.get(), fill_);
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DrawUnderline(
        void*, FLOAT, FLOAT, const DWRITE_UNDERLINE*, IUnknown*) noexcept override
    {
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DrawStrikethrough(
        void*, FLOAT, FLOAT, const DWRITE_STRIKETHROUGH*, IUnknown*) noexcept override
    {
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DrawInlineObject(
        void*, FLOAT, FLOAT, IDWriteInlineObject*, BOOL, BOOL,
        IUnknown*) noexcept override
    {
        return S_OK;
    }

private:
    ~GlyphRenderer()
    {
        if (outline_) outline_->Release();
        if (fill_) fill_->Release();
        if (target_) target_->Release();
        if (factory_) factory_->Release();
    }
    std::atomic<ULONG> references_{1U};
    ID2D1Factory* factory_ = nullptr;
    ID2D1RenderTarget* target_ = nullptr;
    ID2D1Brush* fill_ = nullptr;
    ID2D1Brush* outline_ = nullptr;
    float outlineWidth_ = 0.0F;
};

IDWriteFactory* sharedDWriteFactory() noexcept
{
    static IDWriteFactory* factory = []() noexcept {
        IDWriteFactory* created = nullptr;
        const auto status = DWriteCreateFactory(
            DWRITE_FACTORY_TYPE_SHARED,
            __uuidof(IDWriteFactory),
            reinterpret_cast<IUnknown**>(&created));
        return SUCCEEDED(status) ? created : nullptr;
    }();
    return factory;
}

HRESULT createTextLayout(
    IDWriteFactory* factory,
    const ShapeAnnotation& annotation,
    IDWriteTextLayout** result) noexcept
{
    if (factory == nullptr || result == nullptr
        || !isTextAnnotation(annotation)) {
        return E_INVALIDARG;
    }
    ComPtr<IDWriteTextFormat> format;
    auto status = createTextFormat(factory, annotation.style, format.put());
    if (FAILED(status)) return status;
    const auto rect = standardized(annotation.rect);
    return factory->CreateTextLayout(
        annotation.text->data(), static_cast<UINT32>(annotation.text->size()),
        format.get(), (std::max)(1.0F, rect.width),
        (std::max)(1.0F, rect.height), result);
}

} // namespace

AnnotationRect measuredTextRect(
    AnnotationPoint anchor,
    const std::wstring& text,
    const AnnotationStyle& style) noexcept
{
    auto* factory = sharedDWriteFactory();
    const auto fontSize = clampedTextSize(style.textSize) * textDisplayScale;
    auto width = textCaretWidthDip;
    auto height = std::ceil(fontSize * 1.25F);
    if (factory != nullptr) {
        ComPtr<IDWriteTextFormat> format;
        if (SUCCEEDED(createTextFormat(factory, style, format.put()))) {
            const auto& measuredText = text.empty()
                ? std::wstring(L" ") : text;
            ComPtr<IDWriteTextLayout> layout;
            if (SUCCEEDED(factory->CreateTextLayout(
                    measuredText.data(),
                    static_cast<UINT32>(measuredText.size()), format.get(),
                    10000.0F, 10000.0F, layout.put()))) {
                DWRITE_TEXT_METRICS metrics{};
                if (SUCCEEDED(layout->GetMetrics(&metrics))) {
                    width = text.empty() ? textCaretWidthDip
                        : std::ceil(metrics.widthIncludingTrailingWhitespace);
                    height = std::ceil(metrics.height);
                }
            }
        }
    }
    width += textHorizontalPaddingDip * 2.0F;
    return {
        anchor.x - textHorizontalPaddingDip,
        anchor.y - height / 2.0F,
        width,
        height,
    };
}

AnnotationRect textCaretRect(
    const ShapeAnnotation& annotation,
    std::size_t textPosition) noexcept
{
    const auto rect = standardized(annotation.rect);
    const auto fallbackHeight = clampedTextSize(annotation.style.textSize)
        * textDisplayScale;
    AnnotationRect caret{
        rect.x + textHorizontalPaddingDip,
        rect.y,
        textCaretWidthDip,
        fallbackHeight,
    };
    if (!isTextAnnotation(annotation)) return caret;
    auto* factory = sharedDWriteFactory();
    ComPtr<IDWriteTextLayout> layout;
    if (factory == nullptr
        || FAILED(createTextLayout(factory, annotation, layout.put()))) {
        return caret;
    }
    const auto clamped = static_cast<UINT32>((std::min)(
        textPosition, annotation.text->size()));
    FLOAT x = 0.0F;
    FLOAT y = 0.0F;
    DWRITE_HIT_TEST_METRICS metrics{};
    if (FAILED(layout->HitTestTextPosition(
            clamped, FALSE, &x, &y, &metrics))) {
        return caret;
    }
    caret.x += x;
    caret.y += y;
    caret.height = (std::max)(1.0F, metrics.height);
    return caret;
}

std::optional<std::size_t> textPositionAtPoint(
    const ShapeAnnotation& annotation,
    AnnotationPoint unrotatedPoint) noexcept
{
    if (!isTextAnnotation(annotation)) return std::nullopt;
    auto* factory = sharedDWriteFactory();
    ComPtr<IDWriteTextLayout> layout;
    if (factory == nullptr
        || FAILED(createTextLayout(factory, annotation, layout.put()))) {
        return std::nullopt;
    }
    const auto rect = standardized(annotation.rect);
    BOOL trailing = FALSE;
    BOOL inside = FALSE;
    DWRITE_HIT_TEST_METRICS metrics{};
    if (FAILED(layout->HitTestPoint(
            unrotatedPoint.x - rect.x - textHorizontalPaddingDip,
            unrotatedPoint.y - rect.y,
            &trailing, &inside, &metrics))) {
        return std::nullopt;
    }
    const auto position = static_cast<std::size_t>(metrics.textPosition)
        + (trailing != FALSE ? metrics.length : 0U);
    return (std::min)(position, annotation.text->size());
}

HRESULT drawTextAnnotation(
    ID2D1Factory* d2dFactory,
    IDWriteFactory* dwriteFactory,
    ID2D1RenderTarget* renderTarget,
    const ShapeAnnotation& annotation) noexcept
{
    if (d2dFactory == nullptr || dwriteFactory == nullptr
        || renderTarget == nullptr || !isTextAnnotation(annotation)) {
        return E_INVALIDARG;
    }
    if (annotation.text->empty()) return S_OK;
    const auto rect = standardized(annotation.rect);
    ComPtr<IDWriteTextLayout> layout;
    auto status = createTextLayout(
        dwriteFactory, annotation, layout.put());
    if (FAILED(status)) return status;
    ComPtr<ID2D1SolidColorBrush> fill;
    status = renderTarget->CreateSolidColorBrush(
        d2dColor(annotation.style.strokeColor), fill.put());
    if (FAILED(status)) return status;
    ComPtr<ID2D1SolidColorBrush> outline;
    if (annotation.style.textOutlineEnabled) {
        status = renderTarget->CreateSolidColorBrush(
            d2dColor(annotation.style.textOutlineColor), outline.put());
        if (FAILED(status)) return status;
    }
    const auto outlineWidth = annotation.style.textOutlineEnabled
        ? (std::max)(1.0F, annotation.style.textSize
            * textDisplayScale * 0.08F) : 0.0F;
    auto* renderer = new (std::nothrow) GlyphRenderer(
        d2dFactory, renderTarget, fill.get(), outline.get(), outlineWidth);
    if (renderer == nullptr) return E_OUTOFMEMORY;
    status = layout->Draw(nullptr, renderer,
        rect.x + textHorizontalPaddingDip, rect.y);
    renderer->Release();
    return status;
}

} // namespace xxsnap::win
