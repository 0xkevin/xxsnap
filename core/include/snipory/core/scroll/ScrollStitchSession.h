#pragma once

#include "snipory/core/scroll/ScrollFrame.h"
#include "snipory/core/scroll/VerticalOverlapMatcher.h"

#include <cstddef>
#include <cstdint>
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
    bool enableFixedSideDetection = true;
    double fixedSideMaximumRatio = 0.375;
    double fixedSideStationaryThreshold = 0.98;

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

    [[nodiscard]] AppendResult append(
        const ScrollFrame& frame,
        ScrollDirection preferredDirection = ScrollDirection::Undetermined);
    // Replaces only the matching baseline. Accepted output is unchanged, so a
    // later overlapping frame can recover after an unmatchable jump.
    [[nodiscard]] bool rebase(const ScrollFrame& frame);
    [[nodiscard]] int outputHeight() const noexcept;
    [[nodiscard]] int previewOutputHeight() const noexcept;
    [[nodiscard]] int outputWidth() const noexcept;
    [[nodiscard]] std::size_t residentBytes() const noexcept;
    [[nodiscard]] std::uint64_t spooledBytes() const noexcept;
    [[nodiscard]] ScrollFrame preview(int maximumHeight) const;
    [[nodiscard]] ScrollFrame previewForWidth(int maximumWidth) const;
    [[nodiscard]] ScrollFrame finalize() const;
    [[nodiscard]] ScrollFrame finalizeIncludingPending() const;
    // Streams the composed top-down image into caller-owned storage without
    // allocating another full-size frame. bottomUp is useful for Core Graphics.
    [[nodiscard]] bool copyFinalPixels(
        void* destination,
        std::size_t destinationBytes,
        std::size_t destinationBytesPerRow,
        bool includePending,
        bool bottomUp = false) const;

private:
    [[nodiscard]] ScrollFrame previewWithSize(int width, int height) const;
    class Implementation;
    std::unique_ptr<Implementation> implementation_;
};

} // namespace snipory::core::scroll
