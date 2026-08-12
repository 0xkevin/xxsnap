#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "snipory/core/portable/Geometry.h"

#include <Windows.h>

#include <optional>
#include <vector>

namespace xxsnap::win {

using snipory::core::portable::PixelPoint;
using snipory::core::portable::PixelRect;

struct ScrollCaptureTargetCandidate {
    PixelRect bounds{};
    int firstProbeIndex = 0;
};

std::vector<PixelPoint> scrollCaptureProbePoints(PixelRect selection);

std::optional<PixelRect> bestScrollCaptureTarget(
    PixelRect selection,
    const std::vector<ScrollCaptureTargetCandidate>& candidates,
    std::int64_t minimumWidth,
    std::int64_t minimumHeight) noexcept;

class ScrollCaptureTargetDetector final {
public:
    std::optional<PixelRect> detect(
        PixelRect selection,
        DWORD targetProcessId,
        UINT dpiX,
        UINT dpiY) const noexcept;
};

} // namespace xxsnap::win
