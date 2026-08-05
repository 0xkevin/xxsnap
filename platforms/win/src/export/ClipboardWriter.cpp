#include "export/ClipboardWriter.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <utility>

namespace xxsnap::win {
namespace {

ExportError failure(ExportErrorCode code, HRESULT nativeCode) noexcept
{
    return {code, nativeCode};
}

HRESULT win32Error(DWORD code) noexcept
{
    return HRESULT_FROM_WIN32(code == ERROR_SUCCESS ? ERROR_GEN_FAILURE : code);
}

void recordError(
    ClipboardWriteResult& result,
    ExportError error) noexcept
{
    if (!result.primaryError.has_value()) {
        result.primaryError = error;
    } else if (!result.secondaryError.has_value()) {
        result.secondaryError = error;
    }
}

class OwnedGlobalMemory final {
public:
    OwnedGlobalMemory(ClipboardApi& api, HGLOBAL handle) noexcept
        : api_(api)
        , handle_(handle)
    {
    }

    ~OwnedGlobalMemory()
    {
        if (handle_ != nullptr) {
            api_.freeGlobal(handle_);
        }
    }

    OwnedGlobalMemory(const OwnedGlobalMemory&) = delete;
    OwnedGlobalMemory& operator=(const OwnedGlobalMemory&) = delete;

