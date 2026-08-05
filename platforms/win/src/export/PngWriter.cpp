#include "export/PngWriter.h"

#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <string>

namespace xxsnap::win {
namespace {

using Microsoft::WRL::ComPtr;

ExportError failure(ExportErrorCode code, HRESULT nativeCode) noexcept
{
    return {code, nativeCode};
}

HRESULT win32Error(DWORD code) noexcept
{
    return HRESULT_FROM_WIN32(code == ERROR_SUCCESS ? ERROR_GEN_FAILURE : code);
}

void appendError(
    ExportError& error,
    ExportErrorCode code,
    HRESULT nativeCode) noexcept
{
    if (error.additionalErrorCount < error.additionalErrors.size()) {
        error.additionalErrors[error.additionalErrorCount++] = {code, nativeCode};
    }
}

class Win32GlobalMemoryApi final : public GlobalMemoryApi {
public:
    SIZE_T globalSize(HGLOBAL handle) noexcept override
    {
        return GlobalSize(handle);
    }

    const void* lockGlobal(HGLOBAL handle) noexcept override
    {
        return GlobalLock(handle);
    }

    BOOL unlockGlobal(HGLOBAL handle) noexcept override
    {
        return GlobalUnlock(handle);
    }

    void clearLastError() noexcept override
    {
        SetLastError(ERROR_SUCCESS);
    }

    DWORD lastError() const noexcept override
    {
        return GetLastError();
    }
};

GlobalMemoryApi& defaultGlobalMemory() noexcept
{
    static Win32GlobalMemoryApi api;
    return api;
}

class ComApartmentScope final {
public:
    ComApartmentScope() noexcept
        : result_(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))
        , ownsInitialization_(result_ == S_OK || result_ == S_FALSE)
    {
    }

    ~ComApartmentScope()
    {
        if (ownsInitialization_) {
            CoUninitialize();
        }
    }

    bool usable() const noexcept
    {
        return result_ == S_OK || result_ == S_FALSE || result_ == RPC_E_CHANGED_MODE;
    }

