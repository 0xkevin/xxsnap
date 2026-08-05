#pragma once

#include "capture/DxgiCaptureBackend.h"

namespace xxsnap::win {

class FallbackCaptureBackend final : public CaptureBackend {
public:
    FallbackCaptureBackend(
        ResettableCaptureBackend& preferred,
        CaptureBackend& fallback) noexcept;

    CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget) noexcept override;

private:
    ResettableCaptureBackend& preferred_;
    CaptureBackend& fallback_;
};

} // namespace xxsnap::win
