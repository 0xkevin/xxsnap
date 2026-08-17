#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include "app/PreferencesSettings.h"
#include "app/HotKeyRegistrar.h"

#include <array>
#include <functional>
#include <memory>
#include <string>

namespace xxsnap::win {

enum class PreferencesSection : std::size_t {
    general,
    shortcuts,
    save,
    update,
    donation,
    about,
};

constexpr std::array<PreferencesSection, 6> preferencesSections() noexcept
{
    return {{
        PreferencesSection::general,
        PreferencesSection::shortcuts,
        PreferencesSection::save,
        PreferencesSection::update,
        PreferencesSection::donation,
        PreferencesSection::about,
    }};
}

SIZE preferencesWindowClientSize(UINT dpi) noexcept;
std::wstring filenameTemplateErrorText(
    FilenameTemplateError error, const std::wstring& invalidVariable);

struct PreferencesShortcutCallbacks {
    std::function<std::array<HotKeyBinding, 5>()> load;
    std::function<bool(HotKeyBinding)> apply;
    std::function<bool()> reset;
};

class PreferencesWindow final {
public:
    ~PreferencesWindow();
    PreferencesWindow(const PreferencesWindow&) = delete;
    PreferencesWindow& operator=(const PreferencesWindow&) = delete;

    static std::unique_ptr<PreferencesWindow> create(
        HINSTANCE instance, HWND owner,
        PreferencesShortcutCallbacks shortcutCallbacks = {});

    void show(PreferencesSection section = PreferencesSection::general) noexcept;
    HWND window() const noexcept;

private:
    struct Impl;
    explicit PreferencesWindow(std::unique_ptr<Impl> impl) noexcept;
    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
