#include "toolbar/ToolbarLayout.h"

namespace xxsnap::win {
namespace {

constexpr bool contains(ToolbarRect rect, ToolbarPoint point) noexcept
{
    return point.x >= rect.x
        && point.x < rect.x + rect.width
        && point.y >= rect.y
        && point.y < rect.y + rect.height;
}

} // namespace

float toolbarWidth(const std::vector<ToolbarAction>& actions) noexcept
{
    float width = ToolbarMetrics::horizontalPaddingDip
        + ToolbarMetrics::buttonStepDip;
    for (const auto action : actions) {
        width += ToolbarMetrics::buttonStepDip + extraGapAfter(action);
    }
    return width + ToolbarMetrics::buttonStepDip;
}

MainToolbarLayout computeMainToolbarLayout(
    ToolbarPoint origin,
    const std::vector<ToolbarAction>& actions)
{
    MainToolbarLayout layout{
        {origin.x, origin.y, toolbarWidth(actions), ToolbarMetrics::heightDip},
        {
            origin.x + ToolbarMetrics::horizontalPaddingDip,
            origin.y + (ToolbarMetrics::heightDip - ToolbarMetrics::buttonSizeDip) / 2.0F,
            ToolbarMetrics::buttonSizeDip,
            ToolbarMetrics::buttonSizeDip,
        },
        {},
        {},
    };

    float x = origin.x + ToolbarMetrics::horizontalPaddingDip
        + ToolbarMetrics::buttonStepDip;
    const float y = origin.y
        + (ToolbarMetrics::heightDip - ToolbarMetrics::buttonSizeDip) / 2.0F;
    layout.items.reserve(actions.size());
    for (const auto action : actions) {
        layout.items.push_back({
            action,
            {x, y, ToolbarMetrics::buttonSizeDip, ToolbarMetrics::buttonSizeDip},
        });
        x += ToolbarMetrics::buttonStepDip + extraGapAfter(action);
    }

    layout.trailingDragHandle = {
        x,
        y,
        ToolbarMetrics::buttonSizeDip,
        ToolbarMetrics::buttonSizeDip,
    };
    return layout;
}

std::optional<ToolbarAction> toolbarActionAt(
    const MainToolbarLayout& layout,
    ToolbarPoint point) noexcept
{
    for (const auto& item : layout.items) {
        if (contains(item.rect, point)) {
            return item.action;
        }
    }
    return std::nullopt;
}

} // namespace xxsnap::win
