#include "session/CaptureSessionCoordinator.h"

#include "session/CaptureMemoryPlan.h"

#include <new>
#include <utility>
#include <variant>

namespace xxsnap::win {

struct CaptureSessionCoordinator::CallbackState final {
    CaptureSessionCoordinator* owner = nullptr;
};

CaptureSessionCoordinator::CaptureSessionCoordinator(
    CaptureSessionServices& services,
    std::uint64_t memoryLimitBytes)
    : services_(services)
    , memoryLimitBytes_(memoryLimitBytes)
    , callbacks_(std::make_shared<CallbackState>())
{
    callbacks_->owner = this;
}

CaptureSessionCoordinator::~CaptureSessionCoordinator()
{
    callbacks_->owner = nullptr;
    releaseSession();
}

CaptureSessionStartResult CaptureSessionCoordinator::start() noexcept
{
    return startSession(true);
}

void CaptureSessionCoordinator::displayConfigurationChanged() noexcept
{
    restart();
}

CaptureSessionStartResult CaptureSessionCoordinator::startSession(
    bool newRequest) noexcept
{
    const auto transition = stateMachine_.dispatch(SessionEvent::start);
    if (transition == TransitionResult::busy) {
        return CaptureSessionStartResult::busy;
    }
    if (transition != TransitionResult::accepted) {
        return CaptureSessionStartResult::failed;
    }

    lastError_.reset();
    if (newRequest) {
        topologyRetryUsed_ = false;
        recentCapture_.reset();
    }
    const auto generation = ++generation_;
    try {
        for (;;) {
            auto topologyResult = services_.snapshotTopology();
            const auto* topology = topologyResult.value();
            if (topology == nullptr) {
                fail(CaptureSessionErrorCode::topologyFailed);
                return CaptureSessionStartResult::failed;
            }

            const auto memoryPlan = planFrozenDesktopMemory(
                topology->displays(), memoryLimitBytes_);
            if (memoryPlan.status != CaptureMemoryPlanStatus::fits) {
                fail(CaptureSessionErrorCode::memoryLimitExceeded);
                return CaptureSessionStartResult::failed;
            }

            budget_ = std::make_unique<MemoryBudget>(memoryLimitBytes_);
            auto captureResult = services_.capture(*topology, *budget_);
            if (!std::holds_alternative<FrozenDesktop>(captureResult)) {
                fail(CaptureSessionErrorCode::captureFailed);
                return CaptureSessionStartResult::failed;
            }
            desktop_ = std::make_unique<FrozenDesktop>(
                std::move(std::get<FrozenDesktop>(captureResult)));

            auto verifiedResult = services_.snapshotTopology();
            const auto* verified = verifiedResult.value();
            if (verified == nullptr) {
                fail(CaptureSessionErrorCode::topologyFailed);
                return CaptureSessionStartResult::failed;
            }
            if (desktop_->topology.fingerprint() == verified->fingerprint()) {
                break;
            }

            desktop_.reset();
            budget_.reset();
            if (topologyRetryUsed_) {
                fail(CaptureSessionErrorCode::topologyChanged);
                return CaptureSessionStartResult::failed;
            }
            topologyRetryUsed_ = true;
        }
        if (stateMachine_.dispatch(SessionEvent::captureSucceeded)
            != TransitionResult::accepted) {
            fail(CaptureSessionErrorCode::unexpectedFailure);
            return CaptureSessionStartResult::failed;
        }

        const std::weak_ptr<CallbackState> weak = callbacks_;
        overlayMayBeOpen_ = true;
        const bool opened = services_.openOverlay(
            *desktop_,
            [weak, generation] {
                if (const auto state = weak.lock(); state && state->owner
                    && state->owner->generation_ == generation) {
                    state->owner->restart();
                }
            },
            [weak, generation](OverlayInputAction action) {
                if (const auto state = weak.lock(); state && state->owner
                    && state->owner->generation_ == generation) {
                    state->owner->handleAction(action);
                }
            });
        if (generation_ != generation) {
            return stateMachine_.state() == CaptureSessionState::idle
                    && lastError_.has_value()
                ? CaptureSessionStartResult::failed
                : CaptureSessionStartResult::started;
        }
        if (!opened) {
            fail(CaptureSessionErrorCode::overlayFailed);
            return CaptureSessionStartResult::failed;
        }
        if (stateMachine_.state() == CaptureSessionState::selecting) {
            services_.showOverlay();
        }
        return CaptureSessionStartResult::started;
    } catch (const std::bad_alloc&) {
        fail(CaptureSessionErrorCode::allocationFailed);
    } catch (...) {
        fail(CaptureSessionErrorCode::unexpectedFailure);
    }
    return CaptureSessionStartResult::failed;
}

CaptureSessionState CaptureSessionCoordinator::state() const noexcept
{
    return stateMachine_.state();
}

const std::optional<CaptureSessionErrorCode>&
CaptureSessionCoordinator::lastError() const noexcept
{
    return lastError_;
}

const PixelBuffer* CaptureSessionCoordinator::recentCapture() const noexcept
{
    return recentCapture_.has_value() ? &*recentCapture_ : nullptr;
}

void CaptureSessionCoordinator::handleAction(OverlayInputAction action) noexcept
{
    if (closingOverlay_ || restarting_
        || stateMachine_.state() != CaptureSessionState::selecting) {
        return;
    }
    if (action == OverlayInputAction::cancel) {
        finish(SessionEvent::cancel);
        return;
    }

    const auto selected = services_.selection();
    if (!selected.has_value()) {
        fail(CaptureSessionErrorCode::selectionUnavailable);
        return;
    }
    if (stateMachine_.dispatch(SessionEvent::selectionCreated)
        != TransitionResult::accepted) {
        fail(CaptureSessionErrorCode::unexpectedFailure);
        return;
    }

    auto composition = services_.compose(*selected, *desktop_, *budget_);
    if (!std::holds_alternative<PixelBuffer>(composition)) {
        fail(CaptureSessionErrorCode::compositionFailed);
        return;
    }
    if (stateMachine_.dispatch(SessionEvent::exportStarted)
        != TransitionResult::accepted) {
        fail(CaptureSessionErrorCode::unexpectedFailure);
        return;
    }
    auto pixels = std::move(std::get<PixelBuffer>(composition));
    const auto exportResult = services_.exportSelection(pixels, action);
    if (exportResult == CaptureExportResult::failed) {
        if (action == OverlayInputAction::copy) {
            recentCapture_.emplace(std::move(pixels));
        }
        fail(CaptureSessionErrorCode::exportFailed);
        return;
    }
    finish(SessionEvent::complete);
}

void CaptureSessionCoordinator::restart() noexcept
{
    if (closingOverlay_ || restarting_
        || stateMachine_.state() != CaptureSessionState::selecting) {
        return;
    }
    if (topologyRetryUsed_) {
        fail(CaptureSessionErrorCode::topologyChanged);
        return;
    }
    topologyRetryUsed_ = true;
    restarting_ = true;
    stateMachine_.dispatch(SessionEvent::cancel);
    releaseSession();
    restarting_ = false;
    startSession(false);
}

void CaptureSessionCoordinator::fail(CaptureSessionErrorCode error) noexcept
{
    lastError_ = error;
    if (stateMachine_.state() != CaptureSessionState::idle) {
        stateMachine_.dispatch(SessionEvent::fail);
    }
    releaseSession();
    services_.reportError(error);
}

void CaptureSessionCoordinator::finish(SessionEvent event) noexcept
{
    if (stateMachine_.dispatch(event) != TransitionResult::accepted) {
        fail(CaptureSessionErrorCode::unexpectedFailure);
        return;
    }
    releaseSession();
}

void CaptureSessionCoordinator::releaseSession() noexcept
{
    ++generation_;
    if (overlayMayBeOpen_) {
        closingOverlay_ = true;
        services_.closeOverlay();
        closingOverlay_ = false;
        overlayMayBeOpen_ = false;
    }
    desktop_.reset();
    budget_.reset();
}

} // namespace xxsnap::win
