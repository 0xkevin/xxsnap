#pragma once

#include <array>
#include <cstdint>

#include "toolbar/ToolbarCatalog.h"

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

enum class VisualFontWeight : std::uint16_t {
    medium = 500,
};

struct VisualStyleCatalog {
    inline static constexpr Rgba8 selectionColor{83, 120, 232, 255};
    inline static constexpr Rgba8 dimColor{0, 0, 0, 255};
    inline static constexpr float dimAlpha = 0.34f;
    inline static constexpr float selectionBorderDip = 2.0f;
    inline static constexpr float toolbarHeightDip = ToolbarMetrics::heightDip;
    inline static constexpr float buttonSizeDip = ToolbarMetrics::buttonSizeDip;
    inline static constexpr float buttonStepDip = ToolbarMetrics::buttonStepDip;
    inline static constexpr float horizontalPaddingDip =
        ToolbarMetrics::horizontalPaddingDip;
    inline static constexpr float mvpToolbarWidthDip = 144.0f;
    inline static constexpr float layoutMarginDip = 8.0f;
    inline static constexpr float toolbarGapDip = 8.0f;
    inline static constexpr float toolbarCornerRadiusDip =
        ToolbarMetrics::cornerRadiusDip;
    inline static constexpr float toolbarBackgroundAlpha = 0.9f;
    inline static constexpr float toolbarBorderDip = 1.0f;
    // Sampled from AppKit under an explicitly forced NSAppearance.aqua.
    inline static constexpr Rgba8 toolbarBackgroundColor{236, 236, 236, 255};
    inline static constexpr Rgba8 toolbarBorderColor{0, 0, 0, 25};

    inline static constexpr float selectionHandleDiameterDip = 10.0f;
    inline static constexpr float selectionHandleStrokeDip = 2.0f;
    inline static constexpr float selectionHandleStrokeAlpha = 0.95f;
    inline static constexpr Rgba8 selectionHandleStrokeColor{255, 255, 255, 255};

    // macOS samplerInfoFont selects Arial at medium weight, falling back to
    // the platform system font. DirectWrite uses the same family and fallback policy.
    inline static constexpr const wchar_t* sizeLabelFontFamily = L"Arial";
    inline static constexpr const wchar_t* sizeLabelLocaleName = L"en-US";
    inline static constexpr float sizeLabelFontSizeDip = 12.0f;
    inline static constexpr VisualFontWeight sizeLabelFontWeight =
        VisualFontWeight::medium;
    inline static constexpr Rgba8 sizeLabelTextColor{255, 255, 255, 255};
    inline static constexpr float sizeLabelBackgroundWhite = 0.12f;
    inline static constexpr float sizeLabelBackgroundAlpha = 0.86f;
    inline static constexpr float sizeLabelHeightDip = 24.0f;
    inline static constexpr float sizeLabelGapDip = 8.0f;
    inline static constexpr float sizeLabelCornerRadiusDip = 5.0f;
    inline static constexpr float sizeLabelHorizontalTextInsetDip = 9.0f;
    inline static constexpr float sizeLabelVerticalTextInsetDip = 4.0f;
    inline static constexpr float sizeLabelExtraWidthDip = 18.0f;
    inline static constexpr const wchar_t* sizeLabelDimensionSeparator = L" x ";
    inline static constexpr const wchar_t* sizeLabelSuffix = L"  px";
    inline static constexpr std::array mvpToolbarActions{
        MvpToolbarAction::cancel,
        MvpToolbarAction::save,
        MvpToolbarAction::copy,
    };
};

} // namespace xxsnap::win
