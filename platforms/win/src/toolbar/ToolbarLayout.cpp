#include "toolbar/ToolbarLayout.h"

#include <algorithm>

namespace xxsnap::win {
namespace {

constexpr bool contains(ToolbarRect rect, ToolbarPoint point) noexcept
{
    return point.x >= rect.x
        && point.x < rect.x + rect.width
        && point.y >= rect.y
        && point.y < rect.y + rect.height;
}

constexpr float clamp(float value, float lower, float upper) noexcept
{
    return value < lower ? lower : value > upper ? upper : value;
}

} // namespace

float toolbarWidth(const std::vector<ToolbarAction>& actions) noexcept
{
    float width = ToolbarMetrics::horizontalPaddingDip
        + ToolbarMetrics::dragHandleStepDip;
    for (const auto action : actions) {
        width += ToolbarMetrics::buttonStepDip + extraGapAfter(action);
    }
    return width + ToolbarMetrics::dragHandleStepDip;
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
        + ToolbarMetrics::dragHandleStepDip;
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
        x - (ToolbarMetrics::dragHandleStepDip
            - ToolbarMetrics::buttonSizeDip),
        y,
        ToolbarMetrics::buttonSizeDip,
        ToolbarMetrics::buttonSizeDip,
    };
    return layout;
}

MainToolbarLayout computeTeachingPenToolbarLayout(
    ToolbarPoint pointer,
    ToolbarRect bounds)
{
    constexpr float margin = 4.0F;
    constexpr float gap = 6.0F;
    constexpr float width = 56.0F;
    constexpr float height = 196.0F;
    constexpr float cell = 20.0F;
    constexpr float cellGap = 8.0F;
    constexpr float separatorHorizontalInset = 7.0F;
    constexpr float separatorHeight = 1.0F;
    const ToolbarRect safe{
        bounds.x + margin,
        bounds.y + margin,
        bounds.width - margin * 2.0F,
        bounds.height - margin * 2.0F,
    };
    auto x = pointer.x + gap + width <= safe.x + safe.width
        ? pointer.x + gap : pointer.x - gap - width;
    auto y = pointer.y + gap + height <= safe.y + safe.height
        ? pointer.y + gap : pointer.y - gap - height;
    x = clamp(x, safe.x, safe.x + safe.width - width);
    y = clamp(y, safe.y, safe.y + safe.height - height);

    MainToolbarLayout layout{
        {x, y, width, height}, {}, {}, {}};
    layout.items.reserve(teachingPenToolbarActions().size());
    for (std::size_t index = 0;
         index < teachingPenToolbarActions().size(); ++index) {
        const auto action = teachingPenToolbarActions()[index];
        const auto column = index % 2U;
        const auto row = index / 2U;
        const auto itemX = action == ToolbarAction::clearAll
            ? x + (width - cell) / 2.0F
            : x + margin + static_cast<float>(column) * (cell + cellGap);
        layout.items.push_back({
            action,
            {
                itemX,
                y + margin + static_cast<float>(row) * (cell + cellGap),
                cell,
                cell,
            },
        });
    }
    const auto actionGroupStart = std::find_if(
        layout.items.begin(), layout.items.end(), [](const auto& item) {
            return item.action == ToolbarAction::copy;
        });
    if (actionGroupStart != layout.items.end()) {
        layout.teachingPenActionSeparator = ToolbarRect{
            x + separatorHorizontalInset,
            actionGroupStart->rect.y - cellGap / 2.0F - separatorHeight,
            width - separatorHorizontalInset * 2.0F,
            separatorHeight,
        };
    }
    return layout;
}

ToolbarPoint attachedTeachingPenToolbarOrigin(
    ToolbarRect toolbar,
    ToolbarRect bounds,
    float attachedHeight) noexcept
{
    constexpr float margin = 4.0F;
    constexpr float gap = 4.0F;
    constexpr float width = 56.0F;
    const ToolbarRect safe{
        bounds.x + margin,
        bounds.y + margin,
        bounds.width - margin * 2.0F,
        bounds.height - margin * 2.0F,
    };
    const auto right = toolbar.x + toolbar.width + gap;
    const auto left = toolbar.x - gap - width;
    float x = right + width <= safe.x + safe.width ? right : left;
    if (x < safe.x || x + width > safe.x + safe.width) {
        const auto rightSpace = safe.x + safe.width
            - (toolbar.x + toolbar.width);
        const auto leftSpace = toolbar.x - safe.x;
        x = rightSpace >= leftSpace ? right : left;
    }
    x = clamp(x, safe.x, safe.x + safe.width - width);
    const auto y = clamp(toolbar.y,
        safe.y, safe.y + safe.height - attachedHeight);
    return {x, y};
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
