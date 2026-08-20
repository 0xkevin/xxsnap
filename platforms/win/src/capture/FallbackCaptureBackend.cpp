#include "capture/FallbackCaptureBackend.h"

#include <chrono>
#include <cstddef>
#include <thread>
#include <utility>
#include <variant>

namespace xxsnap::win {
namespace {

bool isTerminal(CaptureErrorCode code) noexcept
{
    switch (code) {
    case CaptureErrorCode::memoryLimit:
    case CaptureErrorCode::arithmeticOverflow:
    case CaptureErrorCode::invalidSize:
    case CaptureErrorCode::topologyChanged:
        return true;
    case CaptureErrorCode::accessDenied:
    case CaptureErrorCode::deviceLost:
    case CaptureErrorCode::unsupported:
    case CaptureErrorCode::noFrame:
    case CaptureErrorCode::systemFailure:
        return false;
    }
    return true;
}

#if !defined(XXSNAP_LEGACY)
bool isSuspiciouslyBlack(const PixelBuffer& pixels) noexcept
{
    const auto pixelCount = pixels.byteCount() / 4U;
    if (pixelCount == 0U) {
        return false;
    }

    const auto maximumNonBlackPixels = pixelCount / 10U;
    std::size_t nonBlackPixels = 0U;
    for (std::size_t offset = 0U; offset + 2U < pixels.byteCount(); offset += 4U) {
        if (pixels.data()[offset + 0U] != std::byte{0U}
            || pixels.data()[offset + 1U] != std::byte{0U}
            || pixels.data()[offset + 2U] != std::byte{0U}) {
            ++nonBlackPixels;
            if (nonBlackPixels > maximumNonBlackPixels) {
                return false;
            }
        }
    }
    return true;
}

bool hasSuspiciouslyBlackDisplay(const FrozenDesktop& desktop) noexcept
{
    for (const auto& display : desktop.displays) {
        if (isSuspiciouslyBlack(display.pixels)) {
            // Some virtual display drivers report DXGI success after copying only
            // a small strip of the desktop, leaving the rest of the frame black.
            return true;
        }
    }
    return false;
}
#endif

} // namespace

FallbackCaptureBackend::FallbackCaptureBackend(
    ResettableCaptureBackend& preferred,
    CaptureBackend& fallback) noexcept
    : preferred_(preferred)
    , fallback_(fallback)
{
}

CaptureResult FallbackCaptureBackend::capture(
    const DisplayTopologySnapshot& snapshot,
    MemoryBudget& budget) noexcept
{
#if defined(XXSNAP_LEGACY)
    auto fallbackResult = fallback_.capture(snapshot, budget);
    lastBackend_ = CaptureBackendKind::fallback;
    return fallbackResult;
#else
    // Output duplication queues frames while no capture is active. Recreate it
    // for each screenshot so a later session cannot freeze an older queued frame.
    preferred_.reset();
    {
        auto preferredResult = preferred_.capture(snapshot, budget);
        auto* preferredError = std::get_if<CaptureError>(&preferredResult);
        if (preferredError == nullptr) {
            if (!hasSuspiciouslyBlackDisplay(std::get<FrozenDesktop>(preferredResult))) {
                lastBackend_ = CaptureBackendKind::preferred;
                return preferredResult;
            }
            // Parallels can expose an all-black initialization frame followed
            // by a partially composed frame when duplication is first created.
            // Drain both before accepting the settled desktop frame.
            preferredResult.emplace<1>(CaptureError{
                CaptureErrorCode::noFrame, DXGI_ERROR_WAIT_TIMEOUT});
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            auto freshFrameResult = preferred_.capture(snapshot, budget);
            const auto* freshFrameError
                = std::get_if<CaptureError>(&freshFrameResult);
            if (freshFrameError == nullptr) {
                freshFrameResult.emplace<1>(CaptureError{
                    CaptureErrorCode::noFrame, DXGI_ERROR_WAIT_TIMEOUT});
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
                auto settledFrameResult = preferred_.capture(snapshot, budget);
                const auto* settledFrameError
                    = std::get_if<CaptureError>(&settledFrameResult);
                if (settledFrameError == nullptr
                    && !hasSuspiciouslyBlackDisplay(
                        std::get<FrozenDesktop>(settledFrameResult))) {
                    lastBackend_ = CaptureBackendKind::preferred;
                    return settledFrameResult;
                }
                if (settledFrameError != nullptr
                    && isTerminal(settledFrameError->code)) {
                    lastBackend_ = CaptureBackendKind::preferred;
                    return settledFrameResult;
                }
            } else if (isTerminal(freshFrameError->code)) {
                lastBackend_ = CaptureBackendKind::preferred;
                return freshFrameResult;
            }
        } else if (isTerminal(preferredError->code)) {
            lastBackend_ = CaptureBackendKind::preferred;
            return preferredResult;
        } else if (preferredError->code == CaptureErrorCode::deviceLost) {
            preferred_.reset();
            auto retryResult = preferred_.capture(snapshot, budget);
            const auto* retryError = std::get_if<CaptureError>(&retryResult);
            if (retryError == nullptr) {
                if (!hasSuspiciouslyBlackDisplay(std::get<FrozenDesktop>(retryResult))) {
                    lastBackend_ = CaptureBackendKind::preferred;
                    return retryResult;
                }
            } else if (isTerminal(retryError->code)) {
                lastBackend_ = CaptureBackendKind::preferred;
                return retryResult;
            }
        }
    }

    auto fallbackResult = fallback_.capture(snapshot, budget);
    lastBackend_ = CaptureBackendKind::fallback;
    return fallbackResult;
#endif
}

CaptureBackendKind FallbackCaptureBackend::lastBackend() const noexcept
{
    return lastBackend_;
}

} // namespace xxsnap::win
