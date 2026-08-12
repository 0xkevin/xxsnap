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

bool HotKeyRegistrar::registerRestorePinnedImage(
    HWND window, Callback callback) noexcept
{
    if (restorePinnedImageRegistered_) return window_ == window;
    if (window == nullptr || (window_ != nullptr && window_ != window)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::invalidWindow, ERROR_INVALID_WINDOW_HANDLE};
        return false;
    }
    constexpr auto binding = defaultAppHotKeys()[4];
    DWORD error = ERROR_SUCCESS;
    if (!api_.registerHotKey(window, restorePinnedImageHotKeyIdentifier,
            binding.modifiers, binding.virtualKey, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, error};
        return false;
    }
    window_ = window;
    restorePinnedImageRegistered_ = true;
    try {
        restorePinnedImageCallback_ = std::move(callback);
    } catch (...) {
        api_.unregisterHotKey(window, restorePinnedImageHotKeyIdentifier, error);
        restorePinnedImageRegistered_ = false;
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, ERROR_NOT_ENOUGH_MEMORY};
        return false;
    }
    lastError_.reset();
    return true;
}

bool HotKeyRegistrar::registerFullScreenCapture(
    HWND window, Callback callback) noexcept
{
    if (fullScreenCaptureRegistered_) return window_ == window;
    if (window == nullptr || (window_ != nullptr && window_ != window)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::invalidWindow, ERROR_INVALID_WINDOW_HANDLE};
        return false;
    }
    constexpr auto binding = defaultAppHotKeys()[1];
    DWORD error = ERROR_SUCCESS;
    if (!api_.registerHotKey(window, fullScreenCaptureHotKeyIdentifier,
            binding.modifiers, binding.virtualKey, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, error};
        return false;
    }
    window_ = window;
    fullScreenCaptureRegistered_ = true;
    try {
        fullScreenCaptureCallback_ = std::move(callback);
    } catch (...) {
        api_.unregisterHotKey(window, fullScreenCaptureHotKeyIdentifier, error);
        fullScreenCaptureRegistered_ = false;
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, ERROR_NOT_ENOUGH_MEMORY};
        return false;
    }
    lastError_.reset();
    return true;
}

bool HotKeyRegistrar::unregister() noexcept
{
    if (!registered_ && !fullScreenCaptureRegistered_
        && !restorePinnedImageRegistered_) {
        return true;
    }
    DWORD error = ERROR_SUCCESS;
    bool succeeded = true;
    if (registered_ && !api_.unregisterHotKey(
            window_, regionCaptureHotKeyIdentifier, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::unregistrationFailed, error};
        succeeded = false;
    } else {
        registered_ = false;
    }
    if (restorePinnedImageRegistered_ && !api_.unregisterHotKey(
            window_, restorePinnedImageHotKeyIdentifier, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::unregistrationFailed, error};
        succeeded = false;
    } else {
        restorePinnedImageRegistered_ = false;
    }
    if (fullScreenCaptureRegistered_ && !api_.unregisterHotKey(
            window_, fullScreenCaptureHotKeyIdentifier, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::unregistrationFailed, error};
        succeeded = false;
    } else {
        fullScreenCaptureRegistered_ = false;
    }
    if (succeeded) {
        window_ = nullptr;
        lastError_.reset();
    }
    return succeeded;
}

bool HotKeyRegistrar::handleMessage(UINT message, WPARAM wParam) noexcept
{
    if (message != WM_HOTKEY) {
        return false;
    }
    Callback callback;
    try {
        if (registered_
            && wParam == static_cast<WPARAM>(regionCaptureHotKeyIdentifier)) {
            callback = callback_;
        } else if (fullScreenCaptureRegistered_
            && wParam == static_cast<WPARAM>(fullScreenCaptureHotKeyIdentifier)) {
            callback = fullScreenCaptureCallback_;
        } else if (restorePinnedImageRegistered_
            && wParam == static_cast<WPARAM>(restorePinnedImageHotKeyIdentifier)) {
            callback = restorePinnedImageCallback_;
        } else {
            return false;
        }
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
