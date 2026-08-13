#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <array>
#include <functional>
#include <optional>

namespace xxsnap::win {

enum class HotKeyCommand {
    regionCapture,
    fullScreen,
    ocr,
    teachingPen,
    restoreMostRecentlyHiddenPinnedImage,
};

struct HotKeyBinding {
    HotKeyCommand command;
    UINT modifiers;
    UINT virtualKey;
};

constexpr bool operator==(HotKeyBinding lhs, HotKeyBinding rhs) noexcept
{
    return lhs.command == rhs.command
        && lhs.modifiers == rhs.modifiers
        && lhs.virtualKey == rhs.virtualKey;
}

using AppHotKey = HotKeyBinding;

constexpr std::array<HotKeyBinding, 5> defaultAppHotKeys() noexcept
{
    return {{
        {HotKeyCommand::regionCapture, MOD_CONTROL, VK_OEM_3},
        {HotKeyCommand::fullScreen, MOD_CONTROL | MOD_SHIFT, '1'},
        {HotKeyCommand::ocr, MOD_CONTROL, '3'},
        {HotKeyCommand::teachingPen, MOD_CONTROL, '2'},
        {HotKeyCommand::restoreMostRecentlyHiddenPinnedImage, MOD_CONTROL, '1'},
    }};
}

inline constexpr int regionCaptureHotKeyIdentifier = 0x5852;
inline constexpr int restorePinnedImageHotKeyIdentifier = 0x585A;
inline constexpr int fullScreenCaptureHotKeyIdentifier = 0x585B;
inline constexpr int ocrHotKeyIdentifier = 0x585C;
inline constexpr int teachingPenHotKeyIdentifier = 0x585D;

class HotKeyApi {
public:
    virtual ~HotKeyApi() = default;
    virtual bool registerHotKey(
        HWND window,
        int identifier,
        UINT modifiers,
        UINT virtualKey,
        DWORD& error) noexcept = 0;
    virtual bool unregisterHotKey(
        HWND window, int identifier, DWORD& error) noexcept = 0;
};

HotKeyApi& systemHotKeyApi() noexcept;

enum class HotKeyErrorCode {
    invalidWindow,
    registrationFailed,
    unregistrationFailed,
};

struct HotKeyError {
    HotKeyErrorCode code;
    DWORD nativeCode;
};

class HotKeyRegistrar final {
public:
    using Callback = std::function<void()>;

    HotKeyRegistrar(HotKeyApi& api, Callback callback,
        std::array<HotKeyBinding, 5> bindings = defaultAppHotKeys());
    ~HotKeyRegistrar();

    HotKeyRegistrar(const HotKeyRegistrar&) = delete;
    HotKeyRegistrar& operator=(const HotKeyRegistrar&) = delete;

    bool registerMvpRegionCapture(HWND window) noexcept;
    bool registerFullScreenCapture(HWND window, Callback callback) noexcept;
    bool registerOcr(HWND window, Callback callback) noexcept;
    bool registerTeachingPen(HWND window, Callback callback) noexcept;
    bool registerRestorePinnedImage(HWND window, Callback callback) noexcept;
    bool rebind(HotKeyBinding binding) noexcept;
    HotKeyBinding binding(HotKeyCommand command) const noexcept;
    bool unregister() noexcept;
    bool handleMessage(UINT message, WPARAM wParam) noexcept;
    const std::optional<HotKeyError>& lastError() const noexcept;

private:
    HotKeyApi& api_;
    Callback callback_;
    Callback fullScreenCaptureCallback_;
    Callback ocrCallback_;
    Callback teachingPenCallback_;
    Callback restorePinnedImageCallback_;
    HWND window_ = nullptr;
    bool registered_ = false;
    bool fullScreenCaptureRegistered_ = false;
    bool ocrRegistered_ = false;
    bool teachingPenRegistered_ = false;
    bool restorePinnedImageRegistered_ = false;
    std::array<HotKeyBinding, 5> bindings_ = defaultAppHotKeys();
    std::optional<HotKeyError> lastError_;
};

} // namespace xxsnap::win
