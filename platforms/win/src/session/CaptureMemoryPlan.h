#pragma once

#include "capture/CaptureTypes.h"

#include <cstdint>
#include <vector>

namespace xxsnap::win {

enum class CaptureMemoryPlanStatus {
    fits,
    invalidSize,
    arithmeticOverflow,
    budgetExceeded,
};

struct CaptureMemoryPlan {
    CaptureMemoryPlanStatus status = CaptureMemoryPlanStatus::fits;
    std::uint64_t requiredBytes = 0;
};

CaptureMemoryPlan planFrozenDesktopMemory(
    const std::vector<DisplayDescriptor>& displays,
    std::uint64_t limitBytes) noexcept;

} // namespace xxsnap::win
