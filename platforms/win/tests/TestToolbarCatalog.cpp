#include "toolbar/ToolbarCatalog.h"

#include <array>
#include <cstdlib>
#include <string_view>

using namespace xxsnap::win;

template <typename T, std::size_t Size>
constexpr bool arraysEqual(
    const std::array<T, Size>& left,
    const std::array<T, Size>& right) noexcept
{
    for (std::size_t index = 0; index < Size; ++index) {
        if (left[index] != right[index]) {
            return false;
        }
    }
    return true;
}

int main()
{
    static_assert(ToolbarMetrics::heightDip == 28.0F);
    static_assert(ToolbarMetrics::buttonSizeDip == 20.0F);
    static_assert(ToolbarMetrics::buttonStepDip == 28.0F);
    static_assert(ToolbarMetrics::horizontalPaddingDip == 4.0F);
    static_assert(ToolbarMetrics::groupGapDip == 8.0F);
    static_assert(ToolbarMetrics::cornerRadiusDip == 6.0F);

    constexpr std::array expected{
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

    static_assert(arraysEqual(fullToolbarActions(), expected));
    static_assert(terminalToolbarActions().size() == 3);
    static_assert(toolbarIcon(ToolbarAction::rectangle).insetDip == -1.0F);
    static_assert(toolbarIcon(ToolbarAction::number).insetDip == 3.0F);
    static_assert(toolbarIcon(ToolbarAction::scroll).insetDip == 0.0F);
    static_assert(toolbarIcon(ToolbarAction::undo).fixedColor);
    static_assert(toolbarIcon(ToolbarAction::redo).fixedColor);
    static_assert(extraGapAfter(ToolbarAction::eraser) == 8.0F);
    static_assert(extraGapAfter(ToolbarAction::scroll) == 8.0F);
    static_assert(extraGapAfter(ToolbarAction::redo) == 8.0F);
    static_assert(extraGapAfter(ToolbarAction::copy) == 0.0F);

    return std::wstring_view(toolbarIcon(ToolbarAction::cancel).resourceName)
            == L"cancel-capture"
        ? EXIT_SUCCESS
        : EXIT_FAILURE;
}
