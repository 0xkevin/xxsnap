#include "app/TrayIcon.h"

#include <new>
#include <utility>

namespace xxsnap::win {
namespace {

constexpr wchar_t taskbarCreatedMessageName[] = L"TaskbarCreated";
constexpr wchar_t tooltip[] = L"XxSnap";
constexpr wchar_t conflictTitle[] = L"XxSnap";

void copyText(wchar_t* destination, std::size_t capacity, const wchar_t* source) noexcept
{
    if (destination == nullptr || capacity == 0) {
        return;
    }
    const auto* value = source == nullptr ? L"" : source;
    std::size_t index = 0;
    while (index + 1 < capacity && value[index] != L'\0') {
        destination[index] = value[index];
        ++index;
    }
    destination[index] = L'\0';
}

class SystemTrayIconApi final : public TrayIconApi {
public:
    UINT registerWindowMessage(
        const wchar_t* name, DWORD& error) noexcept override
    {
        const auto message = RegisterWindowMessageW(name);
        error = message == 0 ? GetLastError() : ERROR_SUCCESS;
        return message;
    }

    bool notifyIcon(
        DWORD operation,
        const NOTIFYICONDATAW& data,
        DWORD& error) noexcept override
    {
        auto mutableData = data;
        if (Shell_NotifyIconW(operation, &mutableData)) {
            error = ERROR_SUCCESS;
            return true;
        }
        error = GetLastError();
        return false;
    }

    std::optional<TrayCommand> showContextMenu(
        HWND owner,
        const std::array<TrayMenuItem, 3>& items,
        DWORD& error) noexcept override
    {
        const auto menu = CreatePopupMenu();
        if (menu == nullptr) {
            error = GetLastError();
            return std::nullopt;
        }
        for (const auto& item : items) {
            if (!AppendMenuW(
                    menu,
                    MF_STRING,
                    static_cast<UINT_PTR>(item.command),
                    item.label)) {
                error = GetLastError();
                DestroyMenu(menu);
                return std::nullopt;
            }
        }
        POINT point{};
        if (!GetCursorPos(&point)) {
            error = GetLastError();
            DestroyMenu(menu);
            return std::nullopt;
        }
        SetForegroundWindow(owner);
        const auto command = TrackPopupMenu(
            menu,
            TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY,
            point.x,
            point.y,
            0,
            owner,
            nullptr);
        PostMessageW(owner, WM_NULL, 0, 0);
        DestroyMenu(menu);
        if (command == 0) {
            error = ERROR_SUCCESS;
            return std::nullopt;
        }
        error = ERROR_SUCCESS;
        if (command == static_cast<UINT>(TrayCommand::regionCapture)) {
            return TrayCommand::regionCapture;
        }
        if (command == static_cast<UINT>(TrayCommand::fullScreenCapture)) {
            return TrayCommand::fullScreenCapture;
        }
        if (command == static_cast<UINT>(TrayCommand::exit)) {
            return TrayCommand::exit;
        }
        return std::nullopt;
    }
};

} // namespace

struct TrayIcon::State final {
    explicit State(CommandCallback sourceCallback)
        : callback(std::move(sourceCallback))
    {
    }

