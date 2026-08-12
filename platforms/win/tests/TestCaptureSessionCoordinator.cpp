#include "session/CaptureSessionCoordinator.h"

#include <Windows.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

namespace {

using snipory::core::portable::MemoryBudget;
using snipory::core::portable::PixelBuffer;
using xxsnap::win::CaptureError;
using xxsnap::win::CaptureErrorCode;
using xxsnap::win::CaptureExportResult;
using xxsnap::win::CaptureResult;
using xxsnap::win::CaptureSessionCoordinator;
using xxsnap::win::CaptureSessionErrorCode;
using xxsnap::win::CaptureSessionServices;
using xxsnap::win::CaptureSessionStartResult;
using xxsnap::win::CaptureSessionState;
using xxsnap::win::DisplayDescriptor;
using xxsnap::win::DisplayTopologyResult;
using xxsnap::win::FrozenDesktop;
using xxsnap::win::FrozenDisplay;
using xxsnap::win::OverlayInputAction;
using xxsnap::win::PixelRect;
using xxsnap::win::SelectionCompositionResult;
using xxsnap::win::ScrollCaptureCompletion;
using xxsnap::win::ScrollCaptureCompletionStatus;
using xxsnap::win::TopologyError;
using xxsnap::win::TopologyErrorCode;
using xxsnap::win::buildDisplayTopologySnapshot;
using xxsnap::win::defaultCaptureSessionMemoryLimit;

int failures = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            std::cerr << __FILE__ << ':' << __LINE__                           \
                      << ": CHECK failed: " #condition << '\n';                \
            ++failures;                                                        \
        }                                                                       \
    } while (false)

DisplayDescriptor descriptor(std::int64_t width = 8)
{
    return {L"DISPLAY1", {0, 0, width, 6}, 96U, 96U, DISPLAYCONFIG_ROTATION_IDENTITY};
}

DisplayTopologyResult topology(std::int64_t width = 8)
{
    return buildDisplayTopologySnapshot({descriptor(width)});
}

PixelBuffer allocatePixels(
    std::int64_t width,
    std::int64_t height,
    MemoryBudget& budget)
{
    auto allocation = PixelBuffer::allocate(width, height, budget);
    CHECK(allocation.value != nullptr);
    return std::move(*allocation.value);
}

class FakeServices final : public CaptureSessionServices {
public:
    DisplayTopologyResult snapshotTopology() noexcept override
    {
        ++topologyCalls;
        if (failTopology) {
            return DisplayTopologyResult(
                TopologyError{TopologyErrorCode::systemFailure, ERROR_GEN_FAILURE});
        }
        const auto index = static_cast<std::size_t>(topologyCalls - 1);
        const auto width = topologyWidths.empty()
            ? 8
            : topologyWidths[(std::min)(index, topologyWidths.size() - 1)];
        return topology(width);
    }

    CaptureResult capture(
        const xxsnap::win::DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget) noexcept override
    {
        ++captureCalls;
        if (failCapture) {
            return CaptureError{CaptureErrorCode::systemFailure, E_FAIL};
        }
        std::vector<FrozenDisplay> displays;
        displays.emplace_back(
            snapshot.displays().front(), allocatePixels(8, 6, budget));
        return FrozenDesktop(
            snapshot, std::move(displays), std::chrono::steady_clock::now());
    }

    bool openOverlay(
        const FrozenDesktop&,
        RestartCallback restart,
        ActionCallback action) override
    {
        ++openCalls;
        restartCallback = std::move(restart);
        actionCallback = std::move(action);
        const bool opened = !failOverlay;
        overlayOpen = opened;
        if (onOpen) {
            onOpen();
        }
        return opened;
    }

    void showOverlay() noexcept override
    {
        ++showCalls;
    }

    std::optional<PixelRect> selection() const noexcept override
    {
        return selectedRect;
    }

    bool beginScrollCapture(
        PixelRect selection,
        std::size_t maximumAcceptedBytes,
        ScrollCaptureCallback callback) override
    {
        ++beginScrollCalls;
        scrollSelection = selection;
        scrollMaximumBytes = maximumAcceptedBytes;
        scrollCallback = std::move(callback);
        return beginScrollSucceeds;
    }

    void cancelScrollCapture() noexcept override
    {
        ++cancelScrollCalls;
        scrollCallback = {};
    }

