#include "capture/GdiCaptureBackend.h"

#include <cstddef>
#include <cstring>
#include <limits>
#include <new>
#include <utility>

namespace xxsnap::win {
namespace {

CaptureResult error(CaptureErrorCode code, HRESULT nativeCode) noexcept
{
    return CaptureError{code, nativeCode};
}

HRESULT lastGdiError(const GdiCaptureApis& apis) noexcept
{
    try {
        const auto nativeError = apis.getLastError();
        return nativeError == ERROR_SUCCESS
            ? E_FAIL
            : HRESULT_FROM_WIN32(nativeError);
    } catch (...) {
        return E_FAIL;
    }
}

CaptureResult allocationError(
    snipory::core::portable::PixelBufferError allocationError) noexcept
{
    using snipory::core::portable::PixelBufferError;
    switch (allocationError) {
    case PixelBufferError::invalidSize:
        return error(CaptureErrorCode::invalidSize, E_INVALIDARG);
    case PixelBufferError::arithmeticOverflow:
        return error(
            CaptureErrorCode::arithmeticOverflow,
            HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    case PixelBufferError::budgetExceeded:
    case PixelBufferError::allocationFailed:
        return error(CaptureErrorCode::memoryLimit, E_OUTOFMEMORY);
    }
    return error(CaptureErrorCode::systemFailure, E_FAIL);
}

bool fitsGdiCoordinates(const DisplayDescriptor& display) noexcept
{
    const auto minimum = static_cast<std::int64_t>(std::numeric_limits<int>::min());
    const auto maximum = static_cast<std::int64_t>(std::numeric_limits<int>::max());
    return display.pixelBounds.x >= minimum
        && display.pixelBounds.x <= maximum
        && display.pixelBounds.y >= minimum
        && display.pixelBounds.y <= maximum
        && display.pixelBounds.width <= maximum
        && display.pixelBounds.height <= maximum;
}

void normalizeBgrxToBgra(
    const std::byte* source,
    PixelBuffer& destination) noexcept
{
    const auto rowBytes = static_cast<std::size_t>(destination.stride());
    const auto height = static_cast<std::size_t>(destination.height());
    for (std::size_t row = 0; row < height; ++row) {
        auto* destinationRow = destination.data() + row * rowBytes;
        std::memcpy(destinationRow, source + row * rowBytes, rowBytes);
        for (std::size_t alpha = 3U; alpha < rowBytes; alpha += 4U) {
            destinationRow[alpha] = std::byte{255U};
        }
    }
}

} // namespace

GdiCaptureApis systemGdiCaptureApis()
{
    GdiCaptureApis apis;
    apis.getDc = [](HWND window) { return GetDC(window); };
    apis.releaseDc = [](HWND window, HDC dc) { return ReleaseDC(window, dc); };
    apis.createCompatibleDc = [](HDC dc) { return CreateCompatibleDC(dc); };
    apis.deleteDc = [](HDC dc) { return DeleteDC(dc); };
    apis.createDibSection = [](HDC dc, const BITMAPINFO* info, UINT usage,
                               void** bits, HANDLE section, DWORD offset) {
        return CreateDIBSection(dc, info, usage, bits, section, offset);
    };
    apis.deleteObject = [](HGDIOBJ object) { return DeleteObject(object); };
    apis.selectObject = [](HDC dc, HGDIOBJ object) {
        return SelectObject(dc, object);
    };
    apis.bitBlt = [](HDC destination, int x, int y, int width, int height,
                     HDC source, int sourceX, int sourceY, DWORD operation) {
        return BitBlt(
            destination, x, y, width, height,
            source, sourceX, sourceY, operation);
    };
    apis.gdiFlush = [] { return GdiFlush(); };
    apis.setLastError = [](DWORD errorCode) { SetLastError(errorCode); };
    apis.getLastError = [] { return GetLastError(); };
    return apis;
}

GdiCaptureBackend::GdiCaptureBackend()
    : GdiCaptureBackend(systemGdiCaptureApis())
{
}

GdiCaptureBackend::GdiCaptureBackend(GdiCaptureApis apis)
    : apis_(std::move(apis))
{
}

CaptureResult GdiCaptureBackend::capture(
    const DisplayTopologySnapshot& snapshot,
    MemoryBudget& budget) noexcept
{
    try {
        std::vector<FrozenDisplay> frozenDisplays;
        frozenDisplays.reserve(snapshot.displays().size());

        for (const auto& display : snapshot.displays()) {
            if (display.pixelBounds.width <= 0 || display.pixelBounds.height <= 0) {
                return error(CaptureErrorCode::invalidSize, E_INVALIDARG);
            }
            if (!fitsGdiCoordinates(display)) {
                return error(
                    CaptureErrorCode::arithmeticOverflow,
                    HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
            }

            auto allocation = PixelBuffer::allocate(
                display.pixelBounds.width,
                display.pixelBounds.height,
                budget);
            if (!allocation.value) {
                return allocationError(*allocation.error);
            }

            {
                apis_.setLastError(ERROR_SUCCESS);
                const auto desktopHandle = apis_.getDc(nullptr);
                if (desktopHandle == nullptr) {
                    return error(CaptureErrorCode::systemFailure, lastGdiError(apis_));
                }
                WindowDc desktopDc(nullptr, desktopHandle, &apis_.releaseDc);

                BitmapHandle bitmap;
                apis_.setLastError(ERROR_SUCCESS);
                const auto memoryHandle = apis_.createCompatibleDc(desktopDc.get());
                if (memoryHandle == nullptr) {
                    return error(CaptureErrorCode::systemFailure, lastGdiError(apis_));
                }
                MemoryDc memoryDc(memoryHandle, &apis_.deleteDc);

                BITMAPINFO bitmapInfo{};
                bitmapInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
                bitmapInfo.bmiHeader.biWidth = static_cast<LONG>(display.pixelBounds.width);
                bitmapInfo.bmiHeader.biHeight = -static_cast<LONG>(display.pixelBounds.height);
                bitmapInfo.bmiHeader.biPlanes = 1U;
                bitmapInfo.bmiHeader.biBitCount = 32U;
                bitmapInfo.bmiHeader.biCompression = BI_RGB;

                void* dibBits = nullptr;
                apis_.setLastError(ERROR_SUCCESS);
                const auto bitmapValue = apis_.createDibSection(
                    desktopDc.get(),
                    &bitmapInfo,
                    DIB_RGB_COLORS,
                    &dibBits,
                    nullptr,
                    0U);
                if (bitmapValue == nullptr) {
                    return error(CaptureErrorCode::systemFailure, lastGdiError(apis_));
                }
                bitmap = BitmapHandle(bitmapValue, &apis_.deleteObject);
                if (dibBits == nullptr) {
                    return error(CaptureErrorCode::systemFailure, lastGdiError(apis_));
                }

                apis_.setLastError(ERROR_SUCCESS);
                const auto previous = apis_.selectObject(memoryDc.get(), bitmap.get());
                if (previous == nullptr || previous == HGDI_ERROR) {
                    return error(CaptureErrorCode::systemFailure, lastGdiError(apis_));
                }
                SelectedObject selection(memoryDc.get(), previous, &apis_.selectObject);

                apis_.setLastError(ERROR_SUCCESS);
                const auto copied = apis_.bitBlt(
                    memoryDc.get(),
                    0,
                    0,
                    static_cast<int>(display.pixelBounds.width),
                    static_cast<int>(display.pixelBounds.height),
                    desktopDc.get(),
                    static_cast<int>(display.pixelBounds.x),
                    static_cast<int>(display.pixelBounds.y),
                    SRCCOPY | CAPTUREBLT);
                if (copied == FALSE) {
                    return error(CaptureErrorCode::systemFailure, lastGdiError(apis_));
                }

                apis_.setLastError(ERROR_SUCCESS);
                if (apis_.gdiFlush() == FALSE) {
                    return error(CaptureErrorCode::systemFailure, lastGdiError(apis_));
                }

                normalizeBgrxToBgra(
                    static_cast<const std::byte*>(dibBits),
                    *allocation.value);

                apis_.setLastError(ERROR_SUCCESS);
                if (!selection.restore()) {
                    return error(CaptureErrorCode::systemFailure, lastGdiError(apis_));
                }
            }

            frozenDisplays.push_back(FrozenDisplay{
                display,
                std::move(*allocation.value),
            });
        }

        return FrozenDesktop{
            snapshot,
            std::move(frozenDisplays),
            std::chrono::steady_clock::now(),
        };
    } catch (const std::bad_alloc&) {
        return error(CaptureErrorCode::systemFailure, E_OUTOFMEMORY);
    } catch (...) {
        return error(CaptureErrorCode::systemFailure, E_FAIL);
    }
}

} // namespace xxsnap::win
