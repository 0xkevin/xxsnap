#pragma once

#include <limits>
#include <optional>

namespace xxsnap::win {

class ScrollCaptureSamplingState final {
public:
    void noteWheel(int delta) noexcept
    {
        if (delta == 0) return;
        const auto combined = static_cast<long long>(pendingWheelDelta_)
            + static_cast<long long>(delta);
        pendingWheelDelta_ = static_cast<int>(
            combined < (std::numeric_limits<int>::min)()
                ? (std::numeric_limits<int>::min)()
                : combined > (std::numeric_limits<int>::max)()
                    ? (std::numeric_limits<int>::max)()
                    : combined);
        samplePending_ = true;
    }

    void beginPointerDrag(bool capturesTarget) noexcept
    {
        pointerDragActive_ = capturesTarget;
    }

    void notePointerMove() noexcept
    {
        if (pointerDragActive_) samplePending_ = true;
    }

    void endPointerDrag() noexcept
    {
        if (pointerDragActive_) samplePending_ = true;
        pointerDragActive_ = false;
    }

    bool hasPendingSample() const noexcept { return samplePending_; }

    std::optional<int> takePendingWheelDelta() noexcept
    {
        if (!samplePending_) return std::nullopt;
        samplePending_ = false;
        const auto result = pendingWheelDelta_;
        pendingWheelDelta_ = 0;
        return result;
    }

private:
    int pendingWheelDelta_ = 0;
    bool pointerDragActive_ = false;
    bool samplePending_ = false;
};

} // namespace xxsnap::win
