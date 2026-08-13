#include "app/HotKeyRegistrar.h"

#include <utility>

namespace xxsnap::win {
namespace {

constexpr std::size_t commandIndex(HotKeyCommand command) noexcept
{
    switch (command) {
    case HotKeyCommand::regionCapture: return 0U;
    case HotKeyCommand::fullScreen: return 1U;
    case HotKeyCommand::ocr: return 2U;
    case HotKeyCommand::teachingPen: return 3U;
    case HotKeyCommand::restoreMostRecentlyHiddenPinnedImage: return 4U;
    }
    return 0U;
}

constexpr int commandIdentifier(HotKeyCommand command) noexcept
{
    switch (command) {
    case HotKeyCommand::regionCapture: return regionCaptureHotKeyIdentifier;
    case HotKeyCommand::fullScreen: return fullScreenCaptureHotKeyIdentifier;
    case HotKeyCommand::ocr: return ocrHotKeyIdentifier;
    case HotKeyCommand::teachingPen: return teachingPenHotKeyIdentifier;
    case HotKeyCommand::restoreMostRecentlyHiddenPinnedImage:
        return restorePinnedImageHotKeyIdentifier;
    }
    return regionCaptureHotKeyIdentifier;
}

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

HotKeyRegistrar::HotKeyRegistrar(HotKeyApi& api, Callback callback,
    std::array<HotKeyBinding, 5> bindings)
    : api_(api)
    , callback_(std::move(callback))
    , bindings_(bindings)
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
    const auto binding = bindings_[0];
    window_ = window;
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
    try {
        restorePinnedImageCallback_ = std::move(callback);
    } catch (...) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, ERROR_NOT_ENOUGH_MEMORY};
        return false;
    }
    window_ = window;
    const auto binding = bindings_[4];
    DWORD error = ERROR_SUCCESS;
    if (!api_.registerHotKey(window, restorePinnedImageHotKeyIdentifier,
            binding.modifiers, binding.virtualKey, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, error};
        return false;
    }
    restorePinnedImageRegistered_ = true;
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
    try {
        fullScreenCaptureCallback_ = std::move(callback);
    } catch (...) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, ERROR_NOT_ENOUGH_MEMORY};
        return false;
    }
    window_ = window;
    const auto binding = bindings_[1];
    DWORD error = ERROR_SUCCESS;
    if (!api_.registerHotKey(window, fullScreenCaptureHotKeyIdentifier,
            binding.modifiers, binding.virtualKey, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, error};
        return false;
    }
    fullScreenCaptureRegistered_ = true;
    lastError_.reset();
    return true;
}

bool HotKeyRegistrar::registerOcr(
    HWND window, Callback callback) noexcept
{
    if (ocrRegistered_) return window_ == window;
    if (window == nullptr || (window_ != nullptr && window_ != window)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::invalidWindow, ERROR_INVALID_WINDOW_HANDLE};
        return false;
    }
    try {
        ocrCallback_ = std::move(callback);
    } catch (...) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, ERROR_NOT_ENOUGH_MEMORY};
        return false;
    }
    window_ = window;
    const auto binding = bindings_[2];
    DWORD error = ERROR_SUCCESS;
    if (!api_.registerHotKey(window, ocrHotKeyIdentifier,
            binding.modifiers, binding.virtualKey, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, error};
        return false;
    }
    ocrRegistered_ = true;
    lastError_.reset();
    return true;
}

bool HotKeyRegistrar::registerTeachingPen(
    HWND window, Callback callback) noexcept
{
    if (teachingPenRegistered_) return window_ == window;
    if (window == nullptr || (window_ != nullptr && window_ != window)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::invalidWindow, ERROR_INVALID_WINDOW_HANDLE};
        return false;
    }
    try {
        teachingPenCallback_ = std::move(callback);
    } catch (...) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, ERROR_NOT_ENOUGH_MEMORY};
        return false;
    }
    window_ = window;
    const auto binding = bindings_[3];
    DWORD error = ERROR_SUCCESS;
    if (!api_.registerHotKey(window, teachingPenHotKeyIdentifier,
            binding.modifiers, binding.virtualKey, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, error};
        return false;
    }
    teachingPenRegistered_ = true;
    lastError_.reset();
    return true;
}

