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
#include <new>
#include <utility>

namespace xxsnap::win {
namespace {

float markerColorLuminance(AnnotationColor color) noexcept
{
    return (0.2126F * static_cast<float>(color.red)
        + 0.7152F * static_cast<float>(color.green)
        + 0.0722F * static_cast<float>(color.blue)) / 255.0F;
}

float distanceSquaredFromSegment(
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

bool mosaicMaskContains(
    const ShapeAnnotation& annotation,
    float dipX,
    float dipY) noexcept
{
    if (isMosaicStrokeAnnotation(annotation)) {
        const auto& points = annotation.mosaicStroke->points;
        const auto radius = (std::max)(0.5F,
            annotation.style.strokeWidthDip / 2.0F);
        const auto radiusSquared = radius * radius;
        if (points.size() == 1U) {
            const auto dx = dipX - points.front().x;
            const auto dy = dipY - points.front().y;
            return dx * dx + dy * dy <= radiusSquared;
        }
        for (std::size_t index = 1U; index < points.size(); ++index) {
            if (distanceSquaredFromSegment(
                    dipX, dipY,
                    points[index - 1U].x, points[index - 1U].y,
                    points[index].x, points[index].y) <= radiusSquared) {
                return true;
            }
        }
        return false;
    }
    if (!isMosaicRectangleAnnotation(annotation)) {
        return false;
    }
    const auto rect = standardized(annotation.rect);
    const auto centerX = rect.x + rect.width / 2.0F;
    const auto centerY = rect.y + rect.height / 2.0F;
    const auto radians = -annotation.rotationDegrees
        * 3.14159265358979323846F / 180.0F;
    const auto sine = std::sin(radians);
    const auto cosine = std::cos(radians);
    const auto dx = dipX - centerX;
    const auto dy = dipY - centerY;
    const auto x = centerX + dx * cosine - dy * sine;
    const auto y = centerY + dx * sine + dy * cosine;
    return x >= rect.x && y >= rect.y
        && x <= rect.x + rect.width && y <= rect.y + rect.height;
}

void pixelateSnapshot(
    const std::vector<std::byte>& source,
    std::vector<std::byte>& redacted,
    std::int64_t width,
    std::int64_t height,
    std::uint64_t stride,
    int block,
    std::int64_t originX,
    std::int64_t originY) noexcept
{
    block = (std::max)(1, block);
    const auto floorToBlock = [block](std::int64_t value) {
        auto quotient = value / block;
        if (value < 0 && value % block != 0) {
            --quotient;
        }
        return quotient * block;
    };
    const auto firstTop = floorToBlock(originY) - originY;
    const auto firstLeft = floorToBlock(originX) - originX;
    for (std::int64_t blockTop = firstTop;
         blockTop < height; blockTop += block) {
        const auto top = (std::max<std::int64_t>)(0, blockTop);
        const auto bottom = (std::min)(height, blockTop + block);
        if (top >= bottom) {
            continue;
        }
        for (std::int64_t blockLeft = firstLeft;
             blockLeft < width; blockLeft += block) {
            const auto left = (std::max<std::int64_t>)(0, blockLeft);
            const auto right = (std::min)(width, blockLeft + block);
            if (left >= right) {
                continue;
            }
            std::uint64_t blue = 0, green = 0, red = 0, alpha = 0;
            std::uint64_t count = 0;
            for (auto y = top; y < bottom; ++y) {
                for (auto x = left; x < right; ++x) {
                    const auto offset = static_cast<std::size_t>(
                        static_cast<std::uint64_t>(y) * stride
                        + static_cast<std::uint64_t>(x) * 4U);
                    blue += std::to_integer<unsigned>(source[offset]);
                    green += std::to_integer<unsigned>(source[offset + 1U]);
                    red += std::to_integer<unsigned>(source[offset + 2U]);
                    alpha += std::to_integer<unsigned>(source[offset + 3U]);
                    ++count;
                }
            }
            const std::array<std::byte, 4> average{
                static_cast<std::byte>(blue / count),
                static_cast<std::byte>(green / count),
                static_cast<std::byte>(red / count),
                static_cast<std::byte>(alpha / count),
            };
            for (auto y = top; y < bottom; ++y) {
                for (auto x = left; x < right; ++x) {
                    const auto offset = static_cast<std::size_t>(
                        static_cast<std::uint64_t>(y) * stride
                        + static_cast<std::uint64_t>(x) * 4U);
                    std::copy(average.begin(), average.end(),
                        redacted.begin() + static_cast<std::ptrdiff_t>(offset));
                }
            }
        }
    }
}

void boxBlurSnapshot(
    const std::vector<std::byte>& source,
    std::vector<std::byte>& redacted,
    std::int64_t width,
    std::int64_t height,
    std::uint64_t stride,
    int radius)
{
    radius = (std::max)(1, radius);
    auto horizontal = source;
    for (std::int64_t y = 0; y < height; ++y) {
        std::array<std::uint64_t, 4> sums{};
        const auto addColumn = [&](std::int64_t x, bool add) {
            x = (std::max<std::int64_t>)(0,
                (std::min<std::int64_t>)(width - 1, x));
            const auto offset = static_cast<std::size_t>(
                static_cast<std::uint64_t>(y) * stride
                + static_cast<std::uint64_t>(x) * 4U);
            for (std::size_t channel = 0; channel < 4U; ++channel) {
                const auto value = std::to_integer<unsigned>(
                    source[offset + channel]);
                add ? sums[channel] += value : sums[channel] -= value;
            }
        };
        for (int x = -radius; x <= radius; ++x) addColumn(x, true);
        const auto count = static_cast<std::uint64_t>(radius * 2 + 1);
        for (std::int64_t x = 0; x < width; ++x) {
            const auto offset = static_cast<std::size_t>(
                static_cast<std::uint64_t>(y) * stride
                + static_cast<std::uint64_t>(x) * 4U);
            for (std::size_t channel = 0; channel < 4U; ++channel) {
                horizontal[offset + channel]
                    = static_cast<std::byte>(sums[channel] / count);
            }
            addColumn(x - radius, false);
            addColumn(x + radius + 1, true);
        }
    }
    redacted = horizontal;
    for (std::int64_t x = 0; x < width; ++x) {
        std::array<std::uint64_t, 4> sums{};
        const auto addRow = [&](std::int64_t y, bool add) {
            y = (std::max<std::int64_t>)(0,
                (std::min<std::int64_t>)(height - 1, y));
            const auto offset = static_cast<std::size_t>(
                static_cast<std::uint64_t>(y) * stride
                + static_cast<std::uint64_t>(x) * 4U);
            for (std::size_t channel = 0; channel < 4U; ++channel) {
                const auto value = std::to_integer<unsigned>(
                    horizontal[offset + channel]);
                add ? sums[channel] += value : sums[channel] -= value;
            }
        };
        for (int y = -radius; y <= radius; ++y) addRow(y, true);
        const auto count = static_cast<std::uint64_t>(radius * 2 + 1);
        for (std::int64_t y = 0; y < height; ++y) {
            const auto offset = static_cast<std::size_t>(
                static_cast<std::uint64_t>(y) * stride
                + static_cast<std::uint64_t>(x) * 4U);
            for (std::size_t channel = 0; channel < 4U; ++channel) {
                redacted[offset + channel]
                    = static_cast<std::byte>(sums[channel] / count);
            }
            addRow(y - radius, false);
            addRow(y + radius + 1, true);
        }
    }
}

struct PixelRegion {
    std::int64_t left = 0;
    std::int64_t top = 0;
    std::int64_t right = 0;
    std::int64_t bottom = 0;

    std::int64_t width() const noexcept { return right - left; }
    std::int64_t height() const noexcept { return bottom - top; }
    bool empty() const noexcept { return left >= right || top >= bottom; }
};

std::int64_t floorToMultiple(std::int64_t value, int multiple) noexcept
{
    auto quotient = value / multiple;
    if (value < 0 && value % multiple != 0) {
        --quotient;
    }
    return quotient * multiple;
}

PixelRegion mosaicOutputRegion(
    const ShapeAnnotation& annotation,
    float scaleX,
    float scaleY,
    std::int64_t width,
    std::int64_t height) noexcept
{
    auto bounds = standardized(annotation.rect);
    if (isMosaicStrokeAnnotation(annotation)) {
        const auto radius = annotation.style.strokeWidthDip / 2.0F;
        bounds = {bounds.x - radius, bounds.y - radius,
            bounds.width + radius * 2.0F,
            bounds.height + radius * 2.0F};
    } else {
        const auto radians = annotation.rotationDegrees
            * 3.14159265358979323846F / 180.0F;
        const auto halfWidth = bounds.width / 2.0F;
        const auto halfHeight = bounds.height / 2.0F;
        const auto rotatedHalfWidth = std::abs(std::cos(radians)) * halfWidth
            + std::abs(std::sin(radians)) * halfHeight;
        const auto rotatedHalfHeight = std::abs(std::sin(radians)) * halfWidth
            + std::abs(std::cos(radians)) * halfHeight;
        const auto centerX = bounds.x + halfWidth;
        const auto centerY = bounds.y + halfHeight;
        bounds = {centerX - rotatedHalfWidth, centerY - rotatedHalfHeight,
            rotatedHalfWidth * 2.0F, rotatedHalfHeight * 2.0F};
    }
    return {
        (std::max<std::int64_t>)(0,
            static_cast<std::int64_t>(std::floor(bounds.x * scaleX))),
        (std::max<std::int64_t>)(0,
            static_cast<std::int64_t>(std::floor(bounds.y * scaleY))),
        (std::min<std::int64_t>)(width,
            static_cast<std::int64_t>(std::ceil(
                (bounds.x + bounds.width) * scaleX))),
        (std::min<std::int64_t>)(height,
            static_cast<std::int64_t>(std::ceil(
                (bounds.y + bounds.height) * scaleY))),
    };
}

PixelRegion mosaicProcessingRegion(
    PixelRegion output,
    MosaicRedaction redaction,
    std::int64_t width,
    std::int64_t height,
    std::int64_t contentOriginX,
    std::int64_t contentOriginY) noexcept
{
    if (redaction.type == MosaicRedactionType::gaussianBlur) {
        return {
            (std::max<std::int64_t>)(0, output.left - redaction.value),
            (std::max<std::int64_t>)(0, output.top - redaction.value),
            (std::min)(width, output.right + redaction.value),
            (std::min)(height, output.bottom + redaction.value),
        };
    }
    const auto block = (std::max)(1, redaction.value);
    const auto left = floorToMultiple(
        contentOriginX + output.left, block) - contentOriginX;
    const auto top = floorToMultiple(
        contentOriginY + output.top, block) - contentOriginY;
    const auto right = floorToMultiple(
        contentOriginX + output.right - 1, block) + block - contentOriginX;
    const auto bottom = floorToMultiple(
        contentOriginY + output.bottom - 1, block) + block - contentOriginY;
    return {
        (std::max<std::int64_t>)(0, left),
        (std::max<std::int64_t>)(0, top),
        (std::min)(width, right),
        (std::min)(height, bottom),
    };
}

std::vector<std::byte> copyRegion(
    const PixelBuffer& pixels,
    PixelRegion region)
{
    const auto stride = static_cast<std::uint64_t>(region.width()) * 4U;
    std::vector<std::byte> result(
        static_cast<std::size_t>(stride)
            * static_cast<std::size_t>(region.height()));
    for (std::int64_t row = 0; row < region.height(); ++row) {
        const auto* source = pixels.data()
            + static_cast<std::uint64_t>(region.top + row) * pixels.stride()
            + static_cast<std::uint64_t>(region.left) * 4U;
        std::memcpy(result.data() + static_cast<std::size_t>(row * stride),
            source, static_cast<std::size_t>(stride));
    }
    return result;
}

void composeMosaic(
    PixelBuffer& pixels,
    const ShapeAnnotation& annotation,
    UINT dpiX,
    UINT dpiY,
    std::int64_t contentOriginX,
    std::int64_t contentOriginY)
{
    if (!isMosaicAnnotation(annotation)) {
        return;
    }
    const auto scaleX = static_cast<float>(dpiX == 0U ? 96U : dpiX) / 96.0F;
    const auto scaleY = static_cast<float>(dpiY == 0U ? 96U : dpiY) / 96.0F;
    auto redaction = *annotation.mosaicRedaction;
    redaction.value = clampedMosaicRedactionValue(redaction.value);
    const auto output = mosaicOutputRegion(annotation, scaleX, scaleY,
        pixels.width(), pixels.height());
    if (output.empty()) {
        return;
    }
    const auto processing = mosaicProcessingRegion(output, redaction,
        pixels.width(), pixels.height(), contentOriginX, contentOriginY);
    auto source = copyRegion(pixels, processing);
    auto redacted = source;
    const auto localStride = static_cast<std::uint64_t>(processing.width()) * 4U;
    if (redaction.type == MosaicRedactionType::pixelMosaic) {
        pixelateSnapshot(source, redacted,
            processing.width(), processing.height(), localStride,
            redaction.value,
            contentOriginX + processing.left,
            contentOriginY + processing.top);
    } else {
        boxBlurSnapshot(source, redacted,
            processing.width(), processing.height(), localStride,
            redaction.value);
    }
    for (auto y = output.top; y < output.bottom; ++y) {
        for (auto x = output.left; x < output.right; ++x) {
            if (!mosaicMaskContains(annotation,
                    (static_cast<float>(x) + 0.5F) / scaleX,
                    (static_cast<float>(y) + 0.5F) / scaleY)) {
                continue;
            }
            const auto destinationOffset = static_cast<std::size_t>(
                static_cast<std::uint64_t>(y) * pixels.stride()
                + static_cast<std::uint64_t>(x) * 4U);
            const auto sourceOffset = static_cast<std::size_t>(
                static_cast<std::uint64_t>(y - processing.top) * localStride
                + static_cast<std::uint64_t>(x - processing.left) * 4U);
            std::memcpy(pixels.data() + destinationOffset,
                redacted.data() + sourceOffset, 4U);
        }
    }
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
            if (distanceSquaredFromSegment(
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
    UINT dpiY,
    std::int64_t contentOriginX,
    std::int64_t contentOriginY) noexcept
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
            if (isMarkerAnnotation(plan.items[index].annotation)
                || isMosaicAnnotation(plan.items[index].annotation)) {
                renderTarget.reset();
                failure = copyBitmapToBuffer(bitmap.get(), pixels);
                if (failure.has_value()) {
                    break;
                }
                do {
                    if (isMarkerAnnotation(plan.items[index].annotation)) {
                        composeMarker(
                            pixels, plan.items[index].annotation, dpiX, dpiY);
                    } else {
                        try {
                            composeMosaic(
                                pixels, plan.items[index].annotation,
                                dpiX, dpiY,
                                contentOriginX, contentOriginY);
                        } catch (const std::bad_alloc&) {
                            failure = compositionError(E_OUTOFMEMORY);
                            break;
                        }
                    }
                    ++index;
                } while (index < plan.items.size()
                    && (isMarkerAnnotation(plan.items[index].annotation)
                        || isMosaicAnnotation(plan.items[index].annotation)));
                if (failure.has_value()) {
                    break;
                }
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
                && !isMarkerAnnotation(plan.items[index].annotation)
                && !isMosaicAnnotation(plan.items[index].annotation));
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
