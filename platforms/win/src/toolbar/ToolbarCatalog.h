#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "../../resources/resource.h"

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
    finishEditing,
};

struct ToolbarIconSpec {
    const wchar_t* resourceName;
    float insetDip;
    bool fixedColor;
    int resourceIdAt96Dpi;
    int resourceIdAt120Dpi;
    int resourceIdAt144Dpi;
    int resourceIdAt192Dpi;
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

inline constexpr std::array pinnedEditorActions{
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
    ToolbarAction::undo,
    ToolbarAction::redo,
    ToolbarAction::save,
    ToolbarAction::copy,
    ToolbarAction::finishEditing,
};

inline constexpr std::array teachingPenActions{
    ToolbarAction::pen,
    ToolbarAction::rectangle,
    ToolbarAction::polyline,
    ToolbarAction::marker,
    ToolbarAction::text,
    ToolbarAction::number,
    ToolbarAction::mosaic,
    ToolbarAction::eyedropper,
    ToolbarAction::eraser,
    ToolbarAction::magnifier,
    ToolbarAction::copy,
    ToolbarAction::save,
};

inline constexpr std::array imageResources{
    ToolbarIconSpec{
        L"settings-more", 2.0F, false,
        IDR_TOOLBAR_100_SETTINGS_MORE_PNG,
        IDR_TOOLBAR_125_SETTINGS_MORE_PNG,
        IDR_TOOLBAR_150_SETTINGS_MORE_PNG,
        IDR_TOOLBAR_200_SETTINGS_MORE_PNG,
    },
    ToolbarIconSpec{
        L"screenshot", 0.0F, false,
        IDR_TOOLBAR_100_SCREENSHOT_PNG,
        IDR_TOOLBAR_125_SCREENSHOT_PNG,
        IDR_TOOLBAR_150_SCREENSHOT_PNG,
        IDR_TOOLBAR_200_SCREENSHOT_PNG,
    },
    ToolbarIconSpec{
        L"arrow", 0.0F, false,
        IDR_TOOLBAR_100_ARROW_PNG,
        IDR_TOOLBAR_125_ARROW_PNG,
        IDR_TOOLBAR_150_ARROW_PNG,
        IDR_TOOLBAR_200_ARROW_PNG,
    },
    ToolbarIconSpec{
        L"pencil-tool", 2.0F, false,
        IDR_TOOLBAR_100_PENCIL_TOOL_PNG,
        IDR_TOOLBAR_125_PENCIL_TOOL_PNG,
        IDR_TOOLBAR_150_PENCIL_TOOL_PNG,
        IDR_TOOLBAR_200_PENCIL_TOOL_PNG,
    },
    ToolbarIconSpec{
        L"highlighter-tool", 2.0F, false,
        IDR_TOOLBAR_100_HIGHLIGHTER_TOOL_PNG,
        IDR_TOOLBAR_125_HIGHLIGHTER_TOOL_PNG,
        IDR_TOOLBAR_150_HIGHLIGHTER_TOOL_PNG,
        IDR_TOOLBAR_200_HIGHLIGHTER_TOOL_PNG,
    },
    ToolbarIconSpec{
        L"straw-ranging", 0.0F, false,
        IDR_TOOLBAR_100_STRAW_RANGING_PNG,
        IDR_TOOLBAR_125_STRAW_RANGING_PNG,
        IDR_TOOLBAR_150_STRAW_RANGING_PNG,
        IDR_TOOLBAR_200_STRAW_RANGING_PNG,
    },
    ToolbarIconSpec{
        L"masaike2", 0.0F, false,
        IDR_TOOLBAR_100_MASAIKE2_PNG,
        IDR_TOOLBAR_125_MASAIKE2_PNG,
        IDR_TOOLBAR_150_MASAIKE2_PNG,
        IDR_TOOLBAR_200_MASAIKE2_PNG,
    },
    ToolbarIconSpec{
        L"text-tool", 0.0F, false,
        IDR_TOOLBAR_100_TEXT_TOOL_PNG,
        IDR_TOOLBAR_125_TEXT_TOOL_PNG,
        IDR_TOOLBAR_150_TEXT_TOOL_PNG,
        IDR_TOOLBAR_200_TEXT_TOOL_PNG,
    },
    ToolbarIconSpec{
        L"number-sequence", 3.0F, false,
        IDR_TOOLBAR_100_NUMBER_SEQUENCE_PNG,
        IDR_TOOLBAR_125_NUMBER_SEQUENCE_PNG,
        IDR_TOOLBAR_150_NUMBER_SEQUENCE_PNG,
        IDR_TOOLBAR_200_NUMBER_SEQUENCE_PNG,
    },
    ToolbarIconSpec{
        L"zoom-in-tool", 2.0F, false,
        IDR_TOOLBAR_100_ZOOM_IN_TOOL_PNG,
        IDR_TOOLBAR_125_ZOOM_IN_TOOL_PNG,
        IDR_TOOLBAR_150_ZOOM_IN_TOOL_PNG,
        IDR_TOOLBAR_200_ZOOM_IN_TOOL_PNG,
    },
    ToolbarIconSpec{
        L"eraser-tool", 2.0F, false,
        IDR_TOOLBAR_100_ERASER_TOOL_PNG,
        IDR_TOOLBAR_125_ERASER_TOOL_PNG,
        IDR_TOOLBAR_150_ERASER_TOOL_PNG,
        IDR_TOOLBAR_200_ERASER_TOOL_PNG,
    },
    ToolbarIconSpec{
        L"scroll-screen2", 0.0F, false,
        IDR_TOOLBAR_100_SCROLL_SCREEN2_PNG,
        IDR_TOOLBAR_125_SCROLL_SCREEN2_PNG,
        IDR_TOOLBAR_150_SCROLL_SCREEN2_PNG,
        IDR_TOOLBAR_200_SCROLL_SCREEN2_PNG,
    },
    ToolbarIconSpec{
        L"undo-enabled", 0.0F, true,
        IDR_TOOLBAR_100_UNDO_ENABLED_PNG,
        IDR_TOOLBAR_125_UNDO_ENABLED_PNG,
        IDR_TOOLBAR_150_UNDO_ENABLED_PNG,
        IDR_TOOLBAR_200_UNDO_ENABLED_PNG,
    },
    ToolbarIconSpec{
        L"undo-disabled", 0.0F, true,
        IDR_TOOLBAR_100_UNDO_DISABLED_PNG,
        IDR_TOOLBAR_125_UNDO_DISABLED_PNG,
        IDR_TOOLBAR_150_UNDO_DISABLED_PNG,
        IDR_TOOLBAR_200_UNDO_DISABLED_PNG,
    },
    ToolbarIconSpec{
        L"redo-enabled", 0.0F, true,
        IDR_TOOLBAR_100_REDO_ENABLED_PNG,
        IDR_TOOLBAR_125_REDO_ENABLED_PNG,
        IDR_TOOLBAR_150_REDO_ENABLED_PNG,
        IDR_TOOLBAR_200_REDO_ENABLED_PNG,
    },
    ToolbarIconSpec{
        L"redo-disabled", 0.0F, true,
        IDR_TOOLBAR_100_REDO_DISABLED_PNG,
        IDR_TOOLBAR_125_REDO_DISABLED_PNG,
        IDR_TOOLBAR_150_REDO_DISABLED_PNG,
        IDR_TOOLBAR_200_REDO_DISABLED_PNG,
    },
    ToolbarIconSpec{
        L"cancel-capture", 2.0F, false,
        IDR_TOOLBAR_100_CANCEL_CAPTURE_PNG,
        IDR_TOOLBAR_125_CANCEL_CAPTURE_PNG,
        IDR_TOOLBAR_150_CANCEL_CAPTURE_PNG,
        IDR_TOOLBAR_200_CANCEL_CAPTURE_PNG,
    },
    ToolbarIconSpec{
        L"pin-to-screen", 2.0F, false,
        IDR_TOOLBAR_100_PIN_TO_SCREEN_PNG,
        IDR_TOOLBAR_125_PIN_TO_SCREEN_PNG,
        IDR_TOOLBAR_150_PIN_TO_SCREEN_PNG,
        IDR_TOOLBAR_200_PIN_TO_SCREEN_PNG,
    },
    ToolbarIconSpec{
        L"save-to-file", 2.0F, false,
        IDR_TOOLBAR_100_SAVE_TO_FILE_PNG,
        IDR_TOOLBAR_125_SAVE_TO_FILE_PNG,
        IDR_TOOLBAR_150_SAVE_TO_FILE_PNG,
        IDR_TOOLBAR_200_SAVE_TO_FILE_PNG,
    },
    ToolbarIconSpec{
        L"copy-to-clipboard", 2.0F, false,
        IDR_TOOLBAR_100_COPY_TO_CLIPBOARD_PNG,
        IDR_TOOLBAR_125_COPY_TO_CLIPBOARD_PNG,
        IDR_TOOLBAR_150_COPY_TO_CLIPBOARD_PNG,
        IDR_TOOLBAR_200_COPY_TO_CLIPBOARD_PNG,
    },
    ToolbarIconSpec{
        L"trash", 2.0F, false,
        IDR_TOOLBAR_100_TRASH_PNG,
        IDR_TOOLBAR_125_TRASH_PNG,
        IDR_TOOLBAR_150_TRASH_PNG,
        IDR_TOOLBAR_200_TRASH_PNG,
    },
    ToolbarIconSpec{
        L"refresh-svgrepo-com3", 4.0F, true,
        IDR_TOOLBAR_100_REFRESH_SVGREPO_COM3_PNG,
        IDR_TOOLBAR_125_REFRESH_SVGREPO_COM3_PNG,
        IDR_TOOLBAR_150_REFRESH_SVGREPO_COM3_PNG,
        IDR_TOOLBAR_200_REFRESH_SVGREPO_COM3_PNG,
    },
    ToolbarIconSpec{
        L"done", 0.0F, false,
        IDR_TOOLBAR_100_DONE_PNG,
        IDR_TOOLBAR_125_DONE_PNG,
        IDR_TOOLBAR_150_DONE_PNG,
        IDR_TOOLBAR_200_DONE_PNG,
    },
};

inline constexpr std::size_t trashIconIndex = 20U;
inline constexpr std::size_t rotationIconIndex = 21U;
inline constexpr std::size_t finishEditingIconIndex = 22U;

inline constexpr std::array<std::size_t, fullActions.size() + 1U> actionIconIndices{
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 17, 18, 19,
    finishEditingIconIndex,
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

constexpr const auto& pinnedEditorToolbarActions() noexcept
{
    return toolbar_catalog_detail::pinnedEditorActions;
}

constexpr const auto& teachingPenToolbarActions() noexcept
{
    return toolbar_catalog_detail::teachingPenActions;
}

constexpr const ToolbarIconSpec& toolbarIcon(ToolbarAction action) noexcept
{
    const auto index = toolbar_catalog_detail::actionIconIndices[
        static_cast<std::size_t>(action)];
    return toolbar_catalog_detail::imageResources[index];
}

constexpr std::size_t toolbarIconIndex(ToolbarAction action) noexcept
{
    return toolbar_catalog_detail::actionIconIndices[
        static_cast<std::size_t>(action)];
}

constexpr std::size_t disabledToolbarIconIndex(ToolbarAction action) noexcept
{
    if (action == ToolbarAction::undo) {
        return 13;
    }
    if (action == ToolbarAction::redo) {
        return 15;
    }
    return toolbarIconIndex(action);
}

constexpr const ToolbarIconSpec& disabledToolbarIcon(
    ToolbarAction action) noexcept
{
    if (action == ToolbarAction::undo) {
        return toolbar_catalog_detail::imageResources[13];
    }
    if (action == ToolbarAction::redo) {
        return toolbar_catalog_detail::imageResources[15];
    }
    return toolbarIcon(action);
}

constexpr const ToolbarIconSpec& dragHandleIcon() noexcept
{
    return toolbar_catalog_detail::imageResources[0];
}

constexpr const ToolbarIconSpec& rotationHandleIcon() noexcept
{
    return toolbar_catalog_detail::imageResources[
        toolbar_catalog_detail::rotationIconIndex];
}

constexpr std::size_t eraserTrashIconIndex() noexcept
{
    return toolbar_catalog_detail::trashIconIndex;
}

constexpr const ToolbarIconSpec& eraserTrashIcon() noexcept
{
    return toolbar_catalog_detail::imageResources[eraserTrashIconIndex()];
}

constexpr std::size_t rotationHandleIconIndex() noexcept
{
    return toolbar_catalog_detail::rotationIconIndex;
}

constexpr const auto& toolbarImageResources() noexcept
{
    return toolbar_catalog_detail::imageResources;
}

constexpr int toolbarResourceId(
    const ToolbarIconSpec& icon,
    std::uint32_t dpi) noexcept
{
    if (dpi <= 96U) {
        return icon.resourceIdAt96Dpi;
    }
    if (dpi <= 120U) {
        return icon.resourceIdAt120Dpi;
    }
    if (dpi <= 144U) {
        return icon.resourceIdAt144Dpi;
    }
    return icon.resourceIdAt192Dpi;
}

constexpr int toolbarIconPixelEdge(
    const ToolbarIconSpec& icon,
    std::uint32_t dpi) noexcept
{
    const auto safeDpi = dpi == 0U ? 96U : dpi;
    const auto logicalEdge = ToolbarMetrics::buttonSizeDip
        - icon.insetDip * 2.0F;
    return static_cast<int>(
        logicalEdge * static_cast<float>(safeDpi) / 96.0F + 0.5F);
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
