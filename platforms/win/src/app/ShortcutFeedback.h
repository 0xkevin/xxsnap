#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "app/HotKeyRegistrar.h"
#include "app/PreferencesSettings.h"

#include <Windows.h>

#include <functional>
#include <memory>
#include <string>

namespace xxsnap::win {

inline constexpr int shortcutFeedbackHoldMilliseconds = 3000;
inline constexpr int shortcutFeedbackFadeMilliseconds = 1000;
inline constexpr int shortcutFeedbackScreenInset = 28;
inline constexpr int shortcutFeedbackHeight = 58;
inline constexpr int shortcutFeedbackTriangleWidth = 14;
inline constexpr int shortcutFeedbackMinimumBodyWidth = 88;

std::wstring shortcutDisplayText(UINT modifiers, UINT virtualKey);
bool isDisplayableSystemShortcut(UINT modifiers, UINT virtualKey) noexcept;
bool matchesHotKeyBinding(
    HotKeyBinding binding, UINT modifiers, UINT virtualKey) noexcept;

class ShortcutFeedbackController final {
public:
    using OwnShortcutPredicate = std::function<bool(UINT, UINT)>;

    static std::unique_ptr<ShortcutFeedbackController> create(
        HINSTANCE instance,
        HWND owner,
        const PreferencesSettingsStore& settingsStore,
        OwnShortcutPredicate isOwnShortcut = {});

    ~ShortcutFeedbackController();

    ShortcutFeedbackController(const ShortcutFeedbackController&) = delete;
    ShortcutFeedbackController& operator=(
        const ShortcutFeedbackController&) = delete;

    void showAppShortcut(HotKeyBinding binding) noexcept;
    void showForTesting(UINT modifiers, UINT virtualKey) noexcept;
    HWND nativeWindow() const noexcept;

private:
    struct Impl;
    explicit ShortcutFeedbackController(std::unique_ptr<Impl> impl) noexcept;

    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
