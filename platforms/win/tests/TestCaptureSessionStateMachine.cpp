#include "session/CaptureSessionStateMachine.h"

#include <array>
#include <cstddef>
#include <iostream>

namespace {

using xxsnap::win::CaptureSessionState;
using xxsnap::win::CaptureSessionStateMachine;
using xxsnap::win::SessionEvent;
using xxsnap::win::TransitionResult;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

struct TransitionCase {
    CaptureSessionState initialState;
    SessionEvent event;
    TransitionResult expectedResult;
    CaptureSessionState expectedState;
};

CaptureSessionStateMachine machineIn(CaptureSessionState targetState)
{
    CaptureSessionStateMachine machine;

    if (targetState == CaptureSessionState::idle) {
        return machine;
    }

    CHECK(machine.dispatch(SessionEvent::start) == TransitionResult::accepted);
    if (targetState == CaptureSessionState::capturing) {
        return machine;
    }

    CHECK(machine.dispatch(SessionEvent::captureSucceeded) == TransitionResult::accepted);
    if (targetState == CaptureSessionState::selecting) {
        return machine;
    }

    CHECK(machine.dispatch(SessionEvent::selectionCreated) == TransitionResult::accepted);
    if (targetState == CaptureSessionState::ready) {
        return machine;
    }

    CHECK(machine.dispatch(SessionEvent::exportStarted) == TransitionResult::accepted);
    return machine;
}

constexpr std::array<TransitionCase, 40> transitions{{
    {CaptureSessionState::idle, SessionEvent::start, TransitionResult::accepted,
     CaptureSessionState::capturing},
    {CaptureSessionState::idle, SessionEvent::captureSucceeded,
     TransitionResult::invalidTransition, CaptureSessionState::idle},
    {CaptureSessionState::idle, SessionEvent::selectionCreated,
     TransitionResult::invalidTransition, CaptureSessionState::idle},
    {CaptureSessionState::idle, SessionEvent::resumeSelection,
     TransitionResult::invalidTransition, CaptureSessionState::idle},
    {CaptureSessionState::idle, SessionEvent::exportStarted,
     TransitionResult::invalidTransition, CaptureSessionState::idle},
    {CaptureSessionState::idle, SessionEvent::complete,
     TransitionResult::invalidTransition, CaptureSessionState::idle},
    {CaptureSessionState::idle, SessionEvent::cancel,
     TransitionResult::invalidTransition, CaptureSessionState::idle},
    {CaptureSessionState::idle, SessionEvent::fail,
     TransitionResult::invalidTransition, CaptureSessionState::idle},

    {CaptureSessionState::capturing, SessionEvent::start, TransitionResult::busy,
     CaptureSessionState::capturing},
    {CaptureSessionState::capturing, SessionEvent::captureSucceeded,
     TransitionResult::accepted, CaptureSessionState::selecting},
    {CaptureSessionState::capturing, SessionEvent::selectionCreated,
     TransitionResult::invalidTransition, CaptureSessionState::capturing},
    {CaptureSessionState::capturing, SessionEvent::resumeSelection,
     TransitionResult::invalidTransition, CaptureSessionState::capturing},
    {CaptureSessionState::capturing, SessionEvent::exportStarted,
     TransitionResult::invalidTransition, CaptureSessionState::capturing},
    {CaptureSessionState::capturing, SessionEvent::complete,
     TransitionResult::invalidTransition, CaptureSessionState::capturing},
    {CaptureSessionState::capturing, SessionEvent::cancel, TransitionResult::accepted,
     CaptureSessionState::idle},
    {CaptureSessionState::capturing, SessionEvent::fail, TransitionResult::accepted,
     CaptureSessionState::idle},

    {CaptureSessionState::selecting, SessionEvent::start, TransitionResult::busy,
     CaptureSessionState::selecting},
    {CaptureSessionState::selecting, SessionEvent::captureSucceeded,
     TransitionResult::invalidTransition, CaptureSessionState::selecting},
    {CaptureSessionState::selecting, SessionEvent::selectionCreated,
     TransitionResult::accepted, CaptureSessionState::ready},
    {CaptureSessionState::selecting, SessionEvent::resumeSelection,
     TransitionResult::invalidTransition, CaptureSessionState::selecting},
    {CaptureSessionState::selecting, SessionEvent::exportStarted,
     TransitionResult::invalidTransition, CaptureSessionState::selecting},
    {CaptureSessionState::selecting, SessionEvent::complete,
     TransitionResult::invalidTransition, CaptureSessionState::selecting},
    {CaptureSessionState::selecting, SessionEvent::cancel, TransitionResult::accepted,
     CaptureSessionState::idle},
    {CaptureSessionState::selecting, SessionEvent::fail, TransitionResult::accepted,
     CaptureSessionState::idle},

    {CaptureSessionState::ready, SessionEvent::start, TransitionResult::busy,
     CaptureSessionState::ready},
    {CaptureSessionState::ready, SessionEvent::captureSucceeded,
     TransitionResult::invalidTransition, CaptureSessionState::ready},
    {CaptureSessionState::ready, SessionEvent::selectionCreated,
     TransitionResult::invalidTransition, CaptureSessionState::ready},
    {CaptureSessionState::ready, SessionEvent::resumeSelection,
     TransitionResult::accepted, CaptureSessionState::selecting},
    {CaptureSessionState::ready, SessionEvent::exportStarted,
     TransitionResult::accepted, CaptureSessionState::exporting},
    {CaptureSessionState::ready, SessionEvent::complete,
     TransitionResult::invalidTransition, CaptureSessionState::ready},
    {CaptureSessionState::ready, SessionEvent::cancel, TransitionResult::accepted,
     CaptureSessionState::idle},
    {CaptureSessionState::ready, SessionEvent::fail, TransitionResult::accepted,
     CaptureSessionState::idle},

    {CaptureSessionState::exporting, SessionEvent::start, TransitionResult::busy,
     CaptureSessionState::exporting},
    {CaptureSessionState::exporting, SessionEvent::captureSucceeded,
     TransitionResult::invalidTransition, CaptureSessionState::exporting},
    {CaptureSessionState::exporting, SessionEvent::selectionCreated,
     TransitionResult::invalidTransition, CaptureSessionState::exporting},
    {CaptureSessionState::exporting, SessionEvent::resumeSelection,
     TransitionResult::invalidTransition, CaptureSessionState::exporting},
    {CaptureSessionState::exporting, SessionEvent::exportStarted,
     TransitionResult::invalidTransition, CaptureSessionState::exporting},
    {CaptureSessionState::exporting, SessionEvent::complete, TransitionResult::accepted,
     CaptureSessionState::idle},
    {CaptureSessionState::exporting, SessionEvent::cancel, TransitionResult::accepted,
     CaptureSessionState::idle},
    {CaptureSessionState::exporting, SessionEvent::fail, TransitionResult::accepted,
     CaptureSessionState::idle},
}};

static_assert(transitions.size() == 5U * 8U);

} // namespace

int main()
{
    CaptureSessionStateMachine initialMachine;
    CHECK(initialMachine.state() == CaptureSessionState::idle);

    for (const auto& transition : transitions) {
        auto machine = machineIn(transition.initialState);
        CHECK(machine.state() == transition.initialState);

        const auto result = machine.dispatch(transition.event);

        CHECK(result == transition.expectedResult);
        CHECK(machine.state() == transition.expectedState);
    }

    return failureCount == 0 ? 0 : 1;
}