    HGLOBAL get() const noexcept { return handle_; }
    HGLOBAL release() noexcept { return std::exchange(handle_, nullptr); }

private:
    ClipboardApi& api_;
    HGLOBAL handle_;
};

std::variant<HGLOBAL, ExportError> copyToGlobal(
    const std::vector<std::byte>& bytes,
    ClipboardApi& api) noexcept
{
    HGLOBAL handle = api.allocateGlobal(bytes.size());
    if (handle == nullptr) {
        return failure(
            ExportErrorCode::clipboardAllocationFailed,
            win32Error(api.lastError()));
    }
    OwnedGlobalMemory owned(api, handle);
    void* memory = api.lockGlobal(handle);
    if (memory == nullptr) {
        const DWORD native = api.lastError();
        return failure(
            ExportErrorCode::clipboardLockFailed,
            win32Error(native));
    }
    std::memcpy(memory, bytes.data(), bytes.size());
    api.clearLastError();
    if (!api.unlockGlobal(handle)) {
        const DWORD native = api.lastError();
        if (native != ERROR_SUCCESS) {
            return failure(
                ExportErrorCode::clipboardLockFailed,
                win32Error(native));
        }
    }
    return owned.release();
}

bool openWithBackoff(HWND owner, ClipboardApi& api) noexcept
{
    constexpr DWORD delays[] = {10U, 25U};
    for (std::size_t attempt = 0U; attempt < 3U; ++attempt) {
        if (api.openClipboard(owner)) {
            return true;
        }
        if (attempt < 2U) {
            api.sleep(delays[attempt]);
        }
    }
    return false;
}

} // namespace

bool ClipboardWriteResult::succeeded() const noexcept
{
    return dib == ClipboardFormatResult::written
        && png == ClipboardFormatResult::written
        && !primaryError.has_value()
        && !closeError.has_value();
}

bool ClipboardWriteResult::partial() const noexcept
{
    const bool anyWritten = dib == ClipboardFormatResult::written
        || png == ClipboardFormatResult::written;
    return anyWritten && !succeeded();
}

DibV5Result buildDibV5(const PixelBuffer& pixels) noexcept
{
    if (pixels.width() <= 0 || pixels.height() <= 0
        || pixels.format()
            != snipory::core::portable::PixelFormat::bgra8Premultiplied) {
        return failure(ExportErrorCode::invalidPixelBuffer, E_INVALIDARG);
    }

    const auto width = static_cast<std::uint64_t>(pixels.width());
    const auto height = static_cast<std::uint64_t>(pixels.height());
    if (width > static_cast<std::uint64_t>(std::numeric_limits<LONG>::max())
        || height > static_cast<std::uint64_t>(std::numeric_limits<LONG>::max())
        || width > std::numeric_limits<std::uint64_t>::max() / 4U) {
        return failure(
            ExportErrorCode::arithmeticOverflow,
            HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    }
    const auto rowBytes = width * 4U;
    if (pixels.stride() < rowBytes
        || height > std::numeric_limits<std::uint64_t>::max() / rowBytes) {
        return failure(
            ExportErrorCode::arithmeticOverflow,
            HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    }
    const auto imageBytes = rowBytes * height;
    if (imageBytes > std::numeric_limits<DWORD>::max()
        || imageBytes > std::numeric_limits<std::size_t>::max()
            - sizeof(BITMAPV5HEADER)) {
        return failure(
            ExportErrorCode::arithmeticOverflow,
            HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    }
    const auto lastRowOffset = (height - 1U) * pixels.stride();
    if (lastRowOffset > std::numeric_limits<std::uint64_t>::max() - rowBytes
        || lastRowOffset + rowBytes > pixels.byteCount()) {
        return failure(ExportErrorCode::invalidPixelBuffer, E_INVALIDARG);
    }

    auto straightResult = convertPremultipliedToStraightBgra(pixels);
    const auto* straightBytes = std::get_if<std::vector<std::byte>>(
        &straightResult);
    if (straightBytes == nullptr) {
        return std::get<ExportError>(straightResult);
    }
    if (straightBytes->size() != static_cast<std::size_t>(imageBytes)) {
        return failure(ExportErrorCode::invalidPixelBuffer, E_INVALIDARG);
    }

    try {
        std::vector<std::byte> result(
            sizeof(BITMAPV5HEADER) + static_cast<std::size_t>(imageBytes));
        BITMAPV5HEADER header{};
        header.bV5Size = sizeof(BITMAPV5HEADER);
        header.bV5Width = static_cast<LONG>(width);
        header.bV5Height = -static_cast<LONG>(height);
        header.bV5Planes = 1U;
        header.bV5BitCount = 32U;
        header.bV5Compression = BI_BITFIELDS;
        header.bV5SizeImage = static_cast<DWORD>(imageBytes);
        header.bV5RedMask = 0x00FF0000U;
        header.bV5GreenMask = 0x0000FF00U;
        header.bV5BlueMask = 0x000000FFU;
        header.bV5AlphaMask = 0xFF000000U;
        header.bV5CSType = LCS_sRGB;
        header.bV5Intent = LCS_GM_IMAGES;
        std::memcpy(result.data(), &header, sizeof(header));

        std::memcpy(
            result.data() + sizeof(header),
            straightBytes->data(),
            straightBytes->size());
        return result;
    } catch (const std::bad_alloc&) {
        return failure(ExportErrorCode::allocationFailed, E_OUTOFMEMORY);
    } catch (...) {
        return failure(ExportErrorCode::allocationFailed, E_FAIL);
    }
}

ClipboardWriteResult writeClipboard(
    const PixelBuffer& pixels,
    HWND owner,
    const PngEncoder& pngEncoder,
    ClipboardApi& api) noexcept
{
    ClipboardWriteResult result;
    try {
        auto dibResult = buildDibV5(pixels);
        const auto* dibBytes = std::get_if<std::vector<std::byte>>(&dibResult);
        if (dibBytes == nullptr) {
            result.dib = ClipboardFormatResult::failed;
            recordError(result, std::get<ExportError>(dibResult));
        }

        auto pngResult = pngEncoder.encodeMemory(pixels);
        const auto* pngBytes = std::get_if<std::vector<std::byte>>(&pngResult);
        if (pngBytes == nullptr) {
            result.png = ClipboardFormatResult::failed;
            recordError(result, std::get<ExportError>(pngResult));
        }

        UINT pngFormat = 0U;
        if (pngBytes != nullptr) {
            pngFormat = api.registerClipboardFormat(L"PNG");
            if (pngFormat == 0U) {
                const DWORD native = api.lastError();
                result.png = ClipboardFormatResult::failed;
                recordError(
                    result,
                    failure(
                        ExportErrorCode::clipboardFormatRegistrationFailed,
                        win32Error(native)));
                pngBytes = nullptr;
            }
        }

        if (dibBytes == nullptr && pngBytes == nullptr) {
            return result;
        }
        if (!openWithBackoff(owner, api)) {
            const DWORD native = api.lastError();
            if (dibBytes != nullptr) {
                result.dib = ClipboardFormatResult::failed;
            }
            if (pngBytes != nullptr) {
                result.png = ClipboardFormatResult::failed;
            }
            recordError(
                result,
                failure(
                    ExportErrorCode::clipboardOpenFailed,
                    win32Error(native)));
            return result;
        }

        if (!api.emptyClipboard()) {
            const DWORD native = api.lastError();
            if (dibBytes != nullptr) {
                result.dib = ClipboardFormatResult::failed;
            }
            if (pngBytes != nullptr) {
                result.png = ClipboardFormatResult::failed;
            }
            recordError(
                result,
                failure(
                    ExportErrorCode::clipboardEmptyFailed,
                    win32Error(native)));
        } else {
            if (dibBytes != nullptr) {
                auto dibGlobal = copyToGlobal(*dibBytes, api);
                auto* handle = std::get_if<HGLOBAL>(&dibGlobal);
                if (handle == nullptr) {
                    result.dib = ClipboardFormatResult::failed;
                    recordError(result, std::get<ExportError>(dibGlobal));
                } else {
                    OwnedGlobalMemory owned(api, *handle);
                    if (api.setClipboardData(CF_DIBV5, owned.get()) == nullptr) {
                        const DWORD native = api.lastError();
                        result.dib = ClipboardFormatResult::failed;
                        recordError(
                            result,
                            failure(
                                ExportErrorCode::clipboardSetDibFailed,
                                win32Error(native)));
                    } else {
                        owned.release();
                        result.dib = ClipboardFormatResult::written;
                    }
                }
            }

            if (pngBytes != nullptr) {
                auto pngGlobal = copyToGlobal(*pngBytes, api);
                auto* handle = std::get_if<HGLOBAL>(&pngGlobal);
                if (handle == nullptr) {
                    result.png = ClipboardFormatResult::failed;
                    recordError(result, std::get<ExportError>(pngGlobal));
                } else {
                    OwnedGlobalMemory owned(api, *handle);
                    if (api.setClipboardData(pngFormat, owned.get()) == nullptr) {
                        const DWORD native = api.lastError();
                        result.png = ClipboardFormatResult::failed;
                        recordError(
                            result,
                            failure(
                                ExportErrorCode::clipboardSetPngFailed,
                                win32Error(native)));
                    } else {
                        owned.release();
                        result.png = ClipboardFormatResult::written;
                    }
                }
            }
        }

        if (!api.closeClipboard()) {
            const DWORD native = api.lastError();
            const auto closeFailure = failure(
                ExportErrorCode::clipboardCloseFailed,
                win32Error(native));
            result.closeError = closeFailure;
        }
        return result;
    } catch (const std::bad_alloc&) {
        recordError(
            result,
            failure(ExportErrorCode::allocationFailed, E_OUTOFMEMORY));
        return result;
    } catch (...) {
        recordError(result, failure(ExportErrorCode::allocationFailed, E_FAIL));
        return result;
    }
}

ClipboardWriteResult writeClipboard(
    const PixelBuffer& pixels,
    HWND owner) noexcept
{
    WicPngEncoder encoder;
    Win32ClipboardApi api;
    return writeClipboard(pixels, owner, encoder, api);
}

bool Win32ClipboardApi::openClipboard(HWND owner) noexcept
{
    return OpenClipboard(owner) != FALSE;
}

bool Win32ClipboardApi::emptyClipboard() noexcept
{
    return EmptyClipboard() != FALSE;
}

UINT Win32ClipboardApi::registerClipboardFormat(const wchar_t* name) noexcept
{
    return RegisterClipboardFormatW(name);
}

HGLOBAL Win32ClipboardApi::allocateGlobal(std::size_t byteCount) noexcept
{
    return GlobalAlloc(GMEM_MOVEABLE, byteCount);
}

void* Win32ClipboardApi::lockGlobal(HGLOBAL handle) noexcept
{
    return GlobalLock(handle);
}

bool Win32ClipboardApi::unlockGlobal(HGLOBAL handle) noexcept
{
    return GlobalUnlock(handle) != FALSE;
}

void Win32ClipboardApi::clearLastError() noexcept
{
    SetLastError(ERROR_SUCCESS);
}

HGLOBAL Win32ClipboardApi::freeGlobal(HGLOBAL handle) noexcept
{
    return GlobalFree(handle);
}

HANDLE Win32ClipboardApi::setClipboardData(UINT format, HANDLE handle) noexcept
{
    return SetClipboardData(format, handle);
}

bool Win32ClipboardApi::closeClipboard() noexcept
{
    return CloseClipboard() != FALSE;
}

DWORD Win32ClipboardApi::lastError() const noexcept
{
    return GetLastError();
}

void Win32ClipboardApi::sleep(DWORD milliseconds) noexcept
{
    Sleep(milliseconds);
}

} // namespace xxsnap::win
