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
    double maximumNormalizedError = 0.08;
    double minimumWinnerMargin = 0.015;
    // A non-zero motion hint resolves otherwise plausible periodic placements;
    // pixel error limits still reject unrelated frames.
    int expectedAdvance = 0;
    int expectedAdvanceTolerance = 0;
    PixelCrop excludedBands;
    int maximumFullResolutionCandidates = 32;
};

struct OverlapResult final
{
    OverlapKind kind = OverlapKind::Insufficient;
    int verticalAdvance = 0;
    int overlapHeight = 0;
    double confidence = 0;
    double normalizedError = 1;
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