    HRESULT result() const noexcept { return result_; }

private:
    HRESULT result_;
    bool ownsInitialization_;
};

struct PixelLayout {
    UINT width = 0U;
    UINT height = 0U;
    UINT stride = 0U;
    UINT byteCount = 0U;
};

std::optional<ExportError> validatePixels(
    const PixelBuffer& pixels,
    PixelLayout& layout) noexcept
{
    if (pixels.width() <= 0 || pixels.height() <= 0
        || pixels.format()
            != snipory::core::portable::PixelFormat::bgra8Premultiplied) {
        return failure(ExportErrorCode::invalidPixelBuffer, E_INVALIDARG);
    }

    const auto width = static_cast<std::uint64_t>(pixels.width());
    const auto height = static_cast<std::uint64_t>(pixels.height());
    if (width > std::numeric_limits<UINT>::max()
        || height > std::numeric_limits<UINT>::max()
        || width > std::numeric_limits<std::uint64_t>::max() / 4U) {
        return failure(
            ExportErrorCode::arithmeticOverflow,
            HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    }

    const auto rowBytes = width * 4U;
    if (pixels.stride() < rowBytes
        || rowBytes > std::numeric_limits<UINT>::max()
        || height > std::numeric_limits<std::uint64_t>::max() / rowBytes) {
        return failure(
            ExportErrorCode::arithmeticOverflow,
            HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    }
    const auto packedByteCount = rowBytes * height;
    if (packedByteCount > std::numeric_limits<UINT>::max()) {
        return failure(
            ExportErrorCode::arithmeticOverflow,
            HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    }

    const auto lastRow = (height - 1U) * pixels.stride();
    if (lastRow > std::numeric_limits<std::uint64_t>::max() - rowBytes
        || lastRow + rowBytes > pixels.byteCount()) {
        return failure(ExportErrorCode::invalidPixelBuffer, E_INVALIDARG);
    }

    layout.width = static_cast<UINT>(width);
    layout.height = static_cast<UINT>(height);
    layout.stride = static_cast<UINT>(rowBytes);
    layout.byteCount = static_cast<UINT>(packedByteCount);
    return std::nullopt;
}

std::variant<std::vector<std::byte>, ExportError> straightBgra(
    const PixelBuffer& pixels,
    const PixelLayout& layout) noexcept
{
    try {
        std::vector<std::byte> result(layout.byteCount);
        for (UINT y = 0U; y < layout.height; ++y) {
            const auto* source = pixels.data()
                + static_cast<std::size_t>(y) * pixels.stride();
            auto* destination = result.data()
                + static_cast<std::size_t>(y) * layout.stride;
            for (UINT x = 0U; x < layout.width; ++x) {
                const auto sourceOffset = static_cast<std::size_t>(x) * 4U;
                const auto alpha = std::to_integer<unsigned int>(source[sourceOffset + 3U]);
                for (std::size_t channel = 0U; channel < 3U; ++channel) {
                    const auto component = std::to_integer<unsigned int>(
                        source[sourceOffset + channel]);
                    const auto straight = alpha == 0U
                        ? 0U
                        : std::min(255U, (component * 255U + alpha / 2U) / alpha);
                    destination[sourceOffset + channel]
                        = std::byte{static_cast<unsigned char>(straight)};
                }
                destination[sourceOffset + 3U]
                    = std::byte{static_cast<unsigned char>(alpha)};
            }
        }
        return result;
    } catch (const std::bad_alloc&) {
        return failure(ExportErrorCode::allocationFailed, E_OUTOFMEMORY);
    } catch (...) {
        return failure(ExportErrorCode::allocationFailed, E_FAIL);
    }
}

ExportResult encodeStream(
    const PixelBuffer& pixels,
    IStream* stream) noexcept
{
    PixelLayout layout;
    if (const auto invalid = validatePixels(pixels, layout); invalid.has_value()) {
        return invalid;
    }
    auto converted = convertPremultipliedToStraightBgra(pixels);
    auto* bytes = std::get_if<std::vector<std::byte>>(&converted);
    if (bytes == nullptr) {
        return std::get<ExportError>(converted);
    }

    ComPtr<IWICImagingFactory> factory;
    HRESULT hr = CoCreateInstance(
        CLSID_WICImagingFactory,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory));
    if (FAILED(hr)) {
        return failure(ExportErrorCode::imagingFailure, hr);
    }

    ComPtr<IWICBitmapEncoder> encoder;
    hr = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
    if (FAILED(hr)) {
        return failure(ExportErrorCode::imagingFailure, hr);
    }
    hr = encoder->Initialize(stream, WICBitmapEncoderNoCache);
    if (FAILED(hr)) {
        return failure(ExportErrorCode::imagingFailure, hr);
    }

    ComPtr<IWICBitmapFrameEncode> frame;
    hr = encoder->CreateNewFrame(&frame, nullptr);
    if (FAILED(hr)) {
        return failure(ExportErrorCode::imagingFailure, hr);
    }
    hr = frame->Initialize(nullptr);
    if (FAILED(hr)) {
        return failure(ExportErrorCode::imagingFailure, hr);
    }
    hr = frame->SetSize(layout.width, layout.height);
    if (FAILED(hr)) {
        return failure(ExportErrorCode::imagingFailure, hr);
    }
    WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
    hr = frame->SetPixelFormat(&format);
    if (FAILED(hr) || !IsEqualGUID(format, GUID_WICPixelFormat32bppBGRA)) {
        return failure(
            ExportErrorCode::imagingFailure,
            FAILED(hr) ? hr : WINCODEC_ERR_UNSUPPORTEDPIXELFORMAT);
    }
    hr = frame->WritePixels(
        layout.height,
        layout.stride,
        layout.byteCount,
        reinterpret_cast<BYTE*>(bytes->data()));
    if (FAILED(hr)) {
        return failure(ExportErrorCode::imagingFailure, hr);
    }
    hr = frame->Commit();
    if (FAILED(hr)) {
        return failure(ExportErrorCode::imagingFailure, hr);
    }
    hr = encoder->Commit();
    if (FAILED(hr)) {
        return failure(ExportErrorCode::imagingFailure, hr);
    }
    hr = stream->Commit(STGC_DEFAULT);
    if (FAILED(hr)) {
        return failure(ExportErrorCode::imagingFailure, hr);
    }
    return std::nullopt;
}

ExportResult initializeCom(ComApartmentScope& apartment) noexcept
{
    if (!apartment.usable()) {
        return failure(ExportErrorCode::comInitializationFailed, apartment.result());
    }
    return std::nullopt;
}

std::wstring temporaryCandidate(
    const wchar_t* target,
    const wchar_t* nonce)
{
    const std::wstring targetString(target);
    const auto separator = targetString.find_last_of(L"\\/");
    std::wstring result = separator == std::wstring::npos
        ? std::wstring{}
        : targetString.substr(0U, separator + 1U);
    result.append(L".xxsnap-");
    result.append(nonce);
    result.append(L".tmp");
    return result;
}

void closeAndDeleteTemporary(
    ExportError& error,
    HANDLE token,
    const wchar_t* path,
    AtomicFileApi& files) noexcept
{
    DWORD native = ERROR_SUCCESS;
    if (!files.closeFile(token, native)) {
        appendError(error, ExportErrorCode::fileCloseFailed, win32Error(native));
    }
    native = ERROR_SUCCESS;
    if (!files.deleteFile(path, native)) {
        appendError(error, ExportErrorCode::fileCleanupFailed, win32Error(native));
    }
}

} // namespace

StraightBgraResult convertPremultipliedToStraightBgra(
    const PixelBuffer& pixels) noexcept
{
    PixelLayout layout;
    if (const auto invalid = validatePixels(pixels, layout); invalid.has_value()) {
        return *invalid;
    }
    return straightBgra(pixels, layout);
}

PngMemoryResult WicPngEncoder::encodeMemory(const PixelBuffer& pixels) const noexcept
{
    try {
        ComApartmentScope apartment;
        if (const auto error = initializeCom(apartment); error.has_value()) {
            return *error;
        }

        ComPtr<IStream> stream;
        HRESULT hr = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
        if (FAILED(hr)) {
            return failure(ExportErrorCode::imagingFailure, hr);
        }
        if (const auto error = encodeStream(pixels, stream.Get()); error.has_value()) {
            return *error;
        }

        STATSTG statistics{};
        hr = stream->Stat(&statistics, STATFLAG_NONAME);
        if (FAILED(hr)) {
            return failure(ExportErrorCode::imagingFailure, hr);
        }
        if (statistics.cbSize.QuadPart
            > static_cast<ULONGLONG>(std::numeric_limits<std::size_t>::max())) {
            return failure(
                ExportErrorCode::arithmeticOverflow,
                HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
        }
        const auto logicalSize = static_cast<std::size_t>(statistics.cbSize.QuadPart);

        HGLOBAL storage = nullptr;
        hr = GetHGlobalFromStream(stream.Get(), &storage);
        if (FAILED(hr)) {
            return failure(ExportErrorCode::imagingFailure, hr);
        }
        GlobalMemoryApi& globals = globalMemory_ == nullptr
            ? defaultGlobalMemory()
            : *globalMemory_;
        const SIZE_T capacity = globals.globalSize(storage);
        if (capacity < logicalSize) {
            const DWORD native = globals.lastError();
            return failure(ExportErrorCode::imagingFailure, win32Error(native));
        }

        std::vector<std::byte> result(logicalSize);
        const void* memory = globals.lockGlobal(storage);
        if (memory == nullptr) {
            const DWORD native = globals.lastError();
            return failure(ExportErrorCode::allocationFailed, win32Error(native));
        }
        std::memcpy(result.data(), memory, logicalSize);
        globals.clearLastError();
        if (!globals.unlockGlobal(storage)) {
            const DWORD native = globals.lastError();
            if (native != ERROR_SUCCESS) {
                return failure(
                    ExportErrorCode::globalMemoryUnlockFailed,
                    win32Error(native));
            }
        }
        return result;
    } catch (const std::bad_alloc&) {
        return failure(ExportErrorCode::allocationFailed, E_OUTOFMEMORY);
    } catch (...) {
        return failure(ExportErrorCode::imagingFailure, E_FAIL);
    }
}

WicPngEncoder::WicPngEncoder(GlobalMemoryApi& globalMemory) noexcept
    : globalMemory_(&globalMemory)
{
}

bool Win32AtomicFileApi::temporaryNonce(
    wchar_t* buffer,
    std::size_t capacity,
    HRESULT& nativeCode) noexcept
{
    GUID guid{};
    nativeCode = CoCreateGuid(&guid);
    if (FAILED(nativeCode)) {
        return false;
    }
    if (capacity > static_cast<std::size_t>(std::numeric_limits<int>::max())
        || StringFromGUID2(guid, buffer, static_cast<int>(capacity)) == 0) {
        nativeCode = E_FAIL;
        return false;
    }
    return true;
}

TemporaryFileReservation Win32AtomicFileApi::reserveTemporary(
    const wchar_t* path) noexcept
{
    const HANDLE handle = CreateFileW(
        path,
        GENERIC_WRITE,
        0U,
        nullptr,
        CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
        const DWORD native = GetLastError();
        const bool collision = native == ERROR_FILE_EXISTS || native == ERROR_ALREADY_EXISTS;
        return {
            collision ? TemporaryFileReservationStatus::collision
                      : TemporaryFileReservationStatus::failed,
            INVALID_HANDLE_VALUE,
            native,
        };
    }
    return {TemporaryFileReservationStatus::created, handle, ERROR_SUCCESS};
}

bool Win32AtomicFileApi::writeFile(
    HANDLE token,
    const std::byte* bytes,
    DWORD byteCount,
    DWORD& written,
    DWORD& nativeCode) noexcept
{
    if (WriteFile(token, bytes, byteCount, &written, nullptr)) {
        nativeCode = ERROR_SUCCESS;
        return true;
    }
    nativeCode = GetLastError();
    return false;
}

bool Win32AtomicFileApi::flushFile(
    HANDLE token,
    DWORD& nativeCode) noexcept
{
    if (FlushFileBuffers(token)) {
        nativeCode = ERROR_SUCCESS;
        return true;
    }
    nativeCode = GetLastError();
    return false;
}

bool Win32AtomicFileApi::closeFile(
    HANDLE token,
    DWORD& nativeCode) noexcept
{
    if (CloseHandle(token)) {
        nativeCode = ERROR_SUCCESS;
        return true;
    }
    nativeCode = GetLastError();
    return false;
}

bool Win32AtomicFileApi::deleteFile(
    const wchar_t* path,
    DWORD& nativeCode) noexcept
{
    if (DeleteFileW(path)) {
        nativeCode = ERROR_SUCCESS;
        return true;
    }
    nativeCode = GetLastError();
    return false;
}

bool Win32AtomicFileApi::moveFile(
    const wchar_t* from,
    const wchar_t* to,
    DWORD flags,
    DWORD& nativeCode) noexcept
{
    if (MoveFileExW(from, to, flags)) {
        nativeCode = ERROR_SUCCESS;
        return true;
    }
    nativeCode = GetLastError();
    return false;
}

ExportResult savePngAtomically(
    const PixelBuffer& pixels,
    const wchar_t* targetPath,
    const PngEncoder& encoder,
    AtomicFileApi& files) noexcept
{
    if (targetPath == nullptr || targetPath[0] == L'\0') {
        return failure(ExportErrorCode::invalidArgument, E_INVALIDARG);
    }
    try {
        std::wstring temporaryPath;
        HANDLE temporaryToken = INVALID_HANDLE_VALUE;
        DWORD lastCollision = ERROR_FILE_EXISTS;
        for (std::size_t attempt = 0U; attempt < maximumTemporaryFileAttempts; ++attempt) {
            std::array<wchar_t, 64U> nonce{};
            HRESULT nonceError = S_OK;
            if (!files.temporaryNonce(
                    nonce.data(), nonce.size(), nonceError)) {
                return failure(
                    ExportErrorCode::temporaryNonceFailed,
                    FAILED(nonceError) ? nonceError : E_FAIL);
            }
            auto candidate = temporaryCandidate(targetPath, nonce.data());
            const auto reservation = files.reserveTemporary(candidate.c_str());
            if (reservation.status == TemporaryFileReservationStatus::created) {
                temporaryPath.swap(candidate);
                temporaryToken = reservation.token;
                break;
            }
            if (reservation.status == TemporaryFileReservationStatus::failed) {
                return failure(
                    ExportErrorCode::temporaryFileCreateFailed,
                    win32Error(reservation.nativeCode));
            }
            lastCollision = reservation.nativeCode;
        }
        if (temporaryPath.empty()) {
            return failure(
                ExportErrorCode::temporaryNameExhausted,
                win32Error(lastCollision));
        }

        auto encoded = encoder.encodeMemory(pixels);
        const auto* bytes = std::get_if<std::vector<std::byte>>(&encoded);
        if (bytes == nullptr) {
            auto result = std::get<ExportError>(encoded);
            closeAndDeleteTemporary(
                result, temporaryToken, temporaryPath.c_str(), files);
            return result;
        }
        if (bytes->empty()) {
            auto result = failure(
                ExportErrorCode::imagingFailure,
                WINCODEC_ERR_BADIMAGE);
            closeAndDeleteTemporary(
                result, temporaryToken, temporaryPath.c_str(), files);
            return result;
        }

        std::size_t offset = 0U;
        while (offset < bytes->size()) {
            const auto remaining = bytes->size() - offset;
            const auto request = static_cast<DWORD>(std::min<std::size_t>(
                remaining,
                static_cast<std::size_t>(std::numeric_limits<DWORD>::max())));
            DWORD written = 0U;
            DWORD native = ERROR_SUCCESS;
            if (!files.writeFile(
                    temporaryToken,
                    bytes->data() + offset,
                    request,
                    written,
                    native)
                || written == 0U || written > request) {
                auto result = failure(
                    ExportErrorCode::fileWriteFailed,
                    win32Error(native));
                closeAndDeleteTemporary(
                    result, temporaryToken, temporaryPath.c_str(), files);
                return result;
            }
            offset += written;
        }

        DWORD native = ERROR_SUCCESS;
        if (!files.flushFile(temporaryToken, native)) {
            auto result = failure(
                ExportErrorCode::fileFlushFailed,
                win32Error(native));
            closeAndDeleteTemporary(
                result, temporaryToken, temporaryPath.c_str(), files);
            return result;
        }
        if (!files.closeFile(temporaryToken, native)) {
            auto result = failure(
                ExportErrorCode::fileCloseFailed,
                win32Error(native));
            DWORD cleanupCode = ERROR_SUCCESS;
            if (!files.deleteFile(temporaryPath.c_str(), cleanupCode)) {
                appendError(
                    result,
                    ExportErrorCode::fileCleanupFailed,
                    win32Error(cleanupCode));
            }
            return result;
        }

        native = ERROR_SUCCESS;
        constexpr DWORD moveFlags = MOVEFILE_REPLACE_EXISTING
            | MOVEFILE_WRITE_THROUGH;
        if (!files.moveFile(
                temporaryPath.c_str(), targetPath, moveFlags, native)) {
            auto commitError = failure(
                ExportErrorCode::fileCommitFailed, win32Error(native));
            DWORD cleanupCode = ERROR_SUCCESS;
            if (!files.deleteFile(temporaryPath.c_str(), cleanupCode)) {
                appendError(
                    commitError,
                    ExportErrorCode::fileCleanupFailed,
                    win32Error(cleanupCode));
            }
            return commitError;
        }
        return std::nullopt;
    } catch (const std::bad_alloc&) {
        return failure(ExportErrorCode::allocationFailed, E_OUTOFMEMORY);
    } catch (...) {
        return failure(ExportErrorCode::temporaryFileCreateFailed, E_FAIL);
    }
}

ExportResult savePngAtomically(
    const PixelBuffer& pixels,
    const wchar_t* targetPath) noexcept
{
    WicPngEncoder encoder;
    Win32AtomicFileApi files;
    return savePngAtomically(pixels, targetPath, encoder, files);
}

} // namespace xxsnap::win