    bool resumeOverlayAfterScrollCapture() noexcept override
    {
        ++resumeOverlayCalls;
        return resumeOverlaySucceeds;
    }

    void closeOverlay() noexcept override
    {
        ++closeCalls;
        overlayOpen = false;
    }

    SelectionCompositionResult compose(
        PixelRect,
        const FrozenDesktop&,
        MemoryBudget& budget) noexcept override
    {
        ++composeCalls;
        if (failComposition) {
            return CaptureError{CaptureErrorCode::systemFailure, E_FAIL};
        }
        return allocatePixels(3, 2, budget);
    }

    CaptureExportResult exportSelection(
        const PixelBuffer& pixels,
        OverlayInputAction action) noexcept override
    {
        ++exportCalls;
        exportedAction = action;
        exportedWidth = pixels.width();
        return exportResult;
    }

    void reportError(CaptureSessionErrorCode error) noexcept override
    {
        reportedErrors.push_back(error);
    }

    void emit(OverlayInputAction action)
    {
        if (actionCallback) {
            actionCallback(action);
        }
    }

    void requestRestart()
    {
        if (restartCallback) {
            restartCallback();
        }
    }

    void completeScroll(ScrollCaptureCompletion completion)
    {
        if (scrollCallback) {
            auto callback = std::move(scrollCallback);
            callback(std::move(completion));
        }
    }

    bool failTopology = false;
    bool failCapture = false;
    bool failOverlay = false;
    bool failComposition = false;
    bool beginScrollSucceeds = true;
    bool resumeOverlaySucceeds = true;
    std::vector<std::int64_t> topologyWidths;
    CaptureExportResult exportResult = CaptureExportResult::completed;
    std::optional<PixelRect> selectedRect = PixelRect{1, 1, 3, 2};
    RestartCallback restartCallback;
    ActionCallback actionCallback;
    ScrollCaptureCallback scrollCallback;
    std::function<void()> onOpen;
    bool overlayOpen = false;
    int topologyCalls = 0;
    int captureCalls = 0;
    int openCalls = 0;
    int showCalls = 0;
    int closeCalls = 0;
    int composeCalls = 0;
    int exportCalls = 0;
    int beginScrollCalls = 0;
    int cancelScrollCalls = 0;
    int resumeOverlayCalls = 0;
    std::optional<PixelRect> scrollSelection;
    std::size_t scrollMaximumBytes = 0U;
    std::optional<OverlayInputAction> exportedAction;
    std::int64_t exportedWidth = 0;
    std::vector<CaptureSessionErrorCode> reportedErrors;
};

void testScrollCaptureCanCancelBackToSelectionAndCompleteToExport()
{
    FakeServices services;
    CaptureSessionCoordinator coordinator(services);
    CHECK(coordinator.start() == CaptureSessionStartResult::started);

    services.emit(OverlayInputAction::scrollCapture);
    CHECK(coordinator.state() == CaptureSessionState::ready);
    CHECK(services.beginScrollCalls == 1);
    CHECK(services.scrollSelection == services.selectedRect);
    CHECK(services.scrollMaximumBytes > 0U);
    CHECK(services.composeCalls == 0);

    services.completeScroll({ScrollCaptureCompletionStatus::cancelled});
    CHECK(coordinator.state() == CaptureSessionState::selecting);
    CHECK(services.resumeOverlayCalls == 1);

    services.emit(OverlayInputAction::scrollCapture);
    CHECK(coordinator.state() == CaptureSessionState::ready);
    MemoryBudget outputBudget(64U);
    ScrollCaptureCompletion completion;
    completion.status = ScrollCaptureCompletionStatus::completed;
    completion.pixels.emplace(allocatePixels(3, 2, outputBudget));
    completion.action = OverlayInputAction::copy;
    services.completeScroll(std::move(completion));

    CHECK(coordinator.state() == CaptureSessionState::idle);
    CHECK(services.exportCalls == 1);
    CHECK(services.exportedAction == OverlayInputAction::copy);
    CHECK(services.closeCalls == 1);
}

