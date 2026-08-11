#pragma once

#include "capture/CaptureTypes.h"
#include "snipory/core/portable/PixelBuffer.h"

#include <chrono>
#include <utility>
#include <variant>
#include <vector>

namespace xxsnap::win {

using snipory::core::portable::MemoryBudget;
using snipory::core::portable::PixelBuffer;

struct FrozenDisplay {
    FrozenDisplay(DisplayDescriptor sourceDescriptor, PixelBuffer sourcePixels) noexcept
        : descriptor(std::move(sourceDescriptor))
        , pixels(std::move(sourcePixels))
    {
    }

    FrozenDisplay(const FrozenDisplay&) = delete;
    FrozenDisplay& operator=(const FrozenDisplay&) = delete;
    FrozenDisplay(FrozenDisplay&&) noexcept = default;
    FrozenDisplay& operator=(FrozenDisplay&&) noexcept = default;

    DisplayDescriptor descriptor;
    PixelBuffer pixels;
};

struct FrozenDesktop {
    FrozenDesktop(
        DisplayTopologySnapshot sourceTopology,
        std::vector<FrozenDisplay> sourceDisplays,
        std::chrono::steady_clock::time_point sourceCapturedAt) noexcept
        : topology(std::move(sourceTopology))
        , displays(std::move(sourceDisplays))
        , capturedAt(sourceCapturedAt)
    {
    }

    FrozenDesktop(const FrozenDesktop&) = delete;
    FrozenDesktop& operator=(const FrozenDesktop&) = delete;
    FrozenDesktop(FrozenDesktop&&) noexcept = default;
    FrozenDesktop& operator=(FrozenDesktop&&) = delete;

    DisplayTopologySnapshot topology;
    std::vector<FrozenDisplay> displays;
    std::chrono::steady_clock::time_point capturedAt;
};

enum class CaptureErrorCode {
    accessDenied,
    deviceLost,
    unsupported,
    noFrame,
    memoryLimit,
    topologyChanged,
    systemFailure,
    invalidSize,
    arithmeticOverflow,
};

struct CaptureError {
    CaptureErrorCode code;
    HRESULT nativeCode;
};

using CaptureResult = std::variant<FrozenDesktop, CaptureError>;

class CaptureBackend {
public:
    virtual ~CaptureBackend() = default;

    virtual CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget) noexcept = 0;
};

} // namespace xxsnap::win
