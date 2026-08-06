#include "overlay/OverlayRenderer.h"

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

D2D1_COLOR_F color(Rgba8 value) noexcept
{
    return D2D1::ColorF(
        static_cast<float>(value.red) / 255.0F,
        static_cast<float>(value.green) / 255.0F,
        static_cast<float>(value.blue) / 255.0F,
        static_cast<float>(value.alpha) / 255.0F);
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
        if (d2dFactory && dwriteFactory && wicFactory && textFormat) {
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

    std::optional<OverlayRendererError> draw(
        const FrozenDisplay& display,
        const std::optional<PixelRect>& selection,
        bool showActions)
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
        };
        for (const auto& brushResult : brushResults) {
            if (brushResult.has_value()) {
                return brushResult;
            }
        }

        std::optional<OverlayLayout> chromeLayout;
        if (selection.has_value()) {
            const auto label = sizeLabelText(*selection);
            float labelWidth = 0.0F;
            if (const auto measureError = measureLabel(label, labelWidth)) {
                return measureError;
            }
            chromeLayout = computeOverlayLayout({
                display.descriptor.pixelBounds,
                *selection,
                display.descriptor.dpiX,
                display.descriptor.dpiY,
                labelWidth,
                showActions,
            });
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

        if (!selection.has_value()) {
            renderTarget->FillRectangle(d2dRect(overlayBounds), dimBrush.get());
        } else {
            const auto& layout = *chromeLayout;
            for (const auto mask : layout.mask) {
                if (mask.width > 0.0F && mask.height > 0.0F) {
                    renderTarget->FillRectangle(d2dRect(mask), dimBrush.get());
                }
            }

            renderTarget->DrawRectangle(
                d2dRect(layout.border),
                selectionBrush.get(),
                VisualStyleCatalog::selectionBorderDip);

            if (layout.showActions) {
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
                    textFormat.get(),
                    d2dRect(labelTextRect),
                    labelTextBrush.get(),
                    D2D1_DRAW_TEXT_OPTIONS_CLIP);

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

                const auto drawToolbarIcon = [this](
                        const ToolbarIconSpec& icon,
                        std::size_t iconIndex,
                        DipRect rect) {
                    renderTarget->DrawBitmap(
                        iconBitmaps[iconIndex].get(),
                        d2dRect(insetRect(rect, icon.insetDip)),
                        1.0F,
                        D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
                };
                drawToolbarIcon(
                    dragHandleIcon(),
                    0U,
                    layout.toolbar.leadingDragHandle);
                for (std::size_t index = 0; index < layout.toolbarItems.size(); ++index) {
                    const auto& item = layout.toolbarItems[index];
                    const auto iconIndex = item.enabled
                        ? toolbarIconIndex(item.action)
                        : disabledToolbarIconIndex(item.action);
                    const auto& icon = toolbarImageResources()[iconIndex];
                    drawToolbarIcon(icon, iconIndex, item.rect);

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
                    layout.toolbar.trailingDragHandle);
            }

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
        for (auto& bitmap : iconBitmaps) {
            bitmap.reset();
        }
        backgroundBitmap.reset();
        renderTarget.reset();
    }

    HMODULE resourceModule = nullptr;
    HWND window = nullptr;
    bool comAttempted = false;
    bool uninitializeCom = false;
    ComPtr<ID2D1Factory> d2dFactory;
    ComPtr<IDWriteFactory> dwriteFactory;
    ComPtr<IWICImagingFactory> wicFactory;
    ComPtr<IDWriteTextFormat> textFormat;
    ComPtr<ID2D1HwndRenderTarget> renderTarget;
    ComPtr<ID2D1Bitmap> backgroundBitmap;
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
    try {
        return impl_->draw(display, selection, showActions);
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
