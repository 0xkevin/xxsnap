#pragma once

#include "capture/DxgiCaptureBackend.h"

namespace xxsnap::win {

enum class CaptureBackendKind {
    preferred,
    fallback,
};

class FallbackCaptureBackend final : public CaptureBackend {
public:
    FallbackCaptureBackend(
        ResettableCaptureBackend& preferred,
        CaptureBackend& fallback) noexcept;

    CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget) noexcept override;

    CaptureBackendKind lastBackend() const noexcept;

private:
    ResettableCaptureBackend& preferred_;
    CaptureBackend& fallback_;
    CaptureBackendKind lastBackend_ = CaptureBackendKind::preferred;
};

} // namespace xxsnap::win
