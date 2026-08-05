#include "app/HotKeyRegistrar.h"

#include <utility>

namespace xxsnap::win {
namespace {

class SystemHotKeyApi final : public HotKeyApi {
public:
    bool registerHotKey(
        HWND window,
        int identifier,
        UINT modifiers,
        UINT virtualKey,
        DWORD& error) noexcept override
    {
        if (RegisterHotKey(window, identifier, modifiers, virtualKey)) {
            error = ERROR_SUCCESS;
            return true;
        }
        error = GetLastError();
        return false;
    }

    bool unregisterHotKey(
        HWND window, int identifier, DWORD& error) noexcept override
    {
        if (UnregisterHotKey(window, identifier)) {
            error = ERROR_SUCCESS;
            return true;
        }
        error = GetLastError();
        return false;
    }
};

} // namespace

HotKeyApi& systemHotKeyApi() noexcept
{
    static SystemHotKeyApi api;
    return api;
}

HotKeyRegistrar::HotKeyRegistrar(HotKeyApi& api, Callback callback)
    : api_(api)
    , callback_(std::move(callback))
{
}

HotKeyRegistrar::~HotKeyRegistrar()
{
    unregister();
}

bool HotKeyRegistrar::registerMvpRegionCapture(HWND window) noexcept
{
    if (registered_) {
        return window_ == window;
    }
    if (window == nullptr) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::invalidWindow, ERROR_INVALID_WINDOW_HANDLE};
        return false;
    }
    constexpr auto binding = defaultAppHotKeys()[0];
    DWORD error = ERROR_SUCCESS;
    if (!api_.registerHotKey(
            window,
            regionCaptureHotKeyIdentifier,
            binding.modifiers,
            binding.virtualKey,
            error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, error};
        return false;
    }
    window_ = window;
    registered_ = true;
    lastError_.reset();
    return true;
}

bool HotKeyRegistrar::unregister() noexcept
{
    if (!registered_) {
        return true;
    }
    DWORD error = ERROR_SUCCESS;
    if (!api_.unregisterHotKey(
            window_, regionCaptureHotKeyIdentifier, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::unregistrationFailed, error};
        return false;
    }
    registered_ = false;
    window_ = nullptr;
    lastError_.reset();
    return true;
}

bool HotKeyRegistrar::handleMessage(UINT message, WPARAM wParam) noexcept
{
    if (!registered_ || message != WM_HOTKEY
        || wParam != static_cast<WPARAM>(regionCaptureHotKeyIdentifier)) {
        return false;
    }
    Callback callback;
    try {
        callback = callback_;
    } catch (...) {
        return true;
    }
    if (callback) {
        try {
            callback();
        } catch (...) {
        }
    }
    return true;
}

const std::optional<HotKeyError>& HotKeyRegistrar::lastError() const noexcept
{
    return lastError_;
}

} // namespace xxsnap::win
