#include "export/AnnotationComposer.h"

#include <d2d1.h>
#include <objbase.h>
#include <wincodec.h>

#include <cstdint>
#include <cstring>
#include <limits>
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
        const auto properties = D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_SOFTWARE,
            D2D1::PixelFormat(
                DXGI_FORMAT_B8G8R8A8_UNORM,
                D2D1_ALPHA_MODE_PREMULTIPLIED),
            dpiX == 0U ? 96.0F : static_cast<float>(dpiX),
            dpiY == 0U ? 96.0F : static_cast<float>(dpiY));
        result = d2dFactory->CreateWicBitmapRenderTarget(
            bitmap.get(), properties, renderTarget.put());
    }
    if (!failure.has_value() && SUCCEEDED(result)) {
        renderTarget->BeginDraw();
        AnnotationRenderer renderer(d2dFactory.get());
        result = renderer.draw(renderTarget.get(), plan);
        if (SUCCEEDED(result)) {
            result = renderTarget->EndDraw();
        }
    }
    renderTarget.reset();
    if (!failure.has_value() && SUCCEEDED(result)) {
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
