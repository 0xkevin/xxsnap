#pragma once

namespace xxsnap::win {

enum class CaptureSessionState {
    idle,
    capturing,
    selecting,
    ready,
    exporting,
};

enum class SessionEvent {
    start,
    captureSucceeded,
    selectionCreated,
    resumeSelection,
    exportStarted,
    complete,
    cancel,
    fail,
};

enum class TransitionResult {
    accepted,
    busy,
    invalidTransition,
};

class CaptureSessionStateMachine final {
public:
    TransitionResult dispatch(SessionEvent event) noexcept;
    CaptureSessionState state() const noexcept;

private:
    CaptureSessionState state_ = CaptureSessionState::idle;
};

} // namespace xxsnap::win
