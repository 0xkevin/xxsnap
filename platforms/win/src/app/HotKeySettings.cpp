#include "app/HotKeySettings.h"

namespace xxsnap::win {
namespace {

constexpr std::array<const wchar_t*, 5> modifierNames{
    L"HotKey.Region.Modifiers",
    L"HotKey.FullScreen.Modifiers",
    L"HotKey.Ocr.Modifiers",
    L"HotKey.TeachingPen.Modifiers",
    L"HotKey.RestorePin.Modifiers",
};

constexpr std::array<const wchar_t*, 5> bindingNames{
    L"HotKey.Region.Binding",
    L"HotKey.FullScreen.Binding",
    L"HotKey.Ocr.Binding",
    L"HotKey.TeachingPen.Binding",
    L"HotKey.RestorePin.Binding",
};

constexpr std::array<const wchar_t*, 5> virtualKeyNames{
    L"HotKey.Region.VirtualKey",
    L"HotKey.FullScreen.VirtualKey",
    L"HotKey.Ocr.VirtualKey",
    L"HotKey.TeachingPen.VirtualKey",
    L"HotKey.RestorePin.VirtualKey",
};

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

bool validBinding(UINT modifiers, UINT virtualKey) noexcept
{
    constexpr UINT supported = MOD_ALT | MOD_CONTROL | MOD_SHIFT | MOD_WIN;
    return modifiers != 0U && (modifiers & ~supported) == 0U
        && virtualKey > 0U && virtualKey <= 0xFFU;
}

constexpr DWORD encodeBinding(UINT modifiers, UINT virtualKey) noexcept
{
    return (modifiers << 16U) | virtualKey;
}

bool decodeBinding(DWORD value, UINT& modifiers, UINT& virtualKey) noexcept
{
    modifiers = value >> 16U;
    virtualKey = value & 0xFFFFU;
    return validBinding(modifiers, virtualKey);
}

} // namespace

HotKeySettingsStore::HotKeySettingsStore(
    PreferencesRegistry& registry) noexcept
    : registry_(registry)
{
}

std::array<HotKeyBinding, 5> HotKeySettingsStore::load() const noexcept
{
    auto result = defaultAppHotKeys();
    for (std::size_t index = 0; index < result.size(); ++index) {
        if (const auto encoded = registry_.readDword(bindingNames[index])) {
            UINT modifiers = 0;
            UINT virtualKey = 0;
            if (decodeBinding(*encoded, modifiers, virtualKey)) {
                result[index].modifiers = modifiers;
                result[index].virtualKey = virtualKey;
                continue;
            }
        }
        // Read the two-value format written by early Windows preview builds.
        const auto modifiers = registry_.readDword(modifierNames[index]);
        const auto virtualKey = registry_.readDword(virtualKeyNames[index]);
        if (modifiers.has_value() && virtualKey.has_value()
            && validBinding(*modifiers, *virtualKey)) {
            result[index].modifiers = *modifiers;
            result[index].virtualKey = *virtualKey;
        }
    }
    return result;
}

bool HotKeySettingsStore::save(HotKeyBinding binding) noexcept
{
    if (!validBinding(binding.modifiers, binding.virtualKey)) return false;
    const auto index = commandIndex(binding.command);
    return registry_.writeDword(bindingNames[index],
        encodeBinding(binding.modifiers, binding.virtualKey));
}

bool HotKeySettingsStore::reset() noexcept
{
    bool succeeded = true;
    for (const auto binding : defaultAppHotKeys()) {
        succeeded = save(binding) && succeeded;
    }
    return succeeded;
}

} // namespace xxsnap::win
