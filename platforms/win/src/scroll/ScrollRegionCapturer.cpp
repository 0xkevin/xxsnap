#include "scroll/ScrollRegionCapturer.h"

#include "capture/DisplayTopology.h"

#include <cstring>
#include <limits>
#include <utility>
#include <variant>

namespace xxsnap::win {
namespace {

bool validRegion(PixelRect region, std::size_t maximumBytes) noexcept
{
    region = snipory::core::portable::standardized(region);
    constexpr auto intMaximum = (std::numeric_limits<int>::max)();
    constexpr auto intMinimum = (std::numeric_limits<int>::min)();
    if (region.width <= 0 || region.height <= 0
        || region.x < intMinimum || region.x > intMaximum
        || region.y < intMinimum || region.y > intMaximum
        || region.width > intMaximum || region.height > intMaximum) {
        return false;
    }
    const auto width = static_cast<std::size_t>(region.width);
    const auto height = static_cast<std::size_t>(region.height);
    return width <= (std::numeric_limits<std::size_t>::max)() / 4U
        && height <= maximumBytes / (width * 4U);
}

} // namespace

ScrollRegionCapturer::ScrollRegionCapturer(
    std::size_t maximumFrameBytes) noexcept
    : maximumFrameBytes_(maximumFrameBytes)
{
}

ScrollRegionCapturer::ScrollRegionCapturer(
    GdiCaptureApis apis,
    std::size_t maximumFrameBytes) noexcept
    : backend_(std::move(apis))
    , maximumFrameBytes_(maximumFrameBytes)
{
}

std::optional<snipory::core::scroll::ScrollFrame>
ScrollRegionCapturer::capture(PixelRect physicalRegion) noexcept
{
    physicalRegion = snipory::core::portable::standardized(physicalRegion);
    if (!validRegion(physicalRegion, maximumFrameBytes_)) {
        return std::nullopt;
    }
    try {
        const DisplayDescriptor descriptor{
            L"XXSNAP_SCROLL_CAPTURE",
            physicalRegion,
            96U,
            96U,
            DISPLAYCONFIG_ROTATION_IDENTITY,
        };
        const auto topology = buildDisplayTopologySnapshot({descriptor});
        if (!topology.hasValue()) return std::nullopt;
        MemoryBudget budget(static_cast<std::uint64_t>(maximumFrameBytes_));
        auto capture = backend_.capture(*topology.value(), budget);
        auto* desktop = std::get_if<FrozenDesktop>(&capture);
        if (desktop == nullptr || desktop->displays.size() != 1U) {
            return std::nullopt;
        }
        const auto& pixels = desktop->displays.front().pixels;
        snipory::core::scroll::ScrollFrame frame(
            static_cast<int>(pixels.width()),
            static_cast<int>(pixels.height()));
        if (!frame.isValid()
            || pixels.stride() != static_cast<std::uint64_t>(frame.bytesPerRow)
            || pixels.byteCount() != frame.pixels.size()) {
            return std::nullopt;
        }
        std::memcpy(frame.pixels.data(), pixels.data(), pixels.byteCount());
        return frame;
    } catch (...) {
        return std::nullopt;
    }
}

} // namespace xxsnap::win
