#include "overlay/OverlayRenderer.h"

#include "annotation/ArrowLineRenderer.h"

#include <d2d1.h>
#include <d2d1helper.h>
#include <dwrite.h>
#include <objbase.h>
#include <wincodec.h>

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <limits>
#include <locale>
#include <new>
#include <sstream>
#include <utility>

namespace xxsnap::win {

namespace {

constexpr float windowsBaselineDpi = 96.0F;

template<typename Interface>
class ComPtr final {
public:
    ComPtr() noexcept = default;
    ~ComPtr() { reset(); }

    ComPtr(const ComPtr&) = delete;
    ComPtr& operator=(const ComPtr&) = delete;

    ComPtr(ComPtr&& other) noexcept
        : value_(std::exchange(other.value_, nullptr))
    {
    }

    ComPtr& operator=(ComPtr&& other) noexcept
    {
        if (this != &other) {
            reset();
            value_ = std::exchange(other.value_, nullptr);
        }
        return *this;
    }

    Interface* get() const noexcept { return value_; }
    Interface* operator->() const noexcept { return value_; }

    Interface** put() noexcept
    {
        reset();
        return &value_;
    }

    void attach(Interface* value) noexcept
    {
        reset();
        value_ = value;
    }

    void reset() noexcept
    {
        if (value_ != nullptr) {
            std::exchange(value_, nullptr)->Release();
        }
    }

    explicit operator bool() const noexcept { return value_ != nullptr; }

private:
    Interface* value_ = nullptr;
};

float normalizedDpi(std::uint32_t dpi) noexcept
{
    return dpi == 0U ? windowsBaselineDpi : static_cast<float>(dpi);
}

float floorDip(float value) noexcept
{
    const auto truncated = static_cast<std::int64_t>(value);
    const auto result = static_cast<float>(truncated);
    return result > value ? result - 1.0F : result;
}

DipRect clampRect(DipRect rect, DipRect bounds) noexcept
{
    if (rect.width > bounds.width) {
        rect.width = bounds.width;
    }
    if (rect.height > bounds.height) {
        rect.height = bounds.height;
    }
    rect.x = (std::max)(bounds.x, (std::min)(rect.x, bounds.x + bounds.width - rect.width));
    rect.y = (std::max)(bounds.y, (std::min)(rect.y, bounds.y + bounds.height - rect.height));
    return rect;
}

DipRect insetRect(DipRect rect, float inset) noexcept
{
    const auto horizontal = (std::min)(inset, rect.width / 2.0F);
    const auto vertical = (std::min)(inset, rect.height / 2.0F);
    return {
        rect.x + horizontal,
        rect.y + vertical,
        rect.width - horizontal * 2.0F,
        rect.height - vertical * 2.0F,
    };
}

float rectRight(DipRect rect) noexcept
{
    return rect.x + rect.width;
}

float rectBottom(DipRect rect) noexcept
{
    return rect.y + rect.height;
}

bool containsRect(DipRect bounds, DipRect rect) noexcept
{
    return rect.x >= bounds.x
        && rect.y >= bounds.y
        && rectRight(rect) <= rectRight(bounds)
        && rectBottom(rect) <= rectBottom(bounds);
}

bool intersectsRect(DipRect lhs, DipRect rhs) noexcept
{
    return lhs.x < rectRight(rhs)
        && rectRight(lhs) > rhs.x
        && lhs.y < rectBottom(rhs)
        && rectBottom(lhs) > rhs.y;
}

DipRect toolbarRect(DipRect anchor, DipRect bounds, float width) noexcept
{
    const auto gap = VisualStyleCatalog::toolbarGapDip;
    const auto height = ToolbarMetrics::heightDip;
    // SelectionToolbarState.toolbarRect order, translated from AppKit's
    // bottom-up coordinates to Direct2D's top-down coordinates.
    const std::array candidates{
        DipRect{rectRight(anchor) - width, rectBottom(anchor) + gap, width, height},
        DipRect{rectRight(anchor) - width, anchor.y - gap - height, width, height},
        DipRect{rectRight(anchor) + gap, rectBottom(anchor) - gap - height, width, height},
        DipRect{rectRight(anchor) + gap, anchor.y + gap, width, height},
        DipRect{anchor.x - gap - width, rectBottom(anchor) - gap - height, width, height},
        DipRect{anchor.x - gap - width, anchor.y + gap, width, height},
    };

    for (const auto candidate : candidates) {
        if (containsRect(bounds, candidate)
            && !intersectsRect(candidate, anchor)) {
            return candidate;
        }
    }
    for (const auto candidate : candidates) {
        const auto clamped = clampRect(candidate, bounds);
        if (!intersectsRect(clamped, anchor)) {
            return clamped;
        }
    }
    return clampRect(candidates[0], bounds);
}

std::wstring sizeLabelText(PixelRect selection)
{
    selection = snipory::core::portable::standardized(selection);
    return std::to_wstring(selection.width)
        + VisualStyleCatalog::sizeLabelDimensionSeparator
        + std::to_wstring(selection.height)
        + VisualStyleCatalog::sizeLabelSuffix;
}

DipRect toLocalDipRect(
    PixelRect rect,
    PixelRect display,
    std::uint32_t dpiX,
    std::uint32_t dpiY) noexcept
{
    return {
        physicalPixelsToDip(rect.x - display.x, dpiX),
        physicalPixelsToDip(rect.y - display.y, dpiY),
        physicalPixelsToDip(rect.width, dpiX),
        physicalPixelsToDip(rect.height, dpiY),
    };
}

void appendNumber(std::ostringstream& stream, float value)
{
    if (std::fabs(value) < 0.0005F) {
        value = 0.0F;
    }
    const auto rounded = std::llround(value);
    if (std::fabs(value - static_cast<float>(rounded)) < 0.0005F) {
        stream << rounded;
        return;
    }

    std::ostringstream number;
    number.imbue(std::locale::classic());
    number << std::fixed << std::setprecision(3) << value;
    auto text = number.str();
    while (!text.empty() && text.back() == '0') {
        text.pop_back();
    }
    if (!text.empty() && text.back() == '.') {
        text.pop_back();
    }
    stream << text;
}

void appendRect(std::ostringstream& stream, DipRect rect)
{
    stream << '[';
    appendNumber(stream, rect.x);
    stream << ',';
    appendNumber(stream, rect.y);
    stream << ',';
    appendNumber(stream, rect.width);
    stream << ',';
    appendNumber(stream, rect.height);
    stream << ']';
}

D2D1_RECT_F d2dRect(DipRect rect) noexcept
{
    return D2D1::RectF(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height);
}

D2D1_RECT_F d2dRect(AnnotationRect rect) noexcept
{
    return D2D1::RectF(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height);
}

D2D1_COLOR_F color(Rgba8 value) noexcept
{
    return D2D1::ColorF(
        static_cast<float>(value.red) / 255.0F,
        static_cast<float>(value.green) / 255.0F,
        static_cast<float>(value.blue) / 255.0F,
        static_cast<float>(value.alpha) / 255.0F);
}

D2D1_COLOR_F annotationColor(AnnotationColor value, float alpha = 1.0F) noexcept
{
    return D2D1::ColorF(
        static_cast<float>(value.red) / 255.0F,
        static_cast<float>(value.green) / 255.0F,
        static_cast<float>(value.blue) / 255.0F,
        static_cast<float>(value.alpha) / 255.0F * alpha);
}

D2D1_COLOR_F colorWithMultipliedAlpha(Rgba8 value, float alpha) noexcept
{
    return D2D1::ColorF(
        static_cast<float>(value.red) / 255.0F,
        static_cast<float>(value.green) / 255.0F,
        static_cast<float>(value.blue) / 255.0F,
        static_cast<float>(value.alpha) / 255.0F * alpha);
}

OverlayRendererError error(
    OverlayRendererErrorCode code,
    HRESULT nativeCode,
    int resourceId = 0) noexcept
{
    return {code, nativeCode, resourceId};
}

} // namespace

float physicalPixelsToDip(std::int64_t pixels, std::uint32_t dpi) noexcept
{
    return static_cast<float>(
        static_cast<long double>(pixels) * windowsBaselineDpi / normalizedDpi(dpi));
}

std::int64_t dipLengthToPhysicalPixels(float dips, std::uint32_t dpi) noexcept
{
    const auto value = static_cast<long double>(dips) * normalizedDpi(dpi)
        / windowsBaselineDpi;
    if (value >= static_cast<long double>(std::numeric_limits<std::int64_t>::max())) {
        return std::numeric_limits<std::int64_t>::max();
    }
    if (value <= static_cast<long double>(std::numeric_limits<std::int64_t>::min())) {
        return std::numeric_limits<std::int64_t>::min();
    }
    return static_cast<std::int64_t>(std::llround(value));
}

std::optional<OverlayRendererError> checkTextFormatConfigurationResult(
    HRESULT result) noexcept
{
    if (FAILED(result)) {
        return OverlayRendererError{
            OverlayRendererErrorCode::textFormatConfigurationFailed,
            result,
            0,
        };
    }
    return std::nullopt;
}

OverlayLayout computeOverlayLayout(const OverlayLayoutInput& input)
{
    const auto display = snipory::core::portable::standardized(input.displayRectPhysical);
    const auto selection = snipory::core::portable::standardized(input.selectionRectPhysical);
    const auto clippedSelection = snipory::core::portable::intersection(display, selection);

    OverlayLayout layout;
    layout.showActions = input.showActions;
    layout.overlayBounds = {
        0.0F,
        0.0F,
        physicalPixelsToDip(display.width, input.dpiX),
        physicalPixelsToDip(display.height, input.dpiY),
    };
    layout.sizeLabelText = sizeLabelText(selection);
    layout.border = toLocalDipRect(
        selection,
        display,
        input.dpiX,
        input.dpiY);

    if (!clippedSelection.has_value()) {
        layout.mask[0] = layout.overlayBounds;
        return layout;
    }

    const auto visibleSelection = toLocalDipRect(
        *clippedSelection,
        display,
        input.dpiX,
        input.dpiY);
    layout.mask = {{
        {0.0F, 0.0F, layout.overlayBounds.width, visibleSelection.y},
        {0.0F, visibleSelection.y, visibleSelection.x, visibleSelection.height},
        {rectRight(visibleSelection), visibleSelection.y,
            layout.overlayBounds.width - rectRight(visibleSelection),
            visibleSelection.height},
        {0.0F, rectBottom(visibleSelection), layout.overlayBounds.width,
            layout.overlayBounds.height - rectBottom(visibleSelection)},
    }};

    const auto diameter = VisualStyleCatalog::selectionHandleDiameterDip;
    const auto radius = diameter / 2.0F;
    const auto centerX = layout.border.x + layout.border.width / 2.0F;
    const auto centerY = layout.border.y + layout.border.height / 2.0F;
    const std::array<std::pair<float, float>, 8> centers{{
        {layout.border.x, layout.border.y},
        {centerX, layout.border.y},
        {rectRight(layout.border), layout.border.y},
        {layout.border.x, centerY},
        {rectRight(layout.border), centerY},
        {layout.border.x, rectBottom(layout.border)},
        {centerX, rectBottom(layout.border)},
        {rectRight(layout.border), rectBottom(layout.border)},
    }};
    for (std::size_t index = 0; index < centers.size(); ++index) {
        layout.handles[index] = {
            centers[index].first - radius,
            centers[index].second - radius,
            diameter,
            diameter,
        };
    }

    if (!layout.showActions) {
        return layout;
    }

    const auto safeBounds = insetRect(
        layout.overlayBounds,
        VisualStyleCatalog::layoutMarginDip);

    const auto labelWidth = std::ceil((std::max)(0.0F, input.sizeLabelTextWidthDip))
        + VisualStyleCatalog::sizeLabelExtraWidthDip;
    layout.sizeLabel = {
        visibleSelection.x,
        visibleSelection.y - VisualStyleCatalog::sizeLabelGapDip
            - VisualStyleCatalog::sizeLabelHeightDip,
        labelWidth,
        VisualStyleCatalog::sizeLabelHeightDip,
    };
    if (layout.sizeLabel.y < safeBounds.y) {
        layout.sizeLabel.y = rectBottom(visibleSelection)
            + VisualStyleCatalog::sizeLabelGapDip;
    }
    layout.sizeLabel = clampRect(layout.sizeLabel, safeBounds);

    const auto positionedToolbar = toolbarRect(
        visibleSelection,
        safeBounds,
        toolbarWidth(input.toolbarActions));
    layout.toolbar = computeMainToolbarLayout(
        {positionedToolbar.x, positionedToolbar.y},
        input.toolbarActions);
    layout.toolbarItems.reserve(layout.toolbar.items.size());
    for (const auto& item : layout.toolbar.items) {
        layout.toolbarItems.push_back({item.action, item.rect, false, true});
    }

    return layout;
}

std::string overlayLayoutManifestJson(const OverlayLayout& layout)
{
    std::ostringstream stream;
    stream.imbue(std::locale::classic());
    stream << "{\"mask\":[";
    for (std::size_t index = 0; index < layout.mask.size(); ++index) {
        if (index != 0U) {
            stream << ',';
        }
        appendRect(stream, layout.mask[index]);
    }
    stream << "],\"border\":";
    appendRect(stream, layout.border);
    stream << ",\"sizeLabel\":";
    appendRect(stream, layout.sizeLabel);
    stream << ",\"toolbar\":";
    appendRect(stream, layout.toolbar.bounds);
    stream << ",\"toolbarItems\":[";
    for (std::size_t index = 0; index < layout.toolbarItems.size(); ++index) {
        if (index != 0U) {
            stream << ',';
        }
        stream << "{\"action\":"
               << static_cast<unsigned int>(layout.toolbarItems[index].action)
               << ",\"rect\":";
        appendRect(stream, layout.toolbarItems[index].rect);
        stream << '}';
    }
    stream << ']';
    stream << ",\"handles\":[";
    for (std::size_t index = 0; index < layout.handles.size(); ++index) {
        if (index != 0U) {
            stream << ',';
        }
        appendRect(stream, layout.handles[index]);
    }
    stream << "]}";
    return stream.str();
}

struct OverlayRenderer::Impl final {
    explicit Impl(HMODULE sourceModule) noexcept
        : resourceModule(sourceModule)
    {
    }

    ~Impl()
    {
        discardDeviceResources();
        measurementTextFormat.reset();
        samplerValueTextFormat.reset();
        samplerTextFormat.reset();
        textFormat.reset();
        wicFactory.reset();
        dwriteFactory.reset();
        d2dFactory.reset();
        if (uninitializeCom) {
            CoUninitialize();
        }
    }

