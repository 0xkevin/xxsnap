#include "capture/FallbackCaptureBackend.h"

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
    auto preferredResult = preferred_.capture(snapshot, budget);
    auto* preferredError = std::get_if<CaptureError>(&preferredResult);
    if (preferredError == nullptr || isTerminal(preferredError->code)) {
        return preferredResult;
    }

    if (preferredError->code == CaptureErrorCode::deviceLost) {
        preferred_.reset();
        auto retryResult = preferred_.capture(snapshot, budget);
        const auto* retryError = std::get_if<CaptureError>(&retryResult);
        if (retryError == nullptr || isTerminal(retryError->code)) {
            return retryResult;
        }
    }

    return fallback_.capture(snapshot, budget);
}

} // namespace xxsnap::win