void testScrollCaptureStartAndRuntimeFailuresAreReported()
{
    FakeServices startFailure;
    startFailure.beginScrollSucceeds = false;
    CaptureSessionCoordinator first(startFailure);
    CHECK(first.start() == CaptureSessionStartResult::started);
    startFailure.emit(OverlayInputAction::scrollCapture);
    CHECK(first.state() == CaptureSessionState::idle);
    CHECK(first.lastError() == CaptureSessionErrorCode::scrollCaptureFailed);

    FakeServices runtimeFailure;
    CaptureSessionCoordinator second(runtimeFailure);
    CHECK(second.start() == CaptureSessionStartResult::started);
    runtimeFailure.emit(OverlayInputAction::scrollCapture);
    runtimeFailure.completeScroll({ScrollCaptureCompletionStatus::failed});
    CHECK(second.state() == CaptureSessionState::idle);
    CHECK(second.lastError() == CaptureSessionErrorCode::scrollCaptureFailed);
}

void testCopyCompletesAndBusyStartIsIgnored()
{
    FakeServices services;
    CaptureSessionCoordinator coordinator(services);

    CHECK(coordinator.start() == CaptureSessionStartResult::started);
    CHECK(coordinator.state() == CaptureSessionState::selecting);
    CHECK(coordinator.start() == CaptureSessionStartResult::busy);
    CHECK(services.captureCalls == 1);
    CHECK(services.topologyCalls == 2);
    CHECK(services.showCalls == 1);

    services.emit(OverlayInputAction::copy);
    CHECK(coordinator.state() == CaptureSessionState::idle);
    CHECK(!coordinator.lastError().has_value());
    CHECK(services.composeCalls == 1);
    CHECK(services.exportCalls == 1);
    CHECK(services.exportedAction == OverlayInputAction::copy);
    CHECK(services.exportedWidth == 3);
    CHECK(services.closeCalls == 1);
}

void testArchitectureDefaultMemoryLimit()
{
#if defined(_WIN64)
    static_assert(
        defaultCaptureSessionMemoryLimit == 2ULL * 1024ULL * 1024ULL * 1024ULL);
#else
    static_assert(
        defaultCaptureSessionMemoryLimit == 512ULL * 1024ULL * 1024ULL);
#endif
}

void testCancelAndCancelledSaveReturnToIdle()
{
    FakeServices cancelServices;
    CaptureSessionCoordinator cancelCoordinator(cancelServices);
    CHECK(cancelCoordinator.start() == CaptureSessionStartResult::started);
    cancelServices.emit(OverlayInputAction::cancel);
    CHECK(cancelCoordinator.state() == CaptureSessionState::idle);
    CHECK(cancelServices.composeCalls == 0);

    FakeServices saveServices;
    saveServices.exportResult = CaptureExportResult::cancelled;
    CaptureSessionCoordinator saveCoordinator(saveServices);
    CHECK(saveCoordinator.start() == CaptureSessionStartResult::started);
    saveServices.emit(OverlayInputAction::save);
    CHECK(saveCoordinator.state() == CaptureSessionState::idle);
    CHECK(!saveCoordinator.lastError().has_value());
    CHECK(saveServices.exportedAction == OverlayInputAction::save);

    FakeServices successfulSave;
    CaptureSessionCoordinator successfulSaveCoordinator(successfulSave);
    CHECK(successfulSaveCoordinator.start() == CaptureSessionStartResult::started);
    successfulSave.emit(OverlayInputAction::save);
    CHECK(successfulSaveCoordinator.state() == CaptureSessionState::idle);
    CHECK(successfulSave.exportCalls == 1);
    CHECK(successfulSave.exportedAction == OverlayInputAction::save);
    CHECK(successfulSave.closeCalls == 1);
}

void testDisplayChangeRestartsWithFreshCapture()
{
    FakeServices services;
    CaptureSessionCoordinator coordinator(services);
    CHECK(coordinator.start() == CaptureSessionStartResult::started);

    services.requestRestart();
    CHECK(coordinator.state() == CaptureSessionState::selecting);
    CHECK(services.topologyCalls == 4);
    CHECK(services.captureCalls == 2);
    CHECK(services.openCalls == 2);
    CHECK(services.closeCalls == 1);

    services.requestRestart();
    CHECK(coordinator.state() == CaptureSessionState::idle);
    CHECK(coordinator.lastError()
          == CaptureSessionErrorCode::topologyChanged);
    CHECK(services.captureCalls == 2);
    CHECK(services.reportedErrors.back()
          == CaptureSessionErrorCode::topologyChanged);
}

