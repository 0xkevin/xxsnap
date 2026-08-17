#pragma once

#include "capture/GdiCaptureBackend.h"
#include "snipory/core/scroll/ScrollFrame.h"

#include <cstddef>
#include <optional>

namespace xxsnap::win {

class ScrollRegionCapturer final {
public:
    explicit ScrollRegionCapturer(std::size_t maximumFrameBytes) noexcept;
    ScrollRegionCapturer(
        GdiCaptureApis apis,
        std::size_t maximumFrameBytes) noexcept;

    std::optional<snipory::core::scroll::ScrollFrame> capture(
        PixelRect physicalRegion) noexcept;

private:
    GdiCaptureBackend backend_;
    std::size_t maximumFrameBytes_;
};

} // namespace xxsnap::win
