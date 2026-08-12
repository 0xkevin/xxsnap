#include "export/AnnotationComposer.h"
#include "annotation/MarkerMetrics.h"

#include <d2d1.h>
#include <objbase.h>
#include <wincodec.h>

#include <cstdint>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <utility>

namespace xxsnap::win {
namespace {

float markerColorLuminance(AnnotationColor color) noexcept
{
    return (0.2126F * static_cast<float>(color.red)
        + 0.7152F * static_cast<float>(color.green)
        + 0.0722F * static_cast<float>(color.blue)) / 255.0F;
}

float markerDistanceSquaredFromSegment(
    float x, float y,
    float startX, float startY,
    float endX, float endY) noexcept
{
    const auto dx = endX - startX;
    const auto dy = endY - startY;
    const auto lengthSquared = dx * dx + dy * dy;
    if (lengthSquared < 0.25F) {
        const auto pointDx = x - startX;
        const auto pointDy = y - startY;
        return pointDx * pointDx + pointDy * pointDy;
    }
    const auto progress = (std::max)(0.0F, (std::min)(1.0F,
        ((x - startX) * dx + (y - startY) * dy) / lengthSquared));
    const auto pointDx = x - (startX + progress * dx);
    const auto pointDy = y - (startY + progress * dy);
    return pointDx * pointDx + pointDy * pointDy;
}

void composeMarker(
    PixelBuffer& pixels,
    const ShapeAnnotation& annotation,
    UINT dpiX,
    UINT dpiY) noexcept
{
    if (!isMarkerAnnotation(annotation)) {
        return;
    }
    const auto scaleX = static_cast<float>(dpiX == 0U ? 96U : dpiX) / 96.0F;
    const auto scaleY = static_cast<float>(dpiY == 0U ? 96U : dpiY) / 96.0F;
    const auto line = *annotation.markerLine;
    const auto startX = line.start.x * scaleX;
    const auto startY = line.start.y * scaleY;
    const auto endX = line.end.x * scaleX;
    const auto endY = line.end.y * scaleY;
    const auto radius = annotation.style.strokeWidthDip
        * (scaleX + scaleY) / 4.0F;

    constexpr int sampleCount = 17;
    auto darkSamples = 0;
    auto validSamples = 0;
    for (int index = 0; index < sampleCount; ++index) {
        const auto progress = static_cast<float>(index)
            / static_cast<float>(sampleCount - 1);
        const auto x = static_cast<std::int64_t>(
            std::round(startX + (endX - startX) * progress));
        const auto y = static_cast<std::int64_t>(
            std::round(startY + (endY - startY) * progress));
        if (x < 0 || y < 0 || x >= pixels.width() || y >= pixels.height()) {
            continue;
        }
        const auto* pixel = pixels.data()
            + static_cast<std::uint64_t>(y) * pixels.stride()
            + static_cast<std::uint64_t>(x) * 4U;
        ++validSamples;
        const auto luminance = (0.2126F * std::to_integer<unsigned>(pixel[2])
            + 0.7152F * std::to_integer<unsigned>(pixel[1])
            + 0.0722F * std::to_integer<unsigned>(pixel[0])) / 255.0F;
        darkSamples += luminance < 0.12F ? 1 : 0;
    }
    const auto normalBlend = validSamples > 0
        && darkSamples >= (std::max)(1, validSamples * 3 / 4);
    auto color = annotation.style.strokeColor;
    if (normalBlend && markerColorLuminance(color) < 0.18F) {
        color = {255, 255, 255, 255};
    }
    const auto left = (std::max<std::int64_t>)(0,
        static_cast<std::int64_t>(std::floor((std::min)(startX, endX) - radius)));
    const auto top = (std::max<std::int64_t>)(0,
        static_cast<std::int64_t>(std::floor((std::min)(startY, endY) - radius)));
    const auto right = (std::min<std::int64_t>)(pixels.width() - 1,
        static_cast<std::int64_t>(std::ceil((std::max)(startX, endX) + radius)));
    const auto bottom = (std::min<std::int64_t>)(pixels.height() - 1,
        static_cast<std::int64_t>(std::ceil((std::max)(startY, endY) + radius)));
    const std::array<std::uint32_t, 3> source{
        color.blue, color.green, color.red};
    const auto radiusSquared = radius * radius;
    for (auto y = top; y <= bottom; ++y) {
        for (auto x = left; x <= right; ++x) {
            if (markerDistanceSquaredFromSegment(
                    static_cast<float>(x) + 0.5F,
                    static_cast<float>(y) + 0.5F,
                    startX, startY, endX, endY) > radiusSquared) {
                continue;
            }
            auto* pixel = pixels.data()
                + static_cast<std::uint64_t>(y) * pixels.stride()
                + static_cast<std::uint64_t>(x) * 4U;
            for (std::size_t channel = 0; channel < 3U; ++channel) {
                const auto destination = std::to_integer<unsigned>(pixel[channel]);
                const auto blended = normalBlend
                    ? source[channel]
                    : source[channel] * destination / 255U;
                pixel[channel] = static_cast<std::byte>(
                    (blended * markerMetrics::opacityByte
                        + destination * (255U - markerMetrics::opacityByte)
                        + 127U)
                        / 255U);
            }
            pixel[3] = std::byte{0xFF};
        }
    }
}

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

CaptureError compositionError(HRESULT result) noexcept
{
    return {CaptureErrorCode::systemFailure, result};
}

std::optional<CaptureError> copyBufferToBitmap(
    PixelBuffer& pixels,
    IWICBitmap* bitmap) noexcept
{
    ComPtr<IWICBitmapLock> lock;
    auto result = bitmap->Lock(nullptr, WICBitmapLockWrite, lock.put());
    if (FAILED(result)) {
        return compositionError(result);
    }
    UINT stride = 0;
    UINT size = 0;
    BYTE* destination = nullptr;
    result = lock->GetStride(&stride);
    if (SUCCEEDED(result)) {
        result = lock->GetDataPointer(&size, &destination);
    }
    const auto rowBytes = static_cast<std::uint64_t>(pixels.width()) * 4U;
    const auto required = pixels.height() <= 0
        ? 0U
        : static_cast<std::uint64_t>(stride)
            * static_cast<std::uint64_t>(pixels.height() - 1)
            + rowBytes;
    if (FAILED(result) || destination == nullptr
        || stride < rowBytes || required > size) {
        return compositionError(FAILED(result) ? result : E_INVALIDARG);
    }
    for (std::int64_t row = 0; row < pixels.height(); ++row) {
        std::memcpy(
            destination + static_cast<std::uint64_t>(row) * stride,
            pixels.data() + static_cast<std::uint64_t>(row) * pixels.stride(),
            static_cast<std::size_t>(rowBytes));
    }
    return std::nullopt;
}

std::optional<CaptureError> copyBitmapToBuffer(
    IWICBitmap* bitmap,
    PixelBuffer& pixels) noexcept
{
    ComPtr<IWICBitmapLock> lock;
    auto result = bitmap->Lock(nullptr, WICBitmapLockRead, lock.put());
    if (FAILED(result)) {
        return compositionError(result);
    }
    UINT stride = 0;
    UINT size = 0;
    BYTE* source = nullptr;
    result = lock->GetStride(&stride);
    if (SUCCEEDED(result)) {
        result = lock->GetDataPointer(&size, &source);
    }
    const auto rowBytes = static_cast<std::uint64_t>(pixels.width()) * 4U;
    const auto required = pixels.height() <= 0
        ? 0U
        : static_cast<std::uint64_t>(stride)
            * static_cast<std::uint64_t>(pixels.height() - 1)
            + rowBytes;
    if (FAILED(result) || source == nullptr
        || stride < rowBytes || required > size) {
        return compositionError(FAILED(result) ? result : E_INVALIDARG);
    }
    for (std::int64_t row = 0; row < pixels.height(); ++row) {
        std::memcpy(
            pixels.data() + static_cast<std::uint64_t>(row) * pixels.stride(),
            source + static_cast<std::uint64_t>(row) * stride,
            static_cast<std::size_t>(rowBytes));
    }
    return std::nullopt;
}

HRESULT createAnnotationRenderTarget(
    ID2D1Factory* factory,
    IWICBitmap* bitmap,
    UINT dpiX,
    UINT dpiY,
    ComPtr<ID2D1RenderTarget>& renderTarget) noexcept
{
    const auto properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_SOFTWARE,
        D2D1::PixelFormat(
            DXGI_FORMAT_B8G8R8A8_UNORM,
            D2D1_ALPHA_MODE_PREMULTIPLIED),
        dpiX == 0U ? 96.0F : static_cast<float>(dpiX),
        dpiY == 0U ? 96.0F : static_cast<float>(dpiY));
    return factory->CreateWicBitmapRenderTarget(
        bitmap, properties, renderTarget.put());
}

} // namespace

