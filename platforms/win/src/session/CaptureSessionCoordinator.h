#pragma once

#include "capture/CaptureBackend.h"
#include "capture/DisplayTopology.h"
#include "export/SelectionComposer.h"
#include "overlay/OverlayHost.h"
#include "session/CaptureSessionStateMachine.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>

namespace xxsnap::win {

enum class CaptureSessionStartResult {
    started,
    busy,
    failed,
};

enum class CaptureSessionErrorCode {
    topologyFailed,
    captureFailed,
    overlayFailed,
    topologyChanged,
    memoryLimitExceeded,
    selectionUnavailable,
    compositionFailed,
    exportFailed,
    scrollCaptureFailed,
    allocationFailed,
    unexpectedFailure,
};

enum class ScrollCaptureCompletionStatus {
    completed,
    cancelled,
    failed,
};

struct ScrollCaptureCompletion {
    ScrollCaptureCompletionStatus status = ScrollCaptureCompletionStatus::failed;
    std::optional<PixelBuffer> pixels;
    OverlayInputAction action = OverlayInputAction::copy;
};

enum class CaptureExportResult {
    completed,
    cancelled,
    failed,
};

class CaptureSessionServices {
public:
    using RestartCallback = std::function<void()>;
    using ActionCallback = std::function<void(OverlayInputAction)>;
    using ScrollCaptureCallback = std::function<void(ScrollCaptureCompletion)>;

    virtual ~CaptureSessionServices() = default;

    virtual DisplayTopologyResult snapshotTopology() noexcept = 0;
    virtual CaptureResult capture(
        const DisplayTopologySnapshot& topology,
        MemoryBudget& budget) noexcept = 0;
    virtual bool openOverlay(
        const FrozenDesktop& desktop,
        RestartCallback restartCallback,
        ActionCallback actionCallback) = 0;
    virtual void showOverlay() noexcept = 0;
    virtual std::optional<PixelRect> selection() const noexcept = 0;
    virtual bool beginScrollCapture(
        PixelRect selection,
        std::size_t maximumAcceptedBytes,
        ScrollCaptureCallback callback) = 0;
    virtual void cancelScrollCapture() noexcept = 0;
    virtual bool resumeOverlayAfterScrollCapture() noexcept = 0;
    virtual void closeOverlay() noexcept = 0;
    virtual SelectionCompositionResult compose(
        PixelRect selection,
        const FrozenDesktop& desktop,
        MemoryBudget& budget) noexcept = 0;
    virtual CaptureExportResult exportSelection(
        const PixelBuffer& pixels,
        OverlayInputAction action) noexcept = 0;
    virtual void reportError(CaptureSessionErrorCode error) noexcept = 0;
};

#if defined(_WIN64)
inline constexpr std::uint64_t defaultCaptureSessionMemoryLimit =
    2ULL * 1024ULL * 1024ULL * 1024ULL;
#else
inline constexpr std::uint64_t defaultCaptureSessionMemoryLimit =
    512ULL * 1024ULL * 1024ULL;
#endif

class CaptureSessionCoordinator final {
public:
    explicit CaptureSessionCoordinator(
        CaptureSessionServices& services,
        std::uint64_t memoryLimitBytes = defaultCaptureSessionMemoryLimit);
    ~CaptureSessionCoordinator();

    CaptureSessionCoordinator(const CaptureSessionCoordinator&) = delete;
    CaptureSessionCoordinator& operator=(const CaptureSessionCoordinator&) = delete;

    CaptureSessionStartResult start() noexcept;
    void displayConfigurationChanged() noexcept;
    CaptureSessionState state() const noexcept;
    const std::optional<CaptureSessionErrorCode>& lastError() const noexcept;
    const PixelBuffer* recentCapture() const noexcept;

private:
    struct CallbackState;

    CaptureSessionStartResult startSession(bool newRequest) noexcept;
    void handleAction(OverlayInputAction action) noexcept;
    void handleScrollCaptureCompletion(
        ScrollCaptureCompletion completion) noexcept;
    void restart() noexcept;
    void fail(CaptureSessionErrorCode error) noexcept;
    void finish(SessionEvent event) noexcept;
    void releaseSession() noexcept;

    CaptureSessionServices& services_;
    std::uint64_t memoryLimitBytes_;
    CaptureSessionStateMachine stateMachine_;
    std::unique_ptr<MemoryBudget> budget_;
    std::unique_ptr<FrozenDesktop> desktop_;
    std::optional<PixelBuffer> recentCapture_;
    std::shared_ptr<CallbackState> callbacks_;
    std::optional<CaptureSessionErrorCode> lastError_;
    bool overlayMayBeOpen_ = false;
    bool closingOverlay_ = false;
    bool restarting_ = false;
    bool topologyRetryUsed_ = false;
    bool scrollCaptureMayBeOpen_ = false;
    std::uint64_t generation_ = 0;
};

} // namespace xxsnap::win
