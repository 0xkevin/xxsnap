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
    exit = 0x5802,
};

struct TrayMenuItem {
    TrayCommand command;
    const wchar_t* label;
};

inline constexpr UINT trayCallbackMessage = WM_APP + 0x58;
inline constexpr UINT trayIconIdentifier = 1;

constexpr std::array<TrayMenuItem, 2> mvpTrayMenuItems() noexcept
{
    return {{
        {TrayCommand::regionCapture, L"\u533a\u57df\u622a\u56fe"},
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
        const std::array<TrayMenuItem, 2>& items,
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
