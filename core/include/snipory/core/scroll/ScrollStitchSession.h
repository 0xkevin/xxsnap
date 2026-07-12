#pragma once

#include "snipory/core/scroll/ScrollFrame.h"
#include "snipory/core/scroll/VerticalOverlapMatcher.h"

#include <cstddef>
#include <memory>

namespace snipory::core::scroll {

enum class AppendKind
{
    AcceptedInitial,
    AcceptedAppend,
    DuplicateDiscarded,
    ReviewDiscarded,
    AwaitingEvidence,
    LowConfidenceDiscarded,
    ResourceLimit,
};

enum class ScrollDirection
{
    Undetermined,
    Down,
    Up,
};

struct AppendResult final
{
    AppendKind kind = AppendKind::LowConfidenceDiscarded;
    ScrollDirection direction = ScrollDirection::Undetermined;
    int appendedHeight = 0;
    int outputHeight = 0;
    double confidence = 0;
};

struct ScrollStitchConfig final
{
    OverlapConfig matcher;
    double duplicateThreshold = 0.01;
    // Caps persistent BGRA buffers and fingerprint byte payloads. Small
    // per-entry container bookkeeping is excluded from this byte budget.
    std::size_t maximumAcceptedBytes = 256U * 1024U * 1024U;

    bool enableFixedBandDetection = true;
    // Zero selects a conservative automatic search budget. Positive values cap
    // the searched prefix/suffix rather than asserting an exact band height.
    int fixedTopCandidateHeight = 0;
    int fixedBottomCandidateHeight = 0;
    int fixedBandConfirmationMovements = 3;
    double fixedBandStationaryThreshold = 0.98;

    int scrollbarMaximumWidth = 8;
    int scrollbarConfirmationMovements = 3;
    double scrollbarPersistenceThreshold = 0.75;
    double scrollbarMotionThreshold = 0.02;
    double scrollbarConfidenceThreshold = 0.80;
};

class ScrollStitchSession final
{
public:
    explicit ScrollStitchSession(ScrollStitchConfig config = {});
    ~ScrollStitchSession();

    ScrollStitchSession(ScrollStitchSession&&) noexcept;
    ScrollStitchSession& operator=(ScrollStitchSession&&) noexcept;
    ScrollStitchSession(const ScrollStitchSession&) = delete;
    ScrollStitchSession& operator=(const ScrollStitchSession&) = delete;

    [[nodiscard]] AppendResult append(const ScrollFrame& frame);
    [[nodiscard]] int outputHeight() const noexcept;
    [[nodiscard]] ScrollFrame preview(int maximumHeight) const;
    [[nodiscard]] ScrollFrame finalize() const;

private:
    class Implementation;
    std::unique_ptr<Implementation> implementation_;
};

} // namespace snipory::core::scroll
