#pragma once

#include "toolbar/ToolbarCatalog.h"

#include <optional>
#include <vector>

namespace xxsnap::win {

struct ToolbarPoint {
    float x;
    float y;
};

struct ToolbarRect {
    float x;
    float y;
    float width;
    float height;
};

constexpr bool operator==(ToolbarRect left, ToolbarRect right) noexcept
{
    return left.x == right.x
        && left.y == right.y
        && left.width == right.width
        && left.height == right.height;
}

struct ToolbarItemLayout {
    ToolbarAction action;
    ToolbarRect rect;
};

struct MainToolbarLayout {
    ToolbarRect bounds;
    ToolbarRect leadingDragHandle;
    ToolbarRect trailingDragHandle;
    std::vector<ToolbarItemLayout> items;
};

float toolbarWidth(const std::vector<ToolbarAction>& actions) noexcept;

MainToolbarLayout computeMainToolbarLayout(
    ToolbarPoint origin,
    const std::vector<ToolbarAction>& actions);

MainToolbarLayout computeTeachingPenToolbarLayout(
    ToolbarPoint pointer,
    ToolbarRect bounds);

ToolbarPoint attachedTeachingPenToolbarOrigin(
    ToolbarRect toolbar,
    ToolbarRect bounds,
    float attachedHeight) noexcept;

std::optional<ToolbarAction> toolbarActionAt(
    const MainToolbarLayout& layout,
    ToolbarPoint point) noexcept;

} // namespace xxsnap::win