    std::optional<OverlayRendererError> ensureFactories() noexcept
    {
        if (d2dFactory && dwriteFactory && wicFactory && textFormat
            && samplerTextFormat && samplerValueTextFormat
            && measurementTextFormat) {
            return std::nullopt;
        }

        if (!comAttempted) {
            comAttempted = true;
            const auto comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
            if (SUCCEEDED(comResult)) {
                uninitializeCom = true;
            } else if (comResult != RPC_E_CHANGED_MODE) {
                return error(
                    OverlayRendererErrorCode::comInitializationFailed,
                    comResult);
            }
        }

        if (!d2dFactory) {
            const auto result = D2D1CreateFactory(
                D2D1_FACTORY_TYPE_SINGLE_THREADED,
                d2dFactory.put());
            if (FAILED(result)) {
                return error(OverlayRendererErrorCode::d2dFactoryFailed, result);
            }
        }

        if (!dwriteFactory) {
            IDWriteFactory* factory = nullptr;
            const auto result = DWriteCreateFactory(
                DWRITE_FACTORY_TYPE_SHARED,
                __uuidof(IDWriteFactory),
                reinterpret_cast<IUnknown**>(&factory));
            if (FAILED(result)) {
                return error(OverlayRendererErrorCode::dwriteFactoryFailed, result);
            }
            dwriteFactory.attach(factory);
        }

        if (!wicFactory) {
            IWICImagingFactory* factory = nullptr;
            const auto result = CoCreateInstance(
                CLSID_WICImagingFactory,
                nullptr,
                CLSCTX_INPROC_SERVER,
                IID_PPV_ARGS(&factory));
            if (FAILED(result)) {
                return error(OverlayRendererErrorCode::wicFactoryFailed, result);
            }
            wicFactory.attach(factory);
        }

        if (!textFormat) {
            const auto result = dwriteFactory->CreateTextFormat(
                VisualStyleCatalog::sizeLabelFontFamily,
                nullptr,
                static_cast<DWRITE_FONT_WEIGHT>(VisualStyleCatalog::sizeLabelFontWeight),
                DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_STRETCH_NORMAL,
                VisualStyleCatalog::sizeLabelFontSizeDip,
                VisualStyleCatalog::sizeLabelLocaleName,
                textFormat.put());
            if (FAILED(result)) {
                return error(OverlayRendererErrorCode::dwriteFactoryFailed, result);
            }
            if (const auto configurationError = checkTextFormatConfigurationResult(
                    textFormat->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP))) {
                textFormat.reset();
                return configurationError;
            }
            if (const auto configurationError = checkTextFormatConfigurationResult(
                    textFormat->SetParagraphAlignment(
                        DWRITE_PARAGRAPH_ALIGNMENT_CENTER))) {
                textFormat.reset();
                return configurationError;
            }
        }
        const auto createSamplerFormat = [this](
            float size,
            DWRITE_FONT_WEIGHT weight,
            DWRITE_TEXT_ALIGNMENT alignment,
            ComPtr<IDWriteTextFormat>& destination)
                -> std::optional<OverlayRendererError> {
            if (destination) {
                return std::nullopt;
            }
            const auto result = dwriteFactory->CreateTextFormat(
                VisualStyleCatalog::sizeLabelFontFamily,
                nullptr,
                weight,
                DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_STRETCH_NORMAL,
                size,
                VisualStyleCatalog::sizeLabelLocaleName,
                destination.put());
            if (FAILED(result)) {
                return error(OverlayRendererErrorCode::dwriteFactoryFailed, result);
            }
            const std::array configurationResults{
                destination->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP),
                destination->SetTextAlignment(alignment),
                destination->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER),
            };
            for (const auto configurationResult : configurationResults) {
                if (const auto configurationError
                    = checkTextFormatConfigurationResult(configurationResult)) {
                    destination.reset();
                    return configurationError;
                }
            }
            return std::nullopt;
        };
        if (const auto formatError = createSamplerFormat(
                12.0F, DWRITE_FONT_WEIGHT_MEDIUM,
                DWRITE_TEXT_ALIGNMENT_CENTER, samplerTextFormat)) {
            return formatError;
        }
        if (const auto formatError = createSamplerFormat(
                13.0F, DWRITE_FONT_WEIGHT_SEMI_BOLD,
                DWRITE_TEXT_ALIGNMENT_LEADING, samplerValueTextFormat)) {
            return formatError;
        }
        if (const auto formatError = createSamplerFormat(
                12.0F, DWRITE_FONT_WEIGHT_SEMI_BOLD,
                DWRITE_TEXT_ALIGNMENT_CENTER, measurementTextFormat)) {
            return formatError;
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> drawArrowLineOptions(
        const OverlayArrowLineOptionsRenderState& options) noexcept
    {
        ComPtr<ID2D1SolidColorBrush> panelBrush;
        ComPtr<ID2D1SolidColorBrush> borderBrush;
        ComPtr<ID2D1SolidColorBrush> separatorBrush;
        ComPtr<ID2D1SolidColorBrush> selectionBrush;
        ComPtr<ID2D1SolidColorBrush> textBrush;
        ComPtr<ID2D1SolidColorBrush> whiteBrush;
        const std::array results{
            createBrush(colorWithMultipliedAlpha(
                VisualStyleCatalog::toolbarBackgroundColor, 0.96F), panelBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.16F), borderBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.15F), separatorBrush),
            createBrush(D2D1::ColorF(0.0F, 0.48F, 1.0F, 1.0F), selectionBrush),
            createBrush(D2D1::ColorF(0.12F, 0.12F, 0.12F, 1.0F), textBrush),
            createBrush(D2D1::ColorF(D2D1::ColorF::White), whiteBrush),
        };
        for (const auto& result : results) {
            if (result.has_value()) {
                return result;
            }
        }
        const auto drawPanel = [this, &panelBrush, &borderBrush](
                                   AnnotationRect bounds) {
            const auto rounded = D2D1::RoundedRect(d2dRect(bounds), 6.0F, 6.0F);
            renderTarget->FillRoundedRectangle(&rounded, panelBrush.get());
            renderTarget->DrawRoundedRectangle(&rounded, borderBrush.get(), 1.0F);
        };
        drawPanel(options.layout.toolbar);
        for (const auto separator : options.layout.separators) {
            const auto rounded = D2D1::RoundedRect(
                d2dRect(separator), 0.75F, 0.75F);
            renderTarget->FillRoundedRectangle(
                &rounded, separatorBrush.get());
        }

        const auto& widths = macArrowStrokeWidths();
        for (std::size_t index = 0;
             index < options.layout.strokeWidths.size() && index < widths.size();
             ++index) {
            const auto rect = options.layout.strokeWidths[index];
            auto* brush = options.state.style().strokeWidthDip == widths[index]
                ? selectionBrush.get()
                : textBrush.get();
            renderTarget->DrawLine(
                D2D1::Point2F(rect.x + 4.0F, rect.y + 10.0F),
                D2D1::Point2F(rect.x + rect.width - 4.0F, rect.y + 10.0F),
                brush, widths[index]);
        }

        const auto field = D2D1::RoundedRect(
            d2dRect(options.layout.strokeStyle), 4.0F, 4.0F);
        renderTarget->FillRoundedRectangle(&field, whiteBrush.get());
        renderTarget->DrawRoundedRectangle(&field, borderBrush.get(), 1.0F);
        auto result = drawStrokeSample(
            options.layout.strokeStyleSampleStart,
            options.layout.strokeStyleSampleEnd,
            options.state.style().strokePattern,
            2.0F,
            textBrush.get());
        if (FAILED(result)) {
            return error(OverlayRendererErrorCode::drawFailed, result);
        }

        const auto drawEndpointField = [this, &borderBrush, &whiteBrush](
            AnnotationRect rect, ArrowType type, bool pointsLeft) {
            const auto rounded = D2D1::RoundedRect(d2dRect(rect), 4.0F, 4.0F);
            renderTarget->FillRoundedRectangle(&rounded, whiteBrush.get());
            renderTarget->DrawRoundedRectangle(&rounded, borderBrush.get(), 1.0F);
            const auto centerY = rect.y + rect.height / 2.0F;
            const auto startX = rect.x + 9.0F;
            const auto endX = rect.x + rect.width - 12.0F;
            AnnotationStyle style;
            style.strokeColor = {31, 31, 31, 255};
            style.strokeWidthDip = 1.5F;
            const ArrowLine line{
                {startX, centerY},
                {endX, centerY},
                {(startX + endX) / 2.0F, centerY},
                pointsLeft ? type : ArrowType::none,
                pointsLeft ? ArrowType::none : type,
            };
            return drawArrowLine(
                d2dFactory.get(),
                renderTarget.get(),
                ShapeAnnotation{
                    invalidAnnotationId,
                    AnnotationKind::arrowLine,
                    arrowLineBounds(line),
                    style,
                    0.0F,
                    line,
                });
        };
        result = drawEndpointField(options.layout.startArrowType,
            options.state.startArrowType(), true);
        if (FAILED(result)) {
            return error(OverlayRendererErrorCode::drawFailed, result);
        }
        result = drawEndpointField(options.layout.endArrowType,
            options.state.endArrowType(), false);
        if (FAILED(result)) {
            return error(OverlayRendererErrorCode::drawFailed, result);
        }

        const auto& palette = macShapePalette();
        for (std::size_t index = 0;
             index < options.layout.paletteCount && index < palette.size();
             ++index) {
            auto swatch = options.layout.colorSwatches[index];
            const auto selected = options.state.selectedPaletteIndex() == index;
            if (selected) {
                swatch = {swatch.x - 3.0F, swatch.y - 3.0F,
                    swatch.width + 6.0F, swatch.height + 6.0F};
            }
            ComPtr<ID2D1SolidColorBrush> swatchBrush;
            if (const auto brushError = createBrush(
                    annotationColor(palette[index]), swatchBrush)) {
                return brushError;
            }
            const auto rounded = D2D1::RoundedRect(
                d2dRect(swatch), selected ? 4.0F : 2.5F,
                selected ? 4.0F : 2.5F);
            renderTarget->FillRoundedRectangle(&rounded, swatchBrush.get());
            renderTarget->DrawRoundedRectangle(&rounded,
                selected ? selectionBrush.get() : borderBrush.get(),
                selected ? 1.5F : 1.0F);
        }
        if (!options.layout.colorSwatches.empty()) {
            renderTarget->DrawBitmap(paletteBitmap.get(),
                d2dRect(options.layout.colorSwatches.back()), 1.0F,
                D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
        }
        if (options.strokePatternMenu.has_value()) {
            drawPanel(options.strokePatternMenu->menu);
            const auto& patterns = macShapeStrokePatterns();
            for (std::size_t index = 0;
                 index < options.strokePatternMenu->items.size()
                    && index < patterns.size(); ++index) {
                result = drawStrokeSample(
                    options.strokePatternMenu->sampleStarts[index],
                    options.strokePatternMenu->sampleEnds[index],
                    patterns[index], 2.0F,
                    patterns[index] == options.state.style().strokePattern
                        ? selectionBrush.get()
                        : textBrush.get());
                if (FAILED(result)) {
                    return error(OverlayRendererErrorCode::drawFailed, result);
                }
            }
        }
        if (options.arrowTypeMenu.has_value()
            && options.arrowTypeMenuEndpoint.has_value()) {
            drawPanel(options.arrowTypeMenu->menu);
            const auto& types = macArrowTypes();
            const auto selectedType = *options.arrowTypeMenuEndpoint
                == ArrowEndpoint::start
                ? options.state.startArrowType()
                : options.state.endArrowType();
            for (std::size_t index = 0;
                 index < options.arrowTypeMenu->items.size()
                    && index < types.size(); ++index) {
                auto item = options.arrowTypeMenu->items[index];
                if (types[index] == selectedType) {
                    const auto selected = D2D1::RoundedRect(
                        d2dRect(item), 4.0F, 4.0F);
                    renderTarget->DrawRoundedRectangle(
                        &selected, selectionBrush.get(), 1.5F);
                }
                item.x += 4.0F;
                item.width -= 8.0F;
                result = drawEndpointField(
                    item,
                    types[index],
                    *options.arrowTypeMenuEndpoint == ArrowEndpoint::start);
                if (FAILED(result)) {
                    return error(OverlayRendererErrorCode::drawFailed, result);
                }
            }
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> drawBrushOptions(
        const OverlayBrushOptionsRenderState& options) noexcept
    {
        ComPtr<ID2D1SolidColorBrush> panelBrush;
        ComPtr<ID2D1SolidColorBrush> borderBrush;
        ComPtr<ID2D1SolidColorBrush> separatorBrush;
        ComPtr<ID2D1SolidColorBrush> selectionBrush;
        ComPtr<ID2D1SolidColorBrush> textBrush;
        ComPtr<ID2D1SolidColorBrush> whiteBrush;
        const std::array results{
            createBrush(colorWithMultipliedAlpha(
                VisualStyleCatalog::toolbarBackgroundColor, 0.96F), panelBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.16F), borderBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.15F), separatorBrush),
            createBrush(D2D1::ColorF(0.0F, 0.48F, 1.0F, 1.0F), selectionBrush),
            createBrush(D2D1::ColorF(0.12F, 0.12F, 0.12F, 1.0F), textBrush),
            createBrush(D2D1::ColorF(D2D1::ColorF::White), whiteBrush),
        };
        for (const auto& result : results) {
            if (result.has_value()) {
                return result;
            }
        }
        const auto drawPanel = [this, &panelBrush, &borderBrush](
                                   AnnotationRect bounds) {
            const auto rounded = D2D1::RoundedRect(d2dRect(bounds), 6.0F, 6.0F);
            renderTarget->FillRoundedRectangle(&rounded, panelBrush.get());
            renderTarget->DrawRoundedRectangle(&rounded, borderBrush.get(), 1.0F);
        };
        drawPanel(options.layout.toolbar);
        for (const auto separator : options.layout.separators) {
            const auto rounded = D2D1::RoundedRect(
                d2dRect(separator), 0.75F, 0.75F);
            renderTarget->FillRoundedRectangle(
                &rounded, separatorBrush.get());
        }

        const auto& widths = macBrushStrokeWidths();
        for (std::size_t index = 0;
             index < options.layout.strokeWidths.size() && index < widths.size();
             ++index) {
            const auto rect = options.layout.strokeWidths[index];
            auto* brush = options.state.style().strokeWidthDip == widths[index]
                ? selectionBrush.get()
                : textBrush.get();
            renderTarget->DrawLine(
                D2D1::Point2F(rect.x + 4.0F, rect.y + rect.height / 2.0F),
                D2D1::Point2F(
                    rect.x + rect.width - 4.0F, rect.y + rect.height / 2.0F),
                brush, widths[index]);
        }

        const auto field = D2D1::RoundedRect(
            d2dRect(options.layout.strokeStyle), 4.0F, 4.0F);
        renderTarget->FillRoundedRectangle(&field, whiteBrush.get());
        renderTarget->DrawRoundedRectangle(&field, borderBrush.get(), 1.0F);
        auto result = drawStrokeSample(
            options.layout.strokeStyleSampleStart,
            options.layout.strokeStyleSampleEnd,
            options.state.style().strokePattern,
            2.0F,
            textBrush.get());
        if (FAILED(result)) {
            return error(OverlayRendererErrorCode::drawFailed, result);
        }
        const auto disclosureX = options.layout.strokeStyle.x
            + options.layout.strokeStyle.width - 8.0F;
        result = fillTriangle(
            D2D1::Point2F(disclosureX - 3.0F,
                options.layout.strokeStyle.y + 8.0F),
            D2D1::Point2F(disclosureX + 3.0F,
                options.layout.strokeStyle.y + 8.0F),
            D2D1::Point2F(disclosureX,
                options.layout.strokeStyle.y + 12.0F),
            textBrush.get());
        if (FAILED(result)) {
            return error(OverlayRendererErrorCode::drawFailed, result);
        }

        const auto& palette = macShapePalette();
        for (std::size_t index = 0;
             index < options.layout.paletteCount && index < palette.size();
             ++index) {
            auto swatch = options.layout.colorSwatches[index];
            const auto selected = options.state.selectedPaletteIndex() == index;
            if (selected) {
                swatch = {swatch.x - 3.0F, swatch.y - 3.0F,
                    swatch.width + 6.0F, swatch.height + 6.0F};
            }
            ComPtr<ID2D1SolidColorBrush> swatchBrush;
            if (const auto brushError = createBrush(
                    annotationColor(palette[index]), swatchBrush)) {
                return brushError;
            }
            const auto rounded = D2D1::RoundedRect(
                d2dRect(swatch), selected ? 4.0F : 2.5F,
                selected ? 4.0F : 2.5F);
            renderTarget->FillRoundedRectangle(&rounded, swatchBrush.get());
            renderTarget->DrawRoundedRectangle(&rounded,
                selected ? selectionBrush.get() : borderBrush.get(),
                selected ? 1.5F : 1.0F);
        }
        if (!options.layout.colorSwatches.empty()) {
            renderTarget->DrawBitmap(paletteBitmap.get(),
                d2dRect(options.layout.colorSwatches.back()), 1.0F,
                D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
        }

        if (options.strokePatternMenu.has_value()) {
            drawPanel(options.strokePatternMenu->menu);
            const auto& patterns = macBrushStrokePatterns();
            for (std::size_t index = 0;
                 index < options.strokePatternMenu->items.size()
                    && index < patterns.size(); ++index) {
                result = drawStrokeSample(
                    options.strokePatternMenu->sampleStarts[index],
                    options.strokePatternMenu->sampleEnds[index],
                    patterns[index], 2.0F,
                    patterns[index] == options.state.style().strokePattern
                        ? selectionBrush.get()
                        : textBrush.get());
                if (FAILED(result)) {
                    return error(OverlayRendererErrorCode::drawFailed, result);
                }
            }
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> drawMarkerOptions(
        const OverlayMarkerOptionsRenderState& options) noexcept
    {
        ComPtr<ID2D1SolidColorBrush> panelBrush;
        ComPtr<ID2D1SolidColorBrush> borderBrush;
        ComPtr<ID2D1SolidColorBrush> separatorBrush;
        ComPtr<ID2D1SolidColorBrush> selectionBrush;
        ComPtr<ID2D1SolidColorBrush> textBrush;
        const std::array results{
            createBrush(colorWithMultipliedAlpha(
                VisualStyleCatalog::toolbarBackgroundColor, 0.96F), panelBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.16F), borderBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.15F), separatorBrush),
            createBrush(D2D1::ColorF(0.0F, 0.48F, 1.0F, 1.0F), selectionBrush),
            createBrush(D2D1::ColorF(0.12F, 0.12F, 0.12F, 1.0F), textBrush),
        };
        for (const auto& result : results) {
            if (result.has_value()) {
                return result;
            }
        }
        const auto panel = D2D1::RoundedRect(
            d2dRect(options.layout.toolbar), 6.0F, 6.0F);
        renderTarget->FillRoundedRectangle(&panel, panelBrush.get());
        renderTarget->DrawRoundedRectangle(&panel, borderBrush.get(), 1.0F);
        for (const auto separator : options.layout.separators) {
            const auto rounded = D2D1::RoundedRect(
                d2dRect(separator), 0.75F, 0.75F);
            renderTarget->FillRoundedRectangle(&rounded, separatorBrush.get());
        }
        const auto& widths = macMarkerStrokeWidths();
        const auto& previews = macBrushStrokeWidths();
        for (std::size_t index = 0;
             index < options.layout.strokeWidths.size()
                && index < widths.size() && index < previews.size(); ++index) {
            const auto rect = options.layout.strokeWidths[index];
            renderTarget->DrawLine(
                D2D1::Point2F(rect.x + 4.0F, rect.y + rect.height / 2.0F),
                D2D1::Point2F(
                    rect.x + rect.width - 4.0F, rect.y + rect.height / 2.0F),
                options.state.style().strokeWidthDip == widths[index]
                    ? selectionBrush.get() : textBrush.get(),
                previews[index]);
        }
        const auto& palette = macShapePalette();
        for (std::size_t index = 0;
             index < options.layout.paletteCount && index < palette.size();
             ++index) {
            auto swatch = options.layout.colorSwatches[index];
            const auto selected = options.state.selectedPaletteIndex() == index;
            if (selected) {
                swatch = {swatch.x - 3.0F, swatch.y - 3.0F,
                    swatch.width + 6.0F, swatch.height + 6.0F};
            }
            ComPtr<ID2D1SolidColorBrush> swatchBrush;
            if (const auto brushError = createBrush(
                    annotationColor(palette[index]), swatchBrush)) {
                return brushError;
            }
            const auto rounded = D2D1::RoundedRect(
                d2dRect(swatch), selected ? 4.0F : 2.5F,
                selected ? 4.0F : 2.5F);
            renderTarget->FillRoundedRectangle(&rounded, swatchBrush.get());
            renderTarget->DrawRoundedRectangle(&rounded,
                selected ? selectionBrush.get() : borderBrush.get(),
                selected ? 1.5F : 1.0F);
        }
        if (!options.layout.colorSwatches.empty()) {
            renderTarget->DrawBitmap(paletteBitmap.get(),
                d2dRect(options.layout.colorSwatches.back()), 1.0F,
                D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> drawMosaicOptions(
        const OverlayMosaicOptionsRenderState& options) noexcept
    {
        if (const auto resourceError = ensureMosaicResources()) {
            return resourceError;
        }
        auto& panelBrush = mosaicPanelBrush;
        auto& borderBrush = mosaicBorderBrush;
        auto& selectionBrush = mosaicSelectionBrush;
        auto& textBrush = mosaicTextBrush;
        auto& whiteBrush = mosaicWhiteBrush;
        auto& backgroundBrush = mosaicVariableBrush;
        const auto panel = D2D1::RoundedRect(
            d2dRect(options.layout.toolbar), 6.0F, 6.0F);
        renderTarget->FillRoundedRectangle(&panel, panelBrush.get());
        renderTarget->DrawRoundedRectangle(&panel, borderBrush.get(), 1.0F);

        const auto& widths = macMosaicStrokeWidths();
        for (std::size_t index = 0;
             index < options.layout.strokeWidths.size() && index < widths.size();
             ++index) {
            const auto rect = options.layout.strokeWidths[index];
            const auto diameter = widths[index] < 20.0F
                ? 5.0F : widths[index] < 35.0F ? 8.0F : 11.0F;
            const auto selected = options.state.kind()
                    == AnnotationKind::mosaicStroke
                && options.state.style().strokeWidthDip == widths[index];
            if (selected) {
                const auto button = D2D1::RoundedRect(
                    d2dRect(AnnotationRect{rect.x - 3.0F, rect.y - 4.0F,
                        rect.width + 6.0F, rect.height + 8.0F}),
                    4.0F, 4.0F);
                renderTarget->DrawRoundedRectangle(
                    &button, selectionBrush.get(), 1.5F);
            }
            const auto dot = D2D1::Ellipse(
                D2D1::Point2F(rect.x + rect.width / 2.0F,
                    rect.y + rect.height / 2.0F),
                diameter / 2.0F, diameter / 2.0F);
            renderTarget->FillEllipse(
                &dot, selected ? selectionBrush.get() : textBrush.get());
        }

        const auto rectangleSelected = options.state.kind()
            == AnnotationKind::mosaicRectangle;
        if (rectangleSelected) {
            const auto button = D2D1::RoundedRect(
                d2dRect(AnnotationRect{options.layout.rectangleMode.x - 3.0F,
                    options.layout.rectangleMode.y - 4.0F,
                    options.layout.rectangleMode.width + 6.0F,
                    options.layout.rectangleMode.height + 8.0F}),
                4.0F, 4.0F);
            renderTarget->DrawRoundedRectangle(
                &button, selectionBrush.get(), 1.5F);
        }
        auto* rectangleBrush = rectangleSelected
            ? selectionBrush.get() : textBrush.get();
        const auto rectangle = options.layout.rectangleMode;
        const auto square = D2D1::RoundedRect(
            D2D1::RectF(rectangle.x + 2.5F, rectangle.y + 2.5F,
                rectangle.x + 17.5F, rectangle.y + 17.5F),
            1.5F, 1.5F);
        renderTarget->FillRoundedRectangle(&square, rectangleBrush);
        constexpr float corner = 4.0F;
        const auto left = rectangle.x + 5.0F;
        const auto right = rectangle.x + 15.0F;
        const auto top = rectangle.y + 5.0F;
        const auto bottom = rectangle.y + 15.0F;
        for (const auto& segment : std::array<std::pair<D2D1_POINT_2F,
                D2D1_POINT_2F>, 8>{{
                {{left, top + corner}, {left, top}},
                {{left, top}, {left + corner, top}},
                {{right - corner, top}, {right, top}},
                {{right, top}, {right, top + corner}},
                {{left, bottom - corner}, {left, bottom}},
                {{left, bottom}, {left + corner, bottom}},
                {{right - corner, bottom}, {right, bottom}},
                {{right, bottom}, {right, bottom - corner}},
            }}) {
            renderTarget->DrawLine(
                segment.first, segment.second, whiteBrush.get(), 1.2F);
        }

        const auto typeRect = options.layout.redactionType;
        const auto typeButton = D2D1::RoundedRect(
            d2dRect(AnnotationRect{typeRect.x - 3.0F, typeRect.y - 4.0F,
                typeRect.width + 6.0F, typeRect.height + 8.0F}),
            4.0F, 4.0F);
        renderTarget->DrawRoundedRectangle(
            &typeButton, selectionBrush.get(), 1.5F);
        const auto value = options.state.redaction().value;
        const auto progress = mosaicRedactionProgress(value);
        if (options.state.redaction().type
            == MosaicRedactionType::pixelMosaic) {
            const auto size = 4.8F + progress * 2.4F;
            const auto spacing = 5.8F + progress * 2.4F;
            const std::array centers{
                D2D1::Point2F(typeRect.x + 10.0F, typeRect.y + 10.0F),
                D2D1::Point2F(typeRect.x + 10.0F, typeRect.y + 10.0F - spacing),
                D2D1::Point2F(typeRect.x + 10.0F, typeRect.y + 10.0F + spacing),
                D2D1::Point2F(typeRect.x + 10.0F - spacing, typeRect.y + 10.0F),
                D2D1::Point2F(typeRect.x + 10.0F + spacing, typeRect.y + 10.0F),
            };
            for (std::size_t index = 0; index < centers.size(); ++index) {
                const auto cell = D2D1::RoundedRect(
                    D2D1::RectF(centers[index].x - size / 2.0F,
                        centers[index].y - size / 2.0F,
                        centers[index].x + size / 2.0F,
                        centers[index].y + size / 2.0F), 1.2F, 1.2F);
                renderTarget->FillRoundedRectangle(
                    &cell, index == 0U ? whiteBrush.get() : selectionBrush.get());
            }
        } else {
            const auto tone = 0.88F - progress * 0.32F;
            backgroundBrush->SetColor(D2D1::ColorF(tone, tone, tone, 1.0F));
            const auto circle = D2D1::Ellipse(
                D2D1::Point2F(typeRect.x + 10.0F, typeRect.y + 10.0F),
                8.0F, 8.0F);
            renderTarget->FillEllipse(&circle, backgroundBrush.get());
            renderTarget->DrawEllipse(
                &circle, selectionBrush.get(), 1.4F);
            const auto center = D2D1::Ellipse(circle.point,
                (7.5F + progress * 3.0F) / 2.0F,
                (7.5F + progress * 3.0F) / 2.0F);
            renderTarget->FillEllipse(&center, selectionBrush.get());
        }

        const auto valueField = D2D1::RoundedRect(
            d2dRect(options.layout.redactionValue), 4.0F, 4.0F);
        renderTarget->FillRoundedRectangle(&valueField, whiteBrush.get());
        renderTarget->DrawRoundedRectangle(&valueField, borderBrush.get(), 1.0F);
        const auto track = D2D1::RoundedRect(
            d2dRect(options.layout.valueTrack), 2.0F, 2.0F);
        renderTarget->FillRoundedRectangle(&track, borderBrush.get());
        auto activeTrack = options.layout.valueTrack;
        activeTrack.width *= progress;
        const auto active = D2D1::RoundedRect(
            d2dRect(activeTrack), 2.0F, 2.0F);
        renderTarget->FillRoundedRectangle(&active, selectionBrush.get());
        const auto thumbX = options.layout.valueTrack.x
            + options.layout.valueTrack.width * progress;
        const auto thumb = D2D1::RoundedRect(
            D2D1::RectF(thumbX - 6.0F,
                options.layout.redactionValue.y + 3.0F,
                thumbX + 6.0F,
                options.layout.redactionValue.y + 17.0F),
            2.0F, 2.0F);
        renderTarget->FillRoundedRectangle(&thumb, whiteBrush.get());
        renderTarget->DrawRoundedRectangle(
            &thumb, selectionBrush.get(), 1.6F);
        const auto valueText = std::to_wstring(value);
        renderTarget->DrawText(
            valueText.data(), static_cast<UINT32>(valueText.size()),
            samplerTextFormat.get(), d2dRect(options.layout.valueLabel),
            textBrush.get(), D2D1_DRAW_TEXT_OPTIONS_CLIP);
        return std::nullopt;
    }

    std::optional<OverlayRendererError> drawTextOptions(
        const OverlayTextOptionsRenderState& options) noexcept
    {
        if (const auto resourceError = ensureTextResources()) {
            return resourceError;
        }
        auto& panelBrush = textPanelBrush;
        auto& borderBrush = textBorderBrush;
        auto& selectionBrush = textSelectionBrush;
        auto& textBrush = textForegroundBrush;
        auto& whiteBrush = textWhiteBrush;
        const auto panel = D2D1::RoundedRect(
            d2dRect(options.layout.toolbar), 6.0F, 6.0F);
        renderTarget->FillRoundedRectangle(&panel, panelBrush.get());
        renderTarget->DrawRoundedRectangle(&panel, borderBrush.get(), 1.0F);

        const auto drawToggle = [&](AnnotationRect rect,
                                    bool selected,
                                    std::size_t iconIndex,
                                    float iconSize) {
            const auto bitmapIndex = iconIndex * 2U + (selected ? 1U : 0U);
            const AnnotationRect iconRect{
                rect.x + (rect.width - iconSize) / 2.0F,
                rect.y + (rect.height - iconSize) / 2.0F,
                iconSize,
                iconSize,
            };
            renderTarget->DrawBitmap(textIconBitmaps[bitmapIndex].get(),
                d2dRect(iconRect), 1.0F,
                D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
        };
        drawToggle(options.layout.bold,
            options.state.style().textBold, 0U, 20.0F);
        drawToggle(options.layout.italic,
            options.state.style().textItalic, 1U, 20.0F);
        drawToggle(options.layout.outline,
            options.state.style().textOutlineEnabled, 2U, 15.0F);

        const auto drawPopup = [&](AnnotationRect rect,
                                   const std::wstring& label) {
            const auto field = D2D1::RoundedRect(d2dRect(rect), 4.0F, 4.0F);
            renderTarget->FillRoundedRectangle(&field, whiteBrush.get());
            renderTarget->DrawRoundedRectangle(&field, borderBrush.get(), 1.0F);
            auto labelRect = rect;
            labelRect.x += 6.0F;
            labelRect.width -= 20.0F;
            renderTarget->DrawText(
                label.data(), static_cast<UINT32>(label.size()),
                textFormat.get(), d2dRect(labelRect), textBrush.get(),
                D2D1_DRAW_TEXT_OPTIONS_CLIP);
            const auto centerX = rect.x + rect.width - 10.0F;
            const auto centerY = rect.y + rect.height / 2.0F + 1.0F;
            renderTarget->DrawLine(
                D2D1::Point2F(centerX - 3.0F, centerY - 2.0F),
                D2D1::Point2F(centerX, centerY + 1.0F), textBrush.get(), 1.0F);
            renderTarget->DrawLine(
                D2D1::Point2F(centerX, centerY + 1.0F),
                D2D1::Point2F(centerX + 3.0F, centerY - 2.0F),
                textBrush.get(), 1.0F);
        };
        drawPopup(options.layout.fontFamily,
            options.state.style().textFontFamily);
        drawPopup(options.layout.textSize,
            std::to_wstring(static_cast<int>(
                options.state.style().textSize + 0.5F)));

        for (const auto separator : options.layout.separators) {
            const auto rounded = D2D1::RoundedRect(
                d2dRect(separator), 0.75F, 0.75F);
            renderTarget->FillRoundedRectangle(&rounded, borderBrush.get());
        }
        const auto& palette = macShapePalette();
        for (std::size_t index = 0;
             index < options.layout.paletteCount && index < palette.size();
             ++index) {
            auto swatch = options.layout.colorSwatches[index];
            const auto selected
                = options.state.selectedPaletteIndex() == index;
            if (selected) {
                swatch = {swatch.x - 3.0F, swatch.y - 3.0F,
                    swatch.width + 6.0F, swatch.height + 6.0F};
            }
            textVariableBrush->SetColor(annotationColor(palette[index]));
            const auto rounded = D2D1::RoundedRect(
                d2dRect(swatch), selected ? 4.0F : 2.5F,
                selected ? 4.0F : 2.5F);
            renderTarget->FillRoundedRectangle(
                &rounded, textVariableBrush.get());
            renderTarget->DrawRoundedRectangle(&rounded,
                selected ? selectionBrush.get() : borderBrush.get(),
                selected ? 1.5F : 1.0F);
        }
        if (!options.layout.colorSwatches.empty()) {
            renderTarget->DrawBitmap(paletteBitmap.get(),
                d2dRect(options.layout.colorSwatches.back()), 1.0F,
                D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
        }
        if (options.popupMenu.has_value()) {
            const auto popup = D2D1::RoundedRect(
                d2dRect(options.popupMenu->menu), 6.0F, 6.0F);
            renderTarget->FillRoundedRectangle(&popup, panelBrush.get());
            renderTarget->DrawRoundedRectangle(
                &popup, borderBrush.get(), 1.0F);
            const auto count = (std::min)(
                options.popupMenu->items.size(),
                options.popupLabels.size());
            for (std::size_t index = 0; index < count; ++index) {
                auto item = options.popupMenu->items[index];
                const auto selected
                    = options.selectedPopupIndex == index;
                if (selected) {
                    const auto highlight = D2D1::RoundedRect(
                        d2dRect(item), 4.0F, 4.0F);
                    renderTarget->FillRoundedRectangle(
                        &highlight, selectionBrush.get());
                }
                item.x += 6.0F;
                item.width -= 12.0F;
                const auto& label = options.popupLabels[index];
                renderTarget->DrawText(
                    label.data(), static_cast<UINT32>(label.size()),
                    textFormat.get(), d2dRect(item),
                    selected ? whiteBrush.get() : textBrush.get(),
                    D2D1_DRAW_TEXT_OPTIONS_CLIP);
            }
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> drawNumberOptions(
        const OverlayNumberOptionsRenderState& options) noexcept
    {
        if (const auto resourceError = ensureTextResources()) {
            return resourceError;
        }
        auto& panelBrush = textPanelBrush;
        auto& borderBrush = textBorderBrush;
        auto& selectionBrush = textSelectionBrush;
        auto& textBrush = textForegroundBrush;
        auto& whiteBrush = textWhiteBrush;
        const auto panel = D2D1::RoundedRect(
            d2dRect(options.layout.toolbar), 6.0F, 6.0F);
        renderTarget->FillRoundedRectangle(&panel, panelBrush.get());
        renderTarget->DrawRoundedRectangle(&panel, borderBrush.get(), 1.0F);

        const auto drawField = [&](AnnotationRect rect) {
            const auto field = D2D1::RoundedRect(d2dRect(rect), 4.0F, 4.0F);
            renderTarget->FillRoundedRectangle(&field, whiteBrush.get());
            renderTarget->DrawRoundedRectangle(&field, borderBrush.get(), 1.0F);
            const auto centerX = rect.x + rect.width - 9.0F;
            const auto centerY = rect.y + rect.height / 2.0F + 1.0F;
            renderTarget->DrawLine(
                {centerX - 3.0F, centerY - 2.0F},
                {centerX, centerY + 1.0F}, textBrush.get(), 1.0F);
            renderTarget->DrawLine(
                {centerX, centerY + 1.0F},
                {centerX + 3.0F, centerY - 2.0F}, textBrush.get(), 1.0F);
        };
        const auto drawMark = [&](NumberMarkType type,
                                  AnnotationRect rect,
                                  ID2D1Brush* brush) {
            rect.width -= 13.0F;
            if (type == NumberMarkType::number) {
                const auto center = D2D1::Point2F(
                    rect.x + rect.width / 2.0F,
                    rect.y + rect.height / 2.0F);
                const auto circle = D2D1::Ellipse(center, 7.0F, 7.0F);
                renderTarget->FillEllipse(&circle, brush);
                const std::wstring label = L"1";
                renderTarget->DrawText(label.data(), 1U, textFormat.get(),
                    d2dRect(AnnotationRect{center.x - 6.0F,
                        center.y - 7.0F, 12.0F, 14.0F}), whiteBrush.get(),
                    D2D1_DRAW_TEXT_OPTIONS_CLIP);
            } else {
                const std::wstring label = type == NumberMarkType::check
                    ? L"✓" : L"×";
                renderTarget->DrawText(
                    label.data(), static_cast<UINT32>(label.size()),
                    textFormat.get(), d2dRect(rect), brush,
                    D2D1_DRAW_TEXT_OPTIONS_CLIP);
            }
        };
        drawField(options.layout.markType);
        textVariableBrush->SetColor(annotationColor(
            options.state.style().strokeColor));
        drawMark(options.state.type(), options.layout.markType,
            textVariableBrush.get());
        drawField(options.layout.size);
        const auto sizeLabel = std::to_wstring(static_cast<int>(
            options.state.style().textSize + 0.5F));
        auto sizeRect = options.layout.size;
        sizeRect.x += 6.0F;
        sizeRect.width -= 20.0F;
        renderTarget->DrawText(sizeLabel.data(),
            static_cast<UINT32>(sizeLabel.size()), textFormat.get(),
            d2dRect(sizeRect), textBrush.get(), D2D1_DRAW_TEXT_OPTIONS_CLIP);

        for (const auto separator : options.layout.separators) {
            const auto rounded = D2D1::RoundedRect(
                d2dRect(separator), 0.75F, 0.75F);
            renderTarget->FillRoundedRectangle(&rounded, borderBrush.get());
        }
        const auto& palette = macShapePalette();
        for (std::size_t index = 0;
             index < options.layout.paletteCount && index < palette.size();
             ++index) {
            auto swatch = options.layout.colorSwatches[index];
            const auto selected
                = options.state.selectedPaletteIndex() == index;
            if (selected) {
                swatch = {swatch.x - 3.0F, swatch.y - 3.0F,
                    swatch.width + 6.0F, swatch.height + 6.0F};
            }
            textVariableBrush->SetColor(annotationColor(palette[index]));
            const auto rounded = D2D1::RoundedRect(d2dRect(swatch),
                selected ? 4.0F : 2.5F, selected ? 4.0F : 2.5F);
            renderTarget->FillRoundedRectangle(
                &rounded, textVariableBrush.get());
            renderTarget->DrawRoundedRectangle(&rounded,
                selected ? selectionBrush.get() : borderBrush.get(),
                selected ? 1.5F : 1.0F);
        }
        if (!options.layout.colorSwatches.empty()) {
            renderTarget->DrawBitmap(paletteBitmap.get(),
                d2dRect(options.layout.colorSwatches.back()), 1.0F,
                D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
        }
        if (options.popupMenu.has_value()) {
            const auto popup = D2D1::RoundedRect(
                d2dRect(options.popupMenu->menu), 6.0F, 6.0F);
            renderTarget->FillRoundedRectangle(&popup, panelBrush.get());
            renderTarget->DrawRoundedRectangle(&popup, borderBrush.get(), 1.0F);
            const auto count = (std::min)(
                options.popupMenu->items.size(), options.popupLabels.size());
            for (std::size_t index = 0; index < count; ++index) {
                auto item = options.popupMenu->items[index];
                const auto selected = options.selectedPopupIndex == index;
                if (selected) {
                    const auto highlight = D2D1::RoundedRect(
                        d2dRect(item), 4.0F, 4.0F);
                    renderTarget->FillRoundedRectangle(
                        &highlight, selectionBrush.get());
                }
                if (options.popupKind == NumberPopupMenu::markType) {
                    if (index < numberMarkTypes.size()) {
                        const auto& descriptor = numberMarkTypes[index];
                        textVariableBrush->SetColor(annotationColor(
                            descriptor.type == NumberMarkType::number
                                ? options.state.style().strokeColor
                                : descriptor.defaultColor));
                        drawMark(descriptor.type, item,
                            textVariableBrush.get());
                    }
                } else {
                    item.x += 6.0F;
                    item.width -= 12.0F;
                    const auto& label = options.popupLabels[index];
                    renderTarget->DrawText(label.data(),
                        static_cast<UINT32>(label.size()), textFormat.get(),
                        d2dRect(item), selected ? whiteBrush.get()
                            : textBrush.get(), D2D1_DRAW_TEXT_OPTIONS_CLIP);
                }
            }
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> drawMagnifierOptions(
        const OverlayMagnifierOptionsRenderState& options) noexcept
    {
        if (const auto resourceError = ensureTextResources()) {
            return resourceError;
        }
        auto& panelBrush = textPanelBrush;
        auto& borderBrush = textBorderBrush;
        auto& selectionBrush = textSelectionBrush;
        auto& foregroundBrush = textForegroundBrush;
        auto& whiteBrush = textWhiteBrush;
        const auto panel = D2D1::RoundedRect(
            d2dRect(options.layout.toolbar), 6.0F, 6.0F);
        renderTarget->FillRoundedRectangle(&panel, panelBrush.get());
        renderTarget->DrawRoundedRectangle(&panel, borderBrush.get(), 1.0F);

        for (const auto separator : options.layout.separators) {
            const auto rounded = D2D1::RoundedRect(
                d2dRect(separator), 0.75F, 0.75F);
            renderTarget->FillRoundedRectangle(&rounded, borderBrush.get());
        }

        const auto& widths = macMagnifierStrokeWidths();
        for (std::size_t index = 0;
             index < options.layout.strokeWidths.size()
                && index < widths.size(); ++index) {
            const auto rect = options.layout.strokeWidths[index];
            renderTarget->DrawLine(
                {rect.x + 4.0F, rect.y + rect.height / 2.0F},
                {rect.x + rect.width - 4.0F,
                    rect.y + rect.height / 2.0F},
                options.state.style().strokeWidthDip == widths[index]
                    ? selectionBrush.get() : foregroundBrush.get(),
                widths[index]);
        }

        const auto drawShape = [&](AnnotationRect rect,
                                   MagnifierShape shape) {
            const auto selected = options.state.shape() == shape;
            if (selected) {
                const auto button = D2D1::RoundedRect(
                    d2dRect(AnnotationRect{rect.x - 3.0F, rect.y - 4.0F,
                        rect.width + 6.0F, rect.height + 8.0F}),
                    4.0F, 4.0F);
                renderTarget->DrawRoundedRectangle(
                    &button, selectionBrush.get(), 1.5F);
            }
            auto* brush = selected
                ? selectionBrush.get() : foregroundBrush.get();
            const auto center = D2D1::Point2F(
                rect.x + rect.width / 2.0F,
                rect.y + rect.height / 2.0F);
            if (shape == MagnifierShape::circle) {
                const auto circle = D2D1::Ellipse(center, 6.5F, 6.5F);
                renderTarget->DrawEllipse(&circle, brush, 1.5F);
            } else {
                const auto rectangle = D2D1::RoundedRect(
                    D2D1::RectF(center.x - 6.5F, center.y - 6.5F,
                        center.x + 6.5F, center.y + 6.5F),
                    1.5F, 1.5F);
                renderTarget->DrawRoundedRectangle(
                    &rectangle, brush, 1.5F);
            }
        };
        drawShape(options.layout.rectangleMode, MagnifierShape::rectangle);
        drawShape(options.layout.circleMode, MagnifierShape::circle);

        const auto zoomField = D2D1::RoundedRect(
            d2dRect(options.layout.zoom), 4.0F, 4.0F);
        renderTarget->FillRoundedRectangle(&zoomField, whiteBrush.get());
        renderTarget->DrawRoundedRectangle(
            &zoomField, borderBrush.get(), 1.0F);
        const auto zoomIndex = static_cast<std::size_t>(std::distance(
            magnifierZoomOptions.begin(),
            std::find_if(magnifierZoomOptions.begin(),
                magnifierZoomOptions.end(), [&](const auto& option) {
                    return option.value == options.state.zoom();
                })));
        const auto zoomLabel = magnifierZoomOptions[(std::min)(
            zoomIndex, magnifierZoomOptions.size() - 1U)].label;
        auto zoomLabelRect = options.layout.zoom;
        zoomLabelRect.x += 6.0F;
        zoomLabelRect.width -= 20.0F;
        renderTarget->DrawText(zoomLabel.data(),
            static_cast<UINT32>(zoomLabel.size()), textFormat.get(),
            d2dRect(zoomLabelRect), foregroundBrush.get(),
            D2D1_DRAW_TEXT_OPTIONS_CLIP);
        const auto arrowX = options.layout.zoom.x
            + options.layout.zoom.width - 10.0F;
        const auto arrowY = options.layout.zoom.y
            + options.layout.zoom.height / 2.0F + 1.0F;
        renderTarget->DrawLine({arrowX - 3.0F, arrowY - 2.0F},
            {arrowX, arrowY + 1.0F}, foregroundBrush.get(), 1.0F);
        renderTarget->DrawLine({arrowX, arrowY + 1.0F},
            {arrowX + 3.0F, arrowY - 2.0F}, foregroundBrush.get(), 1.0F);

        const auto& palette = macShapePalette();
        for (std::size_t index = 0;
             index < options.layout.paletteCount && index < palette.size();
             ++index) {
            auto swatch = options.layout.colorSwatches[index];
            const auto selected
                = options.state.selectedPaletteIndex() == index;
            if (selected) {
                swatch = {swatch.x - 3.0F, swatch.y - 3.0F,
                    swatch.width + 6.0F, swatch.height + 6.0F};
            }
            textVariableBrush->SetColor(annotationColor(palette[index]));
            const auto rounded = D2D1::RoundedRect(d2dRect(swatch),
                selected ? 4.0F : 2.5F, selected ? 4.0F : 2.5F);
            renderTarget->FillRoundedRectangle(
                &rounded, textVariableBrush.get());
            renderTarget->DrawRoundedRectangle(&rounded,
                selected ? selectionBrush.get() : borderBrush.get(),
                selected ? 1.5F : 1.0F);
        }
        if (!options.layout.colorSwatches.empty()) {
            renderTarget->DrawBitmap(paletteBitmap.get(),
                d2dRect(options.layout.colorSwatches.back()), 1.0F,
                D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
        }

        if (options.zoomMenu.has_value()) {
            const auto popup = D2D1::RoundedRect(
                d2dRect(options.zoomMenu->menu), 6.0F, 6.0F);
            renderTarget->FillRoundedRectangle(&popup, panelBrush.get());
            renderTarget->DrawRoundedRectangle(
                &popup, borderBrush.get(), 1.0F);
            const auto count = (std::min)(
                options.zoomMenu->items.size(), magnifierZoomOptions.size());
            for (std::size_t index = 0; index < count; ++index) {
                auto item = options.zoomMenu->items[index];
                const auto selected = options.state.zoom()
                    == magnifierZoomOptions[index].value;
                if (selected) {
                    textVariableBrush->SetColor(
                        D2D1::ColorF(0.0F, 0.48F, 1.0F, 0.16F));
                    const auto highlight = D2D1::RoundedRect(
                        d2dRect(item), 4.0F, 4.0F);
                    renderTarget->FillRoundedRectangle(
                        &highlight, textVariableBrush.get());
                }
                const auto label = magnifierZoomOptions[index].label;
                item.x += 8.0F;
                item.width -= 16.0F;
                renderTarget->DrawText(label.data(),
                    static_cast<UINT32>(label.size()), textFormat.get(),
                    d2dRect(item), selected ? selectionBrush.get()
                        : foregroundBrush.get(),
                    D2D1_DRAW_TEXT_OPTIONS_CLIP);
            }
        }
        return std::nullopt;
    }

    void drawToolbarIcon(
        const ToolbarIconSpec& icon,
        std::size_t iconIndex,
        DipRect rect,
        ID2D1Brush* selectedBrush,
        bool selected) noexcept
    {
        const auto destination = d2dRect(insetRect(rect, icon.insetDip));
        if (selected && !icon.fixedColor) {
            const auto previousMode = renderTarget->GetAntialiasMode();
            renderTarget->SetAntialiasMode(D2D1_ANTIALIAS_MODE_ALIASED);
            const auto bitmapSize = iconBitmaps[iconIndex]->GetSize();
            const auto source = D2D1::RectF(
                0.0F, 0.0F, bitmapSize.width, bitmapSize.height);
            renderTarget->FillOpacityMask(
                iconBitmaps[iconIndex].get(), selectedBrush,
                D2D1_OPACITY_MASK_CONTENT_GRAPHICS,
                &destination, &source);
            renderTarget->SetAntialiasMode(previousMode);
            return;
        }
        renderTarget->DrawBitmap(iconBitmaps[iconIndex].get(),
            destination, 1.0F, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
    }

    std::optional<OverlayRendererError> drawEraserOptions(
        const OverlayEraserOptionsRenderState& options) noexcept
    {
        if (const auto resourceError = ensureTextResources()) {
            return resourceError;
        }
        const auto panel = D2D1::RoundedRect(
            d2dRect(options.layout.toolbar), 6.0F, 6.0F);
        renderTarget->FillRoundedRectangle(&panel, textPanelBrush.get());
        renderTarget->DrawRoundedRectangle(
            &panel, textBorderBrush.get(), 1.0F);
        const auto separator = D2D1::RoundedRect(
            d2dRect(options.layout.separator), 0.75F, 0.75F);
        renderTarget->FillRoundedRectangle(
            &separator, textBorderBrush.get());

        const auto iconRect = [](AnnotationRect rect) {
            return DipRect{rect.x, rect.y, rect.width, rect.height};
        };
        const auto pointIndex = toolbarIconIndex(ToolbarAction::eraser);
        drawToolbarIcon(
            toolbarImageResources()[pointIndex],
            pointIndex, iconRect(options.layout.pointMode),
            textSelectionBrush.get(),
            options.mode == EraserMode::point);
        const auto rectangleIndex = toolbarIconIndex(ToolbarAction::rectangle);
        drawToolbarIcon(
            toolbarImageResources()[rectangleIndex],
            rectangleIndex, iconRect(options.layout.rectangleMode),
            textSelectionBrush.get(),
            options.mode == EraserMode::rectangle);
        drawToolbarIcon(eraserTrashIcon(), eraserTrashIconIndex(),
            iconRect(options.layout.clearAll), textSelectionBrush.get(), false);
        return std::nullopt;
    }

    std::optional<OverlayRendererError> drawEyedropper(
        const OverlayEyedropperRenderState& state,
        AnnotationRect safeBounds) noexcept
    {
        if (const auto resourceError = ensureEyedropperResources()) {
            return resourceError;
        }
        auto& panelWhiteBrush = eyedropperPanelWhiteBrush;
        auto& whiteBrush = eyedropperWhiteBrush;
        auto& blueBrush = eyedropperBlueBrush;
        auto& darkBrush = eyedropperDarkBrush;
        auto& infoBrush = eyedropperInfoBrush;
        auto& borderBrush = eyedropperBorderBrush;
        auto& gridBrush = eyedropperGridBrush;
        auto& successBrush = eyedropperSuccessBrush;
        auto& cellBrush = eyedropperCellBrush;

        if (state.measurementStart.has_value()
            && state.measurementEnd.has_value()
            && !state.measurementLabel.empty()) {
            const auto start = D2D1::Point2F(
                state.measurementStart->x, state.measurementStart->y);
            const auto end = D2D1::Point2F(
                state.measurementEnd->x, state.measurementEnd->y);
            renderTarget->DrawLine(
                start, end, whiteBrush.get(), 3.0F,
                eyedropperWhiteStrokeStyle.get());
            renderTarget->DrawLine(
                start, end, blueBrush.get(), 1.5F,
                eyedropperBlueStrokeStyle.get());

            float labelWidth = 0.0F;
            if (const auto measureError = measureLabel(
                    state.measurementLabel, labelWidth)) {
                return measureError;
            }
            const auto midpointX = (start.x + end.x) / 2.0F;
            AnnotationRect label{
                midpointX - (labelWidth + 14.0F) / 2.0F,
                (std::min)(start.y, end.y) - 30.0F,
                labelWidth + 14.0F,
                24.0F,
            };
            label.x = (std::max)(safeBounds.x + 4.0F, (std::min)(
                label.x, safeBounds.x + safeBounds.width - label.width - 4.0F));
            label.y = (std::max)(safeBounds.y + 4.0F, (std::min)(
                label.y, safeBounds.y + safeBounds.height - label.height - 4.0F));
            const auto rounded = D2D1::RoundedRect(d2dRect(label), 5.0F, 5.0F);
            renderTarget->FillRoundedRectangle(&rounded, darkBrush.get());
            renderTarget->DrawText(
                state.measurementLabel.data(),
                static_cast<UINT32>(state.measurementLabel.size()),
                measurementTextFormat.get(), d2dRect(label), whiteBrush.get(),
                D2D1_DRAW_TEXT_OPTIONS_CLIP);
        }

        const auto layout = eyedropperPanelLayout(state.pointer, safeBounds);
        const auto panel = D2D1::RoundedRect(
            d2dRect(layout.panel), 10.0F, 10.0F);
        renderTarget->FillRoundedRectangle(&panel, panelWhiteBrush.get());
        renderTarget->DrawRoundedRectangle(&panel, borderBrush.get(), 1.0F);

        ComPtr<ID2D1RoundedRectangleGeometry> panelClipGeometry;
        auto geometryResult = d2dFactory->CreateRoundedRectangleGeometry(
            panel, panelClipGeometry.put());
        if (FAILED(geometryResult)) {
            return error(OverlayRendererErrorCode::drawFailed, geometryResult);
        }
        ComPtr<ID2D1Layer> panelClipLayer;
        geometryResult = renderTarget->CreateLayer(nullptr, panelClipLayer.put());
        if (FAILED(geometryResult)) {
            return error(OverlayRendererErrorCode::drawFailed, geometryResult);
        }
        const auto layerParameters = D2D1::LayerParameters(
            D2D1::InfiniteRect(), panelClipGeometry.get());
        renderTarget->PushLayer(layerParameters, panelClipLayer.get());

        const auto cellWidth = layout.magnifier.width / 9.0F;
        const auto cellHeight = layout.magnifier.height / 9.0F;
        for (int row = 0; row < 9; ++row) {
            for (int column = 0; column < 9; ++column) {
                cellBrush->SetColor(annotationColor(
                    state.magnifier[static_cast<std::size_t>(
                        row * 9 + column)]));
                const AnnotationRect cell{
                    layout.magnifier.x + column * cellWidth,
                    layout.magnifier.y + row * cellHeight,
                    cellWidth,
                    cellHeight,
                };
                renderTarget->FillRectangle(d2dRect(cell), cellBrush.get());
            }
        }
        for (int step = 0; step <= 9; ++step) {
            const auto x = layout.magnifier.x + step * cellWidth;
            const auto y = layout.magnifier.y + step * cellHeight;
            renderTarget->DrawLine(
                D2D1::Point2F(x, layout.magnifier.y),
                D2D1::Point2F(x, layout.magnifier.y + layout.magnifier.height),
                gridBrush.get(), 0.8F);
            renderTarget->DrawLine(
                D2D1::Point2F(layout.magnifier.x, y),
                D2D1::Point2F(layout.magnifier.x + layout.magnifier.width, y),
                gridBrush.get(), 0.8F);
        }
        const AnnotationRect centerCell{
            layout.magnifier.x + 4.0F * cellWidth,
            layout.magnifier.y + 4.0F * cellHeight,
            cellWidth,
            cellHeight,
        };
        renderTarget->DrawRectangle(d2dRect(centerCell), darkBrush.get(), 1.6F);
        renderTarget->PopLayer();
        renderTarget->FillRectangle(d2dRect(layout.info), infoBrush.get());

        const auto coordinate = L"(" + std::to_wstring(
            static_cast<int>(state.pointer.x)) + L" , " + std::to_wstring(
            static_cast<int>(safeBounds.height - state.pointer.y)) + L")";
        const auto value = eyedropperColorText(state.color, state.copyMode);
        const auto copySucceeded
            = state.copySuccessMillisecondsRemaining > 0;
        const auto copyHint = copySucceeded
            ? std::wstring(L"复制成功")
            : state.copyMode == EyedropperCopyMode::hex
                ? std::wstring(L"按 C 复制HEX颜色值")
                : std::wstring(L"按 C 复制RGB颜色值");
        const std::wstring switchHint = L"按 Shift 切换 RGB/HEX";
        const std::array<std::pair<std::wstring, AnnotationRect>, 3> rows{{
            {coordinate, {layout.info.x + 8.0F, layout.info.y + 5.0F,
                layout.info.width - 16.0F, 18.0F}},
            {copyHint, {layout.info.x + 8.0F, layout.info.y + 50.0F,
                layout.info.width - 16.0F, 18.0F}},
            {switchHint, {layout.info.x + 8.0F, layout.info.y + 70.0F,
                layout.info.width - 16.0F, 18.0F}},
        }};
        for (const auto& [text, rect] : rows) {
            renderTarget->DrawText(
                text.data(), static_cast<UINT32>(text.size()),
                samplerTextFormat.get(), d2dRect(rect),
                copySucceeded && text == copyHint
                    ? successBrush.get() : panelWhiteBrush.get(),
                D2D1_DRAW_TEXT_OPTIONS_CLIP);
        }

        ComPtr<IDWriteTextLayout> valueLayout;
        auto textResult = dwriteFactory->CreateTextLayout(
            value.data(), static_cast<UINT32>(value.size()),
            samplerValueTextFormat.get(), layout.info.width, 18.0F,
            valueLayout.put());
        if (FAILED(textResult)) {
            return error(OverlayRendererErrorCode::drawFailed, textResult);
        }
        DWRITE_TEXT_METRICS valueMetrics{};
        textResult = valueLayout->GetMetrics(&valueMetrics);
        if (FAILED(textResult)) {
            return error(OverlayRendererErrorCode::drawFailed, textResult);
        }
        constexpr float swatchSize = 18.0F;
        constexpr float swatchGap = 7.0F;
        const auto groupWidth = swatchSize + swatchGap
            + valueMetrics.widthIncludingTrailingWhitespace;
        const AnnotationRect swatch{
            layout.info.x + (layout.info.width - groupWidth) / 2.0F,
            layout.info.y + 27.0F,
            swatchSize,
            swatchSize,
        };
        cellBrush->SetColor(annotationColor(state.color));
        const auto roundedSwatch = D2D1::RoundedRect(
            d2dRect(swatch), 3.0F, 3.0F);
        renderTarget->FillRoundedRectangle(&roundedSwatch, cellBrush.get());
        renderTarget->DrawRoundedRectangle(
            &roundedSwatch, panelWhiteBrush.get(), 1.2F);
        const AnnotationRect valueRect{
            swatch.x + swatch.width + swatchGap,
            layout.info.y + 27.0F,
            valueMetrics.widthIncludingTrailingWhitespace + 2.0F,
            18.0F,
        };
        renderTarget->DrawText(
            value.data(), static_cast<UINT32>(value.size()),
            samplerValueTextFormat.get(), d2dRect(valueRect),
            panelWhiteBrush.get(), D2D1_DRAW_TEXT_OPTIONS_CLIP);
        return std::nullopt;
    }

    std::optional<OverlayRendererError> ensureEyedropperResources() noexcept
    {
        if (eyedropperPanelWhiteBrush && eyedropperWhiteBrush
            && eyedropperBlueBrush && eyedropperDarkBrush
            && eyedropperInfoBrush && eyedropperBorderBrush
            && eyedropperGridBrush && eyedropperSuccessBrush
            && eyedropperCellBrush && eyedropperWhiteStrokeStyle
            && eyedropperBlueStrokeStyle) {
            return std::nullopt;
        }
        discardEyedropperResources();
        const std::array results{
            createBrush(D2D1::ColorF(1.0F, 1.0F, 1.0F, 1.0F),
                eyedropperPanelWhiteBrush),
            createBrush(D2D1::ColorF(1.0F, 1.0F, 1.0F, 0.95F),
                eyedropperWhiteBrush),
            createBrush(D2D1::ColorF(0.0F, 0.48F, 1.0F, 1.0F),
                eyedropperBlueBrush),
            createBrush(D2D1::ColorF(0.08F, 0.08F, 0.08F, 0.90F),
                eyedropperDarkBrush),
            createBrush(D2D1::ColorF(0.33F, 0.33F, 0.33F, 0.98F),
                eyedropperInfoBrush),
            createBrush(D2D1::ColorF(0.72F, 0.72F, 0.72F, 1.0F),
                eyedropperBorderBrush),
            createBrush(D2D1::ColorF(0.78F, 0.78F, 0.78F, 1.0F),
                eyedropperGridBrush),
            createBrush(D2D1::ColorF(0.20F, 0.78F, 0.35F, 1.0F),
                eyedropperSuccessBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 1.0F),
                eyedropperCellBrush),
        };
        for (const auto& result : results) {
            if (result.has_value()) {
                discardEyedropperResources();
                return result;
            }
        }
        D2D1_STROKE_STYLE_PROPERTIES properties{};
        properties.startCap = D2D1_CAP_STYLE_ROUND;
        properties.endCap = D2D1_CAP_STYLE_ROUND;
        properties.dashCap = D2D1_CAP_STYLE_ROUND;
        properties.dashStyle = D2D1_DASH_STYLE_CUSTOM;
        const float whiteDashes[]{6.0F / 3.0F, 4.0F / 3.0F};
        const float blueDashes[]{6.0F / 1.5F, 4.0F / 1.5F};
        auto result = d2dFactory->CreateStrokeStyle(
            properties, whiteDashes, 2U, eyedropperWhiteStrokeStyle.put());
        if (SUCCEEDED(result)) {
            result = d2dFactory->CreateStrokeStyle(
                properties, blueDashes, 2U,
                eyedropperBlueStrokeStyle.put());
        }
        if (FAILED(result)) {
            discardEyedropperResources();
            return error(OverlayRendererErrorCode::drawFailed, result);
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> ensureMosaicResources() noexcept
    {
        if (mosaicPanelBrush && mosaicBorderBrush && mosaicSelectionBrush
            && mosaicTextBrush && mosaicWhiteBrush && mosaicVariableBrush) {
            return std::nullopt;
        }
        discardMosaicResources();
        const std::array results{
            createBrush(colorWithMultipliedAlpha(
                VisualStyleCatalog::toolbarBackgroundColor, 0.96F),
                mosaicPanelBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.16F),
                mosaicBorderBrush),
            createBrush(D2D1::ColorF(0.0F, 0.48F, 1.0F, 1.0F),
                mosaicSelectionBrush),
            createBrush(D2D1::ColorF(0.12F, 0.12F, 0.12F, 1.0F),
                mosaicTextBrush),
            createBrush(D2D1::ColorF(D2D1::ColorF::White),
                mosaicWhiteBrush),
            createBrush(D2D1::ColorF(0.78F, 0.78F, 0.78F, 1.0F),
                mosaicVariableBrush),
        };
        for (const auto& result : results) {
            if (result.has_value()) {
                discardMosaicResources();
                return result;
            }
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> ensureTextResources() noexcept
    {
        if (textPanelBrush && textBorderBrush && textSelectionBrush
            && textForegroundBrush && textWhiteBrush && textVariableBrush
            && std::all_of(textIconBitmaps.begin(), textIconBitmaps.end(),
                [](const auto& bitmap) { return bitmap.get() != nullptr; })) {
            return std::nullopt;
        }
        discardTextResources();
        const std::array results{
            createBrush(colorWithMultipliedAlpha(
                VisualStyleCatalog::toolbarBackgroundColor, 0.96F),
                textPanelBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.18F),
                textBorderBrush),
            createBrush(D2D1::ColorF(0.0F, 0.48F, 1.0F, 1.0F),
                textSelectionBrush),
            createBrush(D2D1::ColorF(0.12F, 0.12F, 0.12F, 1.0F),
                textForegroundBrush),
            createBrush(D2D1::ColorF(D2D1::ColorF::White),
                textWhiteBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 1.0F),
                textVariableBrush),
        };
        for (const auto& result : results) {
            if (result.has_value()) {
                discardTextResources();
                return result;
            }
        }
        constexpr std::array iconResources{
            IDR_TEXT_BOLD_PNG,
            IDR_TEXT_BOLD_SELECTED_PNG,
            IDR_TEXT_ITALIC_PNG,
            IDR_TEXT_ITALIC_SELECTED_PNG,
            IDR_TEXT_STROKE_PNG,
            IDR_TEXT_STROKE_SELECTED_PNG,
        };
        for (std::size_t index = 0; index < iconResources.size(); ++index) {
            if (const auto iconError = createIconBitmap(
                    iconResources[index], textIconBitmaps[index].put())) {
                discardTextResources();
                return iconError;
            }
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> createIconBitmap(
        int resourceId,
        ID2D1Bitmap** destination) noexcept
    {
        const auto resource = FindResourceW(
            resourceModule,
            MAKEINTRESOURCEW(resourceId),
            MAKEINTRESOURCEW(10)); // RT_RCDATA, explicitly wide for FindResourceW.
        if (resource == nullptr) {
            return error(
                OverlayRendererErrorCode::resourceNotFound,
                HRESULT_FROM_WIN32(GetLastError()),
                resourceId);
        }
        const auto size = SizeofResource(resourceModule, resource);
        const auto loaded = LoadResource(resourceModule, resource);
        if (size == 0U || loaded == nullptr) {
            return error(
                OverlayRendererErrorCode::resourceDecodeFailed,
                E_FAIL,
                resourceId);
        }
        auto* bytes = static_cast<BYTE*>(LockResource(loaded));
        if (bytes == nullptr) {
            return error(
                OverlayRendererErrorCode::resourceDecodeFailed,
                E_FAIL,
                resourceId);
        }

        ComPtr<IWICStream> stream;
        auto result = wicFactory->CreateStream(stream.put());
        if (SUCCEEDED(result)) {
            result = stream->InitializeFromMemory(bytes, size);
        }
        ComPtr<IWICBitmapDecoder> decoder;
        if (SUCCEEDED(result)) {
            result = wicFactory->CreateDecoderFromStream(
                stream.get(),
                nullptr,
                WICDecodeMetadataCacheOnLoad,
                decoder.put());
        }
        ComPtr<IWICBitmapFrameDecode> frame;
        if (SUCCEEDED(result)) {
            result = decoder->GetFrame(0U, frame.put());
        }
        ComPtr<IWICFormatConverter> converter;
        if (SUCCEEDED(result)) {
            result = wicFactory->CreateFormatConverter(converter.put());
        }
        if (SUCCEEDED(result)) {
            result = converter->Initialize(
                frame.get(),
                GUID_WICPixelFormat32bppPBGRA,
                WICBitmapDitherTypeNone,
                nullptr,
                0.0,
                WICBitmapPaletteTypeCustom);
        }
        if (SUCCEEDED(result)) {
            result = renderTarget->CreateBitmapFromWicBitmap(
                converter.get(),
                nullptr,
                destination);
        }
        if (FAILED(result)) {
            return error(
                OverlayRendererErrorCode::resourceDecodeFailed,
                result,
                resourceId);
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> ensureDeviceResources(
        const FrozenDisplay& display) noexcept
    {
        if (const auto factoryError = ensureFactories()) {
            return factoryError;
        }
        if (renderTarget && backgroundBitmap) {
            return std::nullopt;
        }
        if (window == nullptr
            || display.pixels.width() <= 0
            || display.pixels.height() <= 0
            || display.pixels.width() != display.descriptor.pixelBounds.width
            || display.pixels.height() != display.descriptor.pixelBounds.height
            || display.pixels.stride() > (std::numeric_limits<UINT32>::max)()) {
            return error(OverlayRendererErrorCode::invalidArgument, E_INVALIDARG);
        }

        RECT client{};
        if (!GetClientRect(window, &client)) {
            return error(
                OverlayRendererErrorCode::renderTargetFailed,
                HRESULT_FROM_WIN32(GetLastError()));
        }
        const auto pixelSize = D2D1::SizeU(
            static_cast<UINT32>((std::max)(0L, client.right - client.left)),
            static_cast<UINT32>((std::max)(0L, client.bottom - client.top)));
        const auto dpiX = normalizedDpi(display.descriptor.dpiX);
        const auto dpiY = normalizedDpi(display.descriptor.dpiY);
        const auto targetProperties = D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_DEFAULT,
            D2D1::PixelFormat(
                DXGI_FORMAT_B8G8R8A8_UNORM,
                D2D1_ALPHA_MODE_PREMULTIPLIED),
            dpiX,
            dpiY);
        const auto hwndProperties = D2D1::HwndRenderTargetProperties(
            window,
            pixelSize,
            D2D1_PRESENT_OPTIONS_IMMEDIATELY);
        auto result = d2dFactory->CreateHwndRenderTarget(
            targetProperties,
            hwndProperties,
            renderTarget.put());
        if (FAILED(result)) {
            return error(OverlayRendererErrorCode::renderTargetFailed, result);
        }

        const auto bitmapSize = D2D1::SizeU(
            static_cast<UINT32>(display.pixels.width()),
            static_cast<UINT32>(display.pixels.height()));
        const auto bitmapProperties = D2D1::BitmapProperties(
            D2D1::PixelFormat(
                DXGI_FORMAT_B8G8R8A8_UNORM,
                D2D1_ALPHA_MODE_PREMULTIPLIED),
            dpiX,
            dpiY);
        result = renderTarget->CreateBitmap(
            bitmapSize,
            display.pixels.data(),
            static_cast<UINT32>(display.pixels.stride()),
            bitmapProperties,
            backgroundBitmap.put());
        if (FAILED(result)) {
            discardDeviceResources();
            return error(OverlayRendererErrorCode::backgroundBitmapFailed, result);
        }

        constexpr auto resources = toolbarImageResources();
        const auto resourceDpi = static_cast<std::uint32_t>((std::max)(dpiX, dpiY));
        for (std::size_t index = 0; index < resources.size(); ++index) {
            if (const auto iconError = createIconBitmap(
                    toolbarResourceId(resources[index], resourceDpi),
                    iconBitmaps[index].put())) {
                discardDeviceResources();
                return iconError;
            }
        }
        if (const auto paletteError = createIconBitmap(
                IDR_PALETTE_TOOL_PNG, paletteBitmap.put())) {
            discardDeviceResources();
            return paletteError;
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> measureLabel(
        const std::wstring& text,
        float& width) noexcept
    {
        ComPtr<IDWriteTextLayout> textLayout;
        const auto result = dwriteFactory->CreateTextLayout(
            text.data(),
            static_cast<UINT32>(text.size()),
            textFormat.get(),
            4096.0F,
            VisualStyleCatalog::sizeLabelHeightDip,
            textLayout.put());
        if (FAILED(result)) {
            return error(OverlayRendererErrorCode::drawFailed, result);
        }
        DWRITE_TEXT_METRICS metrics{};
        const auto metricsResult = textLayout->GetMetrics(&metrics);
        if (FAILED(metricsResult)) {
            return error(OverlayRendererErrorCode::drawFailed, metricsResult);
        }
        width = metrics.widthIncludingTrailingWhitespace;
        return std::nullopt;
    }

    std::optional<OverlayRendererError> createBrush(
        D2D1_COLOR_F brushColor,
        ComPtr<ID2D1SolidColorBrush>& brush) noexcept
    {
        const auto result = renderTarget->CreateSolidColorBrush(
            brushColor,
            brush.put());
        if (FAILED(result)) {
            return error(OverlayRendererErrorCode::drawFailed, result);
        }
        return std::nullopt;
    }

    HRESULT drawStrokeSample(
        AnnotationPoint startPoint,
        AnnotationPoint endPoint,
        AnnotationStrokePattern pattern,
        float width,
        ID2D1Brush* brush) noexcept
    {
        const auto start = D2D1::Point2F(startPoint.x, startPoint.y);
        const auto end = D2D1::Point2F(endPoint.x, endPoint.y);
        const auto dashes = normalizedStrokeDashPattern(pattern, width);
        ComPtr<ID2D1StrokeStyle> strokeStyle;
        if (!dashes.empty()) {
            auto properties = D2D1::StrokeStyleProperties(
                D2D1_CAP_STYLE_ROUND,
                D2D1_CAP_STYLE_ROUND,
                D2D1_CAP_STYLE_ROUND,
                D2D1_LINE_JOIN_ROUND,
                10.0F,
                D2D1_DASH_STYLE_CUSTOM,
                0.0F);
            const auto result = d2dFactory->CreateStrokeStyle(
                &properties,
                dashes.data(),
                static_cast<UINT32>(dashes.size()),
                strokeStyle.put());
            if (FAILED(result)) {
                return result;
            }
        }
        if (pattern == AnnotationStrokePattern::sketchSolid
            || pattern == AnnotationStrokePattern::sketchDashed) {
            ComPtr<ID2D1PathGeometry> geometry;
            auto result = d2dFactory->CreatePathGeometry(geometry.put());
            ComPtr<ID2D1GeometrySink> sink;
            if (SUCCEEDED(result)) {
                result = geometry->Open(sink.put());
            }
            if (FAILED(result)) {
                return result;
            }
            const auto points = sketchStrokeSamplePoints(
                startPoint, endPoint, width);
            if (!points.empty()) {
                sink->BeginFigure(
                    D2D1::Point2F(points.front().x, points.front().y),
                    D2D1_FIGURE_BEGIN_HOLLOW);
                for (std::size_t index = 1; index < points.size(); ++index) {
                    sink->AddLine(D2D1::Point2F(points[index].x, points[index].y));
                }
                sink->EndFigure(D2D1_FIGURE_END_OPEN);
            }
            result = sink->Close();
            if (FAILED(result)) {
                return result;
            }
            renderTarget->DrawGeometry(
                geometry.get(), brush, width, strokeStyle.get());
        } else {
            renderTarget->DrawLine(start, end, brush, width, strokeStyle.get());
        }
        return S_OK;
    }

    HRESULT fillTriangle(
        D2D1_POINT_2F first,
        D2D1_POINT_2F second,
        D2D1_POINT_2F third,
        ID2D1Brush* brush) noexcept
    {
        ComPtr<ID2D1PathGeometry> geometry;
        auto result = d2dFactory->CreatePathGeometry(geometry.put());
        ComPtr<ID2D1GeometrySink> sink;
        if (SUCCEEDED(result)) {
            result = geometry->Open(sink.put());
        }
        if (FAILED(result)) {
            return result;
        }
        sink->BeginFigure(first, D2D1_FIGURE_BEGIN_FILLED);
        sink->AddLine(second);
        sink->AddLine(third);
        sink->EndFigure(D2D1_FIGURE_END_CLOSED);
        result = sink->Close();
        if (SUCCEEDED(result)) {
            renderTarget->FillGeometry(geometry.get(), brush);
        }
        return result;
    }

    std::optional<OverlayRendererError> drawShapeOptions(
        const OverlayShapeOptionsRenderState& options) noexcept
    {
        ComPtr<ID2D1SolidColorBrush> panelBrush;
        ComPtr<ID2D1SolidColorBrush> borderBrush;
        ComPtr<ID2D1SolidColorBrush> separatorBrush;
        ComPtr<ID2D1SolidColorBrush> selectionStrokeBrush;
        ComPtr<ID2D1SolidColorBrush> controlBrush;
        ComPtr<ID2D1SolidColorBrush> controlBackgroundBrush;
        ComPtr<ID2D1SolidColorBrush> textBrush;
        ComPtr<ID2D1SolidColorBrush> fillPreviewBrush;
        const std::array results{
            createBrush(
                colorWithMultipliedAlpha(
                    VisualStyleCatalog::toolbarBackgroundColor, 0.96F),
                panelBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.16F), borderBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.15F), separatorBrush),
            createBrush(D2D1::ColorF(0.0F, 0.48F, 1.0F, 1.0F), selectionStrokeBrush),
            createBrush(annotationColor(options.state.style().strokeColor), controlBrush),
            createBrush(D2D1::ColorF(1.0F, 1.0F, 1.0F, 1.0F), controlBackgroundBrush),
            createBrush(D2D1::ColorF(0.12F, 0.12F, 0.12F, 1.0F), textBrush),
            createBrush(
                options.state.style().fillEnabled
                    ? annotationColor(options.state.style().fillColor)
                    : D2D1::ColorF(0.56F, 0.56F, 0.58F, 1.0F),
                fillPreviewBrush),
        };
        for (const auto& result : results) {
            if (result.has_value()) {
                return result;
            }
        }

        const auto drawPanel = [this, &panelBrush, &borderBrush](
                                   AnnotationRect bounds, float radius) {
            const auto rounded = D2D1::RoundedRect(d2dRect(bounds), radius, radius);
            renderTarget->FillRoundedRectangle(&rounded, panelBrush.get());
            renderTarget->DrawRoundedRectangle(&rounded, borderBrush.get(), 1.0F);
        };
        drawPanel(options.layout.toolbar, 6.0F);
        for (const auto separator : options.layout.separators) {
            const auto rounded = D2D1::RoundedRect(d2dRect(separator), 0.75F, 0.75F);
            renderTarget->FillRoundedRectangle(&rounded, separatorBrush.get());
        }

        constexpr std::array<float, 3> widths{2.0F, 4.0F, 7.0F};
        for (std::size_t index = 0; index < options.layout.strokeWidths.size(); ++index) {
            const auto rect = options.layout.strokeWidths[index];
            const bool selected = index < widths.size()
                && options.state.style().strokeWidthDip == widths[index];
            renderTarget->DrawLine(
                D2D1::Point2F(rect.x + 4.0F, rect.y + rect.height / 2.0F),
                D2D1::Point2F(rect.x + rect.width - 4.0F, rect.y + rect.height / 2.0F),
                selected ? selectionStrokeBrush.get() : textBrush.get(),
                widths[index]);
        }

        const AnnotationRect fillIconBounds{
            options.layout.fillToggle.x + 4.0F,
            options.layout.fillToggle.y + 4.0F,
            options.layout.fillToggle.width - 8.0F,
            options.layout.fillToggle.height - 8.0F,
        };
        if (options.state.kind() == AnnotationKind::ellipse) {
            const auto fillIcon = D2D1::Ellipse(
                D2D1::Point2F(
                    fillIconBounds.x + fillIconBounds.width / 2.0F,
                    fillIconBounds.y + fillIconBounds.height / 2.0F),
                fillIconBounds.width / 2.0F,
                fillIconBounds.height / 2.0F);
            renderTarget->FillEllipse(&fillIcon, fillPreviewBrush.get());
        } else {
            const auto fillIcon = D2D1::RoundedRect(
                d2dRect(fillIconBounds), 2.0F, 2.0F);
            renderTarget->FillRoundedRectangle(&fillIcon, fillPreviewBrush.get());
        }

        const bool rectangle = options.state.kind() == AnnotationKind::rectangle;
        const auto rectangleIcon = D2D1::RoundedRect(
            d2dRect(AnnotationRect{
                options.layout.rectangleMode.x
                    + (options.layout.rectangleMode.width - 13.0F) / 2.0F,
                options.layout.rectangleMode.y
                    + (options.layout.rectangleMode.height - 13.0F) / 2.0F,
                13.0F,
                13.0F,
            }),
            1.5F,
            1.5F);
        renderTarget->DrawRoundedRectangle(
            &rectangleIcon,
            rectangle ? selectionStrokeBrush.get() : textBrush.get(),
            1.5F);
        const auto ellipse = D2D1::Ellipse(
            D2D1::Point2F(
                options.layout.ellipseMode.x + options.layout.ellipseMode.width / 2.0F,
                options.layout.ellipseMode.y + options.layout.ellipseMode.height / 2.0F),
            6.5F,
            6.0F);
        renderTarget->DrawEllipse(
            &ellipse,
            rectangle ? textBrush.get() : selectionStrokeBrush.get(),
            1.6F);

        auto shapeResult = fillTriangle(
            D2D1::Point2F(
                options.layout.rectangleModeBackground.x
                    + options.layout.rectangleModeBackground.width,
                options.layout.rectangleModeBackground.y
                    + options.layout.rectangleModeBackground.height),
            D2D1::Point2F(
                options.layout.rectangleModeBackground.x
                    + options.layout.rectangleModeBackground.width - 6.0F,
                options.layout.rectangleModeBackground.y
                    + options.layout.rectangleModeBackground.height),
            D2D1::Point2F(
                options.layout.rectangleModeBackground.x
                    + options.layout.rectangleModeBackground.width,
                options.layout.rectangleModeBackground.y
                    + options.layout.rectangleModeBackground.height - 6.0F),
            textBrush.get());
        if (FAILED(shapeResult)) {
            return error(OverlayRendererErrorCode::drawFailed, shapeResult);
        }

        const auto strokeField = D2D1::RoundedRect(
            d2dRect(options.layout.strokeStyle), 4.0F, 4.0F);
        renderTarget->FillRoundedRectangle(
            &strokeField, controlBackgroundBrush.get());
        renderTarget->DrawRoundedRectangle(&strokeField, borderBrush.get(), 1.0F);
        auto strokeResult = drawStrokeSample(
            options.layout.strokeStyleSampleStart,
            options.layout.strokeStyleSampleEnd,
            options.state.style().strokePattern,
            2.0F,
            textBrush.get());
        if (FAILED(strokeResult)) {
            return error(OverlayRendererErrorCode::drawFailed, strokeResult);
        }
        const auto disclosure = options.layout.strokeStyleDisclosure;
        strokeResult = fillTriangle(
            D2D1::Point2F(disclosure.x, disclosure.y),
            D2D1::Point2F(disclosure.x + disclosure.width, disclosure.y),
            D2D1::Point2F(
                disclosure.x + disclosure.width / 2.0F,
                disclosure.y + disclosure.height),
            textBrush.get());
        if (FAILED(strokeResult)) {
            return error(OverlayRendererErrorCode::drawFailed, strokeResult);
        }

        const auto& palette = macShapePalette();
        for (std::size_t index = 0;
             index < options.layout.paletteCount && index < palette.size();
             ++index) {
            auto swatch = options.layout.colorSwatches[index];
            const bool selected = options.state.selectedPaletteIndex() == index;
            if (selected) {
                swatch = {
                    swatch.x - 3.0F,
                    swatch.y - 3.0F,
                    swatch.width + 6.0F,
                    swatch.height + 6.0F,
                };
            }
            ComPtr<ID2D1SolidColorBrush> swatchBrush;
            if (const auto brushError = createBrush(
                    annotationColor(palette[index]), swatchBrush)) {
                return brushError;
            }
            const auto rounded = D2D1::RoundedRect(
                d2dRect(swatch), selected ? 4.0F : 2.5F, selected ? 4.0F : 2.5F);
            renderTarget->FillRoundedRectangle(&rounded, swatchBrush.get());
            renderTarget->DrawRoundedRectangle(
                &rounded,
                selected ? selectionStrokeBrush.get() : borderBrush.get(),
                selected ? 1.5F : 1.0F);
        }

        if (!options.layout.colorSwatches.empty()) {
            const auto custom = options.layout.colorSwatches.back();
            renderTarget->DrawBitmap(
                paletteBitmap.get(),
                d2dRect(custom),
                1.0F,
                D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
        }

        if (options.strokePatternMenu.has_value()) {
            drawPanel(options.strokePatternMenu->menu, 6.0F);
            const auto& patterns = macShapeStrokePatterns();
            for (std::size_t index = 0;
                 index < options.strokePatternMenu->items.size()
                    && index < patterns.size();
                 ++index) {
                const bool selected = patterns[index]
                    == options.state.style().strokePattern;
                strokeResult = drawStrokeSample(
                    options.strokePatternMenu->sampleStarts[index],
                    options.strokePatternMenu->sampleEnds[index],
                    patterns[index],
                    2.0F,
                    selected ? selectionStrokeBrush.get() : textBrush.get());
                if (FAILED(strokeResult)) {
                    return error(OverlayRendererErrorCode::drawFailed, strokeResult);
                }
            }
        }

        if (options.cornerRadiusPanel.has_value()) {
            const auto& panel = *options.cornerRadiusPanel;
            drawPanel(panel.panel, 6.0F);
            const wchar_t label[] = L"\u5706\u89d2";
            renderTarget->DrawText(
                label, 2U, textFormat.get(), d2dRect(panel.label),
                textBrush.get(), D2D1_DRAW_TEXT_OPTIONS_CLIP);
            const auto track = D2D1::RoundedRect(
                d2dRect(panel.sliderTrack), 2.0F, 2.0F);
            renderTarget->FillRoundedRectangle(&track, borderBrush.get());
            const auto ratio = options.state.style().cornerRadiusDip / 30.0F;
            const auto thumb = D2D1::Ellipse(
                D2D1::Point2F(
                    panel.sliderTrack.x + panel.sliderTrack.width * ratio,
                    panel.sliderTrack.y + panel.sliderTrack.height / 2.0F),
                7.0F, 7.0F);
            renderTarget->FillEllipse(&thumb, selectionStrokeBrush.get());
            const auto valueRounded = D2D1::RoundedRect(
                d2dRect(panel.value), 4.0F, 4.0F);
            renderTarget->DrawRoundedRectangle(&valueRounded, borderBrush.get(), 1.0F);
            const auto value = std::to_wstring(static_cast<int>(
                options.state.style().cornerRadiusDip + 0.5F));
            const AnnotationRect valueText{
                panel.value.x + 6.0F, panel.value.y,
                panel.value.width - 24.0F, panel.value.height};
            renderTarget->DrawText(
                value.data(), static_cast<UINT32>(value.size()), textFormat.get(),
                d2dRect(valueText), textBrush.get(), D2D1_DRAW_TEXT_OPTIONS_CLIP);
            const auto arrowX = panel.increment.x + panel.increment.width / 2.0F;
            renderTarget->DrawLine(
                D2D1::Point2F(arrowX - 2.5F, panel.increment.y + 7.0F),
                D2D1::Point2F(arrowX, panel.increment.y + 4.5F),
                textBrush.get(), 1.0F);
            renderTarget->DrawLine(
                D2D1::Point2F(arrowX, panel.increment.y + 4.5F),
                D2D1::Point2F(arrowX + 2.5F, panel.increment.y + 7.0F),
                textBrush.get(), 1.0F);
            renderTarget->DrawLine(
                D2D1::Point2F(arrowX - 2.5F, panel.decrement.y + 5.0F),
                D2D1::Point2F(arrowX, panel.decrement.y + 7.5F),
                textBrush.get(), 1.0F);
            renderTarget->DrawLine(
                D2D1::Point2F(arrowX, panel.decrement.y + 7.5F),
                D2D1::Point2F(arrowX + 2.5F, panel.decrement.y + 5.0F),
                textBrush.get(), 1.0F);
        }
        return std::nullopt;
    }

    std::optional<OverlayRendererError> draw(
        const FrozenDisplay& display,
        const OverlayRenderState& state)
    {
        if (const auto deviceError = ensureDeviceResources(display)) {
            return deviceError;
        }

        ComPtr<ID2D1SolidColorBrush> dimBrush;
        ComPtr<ID2D1SolidColorBrush> selectionBrush;
        ComPtr<ID2D1SolidColorBrush> handleStrokeBrush;
        ComPtr<ID2D1SolidColorBrush> labelBackgroundBrush;
        ComPtr<ID2D1SolidColorBrush> labelTextBrush;
        ComPtr<ID2D1SolidColorBrush> toolbarBackgroundBrush;
        ComPtr<ID2D1SolidColorBrush> toolbarBorderBrush;
        ComPtr<ID2D1SolidColorBrush> toolbarSeparatorBrush;
        ComPtr<ID2D1SolidColorBrush> recognitionFillBrush;

        const std::array brushResults{
            createBrush(D2D1::ColorF(
                color(VisualStyleCatalog::dimColor).r,
                color(VisualStyleCatalog::dimColor).g,
                color(VisualStyleCatalog::dimColor).b,
                VisualStyleCatalog::dimAlpha), dimBrush),
            createBrush(color(VisualStyleCatalog::selectionColor), selectionBrush),
            createBrush(D2D1::ColorF(
                color(VisualStyleCatalog::selectionHandleStrokeColor).r,
                color(VisualStyleCatalog::selectionHandleStrokeColor).g,
                color(VisualStyleCatalog::selectionHandleStrokeColor).b,
                VisualStyleCatalog::selectionHandleStrokeAlpha), handleStrokeBrush),
            createBrush(D2D1::ColorF(
                VisualStyleCatalog::sizeLabelBackgroundWhite,
                VisualStyleCatalog::sizeLabelBackgroundWhite,
                VisualStyleCatalog::sizeLabelBackgroundWhite,
                VisualStyleCatalog::sizeLabelBackgroundAlpha), labelBackgroundBrush),
            createBrush(color(VisualStyleCatalog::sizeLabelTextColor), labelTextBrush),
            createBrush(colorWithMultipliedAlpha(
                VisualStyleCatalog::toolbarBackgroundColor,
                VisualStyleCatalog::toolbarBackgroundAlpha), toolbarBackgroundBrush),
            createBrush(color(VisualStyleCatalog::toolbarBorderColor), toolbarBorderBrush),
            createBrush(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.15F), toolbarSeparatorBrush),
            createBrush(D2D1::ColorF(0.70F, 0.70F, 0.70F, 0.28F), recognitionFillBrush),
        };
        for (const auto& brushResult : brushResults) {
            if (brushResult.has_value()) {
                return brushResult;
            }
        }

        std::optional<OverlayLayout> chromeLayout;
        if (state.selection.has_value()) {
            const auto label = sizeLabelText(*state.selection);
            float labelWidth = 0.0F;
            if (const auto measureError = measureLabel(label, labelWidth)) {
                return measureError;
            }
            chromeLayout = computeOverlayLayout({
                display.descriptor.pixelBounds,
                *state.selection,
                display.descriptor.dpiX,
                display.descriptor.dpiY,
                labelWidth,
                state.showActions,
                state.toolbarActions,
            });
            for (auto& item : chromeLayout->toolbarItems) {
                item.selected = state.selectedToolbarAction == item.action;
                if (item.action == ToolbarAction::undo) {
                    item.enabled = state.canUndo;
                } else if (item.action == ToolbarAction::redo) {
                    item.enabled = state.canRedo;
                }
            }
        }

        renderTarget->BeginDraw();
        renderTarget->SetTransform(D2D1::Matrix3x2F::Identity());
        renderTarget->Clear(D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.0F));

        const DipRect overlayBounds{
            0.0F,
            0.0F,
            physicalPixelsToDip(display.pixels.width(), display.descriptor.dpiX),
            physicalPixelsToDip(display.pixels.height(), display.descriptor.dpiY),
        };
        renderTarget->DrawBitmap(
            backgroundBitmap.get(),
            d2dRect(overlayBounds),
            1.0F,
            D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);

        if (!state.selection.has_value()) {
            if (!state.textRecognition) {
                renderTarget->FillRectangle(d2dRect(overlayBounds), dimBrush.get());
            }
        } else {
            const auto& layout = *chromeLayout;
            if (!state.pinnedImageEditor && !state.textRecognition) {
                for (const auto mask : layout.mask) {
                    if (mask.width > 0.0F && mask.height > 0.0F) {
                        renderTarget->FillRectangle(d2dRect(mask), dimBrush.get());
                    }
                }
            }

            if (state.annotationComposite != nullptr) {
                const auto& pixels = *state.annotationComposite;
                if (pixels.width() > 0 && pixels.height() > 0
                    && pixels.stride()
                        <= (std::numeric_limits<UINT32>::max)()) {
                    if (annotationCompositeSource
                        != state.annotationComposite) {
                        annotationCompositeBitmap.reset();
                        const auto bitmapSize = D2D1::SizeU(
                            static_cast<UINT32>(pixels.width()),
                            static_cast<UINT32>(pixels.height()));
                        const auto properties = D2D1::BitmapProperties(
                            D2D1::PixelFormat(
                                DXGI_FORMAT_B8G8R8A8_UNORM,
                                D2D1_ALPHA_MODE_PREMULTIPLIED),
                            normalizedDpi(display.descriptor.dpiX),
                            normalizedDpi(display.descriptor.dpiY));
                        const auto bitmapResult = renderTarget->CreateBitmap(
                            bitmapSize,
                            pixels.data(),
                            static_cast<UINT32>(pixels.stride()),
                            properties,
                            annotationCompositeBitmap.put());
                        if (FAILED(bitmapResult)) {
                            renderTarget->EndDraw();
                            return error(
                                OverlayRendererErrorCode::drawFailed,
                                bitmapResult);
                        }
                        annotationCompositeSource
                            = state.annotationComposite;
                    }
                    renderTarget->DrawBitmap(
                        annotationCompositeBitmap.get(),
                        d2dRect(layout.border),
                        1.0F,
                        D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
                }
            } else {
                annotationCompositeBitmap.reset();
                annotationCompositeSource.reset();
            }

            if (state.textRecognition) {
                renderTarget->FillRectangle(
                    d2dRect(layout.border), recognitionFillBrush.get());
            } else {
                renderTarget->DrawRectangle(
                    d2dRect(layout.border),
                    selectionBrush.get(),
                    VisualStyleCatalog::selectionBorderDip);
            }

            if (!state.annotationPlan.items.empty()
                || !state.annotationPlan.resizeHandles.empty()) {
                AnnotationRenderer annotationRenderer(d2dFactory.get());
                const auto annotationResult = annotationRenderer.draw(
                    renderTarget.get(), state.annotationPlan);
                if (FAILED(annotationResult)) {
                    renderTarget->EndDraw();
                    return error(
                        OverlayRendererErrorCode::drawFailed,
                        annotationResult);
                }
                if (state.annotationPlan.rotationHandle.has_value()) {
                    const auto& point = *state.annotationPlan.rotationHandle;
                    constexpr auto iconSizeDip = ToolbarMetrics::buttonSizeDip
                        - rotationHandleIcon().insetDip * 2.0F;
                    const auto destination = D2D1::RectF(
                        point.x - iconSizeDip / 2.0F,
                        point.y - iconSizeDip / 2.0F,
                        point.x + iconSizeDip / 2.0F,
                        point.y + iconSizeDip / 2.0F);
                    renderTarget->DrawBitmap(
                        iconBitmaps[rotationHandleIconIndex()].get(),
                        destination,
                        1.0F,
                        D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
                }
            }

            if (layout.showActions) {
                if (!state.pinnedImageEditor) {
                    const auto labelRounded = D2D1::RoundedRect(
                        d2dRect(layout.sizeLabel),
                        VisualStyleCatalog::sizeLabelCornerRadiusDip,
                        VisualStyleCatalog::sizeLabelCornerRadiusDip);
                    renderTarget->FillRoundedRectangle(
                        &labelRounded, labelBackgroundBrush.get());
                    const DipRect labelTextRect{
                        layout.sizeLabel.x
                            + VisualStyleCatalog::sizeLabelHorizontalTextInsetDip,
                        layout.sizeLabel.y
                            + VisualStyleCatalog::sizeLabelVerticalTextInsetDip,
                        (std::max)(0.0F, layout.sizeLabel.width
                            - VisualStyleCatalog::sizeLabelHorizontalTextInsetDip * 2.0F),
                        (std::max)(0.0F, layout.sizeLabel.height
                            - VisualStyleCatalog::sizeLabelVerticalTextInsetDip * 2.0F),
                    };
                    renderTarget->DrawText(
                        layout.sizeLabelText.data(),
                        static_cast<UINT32>(layout.sizeLabelText.size()),
                        textFormat.get(), d2dRect(labelTextRect),
                        labelTextBrush.get(), D2D1_DRAW_TEXT_OPTIONS_CLIP);
                }

                const auto toolbarRounded = D2D1::RoundedRect(
                    d2dRect(layout.toolbar.bounds),
                    ToolbarMetrics::cornerRadiusDip,
                    ToolbarMetrics::cornerRadiusDip);
                renderTarget->FillRoundedRectangle(
                    &toolbarRounded, toolbarBackgroundBrush.get());
                renderTarget->DrawRoundedRectangle(
                    &toolbarRounded,
                    toolbarBorderBrush.get(),
                    VisualStyleCatalog::toolbarBorderDip);

                drawToolbarIcon(
                    dragHandleIcon(),
                    0U,
                    layout.toolbar.leadingDragHandle,
                    selectionBrush.get(),
                    false);
                for (std::size_t index = 0; index < layout.toolbarItems.size(); ++index) {
                    const auto& item = layout.toolbarItems[index];
                    if (toolbarIcon(item.action).kind
                        == ToolbarIconSpec::Kind::checkmark) {
                        const auto left = item.rect.x + 4.5F;
                        const auto middleX = item.rect.x + 9.0F;
                        const auto middleY = item.rect.y + 14.0F;
                        renderTarget->DrawLine(
                            D2D1::Point2F(left, item.rect.y + 10.5F),
                            D2D1::Point2F(middleX, middleY),
                            labelTextBrush.get(), 2.4F);
                        renderTarget->DrawLine(
                            D2D1::Point2F(middleX, middleY),
                            D2D1::Point2F(item.rect.x + 16.5F, item.rect.y + 6.0F),
                            labelTextBrush.get(), 2.4F);
                        continue;
                    }
                    const auto iconIndex = item.enabled
                        ? toolbarIconIndex(item.action)
                        : disabledToolbarIconIndex(item.action);
                    const auto& icon = toolbarImageResources()[iconIndex];
                    drawToolbarIcon(
                        icon, iconIndex, item.rect,
                        selectionBrush.get(), item.selected);

                    if (index + 1U < layout.toolbarItems.size()
                        && extraGapAfter(item.action) > 0.0F) {
                        const auto& next = layout.toolbarItems[index + 1U].rect;
                        const auto separatorX = floorDip(
                            item.rect.x + item.rect.width
                            + (next.x - item.rect.x - item.rect.width) / 2.0F)
                            + 0.25F;
                        const DipRect separator{
                            separatorX,
                            layout.toolbar.bounds.y
                                + layout.toolbar.bounds.height / 2.0F - 6.0F,
                            1.5F,
                            12.0F,
                        };
                        const auto roundedSeparator = D2D1::RoundedRect(
                            d2dRect(separator), 0.75F, 0.75F);
                        renderTarget->FillRoundedRectangle(
                            &roundedSeparator, toolbarSeparatorBrush.get());
                    }
                }
                drawToolbarIcon(
                    dragHandleIcon(),
                    0U,
                    layout.toolbar.trailingDragHandle,
                    selectionBrush.get(),
                    false);
            }

            if (state.shapeOptions.has_value()) {
                if (const auto optionsError = drawShapeOptions(*state.shapeOptions)) {
                    renderTarget->EndDraw();
                    return optionsError;
                }
            }
            if (state.arrowLineOptions.has_value()) {
                if (const auto optionsError = drawArrowLineOptions(
                        *state.arrowLineOptions)) {
                    renderTarget->EndDraw();
                    return optionsError;
                }
            }
            if (state.brushOptions.has_value()) {
                if (const auto optionsError = drawBrushOptions(
                        *state.brushOptions)) {
                    renderTarget->EndDraw();
                    return optionsError;
                }
            }
            if (state.markerOptions.has_value()) {
                if (const auto optionsError = drawMarkerOptions(
                        *state.markerOptions)) {
                    renderTarget->EndDraw();
                    return optionsError;
                }
            }
            if (state.mosaicOptions.has_value()) {
                if (const auto optionsError = drawMosaicOptions(
                        *state.mosaicOptions)) {
                    renderTarget->EndDraw();
                    return optionsError;
                }
            }
            if (state.textOptions.has_value()) {
                if (const auto optionsError = drawTextOptions(
                        *state.textOptions)) {
                    renderTarget->EndDraw();
                    return optionsError;
                }
            }
            if (state.numberOptions.has_value()) {
                if (const auto optionsError = drawNumberOptions(
                        *state.numberOptions)) {
                    renderTarget->EndDraw();
                    return optionsError;
                }
            }
            if (state.magnifierOptions.has_value()) {
                if (const auto optionsError = drawMagnifierOptions(
                        *state.magnifierOptions)) {
                    renderTarget->EndDraw();
                    return optionsError;
                }
            }
            if (state.eraserOptions.has_value()) {
                if (const auto optionsError = drawEraserOptions(
                        *state.eraserOptions)) {
                    return *optionsError;
                }
            }

            if (!state.pinnedImageEditor && !state.textRecognition) {
                for (const auto handle : layout.handles) {
                    const auto ellipse = D2D1::Ellipse(
                        D2D1::Point2F(
                            handle.x + handle.width / 2.0F,
                            handle.y + handle.height / 2.0F),
                        handle.width / 2.0F,
                        handle.height / 2.0F);
                    renderTarget->FillEllipse(&ellipse, selectionBrush.get());
                    renderTarget->DrawEllipse(
                        &ellipse,
                        handleStrokeBrush.get(),
                        VisualStyleCatalog::selectionHandleStrokeDip);
                }
            }
            if (state.eyedropper.has_value()) {
                if (const auto eyedropperError = drawEyedropper(
                        *state.eyedropper,
                        {overlayBounds.x, overlayBounds.y,
                            overlayBounds.width, overlayBounds.height})) {
                    renderTarget->EndDraw();
                    return eyedropperError;
                }
            }
        }

        const auto result = renderTarget->EndDraw();
        if (result == D2DERR_RECREATE_TARGET) {
            discardDeviceResources();
            return error(OverlayRendererErrorCode::deviceLost, result);
        }
        if (FAILED(result)) {
            return error(OverlayRendererErrorCode::drawFailed, result);
        }
        return std::nullopt;
    }

    void discardDeviceResources() noexcept
    {
        discardEyedropperResources();
        discardMosaicResources();
        discardTextResources();
        annotationCompositeBitmap.reset();
        annotationCompositeSource.reset();
        paletteBitmap.reset();
        for (auto& bitmap : iconBitmaps) {
            bitmap.reset();
        }
        backgroundBitmap.reset();
        renderTarget.reset();
    }

    void discardEyedropperResources() noexcept
    {
        eyedropperPanelWhiteBrush.reset();
        eyedropperWhiteBrush.reset();
        eyedropperBlueBrush.reset();
        eyedropperDarkBrush.reset();
        eyedropperInfoBrush.reset();
        eyedropperBorderBrush.reset();
        eyedropperGridBrush.reset();
        eyedropperSuccessBrush.reset();
        eyedropperCellBrush.reset();
        eyedropperWhiteStrokeStyle.reset();
        eyedropperBlueStrokeStyle.reset();
    }

    void discardMosaicResources() noexcept
    {
        mosaicPanelBrush.reset();
        mosaicBorderBrush.reset();
        mosaicSelectionBrush.reset();
        mosaicTextBrush.reset();
        mosaicWhiteBrush.reset();
        mosaicVariableBrush.reset();
    }

    void discardTextResources() noexcept
    {
        textPanelBrush.reset();
        textBorderBrush.reset();
        textSelectionBrush.reset();
        textForegroundBrush.reset();
        textWhiteBrush.reset();
        textVariableBrush.reset();
        for (auto& bitmap : textIconBitmaps) bitmap.reset();
    }

    HMODULE resourceModule = nullptr;
    HWND window = nullptr;
    bool comAttempted = false;
    bool uninitializeCom = false;
    ComPtr<ID2D1Factory> d2dFactory;
    ComPtr<IDWriteFactory> dwriteFactory;
    ComPtr<IWICImagingFactory> wicFactory;
    ComPtr<IDWriteTextFormat> textFormat;
    ComPtr<IDWriteTextFormat> samplerTextFormat;
    ComPtr<IDWriteTextFormat> samplerValueTextFormat;
    ComPtr<IDWriteTextFormat> measurementTextFormat;
    ComPtr<ID2D1HwndRenderTarget> renderTarget;
    ComPtr<ID2D1Bitmap> backgroundBitmap;
    ComPtr<ID2D1Bitmap> paletteBitmap;
    ComPtr<ID2D1Bitmap> annotationCompositeBitmap;
    std::shared_ptr<const PixelBuffer> annotationCompositeSource;
    ComPtr<ID2D1SolidColorBrush> eyedropperPanelWhiteBrush;
    ComPtr<ID2D1SolidColorBrush> eyedropperWhiteBrush;
    ComPtr<ID2D1SolidColorBrush> eyedropperBlueBrush;
    ComPtr<ID2D1SolidColorBrush> eyedropperDarkBrush;
    ComPtr<ID2D1SolidColorBrush> eyedropperInfoBrush;
    ComPtr<ID2D1SolidColorBrush> eyedropperBorderBrush;
    ComPtr<ID2D1SolidColorBrush> eyedropperGridBrush;
    ComPtr<ID2D1SolidColorBrush> eyedropperSuccessBrush;
    ComPtr<ID2D1SolidColorBrush> eyedropperCellBrush;
    ComPtr<ID2D1SolidColorBrush> mosaicPanelBrush;
    ComPtr<ID2D1SolidColorBrush> mosaicBorderBrush;
    ComPtr<ID2D1SolidColorBrush> mosaicSelectionBrush;
    ComPtr<ID2D1SolidColorBrush> mosaicTextBrush;
    ComPtr<ID2D1SolidColorBrush> mosaicWhiteBrush;
    ComPtr<ID2D1SolidColorBrush> mosaicVariableBrush;
    ComPtr<ID2D1SolidColorBrush> textPanelBrush;
    ComPtr<ID2D1SolidColorBrush> textBorderBrush;
    ComPtr<ID2D1SolidColorBrush> textSelectionBrush;
    ComPtr<ID2D1SolidColorBrush> textForegroundBrush;
    ComPtr<ID2D1SolidColorBrush> textWhiteBrush;
    ComPtr<ID2D1SolidColorBrush> textVariableBrush;
    std::array<ComPtr<ID2D1Bitmap>, 6> textIconBitmaps;
    ComPtr<ID2D1StrokeStyle> eyedropperWhiteStrokeStyle;
    ComPtr<ID2D1StrokeStyle> eyedropperBlueStrokeStyle;
    std::array<ComPtr<ID2D1Bitmap>, toolbarImageResources().size()> iconBitmaps;
};

OverlayRenderer::OverlayRenderer(HMODULE resourceModule)
    : impl_(std::make_unique<Impl>(resourceModule))
{
}

OverlayRenderer::~OverlayRenderer() = default;
std::optional<OverlayRendererError> OverlayRenderer::initialize(
    HWND window,
    const FrozenDisplay& display) noexcept
{
    impl_->window = window;
    return impl_->ensureDeviceResources(display);
}

std::optional<OverlayRendererError> OverlayRenderer::resize(
    std::uint32_t width,
    std::uint32_t height) noexcept
{
    if (!impl_->renderTarget) {
        return std::nullopt;
    }
    const auto result = impl_->renderTarget->Resize(D2D1::SizeU(width, height));
    if (result == D2DERR_RECREATE_TARGET) {
        impl_->discardDeviceResources();
        return error(OverlayRendererErrorCode::deviceLost, result);
    }
    if (FAILED(result)) {
        return error(OverlayRendererErrorCode::renderTargetFailed, result);
    }
    return std::nullopt;
}

std::optional<OverlayRendererError> OverlayRenderer::render(
    const FrozenDisplay& display,
    const std::optional<PixelRect>& selection,
    bool showActions) noexcept
{
    OverlayRenderState state;
    state.selection = selection;
    state.showActions = showActions;
    return render(display, state);
}

std::optional<OverlayRendererError> OverlayRenderer::render(
    const FrozenDisplay& display,
    const OverlayRenderState& state) noexcept
{
    try {
        return impl_->draw(display, state);
    } catch (const std::bad_alloc&) {
        return error(OverlayRendererErrorCode::drawFailed, E_OUTOFMEMORY);
    } catch (...) {
        return error(OverlayRendererErrorCode::drawFailed, E_FAIL);
    }
}

void OverlayRenderer::discardDeviceResources() noexcept
{
    impl_->discardDeviceResources();
}

} // namespace xxsnap::win
