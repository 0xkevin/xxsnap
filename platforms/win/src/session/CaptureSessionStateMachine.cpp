#include "session/CaptureSessionStateMachine.h"

namespace xxsnap::win {

TransitionResult CaptureSessionStateMachine::dispatch(SessionEvent event) noexcept
{
    if (event == SessionEvent::start) {
        if (state_ != CaptureSessionState::idle) {
            return TransitionResult::busy;
        }

        state_ = CaptureSessionState::capturing;
        return TransitionResult::accepted;
    }

    if (event == SessionEvent::cancel || event == SessionEvent::fail) {
        if (state_ == CaptureSessionState::idle) {
            return TransitionResult::invalidTransition;
        }

        state_ = CaptureSessionState::idle;
        return TransitionResult::accepted;
    }

    switch (state_) {
    case CaptureSessionState::capturing:
        if (event == SessionEvent::captureSucceeded) {
            state_ = CaptureSessionState::selecting;
            return TransitionResult::accepted;
        }
        break;
    case CaptureSessionState::selecting:
        if (event == SessionEvent::selectionCreated) {
            state_ = CaptureSessionState::ready;
            return TransitionResult::accepted;
        }
        break;
    case CaptureSessionState::ready:
        if (event == SessionEvent::resumeSelection) {
            state_ = CaptureSessionState::selecting;
            return TransitionResult::accepted;
        }
        if (event == SessionEvent::exportStarted) {
            state_ = CaptureSessionState::exporting;
            return TransitionResult::accepted;
        }
        break;
    case CaptureSessionState::exporting:
        if (event == SessionEvent::complete) {
            state_ = CaptureSessionState::idle;
            return TransitionResult::accepted;
        }
        break;
    case CaptureSessionState::idle:
        break;
    }

    return TransitionResult::invalidTransition;
}

CaptureSessionState CaptureSessionStateMachine::state() const noexcept
{
    return state_;
}

} // namespace xxsnap::win