void testCaptureTopologyMismatchRetriesOnlyOnce()
{
    FakeServices retry;
    retry.topologyWidths = {8, 9, 9, 9};
    CaptureSessionCoordinator retryCoordinator(retry);
    CHECK(retryCoordinator.start() == CaptureSessionStartResult::started);
    CHECK(retry.captureCalls == 2);
    CHECK(retry.topologyCalls == 4);

    retry.requestRestart();
    CHECK(retryCoordinator.state() == CaptureSessionState::idle);
    CHECK(retryCoordinator.lastError()
          == CaptureSessionErrorCode::topologyChanged);

    FakeServices unstable;
    unstable.topologyWidths = {8, 9, 9, 10};
    CaptureSessionCoordinator unstableCoordinator(unstable);
    CHECK(unstableCoordinator.start() == CaptureSessionStartResult::failed);
    CHECK(unstableCoordinator.state() == CaptureSessionState::idle);
    CHECK(unstableCoordinator.lastError()
          == CaptureSessionErrorCode::topologyChanged);
    CHECK(unstable.captureCalls == 2);
    CHECK(unstable.reportedErrors.back()
          == CaptureSessionErrorCode::topologyChanged);
}

void testFailuresAreExplicitAndRecoverable()
{
    FakeServices memoryFailure;
    CaptureSessionCoordinator memoryCoordinator(memoryFailure, 100);
    CHECK(memoryCoordinator.start() == CaptureSessionStartResult::failed);
    CHECK(memoryCoordinator.lastError()
          == CaptureSessionErrorCode::memoryLimitExceeded);
    CHECK(memoryFailure.captureCalls == 0);
    CHECK(memoryFailure.reportedErrors.back()
          == CaptureSessionErrorCode::memoryLimitExceeded);

    FakeServices topologyFailure;
    topologyFailure.failTopology = true;
    CaptureSessionCoordinator topologyCoordinator(topologyFailure);
    CHECK(topologyCoordinator.start() == CaptureSessionStartResult::failed);
    CHECK(topologyCoordinator.state() == CaptureSessionState::idle);
    CHECK(topologyCoordinator.lastError()
          == CaptureSessionErrorCode::topologyFailed);
    CHECK(topologyFailure.closeCalls == 0);

    topologyFailure.failTopology = false;
    CHECK(topologyCoordinator.start() == CaptureSessionStartResult::started);
    topologyFailure.emit(OverlayInputAction::cancel);

    FakeServices captureFailure;
    captureFailure.failCapture = true;
    CaptureSessionCoordinator captureCoordinator(captureFailure);
    CHECK(captureCoordinator.start() == CaptureSessionStartResult::failed);
    CHECK(captureCoordinator.lastError()
          == CaptureSessionErrorCode::captureFailed);
    CHECK(captureCoordinator.state() == CaptureSessionState::idle);
    CHECK(captureFailure.closeCalls == 0);

    FakeServices overlayFailure;
    overlayFailure.failOverlay = true;
    CaptureSessionCoordinator overlayCoordinator(overlayFailure);
    CHECK(overlayCoordinator.start() == CaptureSessionStartResult::failed);
    CHECK(overlayCoordinator.lastError()
          == CaptureSessionErrorCode::overlayFailed);
    CHECK(overlayCoordinator.state() == CaptureSessionState::idle);
    CHECK(overlayFailure.closeCalls == 1);

    FakeServices selectionFailure;
    selectionFailure.selectedRect.reset();
    CaptureSessionCoordinator selectionCoordinator(selectionFailure);
    CHECK(selectionCoordinator.start() == CaptureSessionStartResult::started);
    selectionFailure.emit(OverlayInputAction::copy);
    CHECK(selectionCoordinator.lastError()
          == CaptureSessionErrorCode::selectionUnavailable);
    CHECK(selectionCoordinator.state() == CaptureSessionState::idle);
    CHECK(selectionFailure.closeCalls == 1);

    FakeServices compositionFailure;
    compositionFailure.failComposition = true;
    CaptureSessionCoordinator compositionCoordinator(compositionFailure);
    CHECK(compositionCoordinator.start() == CaptureSessionStartResult::started);
    compositionFailure.emit(OverlayInputAction::copy);
    CHECK(compositionCoordinator.lastError()
          == CaptureSessionErrorCode::compositionFailed);
    CHECK(compositionCoordinator.state() == CaptureSessionState::idle);
    CHECK(compositionFailure.closeCalls == 1);

    FakeServices exportFailure;
    exportFailure.exportResult = CaptureExportResult::failed;
    CaptureSessionCoordinator exportCoordinator(exportFailure);
    CHECK(exportCoordinator.start() == CaptureSessionStartResult::started);
    exportFailure.emit(OverlayInputAction::copy);
    CHECK(exportCoordinator.lastError()
          == CaptureSessionErrorCode::exportFailed);
    CHECK(exportCoordinator.recentCapture() != nullptr);
    CHECK(exportCoordinator.recentCapture()->width() == 3);
    CHECK(exportCoordinator.state() == CaptureSessionState::idle);
    CHECK(exportFailure.closeCalls == 1);

    FakeServices saveFailure;
    saveFailure.exportResult = CaptureExportResult::failed;
    CaptureSessionCoordinator saveFailureCoordinator(saveFailure);
    CHECK(saveFailureCoordinator.start() == CaptureSessionStartResult::started);
    saveFailure.emit(OverlayInputAction::save);
    CHECK(saveFailureCoordinator.lastError()
          == CaptureSessionErrorCode::exportFailed);
    CHECK(saveFailureCoordinator.recentCapture() == nullptr);
    CHECK(saveFailureCoordinator.state() == CaptureSessionState::idle);
    CHECK(saveFailure.closeCalls == 1);
}

