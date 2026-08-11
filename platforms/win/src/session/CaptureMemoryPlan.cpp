#include "session/CaptureMemoryPlan.h"

#include "snipory/core/portable/Geometry.h"

#include <limits>

namespace xxsnap::win {

CaptureMemoryPlan planFrozenDesktopMemory(
    const std::vector<DisplayDescriptor>& displays,
    std::uint64_t limitBytes) noexcept
{
    std::uint64_t total = 0;
    for (const auto& display : displays) {
        const auto width = display.pixelBounds.width;
        const auto height = display.pixelBounds.height;
        if (width <= 0 || height <= 0) {
            return {CaptureMemoryPlanStatus::invalidSize, total};
        }
        const auto bytes = snipory::core::portable::checkedByteCount(
            width, height, 4);
        if (!bytes.has_value()
            || *bytes > (std::numeric_limits<std::uint64_t>::max)() - total) {
            return {CaptureMemoryPlanStatus::arithmeticOverflow, total};
        }
        total += *bytes;
        if (total > limitBytes) {
            return {CaptureMemoryPlanStatus::budgetExceeded, total};
        }
    }
    return {CaptureMemoryPlanStatus::fits, total};
}

} // namespace xxsnap::win
