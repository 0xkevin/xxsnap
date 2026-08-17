#pragma once

#include "snipory/core/portable/PixelBuffer.h"
#include "snipory/core/scroll/ScrollStitchSession.h"

#include <cstddef>
#include <optional>

namespace xxsnap::win {

enum class ScrollCapturePhase {
    idle,
    capturing,
    paused,
    finished,
    cancelled,
};

enum class ScrollCaptureWarning {
    lowConfidence,
};

enum class ScrollCapturePauseReason {
    captureFailure,
    resourceLimit,
    maximumHeightReached,
};

struct ScrollCaptureUpdate {
    snipory::core::scroll::AppendResult append;
    std::optional<snipory::core::scroll::ScrollFrame> preview;
    std::optional<ScrollCaptureWarning> warning;
    ScrollCapturePhase phase = ScrollCapturePhase::idle;
};

class ScrollCaptureSession final {
public:
    explicit ScrollCaptureSession(std::size_t maximumAcceptedBytes);

    bool start(
        snipory::core::scroll::ScrollFrame seed,
        ScrollCaptureUpdate& update) noexcept;
    bool append(
        snipory::core::scroll::ScrollFrame frame,
        int wheelDelta,
        ScrollCaptureUpdate& update) noexcept;
    std::optional<snipory::core::portable::PixelBuffer> finish(
        std::size_t maximumAcceptedBytes) noexcept;
    void pause(ScrollCapturePauseReason reason) noexcept;
    void cancel() noexcept;

    ScrollCapturePhase phase() const noexcept;
    std::optional<ScrollCaptureWarning> warning() const noexcept;
    std::optional<ScrollCapturePauseReason> pauseReason() const noexcept;
    int outputHeight() const noexcept;

    static snipory::core::scroll::ScrollDirection directionForWheelDelta(
        int wheelDelta) noexcept;
    static bool requiresSaveOnlyForHeight(int outputHeight) noexcept;

private:
    bool updateAfterAppend(
        const snipory::core::scroll::AppendResult& result,
        ScrollCaptureUpdate& update);

    snipory::core::scroll::ScrollStitchSession stitcher_;
    ScrollCapturePhase phase_ = ScrollCapturePhase::idle;
    std::optional<ScrollCaptureWarning> warning_;
    std::optional<ScrollCapturePauseReason> pauseReason_;
};

} // namespace xxsnap::win