void testCallbacksDoNotOutliveCoordinator()
{
    FakeServices services;
    {
        CaptureSessionCoordinator coordinator(services);
        CHECK(coordinator.start() == CaptureSessionStartResult::started);
    }
    services.emit(OverlayInputAction::copy);
    services.requestRestart();
    CHECK(services.exportCalls == 0);
}

void testSynchronousOverlayCallbacksCannotCorruptNewGeneration()
{
    FakeServices restartServices;
    CaptureSessionCoordinator restartCoordinator(restartServices);
    CaptureSessionServices::ActionCallback staleAction;
    restartServices.onOpen = [&] {
        restartServices.onOpen = nullptr;
        staleAction = restartServices.actionCallback;
        restartServices.requestRestart();
    };
    CHECK(restartCoordinator.start() == CaptureSessionStartResult::started);
    CHECK(restartCoordinator.state() == CaptureSessionState::selecting);
    CHECK(restartServices.captureCalls == 2);
    CHECK(restartServices.showCalls == 1);
    CHECK(!restartCoordinator.lastError().has_value());

    staleAction(OverlayInputAction::copy);
    CHECK(restartCoordinator.state() == CaptureSessionState::selecting);
    CHECK(restartServices.exportCalls == 0);

    FakeServices cancelServices;
    CaptureSessionCoordinator cancelCoordinator(cancelServices);
    cancelServices.onOpen = [&] { cancelServices.emit(OverlayInputAction::cancel); };
    CHECK(cancelCoordinator.start() == CaptureSessionStartResult::started);
    CHECK(cancelCoordinator.state() == CaptureSessionState::idle);
    CHECK(cancelServices.showCalls == 0);
    CHECK(cancelServices.composeCalls == 0);

    FakeServices falseReturningRestart;
    falseReturningRestart.failOverlay = true;
    CaptureSessionCoordinator falseReturningCoordinator(falseReturningRestart);
    falseReturningRestart.onOpen = [&] {
        falseReturningRestart.onOpen = nullptr;
        falseReturningRestart.failOverlay = false;
        falseReturningRestart.requestRestart();
    };
    CHECK(falseReturningCoordinator.start() == CaptureSessionStartResult::started);
    CHECK(falseReturningCoordinator.state() == CaptureSessionState::selecting);
    CHECK(!falseReturningCoordinator.lastError().has_value());
    CHECK(falseReturningRestart.captureCalls == 2);
    CHECK(falseReturningRestart.showCalls == 1);
}

} // namespace

int main()
{
    testArchitectureDefaultMemoryLimit();
    testCopyCompletesAndBusyStartIsIgnored();
    testScrollCaptureCanCancelBackToSelectionAndCompleteToExport();
    testScrollCaptureStartAndRuntimeFailuresAreReported();
    testCancelAndCancelledSaveReturnToIdle();
    testDisplayChangeRestartsWithFreshCapture();
    testCaptureTopologyMismatchRetriesOnlyOnce();
    testFailuresAreExplicitAndRecoverable();
    testCallbacksDoNotOutliveCoordinator();
    testSynchronousOverlayCallbacksCannotCorruptNewGeneration();

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