bool HotKeyRegistrar::rebind(HotKeyBinding replacement) noexcept
{
    if (window_ == nullptr || replacement.modifiers == 0U
        || replacement.virtualKey == 0U) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::invalidWindow, ERROR_INVALID_PARAMETER};
        return false;
    }
    bool* registered = nullptr;
    switch (replacement.command) {
    case HotKeyCommand::regionCapture: registered = &registered_; break;
    case HotKeyCommand::fullScreen:
        registered = &fullScreenCaptureRegistered_;
        break;
    case HotKeyCommand::ocr: registered = &ocrRegistered_; break;
    case HotKeyCommand::teachingPen:
        registered = &teachingPenRegistered_;
        break;
    case HotKeyCommand::restoreMostRecentlyHiddenPinnedImage:
        registered = &restorePinnedImageRegistered_;
        break;
    }
    if (registered == nullptr) return false;

    const auto index = commandIndex(replacement.command);
    const auto previous = bindings_[index];
    const auto identifier = commandIdentifier(replacement.command);
    const auto wasRegistered = *registered;
    DWORD error = ERROR_SUCCESS;
    if (wasRegistered
        && !api_.unregisterHotKey(window_, identifier, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::unregistrationFailed, error};
        return false;
    }
    *registered = false;
    if (!api_.registerHotKey(window_, identifier,
            replacement.modifiers, replacement.virtualKey, error)) {
        const auto registrationError = error;
        if (wasRegistered) {
            DWORD rollbackError = ERROR_SUCCESS;
            *registered = api_.registerHotKey(window_, identifier,
                previous.modifiers, previous.virtualKey, rollbackError);
        }
        lastError_ = HotKeyError{
            HotKeyErrorCode::registrationFailed, registrationError};
        return false;
    }
    bindings_[index] = replacement;
    *registered = true;
    lastError_.reset();
    return true;
}

HotKeyBinding HotKeyRegistrar::binding(HotKeyCommand command) const noexcept
{
    return bindings_[commandIndex(command)];
}

bool HotKeyRegistrar::isRegistered(HotKeyCommand command) const noexcept
{
    switch (command) {
    case HotKeyCommand::regionCapture: return registered_;
    case HotKeyCommand::fullScreen: return fullScreenCaptureRegistered_;
    case HotKeyCommand::ocr: return ocrRegistered_;
    case HotKeyCommand::teachingPen: return teachingPenRegistered_;
    case HotKeyCommand::restoreMostRecentlyHiddenPinnedImage:
        return restorePinnedImageRegistered_;
    }
    return false;
}

bool HotKeyRegistrar::unregister() noexcept
{
    if (!registered_ && !fullScreenCaptureRegistered_ && !ocrRegistered_
        && !teachingPenRegistered_
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
    if (ocrRegistered_ && !api_.unregisterHotKey(
            window_, ocrHotKeyIdentifier, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::unregistrationFailed, error};
        succeeded = false;
    } else {
        ocrRegistered_ = false;
    }
    if (teachingPenRegistered_ && !api_.unregisterHotKey(
            window_, teachingPenHotKeyIdentifier, error)) {
        lastError_ = HotKeyError{
            HotKeyErrorCode::unregistrationFailed, error};
        succeeded = false;
    } else {
        teachingPenRegistered_ = false;
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
        } else if (ocrRegistered_
            && wParam == static_cast<WPARAM>(ocrHotKeyIdentifier)) {
            callback = ocrCallback_;
        } else if (teachingPenRegistered_
            && wParam == static_cast<WPARAM>(teachingPenHotKeyIdentifier)) {
            callback = teachingPenCallback_;
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
