#pragma once

#include <algorithm>
#include <cstdint>
#include <limits>
#include <optional>

namespace snipory::core::portable {

struct PixelPoint {
    std::int64_t x;
    std::int64_t y;
};

constexpr bool operator==(PixelPoint lhs, PixelPoint rhs) noexcept
{
    return lhs.x == rhs.x && lhs.y == rhs.y;
}

constexpr bool operator!=(PixelPoint lhs, PixelPoint rhs) noexcept
{
    return !(lhs == rhs);
}

struct PixelSize {
    std::int64_t width;
    std::int64_t height;
};

constexpr bool operator==(PixelSize lhs, PixelSize rhs) noexcept
{
    return lhs.width == rhs.width && lhs.height == rhs.height;
}

constexpr bool operator!=(PixelSize lhs, PixelSize rhs) noexcept
{
    return !(lhs == rhs);
}

struct PixelRect {
    std::int64_t x;
    std::int64_t y;
    std::int64_t width;
    std::int64_t height;
};

constexpr bool operator==(PixelRect lhs, PixelRect rhs) noexcept
{
    return lhs.x == rhs.x
        && lhs.y == rhs.y
        && lhs.width == rhs.width
        && lhs.height == rhs.height;
}

constexpr bool operator!=(PixelRect lhs, PixelRect rhs) noexcept
{
    return !(lhs == rhs);
}

namespace detail {

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

constexpr std::int64_t nonnegativeDifference(std::int64_t upper, std::int64_t lower) noexcept
{
    const auto difference = static_cast<std::uint64_t>(upper) - static_cast<std::uint64_t>(lower);
    const auto maximum = static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max());
    return difference > maximum
        ? std::numeric_limits<std::int64_t>::max()
        : static_cast<std::int64_t>(difference);
}

} // namespace detail

constexpr PixelRect standardized(PixelRect rect) noexcept
{
    const auto oppositeX = detail::saturatingAdd(rect.x, rect.width);
    const auto oppositeY = detail::saturatingAdd(rect.y, rect.height);
    const auto minimumX = std::min(rect.x, oppositeX);
    const auto minimumY = std::min(rect.y, oppositeY);
    const auto maximumX = std::max(rect.x, oppositeX);
    const auto maximumY = std::max(rect.y, oppositeY);

    return {
        minimumX,
        minimumY,
        detail::nonnegativeDifference(maximumX, minimumX),
        detail::nonnegativeDifference(maximumY, minimumY),
    };
}

constexpr std::optional<PixelRect> intersection(PixelRect lhs, PixelRect rhs) noexcept
{
    const auto lhsOppositeX = detail::saturatingAdd(lhs.x, lhs.width);
    const auto lhsOppositeY = detail::saturatingAdd(lhs.y, lhs.height);
    const auto rhsOppositeX = detail::saturatingAdd(rhs.x, rhs.width);
    const auto rhsOppositeY = detail::saturatingAdd(rhs.y, rhs.height);

    const auto lhsMinimumX = std::min(lhs.x, lhsOppositeX);
    const auto lhsMinimumY = std::min(lhs.y, lhsOppositeY);
    const auto lhsMaximumX = std::max(lhs.x, lhsOppositeX);
    const auto lhsMaximumY = std::max(lhs.y, lhsOppositeY);
    const auto rhsMinimumX = std::min(rhs.x, rhsOppositeX);
    const auto rhsMinimumY = std::min(rhs.y, rhsOppositeY);
    const auto rhsMaximumX = std::max(rhs.x, rhsOppositeX);
    const auto rhsMaximumY = std::max(rhs.y, rhsOppositeY);

    const auto left = std::max(lhsMinimumX, rhsMinimumX);
    const auto top = std::max(lhsMinimumY, rhsMinimumY);
    const auto right = std::min(lhsMaximumX, rhsMaximumX);
    const auto bottom = std::min(lhsMaximumY, rhsMaximumY);

    if (right <= left || bottom <= top) {
        return std::nullopt;
    }

    return PixelRect{
        left,
        top,
        detail::nonnegativeDifference(right, left),
        detail::nonnegativeDifference(bottom, top),
    };
}

constexpr std::optional<std::uint64_t> checkedByteCount(
    std::int64_t width,
    std::int64_t height,
    std::int64_t bytesPerPixel) noexcept
{
    if (width <= 0 || height <= 0 || bytesPerPixel <= 0) {
        return std::nullopt;
    }

    const auto unsignedWidth = static_cast<std::uint64_t>(width);
    const auto unsignedHeight = static_cast<std::uint64_t>(height);
    const auto unsignedBytesPerPixel = static_cast<std::uint64_t>(bytesPerPixel);
    constexpr auto maximum = std::numeric_limits<std::uint64_t>::max();

    if (unsignedWidth > maximum / unsignedHeight) {
        return std::nullopt;
    }
    const auto pixels = unsignedWidth * unsignedHeight;
    if (pixels > maximum / unsignedBytesPerPixel) {
        return std::nullopt;
    }

    return pixels * unsignedBytesPerPixel;
}

} // namespace snipory::core::portable
