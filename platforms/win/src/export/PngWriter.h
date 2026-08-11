#pragma once

#include "snipory/core/portable/PixelBuffer.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#include <array>
#include <cstddef>
#include <optional>
#include <variant>
#include <vector>

namespace xxsnap::win {

using snipory::core::portable::PixelBuffer;

enum class ExportErrorCode {
    invalidArgument,
    invalidPixelBuffer,
    arithmeticOverflow,
    allocationFailed,
    comInitializationFailed,
    imagingFailure,
    globalMemoryUnlockFailed,
    clipboardOpenFailed,
    clipboardEmptyFailed,
    clipboardFormatRegistrationFailed,
    clipboardAllocationFailed,
    clipboardLockFailed,
    clipboardSetDibFailed,
    clipboardSetPngFailed,
    clipboardCloseFailed,
    temporaryFileCreateFailed,
    temporaryNonceFailed,
    temporaryNameExhausted,
    fileWriteFailed,
    fileFlushFailed,
    fileCloseFailed,
    fileCommitFailed,
    fileCleanupFailed,
};

struct ExportErrorDetail {
    ExportErrorCode code;
    HRESULT nativeCode;
};

struct ExportError {
    ExportErrorCode code;
    HRESULT nativeCode;
    std::array<ExportErrorDetail, 2U> additionalErrors{};
    std::size_t additionalErrorCount = 0U;
};

using ExportResult = std::optional<ExportError>;
using PngMemoryResult = std::variant<std::vector<std::byte>, ExportError>;
using StraightBgraResult = std::variant<std::vector<std::byte>, ExportError>;

// Returns tightly packed, top-down, straight-alpha BGRA without modifying the
// caller's premultiplied PixelBuffer.
StraightBgraResult convertPremultipliedToStraightBgra(
    const PixelBuffer& pixels) noexcept;

// WIC operations initialize COM for the current call. Existing apartments are
// accepted (including RPC_E_CHANGED_MODE), and only S_OK/S_FALSE calls made by
// this library are balanced with CoUninitialize.
class PngEncoder {
public:
    virtual ~PngEncoder() = default;

    virtual PngMemoryResult encodeMemory(const PixelBuffer& pixels) const noexcept = 0;
};

class GlobalMemoryApi {
public:
    virtual ~GlobalMemoryApi() = default;

    virtual SIZE_T globalSize(HGLOBAL handle) noexcept = 0;
    virtual const void* lockGlobal(HGLOBAL handle) noexcept = 0;
    virtual BOOL unlockGlobal(HGLOBAL handle) noexcept = 0;
    virtual void clearLastError() noexcept = 0;
    virtual DWORD lastError() const noexcept = 0;
};

class WicPngEncoder final : public PngEncoder {
public:
    WicPngEncoder() noexcept = default;
    explicit WicPngEncoder(GlobalMemoryApi& globalMemory) noexcept;

    PngMemoryResult encodeMemory(const PixelBuffer& pixels) const noexcept override;

private:
    GlobalMemoryApi* globalMemory_ = nullptr;
};

enum class TemporaryFileReservationStatus {
    created,
    collision,
    failed,
};

struct TemporaryFileReservation {
    TemporaryFileReservationStatus status;
    HANDLE token;
    DWORD nativeCode;
};

class AtomicFileApi {
public:
    virtual ~AtomicFileApi() = default;

    virtual bool temporaryNonce(
        wchar_t* buffer,
        std::size_t capacity,
        HRESULT& nativeCode) noexcept = 0;
    virtual TemporaryFileReservation reserveTemporary(const wchar_t* path) noexcept = 0;
    virtual bool writeFile(
        HANDLE token,
        const std::byte* bytes,
        DWORD byteCount,
        DWORD& written,
        DWORD& nativeCode) noexcept = 0;
    virtual bool flushFile(HANDLE token, DWORD& nativeCode) noexcept = 0;
    virtual bool closeFile(HANDLE token, DWORD& nativeCode) noexcept = 0;
    virtual bool deleteFile(const wchar_t* path, DWORD& nativeCode) noexcept = 0;
    virtual bool moveFile(
        const wchar_t* from,
        const wchar_t* to,
        DWORD flags,
        DWORD& nativeCode) noexcept = 0;
};

class Win32AtomicFileApi final : public AtomicFileApi {
public:
    bool temporaryNonce(
        wchar_t* buffer,
        std::size_t capacity,
        HRESULT& nativeCode) noexcept override;
    TemporaryFileReservation reserveTemporary(const wchar_t* path) noexcept override;
    bool writeFile(
        HANDLE token,
        const std::byte* bytes,
        DWORD byteCount,
        DWORD& written,
        DWORD& nativeCode) noexcept override;
    bool flushFile(HANDLE token, DWORD& nativeCode) noexcept override;
    bool closeFile(HANDLE token, DWORD& nativeCode) noexcept override;
    bool deleteFile(const wchar_t* path, DWORD& nativeCode) noexcept override;
    bool moveFile(
        const wchar_t* from,
        const wchar_t* to,
        DWORD flags,
        DWORD& nativeCode) noexcept override;
};

inline constexpr std::size_t maximumTemporaryFileAttempts = 16U;

ExportResult savePngAtomically(
    const PixelBuffer& pixels,
    const wchar_t* targetPath,
    const PngEncoder& encoder,
    AtomicFileApi& files) noexcept;

ExportResult savePngAtomically(
    const PixelBuffer& pixels,
    const wchar_t* targetPath) noexcept;

} // namespace xxsnap::win