std::optional<CaptureError> composeAnnotations(
    PixelBuffer& pixels,
    const AnnotationRenderPlan& plan,
    UINT dpiX,
    UINT dpiY) noexcept
{
    if (plan.items.empty()) {
        return std::nullopt;
    }
    if (pixels.width() <= 0 || pixels.height() <= 0
        || pixels.width() > (std::numeric_limits<UINT>::max)()
        || pixels.height() > (std::numeric_limits<UINT>::max)()
        || pixels.format()
            != snipory::core::portable::PixelFormat::bgra8Premultiplied) {
        return compositionError(E_INVALIDARG);
    }

    const auto comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool uninitialize = SUCCEEDED(comResult);
    if (FAILED(comResult) && comResult != RPC_E_CHANGED_MODE) {
        return compositionError(comResult);
    }

    ComPtr<IWICImagingFactory> wicFactory;
    auto result = CoCreateInstance(
        CLSID_WICImagingFactory,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(wicFactory.put()));
    ComPtr<ID2D1Factory> d2dFactory;
    if (SUCCEEDED(result)) {
        result = D2D1CreateFactory(
            D2D1_FACTORY_TYPE_SINGLE_THREADED,
            d2dFactory.put());
    }
    ComPtr<IWICBitmap> bitmap;
    if (SUCCEEDED(result)) {
        result = wicFactory->CreateBitmap(
            static_cast<UINT>(pixels.width()),
            static_cast<UINT>(pixels.height()),
            GUID_WICPixelFormat32bppPBGRA,
            WICBitmapCacheOnLoad,
            bitmap.put());
    }
    std::optional<CaptureError> failure;
    if (SUCCEEDED(result)) {
        failure = copyBufferToBitmap(pixels, bitmap.get());
    }

    ComPtr<ID2D1RenderTarget> renderTarget;
    if (!failure.has_value() && SUCCEEDED(result)) {
        result = createAnnotationRenderTarget(
            d2dFactory.get(), bitmap.get(), dpiX, dpiY, renderTarget);
    }
    auto pixelsContainLatestResult = false;
    if (!failure.has_value() && SUCCEEDED(result)) {
        AnnotationRenderer renderer(d2dFactory.get());
        std::size_t index = 0U;
        while (index < plan.items.size()) {
            if (isMarkerAnnotation(plan.items[index].annotation)) {
                renderTarget.reset();
                failure = copyBitmapToBuffer(bitmap.get(), pixels);
                if (failure.has_value()) {
                    break;
                }
                do {
                    composeMarker(
                        pixels, plan.items[index].annotation, dpiX, dpiY);
                    ++index;
                } while (index < plan.items.size()
                    && isMarkerAnnotation(plan.items[index].annotation));
                pixelsContainLatestResult = true;
                if (index < plan.items.size()) {
                    failure = copyBufferToBitmap(pixels, bitmap.get());
                    if (failure.has_value()) {
                        break;
                    }
                    pixelsContainLatestResult = false;
                    result = createAnnotationRenderTarget(
                        d2dFactory.get(), bitmap.get(),
                        dpiX, dpiY, renderTarget);
                    if (FAILED(result)) {
                        break;
                    }
                }
                continue;
            }
            AnnotationRenderPlan runPlan;
            do {
                runPlan.items.push_back(plan.items[index]);
                ++index;
            } while (index < plan.items.size()
                && !isMarkerAnnotation(plan.items[index].annotation));
            renderTarget->BeginDraw();
            result = renderer.draw(renderTarget.get(), runPlan);
            if (SUCCEEDED(result)) {
                result = renderTarget->EndDraw();
            }
            if (FAILED(result)) {
                break;
            }
        }
    }
    renderTarget.reset();
    if (!pixelsContainLatestResult
        && !failure.has_value() && SUCCEEDED(result)) {
        failure = copyBitmapToBuffer(bitmap.get(), pixels);
    }
    if (!failure.has_value() && FAILED(result)) {
        failure = compositionError(result);
    }
    bitmap.reset();
    d2dFactory.reset();
    wicFactory.reset();
    if (uninitialize) {
        CoUninitialize();
    }
    return failure;
}

} // namespace xxsnap::win
