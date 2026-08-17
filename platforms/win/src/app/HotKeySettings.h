#pragma once

#include "app/HotKeyRegistrar.h"
#include "app/PreferencesSettings.h"

#include <array>

namespace xxsnap::win {

class HotKeySettingsStore final {
public:
    explicit HotKeySettingsStore(PreferencesRegistry& registry) noexcept;

    std::array<HotKeyBinding, 5> load() const noexcept;
    bool save(HotKeyBinding binding) noexcept;
    bool reset() noexcept;

private:
    PreferencesRegistry& registry_;
};

} // namespace xxsnap::win