    CommandCallback callback;
    std::optional<TrayIconError> lastError;
};

TrayIconApi& systemTrayIconApi() noexcept
{
    static SystemTrayIconApi api;
    return api;
}

TrayIcon::TrayIcon(
    TrayIconApi& api,
    HWND owner,
    HICON icon,
    UINT taskbarCreatedMessage,
    CommandCallback callback)
    : api_(api)
    , owner_(owner)
    , icon_(icon)
    , taskbarCreatedMessage_(taskbarCreatedMessage)
    , state_(std::make_shared<State>(std::move(callback)))
{
}

TrayIcon::~TrayIcon()
{
    remove();
}

NOTIFYICONDATAW TrayIcon::notificationData(UINT flags) const noexcept
{
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = owner_;
    data.uID = trayIconIdentifier;
    data.uFlags = flags;
    data.uCallbackMessage = trayCallbackMessage;
    data.hIcon = icon_;
    copyText(data.szTip, ARRAYSIZE(data.szTip), tooltip);
    return data;
}

bool TrayIcon::add() noexcept
{
    auto data = notificationData(
        NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP);
    DWORD error = ERROR_SUCCESS;
    if (!api_.notifyIcon(NIM_ADD, data, error)) {
        added_ = false;
        state_->lastError = TrayIconError{TrayIconErrorCode::addFailed, error};
        return false;
    }
    added_ = true;
    data.uVersion = NOTIFYICON_VERSION_4;
    if (!api_.notifyIcon(NIM_SETVERSION, data, error)) {
        const TrayIconError versionError{
            TrayIconErrorCode::versionFailed, error};
        remove();
        state_->lastError = versionError;
        return false;
    }
    state_->lastError.reset();
    return true;
}

bool TrayIcon::remove() noexcept
{
    if (!added_) {
        return true;
    }
    const auto data = notificationData(0);
    DWORD error = ERROR_SUCCESS;
    if (!api_.notifyIcon(NIM_DELETE, data, error)) {
        state_->lastError = TrayIconError{TrayIconErrorCode::deleteFailed, error};
        return false;
    }
    added_ = false;
    state_->lastError.reset();
    return true;
}

TrayIconCreateResult TrayIcon::create(
    TrayIconApi& api,
    HWND owner,
    HICON icon,
    CommandCallback callback)
{
    if (owner == nullptr || icon == nullptr) {
        return {
            nullptr,
            TrayIconError{
                TrayIconErrorCode::invalidArgument,
                ERROR_INVALID_PARAMETER,
            },
        };
    }
    DWORD messageError = ERROR_SUCCESS;
    const auto taskbarMessage = api.registerWindowMessage(
        taskbarCreatedMessageName, messageError);
    if (taskbarMessage == 0) {
        return {
            nullptr,
            TrayIconError{
                TrayIconErrorCode::taskbarMessageRegistrationFailed,
                messageError,
            },
        };
    }
    try {
        auto value = std::unique_ptr<TrayIcon>(new TrayIcon(
            api, owner, icon, taskbarMessage, std::move(callback)));
        if (!value->add()) {
            const auto error = value->lastError();
            return {nullptr, error};
        }
        return {std::move(value), std::nullopt};
    } catch (const std::bad_alloc&) {
        return {
            nullptr,
            TrayIconError{
                TrayIconErrorCode::addFailed,
                ERROR_NOT_ENOUGH_MEMORY,
            },
        };
    }
}

UINT TrayIcon::taskbarCreatedMessage() const noexcept
{
    return taskbarCreatedMessage_;
}

void TrayIcon::dispatch(TrayCommand command) noexcept
{
    const auto state = state_;
    CommandCallback callback;
    try {
        callback = state->callback;
    } catch (...) {
        return;
    }
    if (callback) {
        try {
            callback(command);
        } catch (...) {
        }
    }
}

bool TrayIcon::handleMessage(UINT message, WPARAM, LPARAM lParam) noexcept
{
    if (message == taskbarCreatedMessage_) {
        added_ = false;
        add();
        return true;
    }
    if (message != trayCallbackMessage) {
        return false;
    }
    if (HIWORD(lParam) != trayIconIdentifier) {
        return false;
    }
    const auto event = static_cast<UINT>(LOWORD(lParam));
    if (event == WM_LBUTTONDBLCLK) {
        dispatch(TrayCommand::regionCapture);
        return true;
    }
    if (event != WM_RBUTTONUP && event != WM_CONTEXTMENU) {
        return false;
    }
    const auto state = state_;
    auto* const api = &api_;
    const auto owner = owner_;
    DWORD error = ERROR_SUCCESS;
    const auto command = api->showContextMenu(
        owner, mvpTrayMenuItems(), error);
    if (!command.has_value()) {
        if (error != ERROR_SUCCESS) {
            state->lastError = TrayIconError{TrayIconErrorCode::menuFailed, error};
        }
        return true;
    }
    state->lastError.reset();
    CommandCallback callback;
    try {
        callback = state->callback;
    } catch (...) {
        return true;
    }
    if (callback) {
        try {
            callback(*command);
        } catch (...) {
        }
    }
    return true;
}

bool TrayIcon::showHotKeyConflict(const wchar_t* text) noexcept
{
    auto data = notificationData(NIF_INFO);
    copyText(data.szInfoTitle, ARRAYSIZE(data.szInfoTitle), conflictTitle);
    copyText(data.szInfo, ARRAYSIZE(data.szInfo), text);
    data.dwInfoFlags = NIIF_WARNING;
    DWORD error = ERROR_SUCCESS;
    if (!api_.notifyIcon(NIM_MODIFY, data, error)) {
        state_->lastError = TrayIconError{TrayIconErrorCode::modifyFailed, error};
        return false;
    }
    state_->lastError.reset();
    return true;
}

const std::optional<TrayIconError>& TrayIcon::lastError() const noexcept
{
    return state_->lastError;
}

} // namespace xxsnap::win
