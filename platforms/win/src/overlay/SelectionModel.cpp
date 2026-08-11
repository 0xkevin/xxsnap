#include "overlay/SelectionModel.h"

#include <algorithm>
#include <array>
#include <limits>

namespace xxsnap::win {
namespace {

constexpr std::int64_t saturatingAdd(std::int64_t lhs, std::int64_t rhs) noexcept
{
    constexpr auto minimum = std::numeric_limits<std::int64_t>::min();
    constexpr auto maximum = std::numeric_limits<std::int64_t>::max();
    if (rhs > 0 && lhs > maximum - rhs) {
        return maximum;
    }
    if (rhs < 0 && lhs < minimum - rhs) {
        return minimum;
    }
    return lhs + rhs;
}

constexpr std::int64_t saturatingSubtract(std::int64_t lhs, std::int64_t rhs) noexcept
{
    if (rhs == std::numeric_limits<std::int64_t>::min()) {
        return lhs >= 0
            ? std::numeric_limits<std::int64_t>::max()
            : saturatingAdd(lhs, std::numeric_limits<std::int64_t>::max()) + 1;
    }
    return saturatingAdd(lhs, -rhs);
}

constexpr std::int64_t rightEdge(PixelRect rect) noexcept
{
    return saturatingAdd(rect.x, rect.width);
}

constexpr std::int64_t bottomEdge(PixelRect rect) noexcept
{
    return saturatingAdd(rect.y, rect.height);
}

constexpr std::int64_t clampCoordinate(
    std::int64_t value, std::int64_t lower, std::int64_t upper) noexcept
{
    return std::clamp(value, lower, upper);
}

constexpr PixelPoint clampPoint(PixelPoint point, PixelRect bounds) noexcept
{
    return {
        clampCoordinate(point.x, bounds.x, rightEdge(bounds)),
        clampCoordinate(point.y, bounds.y, bottomEdge(bounds)),
    };
}

constexpr bool hasArea(PixelRect rect) noexcept
{
    return rect.width >= 1 && rect.height >= 1;
}

constexpr bool contains(PixelRect rect, PixelPoint point) noexcept
{
    return point.x >= rect.x && point.x < rightEdge(rect)
        && point.y >= rect.y && point.y < bottomEdge(rect);
}

constexpr bool hasWest(SelectionHandle handle) noexcept
{
    return handle == SelectionHandle::west
        || handle == SelectionHandle::northWest
        || handle == SelectionHandle::southWest;
}

constexpr bool hasEast(SelectionHandle handle) noexcept
{
    return handle == SelectionHandle::east
        || handle == SelectionHandle::northEast
        || handle == SelectionHandle::southEast;
}

constexpr bool hasNorth(SelectionHandle handle) noexcept
{
    return handle == SelectionHandle::north
        || handle == SelectionHandle::northWest
        || handle == SelectionHandle::northEast;
}

constexpr bool hasSouth(SelectionHandle handle) noexcept
{
    return handle == SelectionHandle::south
        || handle == SelectionHandle::southWest
        || handle == SelectionHandle::southEast;
}

constexpr bool isResizeHandle(SelectionHandle handle) noexcept
{
    return hasWest(handle) || hasEast(handle) || hasNorth(handle) || hasSouth(handle);
}

constexpr SelectionHandle handleForSides(int horizontal, int vertical) noexcept
{
    if (horizontal < 0 && vertical < 0) {
        return SelectionHandle::northWest;
    }
    if (horizontal > 0 && vertical < 0) {
        return SelectionHandle::northEast;
    }
    if (horizontal > 0 && vertical > 0) {
        return SelectionHandle::southEast;
    }
    if (horizontal < 0 && vertical > 0) {
        return SelectionHandle::southWest;
    }
    if (vertical < 0) {
        return SelectionHandle::north;
    }
    if (horizontal > 0) {
        return SelectionHandle::east;
    }
    if (vertical > 0) {
        return SelectionHandle::south;
    }
    if (horizontal < 0) {
        return SelectionHandle::west;
    }
    return SelectionHandle::none;
}

constexpr std::int64_t onePixelFrom(
    std::int64_t fixed,
    int& side,
    std::int64_t lower,
    std::int64_t upper) noexcept
{
    if (side >= 0 && fixed < upper) {
        side = 1;
        return fixed + 1;
    }
    if (fixed > lower) {
        side = -1;
        return fixed - 1;
    }
    side = 0;
    return fixed;
}

constexpr std::uint64_t coordinateDistance(
    std::int64_t lhs, std::int64_t rhs) noexcept
{
    return lhs >= rhs
        ? static_cast<std::uint64_t>(lhs) - static_cast<std::uint64_t>(rhs)
        : static_cast<std::uint64_t>(rhs) - static_cast<std::uint64_t>(lhs);
}

constexpr std::uint64_t chebyshevDistance(PixelPoint lhs, PixelPoint rhs) noexcept
{
    return std::max(
        coordinateDistance(lhs.x, rhs.x),
        coordinateDistance(lhs.y, rhs.y));
}

} // namespace

SelectionModel::SelectionModel(PixelRect virtualBounds) noexcept
    : virtualBounds_(snipory::core::portable::standardized(virtualBounds))
{
}

SelectionPhase SelectionModel::phase() const noexcept
{
    return phase_;
}

SelectionHandle SelectionModel::activeHandle() const noexcept
{
    return activeHandle_;
}

const std::optional<PixelRect>& SelectionModel::selection() const noexcept
{
    return selection_;
}

void SelectionModel::beginCreation(PixelPoint anchor) noexcept
{
    creationAnchor_ = clampPoint(anchor, virtualBounds_);
    selection_.reset();
    phase_ = SelectionPhase::creating;
    activeHandle_ = SelectionHandle::none;
}

bool SelectionModel::beginMove(PixelPoint grabPoint) noexcept
{
    if (phase_ != SelectionPhase::ready || !selection_.has_value()
        || !contains(*selection_, grabPoint)) {
        return false;
    }

    grabOffset_ = {
        saturatingSubtract(grabPoint.x, selection_->x),
        saturatingSubtract(grabPoint.y, selection_->y),
    };
    phase_ = SelectionPhase::moving;
    activeHandle_ = SelectionHandle::body;
    return true;
}

bool SelectionModel::beginResize(SelectionHandle handle, PixelPoint grabPoint) noexcept
{
    if (phase_ != SelectionPhase::ready || !selection_.has_value()
        || !isResizeHandle(handle)) {
        return false;
    }

    const auto rect = *selection_;
    const auto right = rightEdge(rect);
    const auto bottom = bottomEdge(rect);

    resizeHorizontalSide_ = hasWest(handle) ? -1 : hasEast(handle) ? 1 : 0;
    resizeVerticalSide_ = hasNorth(handle) ? -1 : hasSouth(handle) ? 1 : 0;
    fixedResizeX_ = hasWest(handle) ? right : rect.x;
    fixedResizeY_ = hasNorth(handle) ? bottom : rect.y;

    const auto movingX = hasWest(handle) ? rect.x : right;
    const auto movingY = hasNorth(handle) ? rect.y : bottom;
    grabOffset_ = {
        resizeHorizontalSide_ == 0 ? 0 : saturatingSubtract(grabPoint.x, movingX),
        resizeVerticalSide_ == 0 ? 0 : saturatingSubtract(grabPoint.y, movingY),
    };

    phase_ = SelectionPhase::resizing;
    activeHandle_ = handle;
    return true;
}

void SelectionModel::updateInteraction(PixelPoint pointer) noexcept
{
    if (phase_ == SelectionPhase::creating) {
        const auto clamped = clampPoint(pointer, virtualBounds_);
        const auto rect = snipory::core::portable::standardized(PixelRect{
            creationAnchor_.x,
            creationAnchor_.y,
            saturatingSubtract(clamped.x, creationAnchor_.x),
            saturatingSubtract(clamped.y, creationAnchor_.y),
        });
        if (hasArea(rect)) {
            selection_ = rect;
        } else {
            selection_.reset();
        }
        return;
    }

    if (phase_ == SelectionPhase::moving && selection_.has_value()) {
        const auto maximumX = saturatingSubtract(rightEdge(virtualBounds_), selection_->width);
        const auto maximumY = saturatingSubtract(bottomEdge(virtualBounds_), selection_->height);
        selection_->x = clampCoordinate(
            saturatingSubtract(pointer.x, grabOffset_.x), virtualBounds_.x, maximumX);
        selection_->y = clampCoordinate(
            saturatingSubtract(pointer.y, grabOffset_.y), virtualBounds_.y, maximumY);
        return;
    }

    if (phase_ != SelectionPhase::resizing || !selection_.has_value()) {
        return;
    }

    auto movingX = fixedResizeX_;
    auto movingY = fixedResizeY_;
    if (resizeHorizontalSide_ != 0) {
        movingX = clampCoordinate(
            saturatingSubtract(pointer.x, grabOffset_.x),
            virtualBounds_.x,
            rightEdge(virtualBounds_));
        if (movingX < fixedResizeX_) {
            resizeHorizontalSide_ = -1;
        } else if (movingX > fixedResizeX_) {
            resizeHorizontalSide_ = 1;
        } else {
            movingX = onePixelFrom(
                fixedResizeX_,
                resizeHorizontalSide_,
                virtualBounds_.x,
                rightEdge(virtualBounds_));
        }
    }
    if (resizeVerticalSide_ != 0) {
        movingY = clampCoordinate(
            saturatingSubtract(pointer.y, grabOffset_.y),
            virtualBounds_.y,
            bottomEdge(virtualBounds_));
        if (movingY < fixedResizeY_) {
            resizeVerticalSide_ = -1;
        } else if (movingY > fixedResizeY_) {
            resizeVerticalSide_ = 1;
        } else {
            movingY = onePixelFrom(
                fixedResizeY_,
                resizeVerticalSide_,
                virtualBounds_.y,
                bottomEdge(virtualBounds_));
        }
    }

    const auto current = *selection_;
    const auto left = resizeHorizontalSide_ == 0 ? current.x : std::min(fixedResizeX_, movingX);
    const auto top = resizeVerticalSide_ == 0 ? current.y : std::min(fixedResizeY_, movingY);
    const auto right = resizeHorizontalSide_ == 0
        ? rightEdge(current)
        : std::max(fixedResizeX_, movingX);
    const auto bottom = resizeVerticalSide_ == 0
        ? bottomEdge(current)
        : std::max(fixedResizeY_, movingY);
    selection_ = PixelRect{
        left,
        top,
        saturatingSubtract(right, left),
        saturatingSubtract(bottom, top),
    };
    activeHandle_ = handleForSides(resizeHorizontalSide_, resizeVerticalSide_);
}

void SelectionModel::finishInteraction() noexcept
{
    if (phase_ == SelectionPhase::creating) {
        phase_ = selection_.has_value() ? SelectionPhase::ready : SelectionPhase::empty;
    } else if (phase_ == SelectionPhase::moving || phase_ == SelectionPhase::resizing) {
        phase_ = SelectionPhase::ready;
    }
    activeHandle_ = SelectionHandle::none;
}

SelectionHandle SelectionModel::hitTest(
    PixelPoint point, std::int64_t handleRadius) const noexcept
{
    if (!selection_.has_value()) {
        return SelectionHandle::none;
    }

    const auto rect = *selection_;
    const auto right = rightEdge(rect);
    const auto bottom = bottomEdge(rect);
    const auto middleX = saturatingAdd(rect.x, rect.width / 2);
    const auto middleY = saturatingAdd(rect.y, rect.height / 2);
    const auto radius = handleRadius > 0
        ? static_cast<std::uint64_t>(handleRadius)
        : std::uint64_t{0};

    constexpr std::array<SelectionHandle, 8> handles{
        SelectionHandle::northWest,
        SelectionHandle::northEast,
        SelectionHandle::southEast,
        SelectionHandle::southWest,
        SelectionHandle::north,
        SelectionHandle::east,
        SelectionHandle::south,
        SelectionHandle::west,
    };
    const std::array<PixelPoint, 8> points{
        PixelPoint{rect.x, rect.y},
        PixelPoint{right, rect.y},
        PixelPoint{right, bottom},
        PixelPoint{rect.x, bottom},
        PixelPoint{middleX, rect.y},
        PixelPoint{right, middleY},
        PixelPoint{middleX, bottom},
        PixelPoint{rect.x, middleY},
    };

    auto nearestHandle = SelectionHandle::none;
    auto nearestDistance = std::numeric_limits<std::uint64_t>::max();
    for (std::size_t index = 0; index < handles.size(); ++index) {
        const auto distance = chebyshevDistance(point, points[index]);
        if (distance <= radius && distance < nearestDistance) {
            nearestHandle = handles[index];
            nearestDistance = distance;
        }
    }
    if (nearestHandle != SelectionHandle::none) {
        return nearestHandle;
    }
    return contains(rect, point) ? SelectionHandle::body : SelectionHandle::none;
}

} // namespace xxsnap::win
