#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace xxsnap::win {

enum class ToolbarAction : std::uint8_t {
    rectangle,
    polyline,
    pen,
    marker,
    eyedropper,
    mosaic,
    text,
    number,
    magnifier,
    eraser,
    scroll,
    undo,
    redo,
    cancel,
    pin,
    save,
    copy,
};

struct ToolbarIconSpec {
    ToolbarAction action;
    const wchar_t* resourceName;
    float insetDip;
    bool fixedColor;
};

struct ToolbarMetrics {
    inline static constexpr float heightDip = 28.0F;
    inline static constexpr float buttonSizeDip = 20.0F;
    inline static constexpr float buttonStepDip = 28.0F;
    inline static constexpr float horizontalPaddingDip = 4.0F;
    inline static constexpr float groupGapDip = 8.0F;
    inline static constexpr float cornerRadiusDip = 6.0F;
};

namespace toolbar_catalog_detail {

inline constexpr std::array fullActions{
    ToolbarAction::rectangle,
    ToolbarAction::polyline,
    ToolbarAction::pen,
    ToolbarAction::marker,
    ToolbarAction::eyedropper,
    ToolbarAction::mosaic,
    ToolbarAction::text,
    ToolbarAction::number,
    ToolbarAction::magnifier,
    ToolbarAction::eraser,
    ToolbarAction::scroll,
    ToolbarAction::undo,
    ToolbarAction::redo,
    ToolbarAction::cancel,
    ToolbarAction::pin,
    ToolbarAction::save,
    ToolbarAction::copy,
};

inline constexpr std::array terminalActions{
    ToolbarAction::cancel,
    ToolbarAction::save,
    ToolbarAction::copy,
};

inline constexpr std::array icons{
    ToolbarIconSpec{ToolbarAction::rectangle, L"screenshot", -1.0F, false},
    ToolbarIconSpec{ToolbarAction::polyline, L"arrow", 0.0F, false},
    ToolbarIconSpec{ToolbarAction::pen, L"pencil-tool", 2.0F, false},
    ToolbarIconSpec{ToolbarAction::marker, L"highlighter-tool", 2.0F, false},
    ToolbarIconSpec{ToolbarAction::eyedropper, L"straw-ranging", 0.0F, false},
    ToolbarIconSpec{ToolbarAction::mosaic, L"masaike2", 0.0F, false},
    ToolbarIconSpec{ToolbarAction::text, L"text-tool", 0.0F, false},
    ToolbarIconSpec{ToolbarAction::number, L"number-sequence", 3.0F, false},
    ToolbarIconSpec{ToolbarAction::magnifier, L"zoom-in-tool", 2.0F, false},
    ToolbarIconSpec{ToolbarAction::eraser, L"eraser-tool", 2.0F, false},
    ToolbarIconSpec{ToolbarAction::scroll, L"scroll-screen2", 0.0F, false},
    ToolbarIconSpec{ToolbarAction::undo, L"undo-enabled", 0.0F, true},
    ToolbarIconSpec{ToolbarAction::redo, L"redo-enabled", 0.0F, true},
    ToolbarIconSpec{ToolbarAction::cancel, L"cancel-capture", 2.0F, false},
    ToolbarIconSpec{ToolbarAction::pin, L"pin-to-screen", 2.0F, false},
    ToolbarIconSpec{ToolbarAction::save, L"save-to-file", 2.0F, false},
    ToolbarIconSpec{ToolbarAction::copy, L"copy-to-clipboard", 2.0F, false},
};

} // namespace toolbar_catalog_detail

constexpr const auto& fullToolbarActions() noexcept
{
    return toolbar_catalog_detail::fullActions;
}

constexpr const auto& terminalToolbarActions() noexcept
{
    return toolbar_catalog_detail::terminalActions;
}

constexpr const ToolbarIconSpec& toolbarIcon(ToolbarAction action) noexcept
{
    return toolbar_catalog_detail::icons[static_cast<std::size_t>(action)];
}

constexpr float extraGapAfter(ToolbarAction action) noexcept
{
    return action == ToolbarAction::eraser
            || action == ToolbarAction::scroll
            || action == ToolbarAction::redo
        ? ToolbarMetrics::groupGapDip
        : 0.0F;
}

} // namespace xxsnap::win
