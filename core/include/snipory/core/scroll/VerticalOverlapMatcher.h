#pragma once

#include "snipory/core/scroll/ScrollFrame.h"

namespace snipory::core::scroll {

enum class OverlapKind
{
    Reliable,
    Ambiguous,
    Insufficient,
};

struct OverlapConfig final
{
    double minimumOverlapRatio = 0.20;
    double maximumAdvanceRatio = 0.85;
    double maximumReliableAdvanceRatio = 2.0 / 3.0;
    double maximumNormalizedError = 0.08;
    double minimumWinnerMargin = 0.015;
    double minimumReliableConfidence = 0.30;
    // A non-zero motion hint resolves otherwise plausible periodic placements;
    // pixel error limits still reject unrelated frames.
    int expectedAdvance = 0;
    int expectedAdvanceTolerance = 0;
    PixelCrop excludedBands;
    int maximumFullResolutionCandidates = 32;
    bool isolateChangedRegion = true;
    bool allowChangedPixelFallback = false;
};

struct OverlapResult final
{
    OverlapKind kind = OverlapKind::Insufficient;
    int verticalAdvance = 0;
    int overlapHeight = 0;
    double confidence = 0;
    double normalizedError = 1;
    bool usedChangedPixelMask = false;
};

class VerticalOverlapMatcher final
{
public:
    [[nodiscard]] OverlapResult match(
        const ScrollFrame& previous,
        const ScrollFrame& current,
        const OverlapConfig& config = {}) const;
};

} // namespace snipory::core::scroll
