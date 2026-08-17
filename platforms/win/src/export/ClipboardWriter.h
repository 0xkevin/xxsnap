#pragma once

#include "export/PngWriter.h"

#include <Windows.h>

#include <cstddef>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace xxsnap::win {

using DibV5Result = std::variant<std::vector<std::byte>, ExportError>;

enum class ClipboardFormatResult {
    notAttempted,
    written,
    failed,
};

struct ClipboardWriteResult {
    ClipboardFormatResult dib = ClipboardFormatResult::notAttempted;
    ClipboardFormatResult png = ClipboardFormatResult::notAttempted;
    std::optional<ExportError> primaryError;
    std::optional<ExportError> secondaryError;
    std::optional<ExportError> closeError;

    bool succeeded() const noexcept;
    bool partial() const noexcept;
};

struct ClipboardTextWriteResult {
    bool written = false;
    std::optional<ExportError> error;
    std::optional<ExportError> closeError;

    bool succeeded() const noexcept
    {
        return written && !error.has_value() && !closeError.has_value();
    }
};

class ClipboardApi {
public:
    virtual ~ClipboardApi() = default;

    virtual bool openClipboard(HWND owner) noexcept = 0;
    virtual bool emptyClipboard() noexcept = 0;
    virtual UINT registerClipboardFormat(const wchar_t* name) noexcept = 0;
    virtual HGLOBAL allocateGlobal(std::size_t byteCount) noexcept = 0;
    virtual void* lockGlobal(HGLOBAL handle) noexcept = 0;
    virtual bool unlockGlobal(HGLOBAL handle) noexcept = 0;
    virtual void clearLastError() noexcept = 0;
    virtual HGLOBAL freeGlobal(HGLOBAL handle) noexcept = 0;
    virtual HANDLE setClipboardData(UINT format, HANDLE handle) noexcept = 0;
    virtual bool closeClipboard() noexcept = 0;
    virtual DWORD lastError() const noexcept = 0;
    virtual void sleep(DWORD milliseconds) noexcept = 0;
};

class Win32ClipboardApi final : public ClipboardApi {
public:
    bool openClipboard(HWND owner) noexcept override;
    bool emptyClipboard() noexcept override;
    UINT registerClipboardFormat(const wchar_t* name) noexcept override;
    HGLOBAL allocateGlobal(std::size_t byteCount) noexcept override;
    void* lockGlobal(HGLOBAL handle) noexcept override;
    bool unlockGlobal(HGLOBAL handle) noexcept override;
    void clearLastError() noexcept override;
    HGLOBAL freeGlobal(HGLOBAL handle) noexcept override;
    HANDLE setClipboardData(UINT format, HANDLE handle) noexcept override;
    bool closeClipboard() noexcept override;
    DWORD lastError() const noexcept override;
    void sleep(DWORD milliseconds) noexcept override;
};

DibV5Result buildDibV5(const PixelBuffer& pixels) noexcept;

ClipboardWriteResult writeClipboard(
    const PixelBuffer& pixels,
    HWND owner,
    const PngEncoder& pngEncoder,
    ClipboardApi& api) noexcept;

ClipboardWriteResult writeClipboard(
    const PixelBuffer& pixels,
    HWND owner = nullptr) noexcept;

ClipboardTextWriteResult writeClipboardText(
    const std::wstring& text,
    HWND owner,
    ClipboardApi& api) noexcept;

ClipboardTextWriteResult writeClipboardText(
    const std::wstring& text,
    HWND owner = nullptr) noexcept;

} // namespace xxsnap::win
