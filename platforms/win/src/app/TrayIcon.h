#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>
#include <shellapi.h>

#include <array>
#include <functional>
#include <memory>
#include <optional>

namespace xxsnap::win {

enum class TrayCommand : UINT {
    regionCapture = 0x5801,
    fullScreenCapture = 0x5802,
    textRecognition = 0x5803,
    teachingPen = 0x5804,
    preferences = 0x5805,
    checkForUpdates = 0x5806,
    donation = 0x5807,
    help = 0x5808,
    exportDiagnostics = 0x5809,
    about = 0x580A,
    exit = 0x580B,
};

struct TrayMenuItem {
    TrayCommand command;
    const wchar_t* label;
    bool separator = false;
};

using TrayMenuItems = std::array<TrayMenuItem, 12>;

inline constexpr UINT trayCallbackMessage = WM_APP + 0x58;
inline constexpr UINT trayIconIdentifier = 1;

constexpr TrayMenuItems mvpTrayMenuItems() noexcept
{
    return {{
        {TrayCommand::regionCapture, L"\u533a\u57df\u622a\u56fe"},
        {TrayCommand::fullScreenCapture, L"\u5168\u5c4f\u622a\u56fe"},
        {TrayCommand::textRecognition, L"\u6587\u5b57\u8bc6\u522b"},
        {TrayCommand::teachingPen, L"\u6559\u7b14"},
        {TrayCommand::regionCapture, nullptr, true},
        {TrayCommand::preferences, L"\u504f\u597d\u8bbe\u7f6e\u2026"},
        {TrayCommand::checkForUpdates, L"\u68c0\u67e5\u66f4\u65b0\u2026"},
        {TrayCommand::donation, L"\u652f\u6301\u5f00\u53d1\u8005 \u2615"},
        {TrayCommand::help, L"\u5e2e\u52a9\u2026"},
        {TrayCommand::exportDiagnostics, L"\u5bfc\u51fa\u8bca\u65ad\u65e5\u5fd7\u2026"},
        {TrayCommand::about, L"\u5173\u4e8e\u2026"},
        {TrayCommand::exit, L"\u9000\u51fa"},
    }};
}

class TrayIconApi {
public:
    virtual ~TrayIconApi() = default;
    virtual UINT registerWindowMessage(
        const wchar_t* name, DWORD& error) noexcept = 0;
    virtual bool notifyIcon(
        DWORD operation,
        const NOTIFYICONDATAW& data,
        DWORD& error) noexcept = 0;
    virtual std::optional<TrayCommand> showContextMenu(
        HWND owner,
        const TrayMenuItems& items,
        DWORD& error) noexcept = 0;
};

TrayIconApi& systemTrayIconApi() noexcept;

enum class TrayIconErrorCode {
    invalidArgument,
    taskbarMessageRegistrationFailed,
    addFailed,
    versionFailed,
    modifyFailed,
    menuFailed,
    deleteFailed,
};

struct TrayIconError {
    TrayIconErrorCode code;
    DWORD nativeCode;
};

struct TrayIconCreateResult;

class TrayIcon final {
public:
    using CommandCallback = std::function<void(TrayCommand)>;

    ~TrayIcon();
    TrayIcon(const TrayIcon&) = delete;
    TrayIcon& operator=(const TrayIcon&) = delete;

    static TrayIconCreateResult create(
        TrayIconApi& api,
        HWND owner,
        HICON icon,
        CommandCallback callback);

    UINT taskbarCreatedMessage() const noexcept;
    bool handleMessage(UINT message, WPARAM wParam, LPARAM lParam) noexcept;
    bool showHotKeyConflict(const wchar_t* text) noexcept;
    const std::optional<TrayIconError>& lastError() const noexcept;

private:
    struct State;
    TrayIcon(
        TrayIconApi& api,
        HWND owner,
        HICON icon,
        UINT taskbarCreatedMessage,
        CommandCallback callback);

    NOTIFYICONDATAW notificationData(UINT flags) const noexcept;
    bool add() noexcept;
    bool remove() noexcept;
    void dispatch(TrayCommand command) noexcept;

    TrayIconApi& api_;
    HWND owner_ = nullptr;
    HICON icon_ = nullptr;
    UINT taskbarCreatedMessage_ = 0;
    std::shared_ptr<State> state_;
    bool added_ = false;
};

struct TrayIconCreateResult {
    std::unique_ptr<TrayIcon> value;
    std::optional<TrayIconError> error;
};

} // namespace xxsnap::win
