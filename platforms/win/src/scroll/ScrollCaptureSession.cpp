#include "scroll/ScrollCaptureSession.h"

#include <limits>
#include <utility>

namespace xxsnap::win {
namespace {

constexpr int maximumScrollCaptureHeight = 200'000;
constexpr int previewMaximumHeight = 1'200;
constexpr int superLongPixelHeightThreshold = 29'000;

snipory::core::scroll::ScrollStitchConfig scrollConfig(
    std::size_t maximumAcceptedBytes) noexcept
{
    snipory::core::scroll::ScrollStitchConfig config;
    config.maximumAcceptedBytes = maximumAcceptedBytes;
    config.seamWhiteCoverage = 0.0;
    return config;
}

} // namespace

ScrollCaptureSession::ScrollCaptureSession(
    std::size_t maximumAcceptedBytes)
    : stitcher_(scrollConfig(maximumAcceptedBytes))
{
}

bool ScrollCaptureSession::start(
    snipory::core::scroll::ScrollFrame seed,
    ScrollCaptureUpdate& update) noexcept
{
    if (phase_ != ScrollCapturePhase::idle || !seed.isValid()) {
        return false;
    }
    try {
        const auto result = stitcher_.append(std::move(seed));
        if (result.kind
            != snipory::core::scroll::AppendKind::AcceptedInitial) {
            return false;
        }
        phase_ = ScrollCapturePhase::capturing;
        warning_.reset();
        pauseReason_.reset();
        update.append = result;
        update.preview = stitcher_.preview(previewMaximumHeight);
        update.warning = warning_;
        update.phase = phase_;
        return update.preview->isValid();
    } catch (...) {
        return false;
    }
}

bool ScrollCaptureSession::append(
    snipory::core::scroll::ScrollFrame frame,
    int wheelDelta,
    ScrollCaptureUpdate& update) noexcept
{
    if (phase_ != ScrollCapturePhase::capturing || !frame.isValid()) {
        return false;
    }
    try {
        const auto result = stitcher_.append(
            std::move(frame), directionForWheelDelta(wheelDelta));
        return updateAfterAppend(result, update);
    } catch (...) {
        pause(ScrollCapturePauseReason::captureFailure);
        return false;
    }
}

std::optional<snipory::core::portable::PixelBuffer>
ScrollCaptureSession::finish(std::size_t maximumAcceptedBytes) noexcept
{
    if (phase_ != ScrollCapturePhase::capturing
        && phase_ != ScrollCapturePhase::paused) {
        return std::nullopt;
    }
    try {
        snipory::core::portable::MemoryBudget budget(maximumAcceptedBytes);
        auto allocation = snipory::core::portable::PixelBuffer::allocate(
            stitcher_.outputWidth(), stitcher_.previewOutputHeight(), budget);
        if (!allocation.value
            || allocation.value->stride()
                > (std::numeric_limits<std::size_t>::max)()
            || !stitcher_.copyFinalPixels(
                allocation.value->data(), allocation.value->byteCount(),
                static_cast<std::size_t>(allocation.value->stride()), true)) {
            return std::nullopt;
        }
        phase_ = ScrollCapturePhase::finished;
        warning_.reset();
        pauseReason_.reset();
        return std::move(*allocation.value);
    } catch (...) {
        pause(ScrollCapturePauseReason::captureFailure);
        return std::nullopt;
    }
}

void ScrollCaptureSession::pause(ScrollCapturePauseReason reason) noexcept
{
    if (phase_ == ScrollCapturePhase::capturing
        || phase_ == ScrollCapturePhase::paused) {
        phase_ = ScrollCapturePhase::paused;
        pauseReason_ = reason;
    }
}

void ScrollCaptureSession::cancel() noexcept
{
    if (phase_ != ScrollCapturePhase::finished) {
        phase_ = ScrollCapturePhase::cancelled;
        warning_.reset();
        pauseReason_.reset();
    }
}

ScrollCapturePhase ScrollCaptureSession::phase() const noexcept
{
    return phase_;
}

std::optional<ScrollCaptureWarning>
ScrollCaptureSession::warning() const noexcept
{
    return warning_;
}

std::optional<ScrollCapturePauseReason>
ScrollCaptureSession::pauseReason() const noexcept
{
    return pauseReason_;
}

int ScrollCaptureSession::outputHeight() const noexcept
{
    return stitcher_.previewOutputHeight();
}

snipory::core::scroll::ScrollDirection
ScrollCaptureSession::directionForWheelDelta(int wheelDelta) noexcept
{
    using snipory::core::scroll::ScrollDirection;
    if (wheelDelta > 0) return ScrollDirection::Down;
    if (wheelDelta < 0) return ScrollDirection::Up;
    return ScrollDirection::Undetermined;
}

bool ScrollCaptureSession::requiresSaveOnlyForHeight(int outputHeight) noexcept
{
    return outputHeight > superLongPixelHeightThreshold;
}

bool ScrollCaptureSession::updateAfterAppend(
    const snipory::core::scroll::AppendResult& result,
    ScrollCaptureUpdate& update)
{
    using snipory::core::scroll::AppendKind;
    update = {};
    update.append = result;
    switch (result.kind) {
    case AppendKind::AcceptedAppend:
        warning_.reset();
        update.preview = stitcher_.preview(previewMaximumHeight);
        if (result.outputHeight > maximumScrollCaptureHeight) {
            pause(ScrollCapturePauseReason::maximumHeightReached);
        }
        break;
    case AppendKind::AwaitingEvidence:
        warning_.reset();
        if (result.appendedHeight > 0) {
            update.preview = stitcher_.preview(previewMaximumHeight);
        }
        if (result.outputHeight > maximumScrollCaptureHeight) {
            pause(ScrollCapturePauseReason::maximumHeightReached);
        }
        break;
    case AppendKind::DuplicateDiscarded:
    case AppendKind::ReviewDiscarded:
        warning_.reset();
        break;
    case AppendKind::LowConfidenceDiscarded:
        warning_ = ScrollCaptureWarning::lowConfidence;
        break;
    case AppendKind::ResourceLimit:
        pause(ScrollCapturePauseReason::resourceLimit);
        break;
    case AppendKind::AcceptedInitial:
        pause(ScrollCapturePauseReason::captureFailure);
        return false;
    }
    update.warning = warning_;
    update.phase = phase_;
    return !update.preview.has_value() || update.preview->isValid();
}

} // namespace xxsnap::win
