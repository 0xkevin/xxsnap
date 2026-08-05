#pragma once

#include <array>
#include <cstdint>

namespace xxsnap::win {

struct Rgba8 {
    std::uint8_t red;
    std::uint8_t green;
    std::uint8_t blue;
    std::uint8_t alpha;
};

constexpr bool operator==(Rgba8 left, Rgba8 right) noexcept
{
    return left.red == right.red
        && left.green == right.green
        && left.blue == right.blue
        && left.alpha == right.alpha;
}

constexpr bool operator!=(Rgba8 left, Rgba8 right) noexcept
{
    return !(left == right);
}

enum class MvpToolbarAction : std::uint8_t {
    cancel,
    save,
    copy,
};

struct VisualStyleCatalog {
    inline static constexpr Rgba8 selectionColor{83, 120, 232, 255};
    inline static constexpr float dimAlpha = 0.34f;
    inline static constexpr float selectionBorderDip = 2.0f;
    inline static constexpr float toolbarHeightDip = 28.0f;
    inline static constexpr float buttonSizeDip = 20.0f;
    inline static constexpr float buttonStepDip = 28.0f;
    inline static constexpr float horizontalPaddingDip = 4.0f;
    inline static constexpr float mvpToolbarWidthDip = 144.0f;
    inline static constexpr std::array mvpToolbarActions{
        MvpToolbarAction::cancel,
        MvpToolbarAction::save,
        MvpToolbarAction::copy,
    };
};

} // namespace xxsnap::win
