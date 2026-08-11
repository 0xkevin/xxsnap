#pragma once

#include "capture/CaptureBackend.h"

#include <cstddef>
#include <memory>
#include <optional>

namespace xxsnap::win {

class ResettableCaptureBackend : public CaptureBackend {
public:
    ~ResettableCaptureBackend() override = default;

    virtual void reset() noexcept = 0;
};

struct DxgiCaptureCacheKey {
    std::wstring deviceName;
    PixelRect pixelBounds;
    DISPLAYCONFIG_ROTATION rotation;
};

enum class DxgiCaptureCacheDecision {
    reuse,
    rebuild,
    noMatch,
};

DxgiCaptureCacheDecision decideDxgiCaptureCache(
    const DisplayDescriptor& requested,
    const DxgiCaptureCacheKey& cached) noexcept;

CaptureError mapDxgiError(HRESULT nativeCode) noexcept;

std::optional<CaptureError> copyMappedBgra(
    const std::byte* source,
    std::size_t sourceRowPitch,
    std::int64_t sourceWidth,
    std::int64_t sourceHeight,
    DISPLAYCONFIG_ROTATION rotation,
    PixelBuffer& destination) noexcept;

// MVP capture sessions call capture() and reset() from one session thread.
// reset() releases every cached duplication, D3D device, and device context;
// the next capture rebuilds them from the supplied topology snapshot.
class DxgiCaptureBackend final : public ResettableCaptureBackend {
public:
    DxgiCaptureBackend();
    ~DxgiCaptureBackend() override;

    DxgiCaptureBackend(const DxgiCaptureBackend&) = delete;
    DxgiCaptureBackend& operator=(const DxgiCaptureBackend&) = delete;

    CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget) noexcept override;

    void reset() noexcept override;

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
