#include "snipory/core/scroll/ScrollStitchSession.h"

#include "snipory/core/scroll/FrameFingerprint.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <iterator>
#include <memory>
#include <new>
#include <optional>
#include <unordered_map>
#include <utility>
#include <vector>

namespace snipory::core::scroll {
namespace {

constexpr FingerprintSize AnchorFingerprintSize{16, 12};
constexpr std::size_t MaximumAnchorSearchCount = 256;
constexpr double AutomaticFixedBandMaximumRatio = 0.75;
constexpr int StationaryPixelChannelTolerance = 3;

[[nodiscard]] bool validUnit(double value)
{
    return std::isfinite(value) && value >= 0.0 && value <= 1.0;
}

[[nodiscard]] bool validConfig(const ScrollStitchConfig& config)
{
    const auto& matcher = config.matcher;
    const bool matcherIsValid = std::isfinite(matcher.minimumOverlapRatio)
        && std::isfinite(matcher.maximumAdvanceRatio)
        && std::isfinite(matcher.maximumNormalizedError)
        && std::isfinite(matcher.minimumWinnerMargin)
        && matcher.minimumOverlapRatio > 0.0
        && matcher.minimumOverlapRatio <= 1.0
        && matcher.maximumAdvanceRatio >= 0.0
        && matcher.maximumAdvanceRatio <= 1.0
        && matcher.maximumNormalizedError >= 0.0
        && matcher.minimumWinnerMargin >= 0.0
        && matcher.expectedAdvance >= 0
        && matcher.expectedAdvanceTolerance >= 0
        && matcher.maximumFullResolutionCandidates > 0
        && matcher.maximumFullResolutionCandidates <= 1'000'000
        && matcher.excludedBands.left >= 0
        && matcher.excludedBands.right >= 0
        && matcher.excludedBands.top >= 0
        && matcher.excludedBands.bottom >= 0;
    return matcherIsValid
        && validUnit(config.duplicateThreshold)
        && validUnit(config.seamWhiteCoverage)
        && config.maximumAcceptedBytes > 0U
        && config.fixedTopCandidateHeight >= 0
        && config.fixedBottomCandidateHeight >= 0
        && config.fixedBandConfirmationMovements >= 3
        && config.fixedBandConfirmationMovements <= 32
        && validUnit(config.fixedBandStationaryThreshold)
        && config.fixedSideMaximumRatio > 0.0
        && config.fixedSideMaximumRatio < 0.5
        && validUnit(config.fixedSideStationaryThreshold)
        && config.scrollbarMaximumWidth >= 0
        && config.scrollbarConfirmationMovements >= 1
        && validUnit(config.scrollbarPersistenceThreshold)
        && validUnit(config.scrollbarMotionThreshold)
        && validUnit(config.scrollbarConfidenceThreshold);
}

[[nodiscard]] std::optional<std::size_t> checkedProduct(
    std::size_t left,
    std::size_t right)
{
    if (left != 0U && right > std::numeric_limits<std::size_t>::max() / left) {
        return std::nullopt;
    }
    return left * right;
}

[[nodiscard]] std::optional<std::size_t> checkedSum(
    std::size_t left,
    std::size_t right)
{
    if (right > std::numeric_limits<std::size_t>::max() - left) {
        return std::nullopt;
    }
    return left + right;
}

[[nodiscard]] std::optional<std::size_t> imageBytes(int width, int height)
{
    if (width <= 0 || height <= 0) {
        return std::nullopt;
    }
    const auto pixels = checkedProduct(
        static_cast<std::size_t>(width),
        static_cast<std::size_t>(height));
    return pixels.has_value() ? checkedProduct(*pixels, 4U) : std::nullopt;
}

[[nodiscard]] double nearWhitePixelRatio(
    const std::uint8_t* row,
    int width)
{
    if (row == nullptr || width <= 0) {
        return 0.0;
    }
    int nearWhitePixels = 0;
    for (int x = 0; x < width; ++x) {
        const auto* pixel = row + static_cast<std::size_t>(x) * 4U;
        nearWhitePixels += pixel[0] >= 250U
                && pixel[1] >= 250U
                && pixel[2] >= 250U
                && pixel[3] >= 250U
            ? 1
            : 0;
    }
    return static_cast<double>(nearWhitePixels) / static_cast<double>(width);
}

void repairIsolatedNearWhiteSeamRows(
    std::uint8_t* pixels,
    int width,
    int height,
    std::size_t bytesPerRow,
    const std::vector<int>& seamRows,
    bool bottomUp = false)
{
    if (pixels == nullptr || width <= 0 || height <= 2) {
        return;
    }
    const auto rowAt = [&](int logicalRow) {
        const int physicalRow = bottomUp ? height - 1 - logicalRow : logicalRow;
        return pixels + static_cast<std::size_t>(physicalRow) * bytesPerRow;
    };
    for (const int seamRow : seamRows) {
        if (seamRow <= 0 || seamRow >= height - 1) {
            continue;
        }
        auto* seam = rowAt(seamRow);
        const auto* above = rowAt(seamRow - 1);
        const auto* below = rowAt(seamRow + 1);
        if (nearWhitePixelRatio(seam, width) < 0.98
            || nearWhitePixelRatio(above, width) > 0.90
            || nearWhitePixelRatio(below, width) > 0.90) {
            continue;
        }
        for (int x = 0; x < width; ++x) {
            const auto offset = static_cast<std::size_t>(x) * 4U;
            for (std::size_t channel = 0; channel < 4U; ++channel) {
                seam[offset + channel] = static_cast<std::uint8_t>(
                    (static_cast<unsigned>(above[offset + channel])
                        + static_cast<unsigned>(below[offset + channel])
                        + 1U)
                    / 2U);
            }
        }
    }
}

[[nodiscard]] std::uint32_t pixelKey(const ScrollFrame& frame, int x, int y)
{
    const auto offset = static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    return static_cast<std::uint32_t>(frame.pixels[offset])
        | (static_cast<std::uint32_t>(frame.pixels[offset + 1U]) << 8U)
        | (static_cast<std::uint32_t>(frame.pixels[offset + 2U]) << 16U);
}

[[nodiscard]] int luminanceAt(const ScrollFrame& frame, int x, int y)
{
    const auto offset = static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    const auto* bgra = frame.pixels.data() + offset;
    const auto weighted = 29U * bgra[0] + 150U * bgra[1] + 77U * bgra[2] + 128U;
    return static_cast<int>(weighted >> 8U);
}

[[nodiscard]] bool pixelEqual(const ScrollFrame& left, const ScrollFrame& right, int x, int y)
{
    return pixelKey(left, x, y) == pixelKey(right, x, y);
}

[[nodiscard]] bool pixelStationary(
    const ScrollFrame& left,
    const ScrollFrame& right,
    int x,
    int y)
{
    const auto leftOffset = static_cast<std::size_t>(y)
            * static_cast<std::size_t>(left.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    const auto rightOffset = static_cast<std::size_t>(y)
            * static_cast<std::size_t>(right.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    for (std::size_t channel = 0; channel < 3U; ++channel) {
        const int difference = static_cast<int>(left.pixels[leftOffset + channel])
            - static_cast<int>(right.pixels[rightOffset + channel]);
        if (std::abs(difference) > StationaryPixelChannelTolerance) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] ScrollFrame copyRows(const ScrollFrame& source, int firstRow, int rowCount)
{
    if (firstRow < 0 || rowCount <= 0 || firstRow > source.height - rowCount) {
        return {};
    }
    ScrollFrame copy(source.width, rowCount);
    if (!copy.isValid()) {
        return {};
    }
    const auto activeBytes = static_cast<std::size_t>(source.width) * 4U;
    for (int row = 0; row < rowCount; ++row) {
        const auto sourceOffset = static_cast<std::size_t>(firstRow + row)
            * static_cast<std::size_t>(source.bytesPerRow);
        const auto destinationOffset = static_cast<std::size_t>(row)
            * static_cast<std::size_t>(copy.bytesPerRow);
        std::memcpy(copy.pixels.data() + destinationOffset, source.pixels.data() + sourceOffset, activeBytes);
    }
    return copy;
}

[[nodiscard]] std::optional<std::shared_ptr<const ScrollFrame>> copyFrame(const ScrollFrame& frame)
{
    auto normalized = copyRows(frame, 0, frame.height);
    if (!normalized.isValid()) {
        return std::nullopt;
    }
    try {
        return std::make_shared<const ScrollFrame>(std::move(normalized));
    } catch (...) {
        return std::nullopt;
    }
}

void blendWhite(std::uint8_t* row, int width, double coverage)
{
    for (int x = 0; x < width; ++x) {
        auto* pixel = row + static_cast<std::size_t>(x) * 4U;
        for (std::size_t channel = 0; channel < 3U; ++channel) {
            const double value = pixel[channel]
                + (pixel[3] - pixel[channel]) * coverage;
            pixel[channel] = static_cast<std::uint8_t>(std::lround(value));
        }
    }
}

} // namespace

class ScrollStitchSession::Implementation final
{
public:
    explicit Implementation(ScrollStitchConfig value)
        : config(std::move(value))
        , configIsValid(validConfig(config))
    {
    }

    struct Segment final
    {
        std::uint64_t fileOffset = 0;
        int outputRows = 0;
        std::int64_t documentStart = 0;
    };

    class SegmentStore final
    {
    public:
        SegmentStore()
            : file_(std::tmpfile())
        {
        }

        ~SegmentStore()
        {
            if (file_ != nullptr) {
                std::fclose(file_);
            }
        }

        SegmentStore(const SegmentStore&) = delete;
        SegmentStore& operator=(const SegmentStore&) = delete;

        [[nodiscard]] std::optional<Segment> appendRows(
            const ScrollFrame& frame,
            int firstRow,
            int rowCount)
        {
            if (file_ == nullptr || firstRow < 0 || rowCount <= 0
                || firstRow > frame.height - rowCount) {
                return std::nullopt;
            }
            const auto activeBytes = checkedProduct(
                static_cast<std::size_t>(frame.width), 4U);
            const auto appendedBytes = activeBytes.has_value()
                ? checkedProduct(*activeBytes, static_cast<std::size_t>(rowCount))
                : std::nullopt;
            if (!activeBytes.has_value() || !appendedBytes.has_value()
                || *appendedBytes > std::numeric_limits<std::uint64_t>::max() - byteCount_
                || !seek(byteCount_)) {
                return std::nullopt;
            }
            const auto offset = byteCount_;
            for (int row = 0; row < rowCount; ++row) {
                const auto sourceOffset = static_cast<std::size_t>(firstRow + row)
                    * static_cast<std::size_t>(frame.bytesPerRow);
                if (std::fwrite(frame.pixels.data() + sourceOffset, 1U, *activeBytes, file_)
                    != *activeBytes) {
                    return std::nullopt;
                }
            }
            if (std::fflush(file_) != 0) {
                return std::nullopt;
            }
            byteCount_ += *appendedBytes;
            return Segment{offset, rowCount};
        }

        [[nodiscard]] bool readRow(
            const Segment& segment,
            int row,
            std::uint8_t* destination,
            std::size_t rowBytes) const
        {
            if (file_ == nullptr || destination == nullptr || row < 0
                || row >= segment.outputRows || rowBytes == 0U) {
                return false;
            }
            const auto rowOffset = checkedProduct(static_cast<std::size_t>(row), rowBytes);
            if (!rowOffset.has_value()
                || *rowOffset > std::numeric_limits<std::uint64_t>::max() - segment.fileOffset
                || !seek(segment.fileOffset + *rowOffset)) {
                return false;
            }
            return std::fread(destination, 1U, rowBytes, file_) == rowBytes;
        }

        [[nodiscard]] std::uint64_t byteCount() const noexcept { return byteCount_; }

    private:
        [[nodiscard]] bool seek(std::uint64_t offset) const
        {
#if defined(_WIN32)
            return offset <= static_cast<std::uint64_t>(std::numeric_limits<__int64>::max())
                && _fseeki64(file_, static_cast<__int64>(offset), SEEK_SET) == 0;
#else
            return offset <= static_cast<std::uint64_t>(std::numeric_limits<off_t>::max())
                && fseeko(file_, static_cast<off_t>(offset), SEEK_SET) == 0;
#endif
        }

        std::FILE* file_ = nullptr;
        std::uint64_t byteCount_ = 0;
    };

    struct ScrollbarObservation final
    {
        int side = 0;
        int width = 0;
        int thumbTop = 0;
        int thumbBottom = 0;
        double trackPersistence = 0.0;
    };

    struct ScrollbarState final
    {
        std::optional<ScrollbarObservation> last;
        int observedMovements = 0;
        int movingMovements = 0;
        double minimumPersistence = 1.0;
        int confirmedSide = 0;
        int confirmedWidth = 0;
    };

    enum class BandDecision
    {
        Ordinary,
        Unresolved,
        Fixed,
    };

    using Direction = ScrollDirection;

    enum class DirectionalDecision
    {
        Movement,
        Opposite,
        Ambiguous,
    };

    struct DirectionalMatch final
    {
        DirectionalDecision decision = DirectionalDecision::Ambiguous;
        Direction candidate = Direction::Undetermined;
        OverlapResult overlap;
        double confidence = 0.0;
    };

    struct PendingMovement final
    {
        std::shared_ptr<const ScrollFrame> frame;
        Fingerprint fingerprint;
        int advance = 0;
        double confidence = 0.0;
        std::size_t persistentBytes = 0U;
        Direction candidate = Direction::Undetermined;
        BandDecision topDecision = BandDecision::Ordinary;
        BandDecision bottomDecision = BandDecision::Ordinary;
    };

    struct FixedBandEvidence final
    {
        OverlapResult overlap;
        Direction candidate = Direction::Undetermined;
        bool top = false;
        bool bottom = false;
        int topHeight = 0;
        int bottomHeight = 0;
    };

    ScrollStitchConfig config;
    bool configIsValid = false;
    Direction direction = Direction::Undetermined;
    std::vector<Segment> segments;
    SegmentStore segmentStore;
    std::vector<Fingerprint> anchors;
    std::vector<PendingMovement> pending;
    std::shared_ptr<const ScrollFrame> tail;
    std::shared_ptr<const ScrollFrame> oppositeFrontier;
    bool tailHasSeparateStorage = false;
    std::size_t persistentBytes = 0;
    int height = 0;
    int width = 0;
    int viewportHeight = 0;
    bool fixedTopConfirmed = false;
    bool fixedBottomConfirmed = false;
    int fixedTopHeight = 0;
    int fixedBottomHeight = 0;
    int fixedTopAgreement = 0;
    int fixedBottomAgreement = 0;
    int fixedTopRunHeight = 0;
    int fixedBottomRunHeight = 0;
    ScrollbarState scrollbar;

    [[nodiscard]] static bool reliableMovement(const OverlapResult& value)
    {
        return value.kind == OverlapKind::Reliable && value.verticalAdvance > 0;
    }

    [[nodiscard]] static bool usableMovement(
        const OverlapResult& value,
        bool allowHighConfidenceAmbiguous)
    {
        constexpr double MinimumUsableAmbiguousConfidence = 0.80;
        return value.verticalAdvance > 0
            && (value.kind == OverlapKind::Reliable
                || (allowHighConfidenceAmbiguous
                    && value.kind == OverlapKind::Ambiguous
                    && value.confidence >= MinimumUsableAmbiguousConfidence));
    }

    [[nodiscard]] static OverlapResult matchInDirection(
        const ScrollFrame& previous,
        const ScrollFrame& current,
        const OverlapConfig& matcherConfig,
        Direction direction)
    {
        VerticalOverlapMatcher matcher;
        return direction == Direction::Up
            ? matcher.match(current, previous, matcherConfig)
            : matcher.match(previous, current, matcherConfig);
    }

    [[nodiscard]] DirectionalMatch directionalMatch(
        const ScrollFrame& previous,
        const ScrollFrame& current,
        const OverlapConfig& matcherConfig,
        Direction expected,
        Direction preferred = Direction::Undetermined) const
    {
        const auto makeMovement = [expected](Direction candidate, OverlapResult overlap) {
            DirectionalMatch result;
            result.candidate = candidate;
            result.confidence = overlap.confidence;
            result.overlap = std::move(overlap);
            result.decision = expected == Direction::Undetermined || expected == candidate
                ? DirectionalDecision::Movement
                : DirectionalDecision::Opposite;
            return result;
        };
        if (preferred != Direction::Undetermined) {
            auto preferredOverlap = matchInDirection(
                previous, current, matcherConfig, preferred);
            const bool preferredUsable = usableMovement(preferredOverlap, true);
            if (matcherConfig.expectedAdvance > 0 && preferredUsable) {
                return makeMovement(preferred, std::move(preferredOverlap));
            }
            const Direction opposite = preferred == Direction::Down
                ? Direction::Up
                : Direction::Down;
            auto oppositeOverlap = matchInDirection(
                previous, current, matcherConfig, opposite);
            const bool oppositeUsable = usableMovement(oppositeOverlap, true);
            const bool oppositeIsSubstantiallyBetter = preferredUsable && oppositeUsable
                && oppositeOverlap.normalizedError + matcherConfig.minimumWinnerMargin
                    < preferredOverlap.normalizedError;
            if (preferredUsable && !oppositeIsSubstantiallyBetter) {
                return makeMovement(preferred, std::move(preferredOverlap));
            }
            if (oppositeUsable) {
                return makeMovement(opposite, std::move(oppositeOverlap));
            }
            DirectionalMatch result;
            result.confidence = std::max(
                preferredOverlap.confidence, oppositeOverlap.confidence);
            return result;
        }
        const auto down = matchInDirection(
            previous, current, matcherConfig, Direction::Down);
        const auto up = matchInDirection(
            previous, current, matcherConfig, Direction::Up);
        const bool downReliable = usableMovement(down, false);
        const bool upReliable = usableMovement(up, false);
        DirectionalMatch result;
        result.confidence = std::max(down.confidence, up.confidence);
        if (!downReliable && !upReliable) {
            return result;
        }
        Direction candidate = Direction::Undetermined;
        if (downReliable && upReliable) {
            return result;
        } else {
            candidate = downReliable ? Direction::Down : Direction::Up;
        }
        result.candidate = candidate;
        result.overlap = candidate == Direction::Down ? down : up;
        result.confidence = result.overlap.confidence;
        if (expected == Direction::Undetermined || expected == candidate) {
            result.decision = DirectionalDecision::Movement;
        } else {
            result.decision = DirectionalDecision::Opposite;
        }
        return result;
    }

    [[nodiscard]] bool duplicateFingerprint(const Fingerprint& left, const Fingerprint& right) const
    {
        const auto distance = FrameFingerprint::meanAbsoluteDistance(left, right);
        return distance.has_value() && *distance <= config.duplicateThreshold;
    }

    [[nodiscard]] std::optional<std::size_t> matchingAnchor(const Fingerprint& fingerprint) const
    {
        const std::size_t searchStart = anchors.size() > MaximumAnchorSearchCount
            ? anchors.size() - MaximumAnchorSearchCount
            : 0U;
        for (std::size_t i = anchors.size(); i > searchStart; --i) {
            if (duplicateFingerprint(anchors[i - 1U], fingerprint)) {
                return i - 1U;
            }
        }
        return std::nullopt;
    }

    [[nodiscard]] std::optional<std::size_t> matchingPending(const Fingerprint& fingerprint) const
    {
        for (std::size_t i = pending.size(); i > 0U; --i) {
            if (duplicateFingerprint(pending[i - 1U].fingerprint, fingerprint)) {
                return i - 1U;
            }
        }
        return std::nullopt;
    }

    [[nodiscard]] const Segment* segmentAtOutputRow(int outputRow, int& rowWithin) const
    {
        if (outputRow < 0 || outputRow >= height || segments.empty()) {
            return nullptr;
        }
        const auto documentRow = segments.front().documentStart
            + static_cast<std::int64_t>(outputRow);
        const auto after = std::upper_bound(
            segments.cbegin(),
            segments.cend(),
            documentRow,
            [](std::int64_t row, const Segment& segment) {
                return row < segment.documentStart;
            });
        if (after == segments.cbegin()) {
            return nullptr;
        }
        const auto& segment = *std::prev(after);
        const auto relative = documentRow - segment.documentStart;
        if (relative < 0 || relative >= segment.outputRows) {
            return nullptr;
        }
        rowWithin = static_cast<int>(relative);
        return &segment;
    }

    [[nodiscard]] std::vector<int> seamRows(bool includePending, int sourceHeight) const
    {
        std::vector<int> result;
        const auto spanCount = checkedSum(
            segments.size(), includePending ? pending.size() : 0U);
        if (spanCount.has_value() && *spanCount > 1U) {
            result.reserve(*spanCount - 1U);
        }
        std::int64_t outputRow = 0;
        const auto appendSpan = [&](int height) {
            if (height <= 0) {
                return;
            }
            if (outputRow > 0 && outputRow < sourceHeight) {
                result.push_back(static_cast<int>(outputRow));
            }
            const auto spanHeight = static_cast<std::int64_t>(height);
            if (outputRow > std::numeric_limits<std::int64_t>::max() - spanHeight) {
                outputRow = std::numeric_limits<std::int64_t>::max();
                return;
            }
            outputRow += spanHeight;
        };
        const Direction pendingDirection = includePending && !pending.empty()
            ? pending.front().candidate
            : Direction::Undetermined;
        if (pendingDirection == Direction::Up) {
            for (auto movement = pending.crbegin(); movement != pending.crend(); ++movement) {
                appendSpan(movement->advance);
            }
        }
        for (const auto& segment : segments) {
            appendSpan(segment.outputRows);
        }
        if (pendingDirection == Direction::Down) {
            for (const auto& movement : pending) {
                appendSpan(movement.advance);
            }
        }
        return result;
    }

    [[nodiscard]] std::size_t pruneAnchorHistory()
    {
        if (anchors.size() <= MaximumAnchorSearchCount) {
            return 0U;
        }
        const auto removeCount = anchors.size() - MaximumAnchorSearchCount;
        std::size_t removedBytes = 0U;
        for (std::size_t index = 0; index < removeCount; ++index) {
            removedBytes += anchors[index].luminance.capacity();
        }
        anchors.erase(
            anchors.begin(),
            anchors.begin() + static_cast<std::ptrdiff_t>(removeCount));
        return removedBytes;
    }

    [[nodiscard]] int stationarySideWidth(
        const ScrollFrame& previous,
        const ScrollFrame& current,
        bool left) const
    {
        if (!config.enableFixedSideDetection) {
            return 0;
        }
        const int budget = std::min(
            current.width / 2 - 1,
            static_cast<int>(std::floor(
                static_cast<double>(current.width) * config.fixedSideMaximumRatio)));
        const int firstRow = std::min(config.fixedTopCandidateHeight, current.height / 4);
        const int lastRow = current.height
            - std::min(config.fixedBottomCandidateHeight, current.height / 4);
        const int rowCount = lastRow - firstRow;
        if (budget <= 0 || rowCount <= 0) {
            return 0;
        }
        int stationaryColumns = 0;
        for (int offset = 0; offset < budget; ++offset) {
            const int x = left ? offset : current.width - 1 - offset;
            int equal = 0;
            for (int y = firstRow; y < lastRow; ++y) {
                equal += pixelStationary(previous, current, x, y) ? 1 : 0;
            }
            const double ratio = static_cast<double>(equal) / static_cast<double>(rowCount);
            if (ratio < config.fixedSideStationaryThreshold) {
                break;
            }
            ++stationaryColumns;
        }
        return stationaryColumns;
    }

    [[nodiscard]] OverlapConfig effectiveMatcherConfig(
        const ScrollFrame* previous = nullptr,
        const ScrollFrame* current = nullptr) const
    {
        auto result = config.matcher;
        if (fixedTopConfirmed) {
            result.excludedBands.top = std::max(
                result.excludedBands.top, fixedTopHeight);
        }
        if (fixedBottomConfirmed) {
            result.excludedBands.bottom = std::max(
                result.excludedBands.bottom, fixedBottomHeight);
        }
        result.excludedBands.right = std::max(
            result.excludedBands.right, config.scrollbarMaximumWidth);
        result.excludedBands.left = std::max(
            result.excludedBands.left, config.scrollbarMaximumWidth);
        if (previous != nullptr && current != nullptr) {
            result.excludedBands.left = std::max(
                result.excludedBands.left,
                stationarySideWidth(*previous, *current, true));
            result.excludedBands.right = std::max(
                result.excludedBands.right,
                stationarySideWidth(*previous, *current, false));
        }
        return result;
    }

    [[nodiscard]] double stationaryRatio(
        const ScrollFrame& previous,
        const ScrollFrame& current,
        int firstRow,
        int rowCount) const
    {
        if (rowCount <= 0) {
            return 0.0;
        }
        std::size_t equal = 0U;
        const auto total = static_cast<std::size_t>(rowCount) * static_cast<std::size_t>(width);
        for (int y = firstRow; y < firstRow + rowCount; ++y) {
            for (int x = 0; x < width; ++x) {
                equal += pixelStationary(previous, current, x, y) ? 1U : 0U;
            }
        }
        return static_cast<double>(equal) / static_cast<double>(total);
    }

    [[nodiscard]] bool centralDocumentMoved(
        const ScrollFrame& previous,
        const ScrollFrame& current) const
    {
        const int firstRow = config.fixedTopCandidateHeight;
        const int rows = current.height - firstRow - config.fixedBottomCandidateHeight;
        return rows > 0
            && stationaryRatio(previous, current, firstRow, rows)
                < config.fixedBandStationaryThreshold;
    }

    [[nodiscard]] int stationaryBandHeight(
        const ScrollFrame& previous,
        const ScrollFrame& current,
        bool top) const
    {
        if (!config.enableFixedBandDetection || (top ? fixedTopConfirmed : fixedBottomConfirmed)) {
            return 0;
        }
        const int configuredBudget = top
            ? config.fixedTopCandidateHeight
            : config.fixedBottomCandidateHeight;
        const int minimumScrollingRows = std::max(1, static_cast<int>(std::ceil(
            static_cast<double>(current.height) * config.matcher.minimumOverlapRatio)));
        const int automaticBudget = std::min(
            current.height - minimumScrollingRows,
            std::max(96, static_cast<int>(std::floor(
                static_cast<double>(current.height) * AutomaticFixedBandMaximumRatio))));
        const int budget = configuredBudget > 0
            ? configuredBudget
            : automaticBudget;
        const int edgeInset = std::min(config.scrollbarMaximumWidth, current.width / 8);
        const int firstColumn = edgeInset;
        const int columnCount = current.width - edgeInset * 2;
        if (budget <= 0 || columnCount <= 0) {
            return 0;
        }
        int stationaryRows = 0;
        for (int offset = 0; offset < budget; ++offset) {
            const int y = top ? offset : current.height - 1 - offset;
            int equal = 0;
            for (int x = firstColumn; x < firstColumn + columnCount; ++x) {
                equal += pixelStationary(previous, current, x, y) ? 1 : 0;
            }
            const double ratio = static_cast<double>(equal) / static_cast<double>(columnCount);
            if (ratio < config.fixedBandStationaryThreshold) {
                break;
            }
            ++stationaryRows;
        }
        return stationaryRows;
    }

    [[nodiscard]] FixedBandEvidence fixedBandEvidence(
        const ScrollFrame& previous,
        const ScrollFrame& current,
        Direction establishedDirection) const
    {
        FixedBandEvidence evidence;
        evidence.topHeight = stationaryBandHeight(previous, current, true);
        evidence.bottomHeight = stationaryBandHeight(previous, current, false);
        evidence.top = evidence.topHeight > 0;
        evidence.bottom = evidence.bottomHeight > 0;
        const int minimumScrollingRows = std::max(1, static_cast<int>(std::ceil(
            static_cast<double>(current.height) * config.matcher.minimumOverlapRatio)));
        if (evidence.topHeight + evidence.bottomHeight
            > current.height - minimumScrollingRows) {
            evidence.top = false;
            evidence.bottom = false;
            return evidence;
        }
        if ((!evidence.top && !evidence.bottom) || !centralDocumentMoved(previous, current)) {
            evidence.top = false;
            evidence.bottom = false;
            return evidence;
        }
        auto matcherConfig = effectiveMatcherConfig(&previous, &current);
        if (evidence.top) {
            matcherConfig.excludedBands.top = std::max(
                matcherConfig.excludedBands.top,
                std::max(evidence.topHeight, fixedTopRunHeight));
        }
        if (evidence.bottom) {
            matcherConfig.excludedBands.bottom = std::max(
                matcherConfig.excludedBands.bottom,
                std::max(evidence.bottomHeight, fixedBottomRunHeight));
        }
        DirectionalMatch directional;
        if (establishedDirection == Direction::Undetermined) {
            directional = directionalMatch(
                previous, current, matcherConfig, Direction::Undetermined);
        } else {
            directional.candidate = establishedDirection;
            directional.overlap = matchInDirection(
                previous, current, matcherConfig, establishedDirection);
            directional.confidence = directional.overlap.confidence;
            if (reliableMovement(directional.overlap)) {
                directional.decision = DirectionalDecision::Movement;
            }
        }
        if (directional.decision != DirectionalDecision::Movement
            && evidence.top && evidence.bottom) {
            const auto matchSingleBand = [&](bool top) {
                auto singleBandConfig = effectiveMatcherConfig(&previous, &current);
                if (top) {
                    singleBandConfig.excludedBands.top = std::max(
                        singleBandConfig.excludedBands.top,
                        std::max(evidence.topHeight, fixedTopRunHeight));
                } else {
                    singleBandConfig.excludedBands.bottom = std::max(
                        singleBandConfig.excludedBands.bottom,
                        std::max(evidence.bottomHeight, fixedBottomRunHeight));
                }
                if (establishedDirection == Direction::Undetermined) {
                    return directionalMatch(
                        previous, current, singleBandConfig, Direction::Undetermined);
                }
                DirectionalMatch result;
                result.candidate = establishedDirection;
                result.overlap = matchInDirection(
                    previous, current, singleBandConfig, establishedDirection);
                result.confidence = result.overlap.confidence;
                if (reliableMovement(result.overlap)) {
                    result.decision = DirectionalDecision::Movement;
                }
                return result;
            };
            const auto topOnly = matchSingleBand(true);
            const auto bottomOnly = matchSingleBand(false);
            const bool topMoves = topOnly.decision == DirectionalDecision::Movement;
            const bool bottomMoves = bottomOnly.decision == DirectionalDecision::Movement;
            const bool compatible = !topMoves || !bottomMoves
                || topOnly.candidate == bottomOnly.candidate;
            if (compatible && (topMoves || bottomMoves)) {
                const bool useTop = topMoves
                    && (!bottomMoves || topOnly.confidence >= bottomOnly.confidence);
                directional = useTop ? topOnly : bottomOnly;
                evidence.top = useTop;
                evidence.bottom = !useTop;
            }
        }
        if (directional.decision != DirectionalDecision::Movement) {
            evidence.top = false;
            evidence.bottom = false;
            return evidence;
        }
        evidence.overlap = directional.overlap;
        evidence.candidate = directional.candidate;

        auto bandIsInformativeAndStationary = [&](bool top, int height) {
            const int edgeInset = std::min(config.scrollbarMaximumWidth, current.width / 8);
            const int firstColumn = edgeInset;
            const int columnCount = current.width - edgeInset * 2;
            if (height <= 0 || columnCount < 2) {
                return false;
            }
            int minimumValue = 255;
            int maximumValue = 0;
            std::size_t horizontalEdges = 0U;
            std::size_t horizontalPairs = 0U;
            double sameError = 0.0;
            double alignedError = 0.0;
            std::size_t alignedSamples = 0U;
            for (int row = 0; row < height; ++row) {
                const int y = top ? row : current.height - height + row;
                int previousValue = -1;
                for (int x = firstColumn; x < firstColumn + columnCount; ++x) {
                    const int currentValue = luminanceAt(current, x, y);
                    const int previousSame = luminanceAt(previous, x, y);
                    minimumValue = std::min(minimumValue, currentValue);
                    maximumValue = std::max(maximumValue, currentValue);
                    if (previousValue >= 0) {
                        ++horizontalPairs;
                        horizontalEdges += std::abs(currentValue - previousValue) >= 1 ? 1U : 0U;
                    }
                    previousValue = currentValue;
                    sameError += std::abs(currentValue - previousSame) / 255.0;

                    const bool upward = evidence.candidate == Direction::Up;
                    const int alignedPreviousY = top
                        ? y + (upward ? 0 : evidence.overlap.verticalAdvance)
                        : y - (upward ? evidence.overlap.verticalAdvance : 0);
                    const int alignedCurrentY = top
                        ? y + (upward ? evidence.overlap.verticalAdvance : 0)
                        : y - (upward ? 0 : evidence.overlap.verticalAdvance);
                    if (alignedPreviousY >= 0 && alignedPreviousY < previous.height
                        && alignedCurrentY >= 0 && alignedCurrentY < current.height) {
                        const int previousAligned = luminanceAt(previous, x, alignedPreviousY);
                        const int currentAligned = luminanceAt(current, x, alignedCurrentY);
                        alignedError += std::abs(previousAligned - currentAligned) / 255.0;
                        ++alignedSamples;
                    }
                }
            }
            const std::size_t sameSamples = static_cast<std::size_t>(height)
                * static_cast<std::size_t>(columnCount);
            const double edgeRatio = horizontalPairs > 0U
                ? static_cast<double>(horizontalEdges) / static_cast<double>(horizontalPairs)
                : 0.0;
            if (maximumValue - minimumValue < 8 || edgeRatio < 0.05
                || alignedSamples < static_cast<std::size_t>(columnCount)) {
                return false;
            }
            const double meanSameError = sameError / static_cast<double>(sameSamples);
            const double meanAlignedError = alignedError / static_cast<double>(alignedSamples);
            return meanAlignedError - meanSameError >= 0.01;
        };

        const bool informativeTop = evidence.top
            && bandIsInformativeAndStationary(true, evidence.topHeight);
        const bool informativeBottom = evidence.bottom
            && bandIsInformativeAndStationary(false, evidence.bottomHeight);
        if (informativeTop != evidence.top || informativeBottom != evidence.bottom) {
            evidence.top = informativeTop;
            evidence.bottom = informativeBottom;
            if (!evidence.top && !evidence.bottom) {
                return evidence;
            }
            matcherConfig = effectiveMatcherConfig(&previous, &current);
            if (evidence.top) {
                matcherConfig.excludedBands.top = std::max(
                    matcherConfig.excludedBands.top,
                    std::max(evidence.topHeight, fixedTopRunHeight));
            }
            if (evidence.bottom) {
                matcherConfig.excludedBands.bottom = std::max(
                    matcherConfig.excludedBands.bottom,
                    std::max(evidence.bottomHeight, fixedBottomRunHeight));
            }
            const auto refined = matchInDirection(
                previous, current, matcherConfig, evidence.candidate);
            if (!reliableMovement(refined)) {
                evidence.top = false;
                evidence.bottom = false;
            } else {
                evidence.overlap = refined;
            }
        }
        return evidence;
    }

    [[nodiscard]] std::optional<ScrollbarObservation> detectScrollbarSide(
        const ScrollFrame& frame,
        int side) const
    {
        const int budget = std::min(config.scrollbarMaximumWidth, frame.width / 8);
        if (budget <= 0) {
            return std::nullopt;
        }

        ScrollbarObservation result;
        result.side = side;
        double minimumPersistence = 1.0;
        for (int offset = 0; offset < budget; ++offset) {
            const int x = side < 0 ? offset : frame.width - 1 - offset;
            std::unordered_map<std::uint32_t, int> counts;
            counts.reserve(static_cast<std::size_t>(frame.height));
            for (int y = 0; y < frame.height; ++y) {
                ++counts[pixelKey(frame, x, y)];
            }
            const auto dominant = std::max_element(
                counts.cbegin(), counts.cend(), [](const auto& left, const auto& right) {
                    return left.second < right.second;
                });
            if (dominant == counts.cend()) {
                break;
            }
            const double persistence = static_cast<double>(dominant->second)
                / static_cast<double>(frame.height);
            if (persistence < config.scrollbarPersistenceThreshold) {
                break;
            }

            int firstContrast = -1;
            int lastContrast = -1;
            int contrastRows = 0;
            for (int y = 0; y < frame.height; ++y) {
                if (pixelKey(frame, x, y) != dominant->first) {
                    firstContrast = firstContrast < 0 ? y : firstContrast;
                    lastContrast = y;
                    ++contrastRows;
                }
            }
            const bool contiguousThumb = firstContrast >= 0
                && lastContrast - firstContrast + 1 == contrastRows
                && contrastRows >= 4
                && contrastRows <= frame.height / 2;
            if (!contiguousThumb
                || (result.width > 0
                    && (std::abs(firstContrast - result.thumbTop) > 1
                        || std::abs(lastContrast + 1 - result.thumbBottom) > 1))) {
                break;
            }
            if (result.width == 0) {
                result.thumbTop = firstContrast;
                result.thumbBottom = lastContrast + 1;
            }
            ++result.width;
            minimumPersistence = std::min(minimumPersistence, persistence);
        }
        if (result.width == 0) {
            return std::nullopt;
        }
        result.trackPersistence = minimumPersistence;
        return result;
    }

    [[nodiscard]] std::optional<ScrollbarObservation> detectScrollbar(
        const ScrollFrame& frame) const
    {
        const auto left = detectScrollbarSide(frame, -1);
        const auto right = detectScrollbarSide(frame, 1);
        if (left.has_value() && right.has_value()) {
            return std::nullopt;
        }
        return left.has_value() ? left : right;
    }

    [[nodiscard]] ScrollbarState nextScrollbarState(
        ScrollbarState state,
        const ScrollFrame& previous,
        const ScrollFrame& current) const
    {
        if (config.scrollbarMaximumWidth <= 0 || state.confirmedWidth > 0) {
            return state;
        }
        if (!state.last.has_value()) {
            state.last = detectScrollbar(previous);
        }
        const auto observation = detectScrollbar(current);
        if (!state.last.has_value() || !observation.has_value()
            || state.last->side != observation->side
            || state.last->width != observation->width) {
            state.last = observation;
            state.observedMovements = 0;
            state.movingMovements = 0;
            state.minimumPersistence = 1.0;
            return state;
        }

        ++state.observedMovements;
        const double normalizedMotion = static_cast<double>(
            std::abs(observation->thumbTop - state.last->thumbTop))
            / static_cast<double>(current.height);
        if (normalizedMotion >= config.scrollbarMotionThreshold) {
            ++state.movingMovements;
        }
        state.minimumPersistence = std::min(
            state.minimumPersistence,
            std::min(state.last->trackPersistence, observation->trackPersistence));
        state.last = observation;

        const double movingRatio = static_cast<double>(state.movingMovements)
            / static_cast<double>(state.observedMovements);
        const double confidence = movingRatio * state.minimumPersistence;
        if (state.observedMovements >= config.scrollbarConfirmationMovements
            && confidence >= config.scrollbarConfidenceThreshold) {
            state.confirmedSide = observation->side;
            state.confirmedWidth = observation->width;
        }
        return state;
    }

    void clearPending() noexcept
    {
        for (const auto& movement : pending) {
            persistentBytes -= movement.persistentBytes;
        }
        pending.clear();
        if (!fixedTopConfirmed) {
            fixedTopAgreement = 0;
            fixedTopRunHeight = 0;
        }
        if (!fixedBottomConfirmed) {
            fixedBottomAgreement = 0;
            fixedBottomRunHeight = 0;
        }
    }
};

ScrollStitchSession::ScrollStitchSession(ScrollStitchConfig config)
    : implementation_(std::make_unique<Implementation>(std::move(config)))
{
}

ScrollStitchSession::~ScrollStitchSession() = default;
ScrollStitchSession::ScrollStitchSession(ScrollStitchSession&&) noexcept = default;
ScrollStitchSession& ScrollStitchSession::operator=(ScrollStitchSession&&) noexcept = default;

AppendResult ScrollStitchSession::append(
    const ScrollFrame& frame,
    ScrollDirection preferredDirection,
    int expectedAdvance)
try {
    AppendResult result;
    result.outputHeight = implementation_->height;
    const auto& config = implementation_->config;
    if (!implementation_->configIsValid || !frame.isValid()
        || config.fixedTopCandidateHeight >= frame.height - config.fixedBottomCandidateHeight
        || config.scrollbarMaximumWidth >= frame.width
        || config.matcher.excludedBands.left >= frame.width - config.matcher.excludedBands.right
        || config.matcher.excludedBands.top >= frame.height - config.matcher.excludedBands.bottom) {
        return result;
    }

    const auto fullFrameBytes = imageBytes(frame.width, frame.height);
    if (!fullFrameBytes.has_value()) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }
    if (implementation_->anchors.empty()
        && *fullFrameBytes >= config.maximumAcceptedBytes) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }
    auto fingerprint = FrameFingerprint::make(frame, AnchorFingerprintSize);
    if (fingerprint.luminance.empty()) {
        return result;
    }
    const std::size_t fingerprintBytes = fingerprint.luminance.capacity();

    if (implementation_->anchors.empty()) {
        const auto projected = checkedSum(*fullFrameBytes, fingerprintBytes);
        if (!projected.has_value() || *projected >= config.maximumAcceptedBytes) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        const auto storedFrame = copyFrame(frame);
        const auto storedSegment = implementation_->segmentStore.appendRows(
            frame, 0, frame.height);
        if (!storedFrame.has_value() || !storedSegment.has_value()) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        try {
            implementation_->segments.reserve(1U);
            implementation_->anchors.reserve(1U);
            implementation_->segments.push_back(*storedSegment);
            implementation_->anchors.push_back(std::move(fingerprint));
        } catch (...) {
            implementation_->segments.clear();
            implementation_->anchors.clear();
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        implementation_->tail = *storedFrame;
        implementation_->oppositeFrontier = *storedFrame;
        implementation_->width = frame.width;
        implementation_->viewportHeight = frame.height;
        implementation_->height = frame.height;
        implementation_->persistentBytes = *projected;
        result.kind = AppendKind::AcceptedInitial;
        result.appendedHeight = frame.height;
        result.outputHeight = frame.height;
        result.confidence = 1.0;
        return result;
    }

    if (frame.width != implementation_->width
        || frame.height != implementation_->viewportHeight) {
        return result;
    }
    if (const auto match = implementation_->matchingAnchor(fingerprint); match.has_value()) {
        result.kind = implementation_->pending.empty()
                && *match + 1U == implementation_->anchors.size()
            ? AppendKind::DuplicateDiscarded
            : AppendKind::ReviewDiscarded;
        result.confidence = 1.0;
        return result;
    }
    if (const auto match = implementation_->matchingPending(fingerprint); match.has_value()) {
        result.kind = *match + 1U == implementation_->pending.size()
            ? AppendKind::DuplicateDiscarded
            : AppendKind::ReviewDiscarded;
        result.confidence = 1.0;
        return result;
    }

    const ScrollFrame* evidenceTail = implementation_->pending.empty()
        ? implementation_->tail.get()
        : implementation_->pending.back().frame.get();
    auto matcherConfig = implementation_->effectiveMatcherConfig(evidenceTail, &frame);
    if (expectedAdvance > 0) {
        matcherConfig.expectedAdvance = expectedAdvance;
        matcherConfig.expectedAdvanceTolerance = std::min(
            16, std::max(2, static_cast<int>(std::ceil(expectedAdvance * 0.03))));
    }
    using Direction = Implementation::Direction;
    using DirectionalDecision = Implementation::DirectionalDecision;
    Direction expectedDirection = implementation_->direction != Direction::Undetermined
        ? implementation_->direction
        : (!implementation_->pending.empty()
                ? implementation_->pending.back().candidate
                : Direction::Undetermined);
    auto directional = implementation_->directionalMatch(
        *evidenceTail, frame, matcherConfig, expectedDirection, preferredDirection);
    if (implementation_->direction == Direction::Undetermined
        && !implementation_->pending.empty()) {
        auto pendingDirectionConfig = matcherConfig;
        if (implementation_->fixedTopAgreement > 0) {
            pendingDirectionConfig.excludedBands.top = std::max(
                pendingDirectionConfig.excludedBands.top,
                implementation_->fixedTopRunHeight);
        }
        if (implementation_->fixedBottomAgreement > 0) {
            pendingDirectionConfig.excludedBands.bottom = std::max(
                pendingDirectionConfig.excludedBands.bottom,
                implementation_->fixedBottomRunHeight);
        }
        const auto pendingDirectional = implementation_->directionalMatch(
            *evidenceTail, frame, pendingDirectionConfig, expectedDirection);
        if (pendingDirectional.decision == DirectionalDecision::Opposite) {
            const Direction restartedCandidate = pendingDirectional.candidate;
            implementation_->clearPending();
            evidenceTail = implementation_->tail.get();
            expectedDirection = Direction::Undetermined;
            directional = implementation_->directionalMatch(
                *evidenceTail, frame, matcherConfig, expectedDirection);
            if (directional.decision != DirectionalDecision::Movement
                || directional.candidate != restartedCandidate) {
                const auto restartedEvidence = implementation_->fixedBandEvidence(
                    *evidenceTail, frame, Direction::Undetermined);
                if ((!restartedEvidence.top && !restartedEvidence.bottom)
                    || restartedEvidence.candidate != restartedCandidate) {
                    result.kind = directional.decision == DirectionalDecision::Ambiguous
                        ? AppendKind::LowConfidenceDiscarded
                        : AppendKind::ReviewDiscarded;
                    result.confidence = std::max(
                        pendingDirectional.confidence, directional.confidence);
                    return result;
                }
                directional.decision = DirectionalDecision::Movement;
                directional.candidate = restartedCandidate;
                directional.overlap = restartedEvidence.overlap;
                directional.confidence = restartedEvidence.overlap.confidence;
            }
        }
    }
    if (implementation_->pending.empty()
        && implementation_->direction != Direction::Undetermined
        && directional.decision != DirectionalDecision::Movement) {
        const auto frontierMatch = implementation_->directionalMatch(
            *implementation_->oppositeFrontier,
            frame,
            matcherConfig,
            implementation_->direction);
        if (frontierMatch.decision == DirectionalDecision::Opposite) {
            directional = frontierMatch;
        }
    }
    auto overlap = directional.overlap;
    result.confidence = directional.confidence;
    bool prepend = directional.candidate == Direction::Up;
    std::optional<Implementation::Direction> directionToLock;
    if (!config.enableFixedBandDetection && implementation_->pending.empty()) {
        if (directional.decision != DirectionalDecision::Movement) {
            result.kind = directional.decision == DirectionalDecision::Opposite
                ? AppendKind::ReviewDiscarded
                : AppendKind::LowConfidenceDiscarded;
            return result;
        }
        directionToLock = implementation_->direction == Direction::Undetermined
            ? std::optional<Direction>(directional.candidate)
            : std::nullopt;
        result.confidence = overlap.confidence;
    }
    const Direction establishedDirection = expectedDirection != Direction::Undetermined
        ? expectedDirection
        : (directional.decision == DirectionalDecision::Movement
                ? directional.candidate
                : Direction::Undetermined);
    const auto evidence = implementation_->fixedBandEvidence(
        *evidenceTail, frame, establishedDirection);
    if (evidence.top || evidence.bottom) {
        directional.decision = DirectionalDecision::Movement;
        directional.candidate = evidence.candidate;
        directional.overlap = evidence.overlap;
        directional.confidence = evidence.overlap.confidence;
        overlap = evidence.overlap;
        prepend = evidence.candidate == Direction::Up;
        result.confidence = evidence.overlap.confidence;
    }
    if (config.enableFixedBandDetection && !implementation_->pending.empty()
        && directional.decision != DirectionalDecision::Movement) {
        auto reviewConfig = matcherConfig;
        if (implementation_->fixedTopAgreement > 0) {
            reviewConfig.excludedBands.top = std::max(
                reviewConfig.excludedBands.top, implementation_->fixedTopRunHeight);
        }
        if (implementation_->fixedBottomAgreement > 0) {
            reviewConfig.excludedBands.bottom = std::max(
                reviewConfig.excludedBands.bottom, implementation_->fixedBottomRunHeight);
        }
        for (auto movement = implementation_->pending.crbegin();
             movement != implementation_->pending.crend(); ++movement) {
            const auto review = implementation_->directionalMatch(
                *movement->frame, frame, reviewConfig, movement->candidate);
            if (review.decision == DirectionalDecision::Opposite) {
                if (implementation_->direction == Direction::Undetermined) {
                    implementation_->clearPending();
                }
                result.kind = AppendKind::ReviewDiscarded;
                result.confidence = review.confidence;
                return result;
            }
        }
    }
    const bool topEvidenceBroke = !implementation_->fixedTopConfirmed
        && implementation_->fixedTopAgreement > 0 && !evidence.top;
    const bool bottomEvidenceBroke = !implementation_->fixedBottomConfirmed
        && implementation_->fixedBottomAgreement > 0 && !evidence.bottom;
    auto movementOverlap = evidence.top || evidence.bottom
        ? evidence.overlap
        : overlap;
    if (!implementation_->pending.empty() && (topEvidenceBroke || bottomEvidenceBroke)) {
        auto transitionConfig = matcherConfig;
        if (evidence.top || topEvidenceBroke) {
            transitionConfig.excludedBands.top = std::max(
                transitionConfig.excludedBands.top,
                std::max(evidence.topHeight, implementation_->fixedTopRunHeight));
        }
        if (evidence.bottom || bottomEvidenceBroke) {
            transitionConfig.excludedBands.bottom = std::max(
                transitionConfig.excludedBands.bottom,
                std::max(evidence.bottomHeight, implementation_->fixedBottomRunHeight));
        }
        const auto transition = implementation_->directionalMatch(
            *evidenceTail, frame, transitionConfig, expectedDirection);
        if (transition.decision == DirectionalDecision::Movement) {
            directional = transition;
            overlap = transition.overlap;
            prepend = transition.candidate == Direction::Up;
            movementOverlap = transition.overlap;
            result.confidence = transition.confidence;
        }
    }
    if (config.enableFixedBandDetection
        && directional.decision != DirectionalDecision::Movement) {
        result.kind = directional.decision == DirectionalDecision::Opposite
            ? AppendKind::ReviewDiscarded
            : AppendKind::LowConfidenceDiscarded;
        return result;
    }

    const bool continuePending = !implementation_->pending.empty()
        || evidence.top || evidence.bottom;
    if (continuePending) {
        if (!Implementation::usableMovement(
                movementOverlap, preferredDirection != Direction::Undetermined)) {
            auto reviewConfig = matcherConfig;
            if (implementation_->fixedTopAgreement > 0) {
                reviewConfig.excludedBands.top = std::max(
                    reviewConfig.excludedBands.top, implementation_->fixedTopRunHeight);
            }
            if (implementation_->fixedBottomAgreement > 0) {
                reviewConfig.excludedBands.bottom = std::max(
                    reviewConfig.excludedBands.bottom, implementation_->fixedBottomRunHeight);
            }
            for (auto movement = implementation_->pending.crbegin();
                 movement != implementation_->pending.crend(); ++movement) {
                const auto review = implementation_->directionalMatch(
                    *movement->frame, frame, reviewConfig, movement->candidate);
                if (review.decision == DirectionalDecision::Opposite) {
                    if (implementation_->direction == Direction::Undetermined) {
                        implementation_->clearPending();
                    }
                    result.kind = AppendKind::ReviewDiscarded;
                    result.confidence = review.confidence;
                    return result;
                }
            }
            return result;
        }
        const auto contribution = checkedSum(*fullFrameBytes, fingerprintBytes);
        const auto projected = contribution.has_value()
            ? checkedSum(implementation_->persistentBytes, *contribution)
            : std::nullopt;
        if (!projected.has_value() || *projected >= config.maximumAcceptedBytes) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        const auto storedPendingFrame = copyFrame(frame);
        if (!storedPendingFrame.has_value()) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }

        Implementation::PendingMovement newMovement{
            *storedPendingFrame,
            std::move(fingerprint),
            movementOverlap.verticalAdvance,
            movementOverlap.confidence,
            *contribution,
            directional.candidate,
        };
        const int requiredEvidence = std::max(3, config.fixedBandConfirmationMovements);
        const auto heightIsConsistent = [](int previousHeight, int currentHeight) {
            const int tolerance = std::max(2, static_cast<int>(
                std::ceil(static_cast<double>(std::max(1, previousHeight)) * 0.15)));
            return std::abs(previousHeight - currentHeight) <= tolerance;
        };
        const bool restartTopRun = evidence.top && implementation_->fixedTopAgreement > 0
            && !heightIsConsistent(implementation_->fixedTopRunHeight, evidence.topHeight);
        const bool restartBottomRun = evidence.bottom && implementation_->fixedBottomAgreement > 0
            && !heightIsConsistent(implementation_->fixedBottomRunHeight, evidence.bottomHeight);
        const int nextTopAgreement = evidence.top
            ? (restartTopRun ? 1 : implementation_->fixedTopAgreement + 1)
            : 0;
        const int nextBottomAgreement = evidence.bottom
            ? (restartBottomRun ? 1 : implementation_->fixedBottomAgreement + 1)
            : 0;
        const int nextTopRunHeight = evidence.top
            ? (implementation_->fixedTopAgreement > 0 && !restartTopRun
                    ? std::min(implementation_->fixedTopRunHeight, evidence.topHeight)
                    : evidence.topHeight)
            : 0;
        const int nextBottomRunHeight = evidence.bottom
            ? (implementation_->fixedBottomAgreement > 0 && !restartBottomRun
                    ? std::min(implementation_->fixedBottomRunHeight, evidence.bottomHeight)
                    : evidence.bottomHeight)
            : 0;
        const bool confirmTop = !implementation_->fixedTopConfirmed
            && nextTopAgreement >= requiredEvidence;
        const bool confirmBottom = !implementation_->fixedBottomConfirmed
            && nextBottomAgreement >= requiredEvidence;

        using BandDecision = Implementation::BandDecision;
        std::vector<std::pair<BandDecision, BandDecision>> decisions;
        decisions.reserve(implementation_->pending.size() + 1U);
        auto resolveExisting = [](BandDecision decision, bool confirm, bool evidenceNow, bool restart) {
            if (decision != BandDecision::Unresolved) {
                return decision;
            }
            if (confirm) {
                return BandDecision::Fixed;
            }
            return evidenceNow && !restart ? BandDecision::Unresolved : BandDecision::Ordinary;
        };
        for (const auto& movement : implementation_->pending) {
            decisions.emplace_back(
                resolveExisting(movement.topDecision, confirmTop, evidence.top, restartTopRun),
                resolveExisting(
                    movement.bottomDecision, confirmBottom, evidence.bottom, restartBottomRun));
        }
        newMovement.topDecision = implementation_->fixedTopConfirmed || confirmTop
            ? BandDecision::Fixed
            : (evidence.top ? BandDecision::Unresolved : BandDecision::Ordinary);
        newMovement.bottomDecision = implementation_->fixedBottomConfirmed || confirmBottom
            ? BandDecision::Fixed
            : (evidence.bottom ? BandDecision::Unresolved : BandDecision::Ordinary);
        decisions.emplace_back(newMovement.topDecision, newMovement.bottomDecision);

        std::size_t safePrefix = 0U;
        while (safePrefix < decisions.size()
            && decisions[safePrefix].first != BandDecision::Unresolved
            && decisions[safePrefix].second != BandDecision::Unresolved) {
            ++safePrefix;
        }
        if (safePrefix == 0U) {
            const int pendingAdvance = newMovement.advance;
            const Direction pendingDirection = newMovement.candidate;
            implementation_->pending.reserve(implementation_->pending.size() + 1U);
            for (std::size_t i = 0; i < implementation_->pending.size(); ++i) {
                implementation_->pending[i].topDecision = decisions[i].first;
                implementation_->pending[i].bottomDecision = decisions[i].second;
            }
            implementation_->pending.push_back(std::move(newMovement));
            implementation_->persistentBytes = *projected;
            implementation_->fixedTopAgreement = nextTopAgreement;
            implementation_->fixedBottomAgreement = nextBottomAgreement;
            implementation_->fixedTopRunHeight = nextTopRunHeight;
            implementation_->fixedBottomRunHeight = nextBottomRunHeight;
            result.kind = AppendKind::AwaitingEvidence;
            result.direction = pendingDirection;
            result.appendedHeight = pendingAdvance;
            result.outputHeight = previewOutputHeight();
            result.confidence = movementOverlap.confidence;
            return result;
        }

        const auto failedPendingCommit = [&]() {
            implementation_->clearPending();
            result.kind = AppendKind::ResourceLimit;
            result.outputHeight = implementation_->height;
            return result;
        };
        std::vector<Implementation::Segment> preparedSegments;
        try {
            preparedSegments.reserve(safePrefix);
        } catch (const std::bad_alloc&) {
            return failedPendingCommit();
        }
        int flushedHeight = 0;
        auto preparedScrollbar = implementation_->scrollbar;
        const ScrollFrame* previous = implementation_->tail.get();
        auto prepareMovement = [&](
                                   const Implementation::PendingMovement& movement,
                                   BandDecision topDecision,
                                   BandDecision bottomDecision) {
            if (movement.advance > std::numeric_limits<int>::max() - flushedHeight) {
                return false;
            }
            const bool excludeTop = topDecision == BandDecision::Fixed;
            const bool excludeBottom = bottomDecision == BandDecision::Fixed;
            const int topHeight = implementation_->fixedTopConfirmed
                ? implementation_->fixedTopHeight
                : nextTopRunHeight;
            const int bottomHeight = implementation_->fixedBottomConfirmed
                ? implementation_->fixedBottomHeight
                : nextBottomRunHeight;
            const int firstRow = movement.candidate == Direction::Up
                ? (excludeTop ? topHeight : 0)
                : movement.frame->height - movement.advance
                    - (excludeBottom ? bottomHeight : 0);
            auto stored = implementation_->segmentStore.appendRows(
                *movement.frame, firstRow, movement.advance);
            if (!stored.has_value()) {
                return false;
            }
            preparedSegments.push_back(*stored);
            preparedScrollbar = implementation_->nextScrollbarState(
                std::move(preparedScrollbar), *previous, *movement.frame);
            previous = movement.frame.get();
            flushedHeight += movement.advance;
            return true;
        };
        try {
            for (std::size_t i = 0; i < safePrefix; ++i) {
                const auto& movement = i < implementation_->pending.size()
                    ? implementation_->pending[i]
                    : newMovement;
                if (!prepareMovement(movement, decisions[i].first, decisions[i].second)) {
                    return failedPendingCommit();
                }
            }
        } catch (const std::bad_alloc&) {
            return failedPendingCommit();
        }
        if (flushedHeight > std::numeric_limits<int>::max() - implementation_->height) {
            return failedPendingCommit();
        }

        std::size_t flushedPersistent = *projected;
        const auto pendingFrameBytes = checkedProduct(*fullFrameBytes, safePrefix);
        if (!pendingFrameBytes.has_value()
            || flushedPersistent < *pendingFrameBytes) {
            return failedPendingCommit();
        }
        flushedPersistent -= *pendingFrameBytes;
        if (implementation_->tailHasSeparateStorage) {
            if (flushedPersistent < *fullFrameBytes) {
                return failedPendingCommit();
            }
            flushedPersistent -= *fullFrameBytes;
        }
        const auto nextPersistent = checkedSum(flushedPersistent, *fullFrameBytes);
        if (!nextPersistent.has_value()) {
            return failedPendingCommit();
        }
        flushedPersistent = *nextPersistent;
        if (flushedPersistent >= config.maximumAcceptedBytes) {
            return failedPendingCommit();
        }

        try {
            implementation_->segments.reserve(
                implementation_->segments.size() + preparedSegments.size());
            implementation_->anchors.reserve(
                implementation_->anchors.size() + safePrefix);
            implementation_->pending.reserve(implementation_->pending.size() + 1U);
        } catch (const std::bad_alloc&) {
            return failedPendingCommit();
        }
        for (std::size_t i = 0; i < implementation_->pending.size(); ++i) {
            implementation_->pending[i].topDecision = decisions[i].first;
            implementation_->pending[i].bottomDecision = decisions[i].second;
        }
        implementation_->pending.push_back(std::move(newMovement));
        const Direction flushedDirection = implementation_->pending.empty()
            ? directional.candidate
            : implementation_->pending.front().candidate;
        for (auto& segment : preparedSegments) {
            if (flushedDirection == Direction::Up) {
                segment.documentStart = implementation_->segments.front().documentStart
                    - segment.outputRows;
                implementation_->segments.insert(
                    implementation_->segments.begin(), std::move(segment));
            } else {
                const auto& last = implementation_->segments.back();
                segment.documentStart = last.documentStart + last.outputRows;
                implementation_->segments.push_back(std::move(segment));
            }
        }
        const auto newTail = implementation_->pending[safePrefix - 1U].frame;
        for (std::size_t i = 0; i < safePrefix; ++i) {
            implementation_->anchors.push_back(std::move(implementation_->pending[i].fingerprint));
        }
        const auto prunedAnchorBytes = implementation_->pruneAnchorHistory();
        if (prunedAnchorBytes <= flushedPersistent) {
            flushedPersistent -= prunedAnchorBytes;
        }
        implementation_->pending.erase(
            implementation_->pending.begin(),
            implementation_->pending.begin() + static_cast<std::ptrdiff_t>(safePrefix));
        implementation_->tail = newTail;
        implementation_->tailHasSeparateStorage = true;
        implementation_->persistentBytes = flushedPersistent;
        if (confirmTop) {
            implementation_->fixedTopHeight = nextTopRunHeight;
        }
        if (confirmBottom) {
            implementation_->fixedBottomHeight = nextBottomRunHeight;
        }
        implementation_->fixedTopConfirmed = implementation_->fixedTopConfirmed || confirmTop;
        implementation_->fixedBottomConfirmed = implementation_->fixedBottomConfirmed || confirmBottom;
        implementation_->fixedTopAgreement = implementation_->fixedTopConfirmed
            ? 0
            : nextTopAgreement;
        implementation_->fixedBottomAgreement = implementation_->fixedBottomConfirmed
            ? 0
            : nextBottomAgreement;
        implementation_->fixedTopRunHeight = implementation_->fixedTopConfirmed
            ? 0
            : nextTopRunHeight;
        implementation_->fixedBottomRunHeight = implementation_->fixedBottomConfirmed
            ? 0
            : nextBottomRunHeight;
        implementation_->scrollbar = std::move(preparedScrollbar);
        implementation_->height += flushedHeight;
        if (implementation_->direction == Direction::Undetermined) {
            implementation_->direction = flushedDirection;
        }
        result.kind = AppendKind::AcceptedAppend;
        result.direction = implementation_->direction;
        result.appendedHeight = flushedHeight;
        result.outputHeight = implementation_->height;
        result.confidence = movementOverlap.confidence;
        return result;
    }

    if (!Implementation::usableMovement(
            overlap, preferredDirection != Direction::Undetermined)) {
        implementation_->clearPending();
        return result;
    }
    if (implementation_->direction == Direction::Undetermined) {
        directionToLock = directional.candidate;
    }

    const int appendedHeight = overlap.verticalAdvance;
    const int excludedTop = implementation_->fixedTopConfirmed
        ? implementation_->fixedTopHeight
        : 0;
    const int excludedBottom = implementation_->fixedBottomConfirmed
        ? implementation_->fixedBottomHeight
        : 0;
    const int firstNewRow = prepend
        ? excludedTop
        : frame.height - excludedBottom - appendedHeight;
    if (appendedHeight > std::numeric_limits<int>::max() - implementation_->height
        || firstNewRow < excludedTop) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }
    std::size_t projected = implementation_->persistentBytes;
    if (implementation_->tailHasSeparateStorage) {
        if (projected < *fullFrameBytes) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        projected -= *fullFrameBytes;
    }
    for (const auto bytes : {*fullFrameBytes, fingerprintBytes}) {
        const auto sum = checkedSum(projected, bytes);
        if (!sum.has_value()) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        projected = *sum;
    }
    if (projected >= config.maximumAcceptedBytes) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }

    const auto storedSegment = implementation_->segmentStore.appendRows(
        frame, firstNewRow, appendedHeight);
    const auto storedTail = copyFrame(frame);
    if (!storedSegment.has_value() || !storedTail.has_value()) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }
    try {
        implementation_->segments.reserve(implementation_->segments.size() + 1U);
        implementation_->anchors.reserve(implementation_->anchors.size() + 1U);
    } catch (...) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }

    const auto preparedScrollbar = implementation_->nextScrollbarState(
        implementation_->scrollbar, *implementation_->tail, frame);
    Implementation::Segment newSegment = *storedSegment;
    if (prepend) {
        newSegment.documentStart = implementation_->segments.front().documentStart
            - newSegment.outputRows;
        implementation_->segments.insert(
            implementation_->segments.begin(), std::move(newSegment));
    } else {
        const auto& last = implementation_->segments.back();
        newSegment.documentStart = last.documentStart + last.outputRows;
        implementation_->segments.push_back(std::move(newSegment));
    }
    implementation_->anchors.push_back(std::move(fingerprint));
    const auto prunedAnchorBytes = implementation_->pruneAnchorHistory();
    if (prunedAnchorBytes <= projected) {
        projected -= prunedAnchorBytes;
    }
    implementation_->tail = *storedTail;
    implementation_->tailHasSeparateStorage = true;
    implementation_->persistentBytes = projected;
    implementation_->scrollbar = preparedScrollbar;
    implementation_->height += appendedHeight;
    if (directionToLock.has_value()) {
        implementation_->direction = *directionToLock;
    }
    result.kind = AppendKind::AcceptedAppend;
    result.direction = implementation_->direction;
    result.appendedHeight = appendedHeight;
    result.outputHeight = implementation_->height;
    return result;
} catch (const std::bad_alloc&) {
    AppendResult failure;
    failure.kind = AppendKind::ResourceLimit;
    failure.outputHeight = implementation_->height;
    return failure;
}

bool ScrollStitchSession::rebase(const ScrollFrame& frame)
try {
    if (!implementation_->configIsValid || implementation_->segments.empty()
        || !frame.isValid() || frame.width != implementation_->width
        || frame.height != implementation_->viewportHeight) {
        return false;
    }
    const auto fullFrameBytes = imageBytes(frame.width, frame.height);
    if (!fullFrameBytes.has_value()) {
        return false;
    }
    std::size_t pendingBytes = 0U;
    for (const auto& movement : implementation_->pending) {
        const auto sum = checkedSum(pendingBytes, movement.persistentBytes);
        if (!sum.has_value()) {
            return false;
        }
        pendingBytes = *sum;
    }
    if (pendingBytes > implementation_->persistentBytes) {
        return false;
    }
    std::size_t projected = implementation_->persistentBytes - pendingBytes;
    if (!implementation_->tailHasSeparateStorage) {
        const auto sum = checkedSum(projected, *fullFrameBytes);
        if (!sum.has_value()) {
            return false;
        }
        projected = *sum;
    }
    if (projected >= implementation_->config.maximumAcceptedBytes) {
        return false;
    }
    const auto storedFrame = copyFrame(frame);
    if (!storedFrame.has_value()) {
        return false;
    }
    implementation_->clearPending();
    implementation_->tail = *storedFrame;
    implementation_->tailHasSeparateStorage = true;
    implementation_->persistentBytes = projected;
    implementation_->scrollbar.last.reset();
    return true;
} catch (const std::bad_alloc&) {
    return false;
}

int ScrollStitchSession::outputHeight() const noexcept
{
    return implementation_->height;
}

int ScrollStitchSession::previewOutputHeight() const noexcept
{
    int result = implementation_->height;
    for (const auto& movement : implementation_->pending) {
        if (movement.advance <= 0
            || movement.advance > std::numeric_limits<int>::max() - result) {
            return implementation_->height;
        }
        result += movement.advance;
    }
    return result;
}

int ScrollStitchSession::outputWidth() const noexcept
{
    return implementation_->segments.empty()
        ? 0
        : implementation_->width - implementation_->scrollbar.confirmedWidth;
}

std::size_t ScrollStitchSession::residentBytes() const noexcept
{
    return implementation_->persistentBytes;
}

std::uint64_t ScrollStitchSession::spooledBytes() const noexcept
{
    return implementation_->segmentStore.byteCount();
}

bool ScrollStitchSession::copyFinalPixels(
    void* destination,
    std::size_t destinationBytes,
    std::size_t destinationBytesPerRow,
    bool includePending,
    bool bottomUp) const
{
    if (implementation_->segments.empty() || destination == nullptr) {
        return false;
    }
    const int leftCrop = implementation_->scrollbar.confirmedSide < 0
        ? implementation_->scrollbar.confirmedWidth
        : 0;
    const int composedWidth = outputWidth();
    const int composedHeight = includePending
        ? previewOutputHeight()
        : implementation_->height;
    const auto rowBytes = checkedProduct(static_cast<std::size_t>(composedWidth), 4U);
    const auto requiredBytes = checkedProduct(
        destinationBytesPerRow, static_cast<std::size_t>(composedHeight));
    if (!rowBytes.has_value() || !requiredBytes.has_value()
        || destinationBytesPerRow < *rowBytes || destinationBytes < *requiredBytes) {
        return false;
    }
    const auto storedRowBytes = static_cast<std::size_t>(implementation_->width) * 4U;
    std::vector<std::uint8_t> storedRow(storedRowBytes);
    auto* destinationPixels = static_cast<std::uint8_t*>(destination);
    const auto seamRows = implementation_->seamRows(includePending, composedHeight);
    std::size_t seamIndex = 0U;
    int outputRow = 0;
    const auto writeRow = [&](const std::uint8_t* pixels) {
        if (pixels == nullptr || outputRow >= composedHeight) {
            return false;
        }
        const int destinationRow = bottomUp
            ? composedHeight - 1 - outputRow
            : outputRow;
        auto* destinationRowPixels = destinationPixels
            + static_cast<std::size_t>(destinationRow) * destinationBytesPerRow;
        std::memcpy(
            destinationRowPixels,
            pixels + static_cast<std::size_t>(leftCrop) * 4U,
            *rowBytes);
        if (implementation_->config.seamWhiteCoverage > 0.0
            && seamIndex < seamRows.size() && outputRow == seamRows[seamIndex]) {
            blendWhite(
                destinationRowPixels,
                composedWidth,
                implementation_->config.seamWhiteCoverage);
            ++seamIndex;
        }
        ++outputRow;
        return true;
    };
    const auto writeFrameRows = [&](const ScrollFrame& frame, int firstRow, int rowCount) {
        if (firstRow < 0 || rowCount <= 0 || firstRow > frame.height - rowCount) {
            return false;
        }
        for (int row = 0; row < rowCount; ++row) {
            const auto* pixels = frame.pixels.data()
                + static_cast<std::size_t>(firstRow + row)
                    * static_cast<std::size_t>(frame.bytesPerRow);
            if (!writeRow(pixels)) {
                return false;
            }
        }
        return true;
    };
    const auto writeCommitted = [&]() {
        for (const auto& segment : implementation_->segments) {
            for (int row = 0; row < segment.outputRows; ++row) {
                if (!implementation_->segmentStore.readRow(
                        segment, row, storedRow.data(), storedRowBytes)
                    || !writeRow(storedRow.data())) {
                    return false;
                }
            }
        }
        return true;
    };
    const ScrollDirection pendingDirection = includePending && !implementation_->pending.empty()
        ? implementation_->pending.front().candidate
        : ScrollDirection::Undetermined;
    if (pendingDirection == ScrollDirection::Up) {
        for (auto movement = implementation_->pending.crbegin();
             movement != implementation_->pending.crend(); ++movement) {
            const int topHeight = movement->topDecision == Implementation::BandDecision::Ordinary
                ? 0
                : (implementation_->fixedTopConfirmed
                        ? implementation_->fixedTopHeight
                        : implementation_->fixedTopRunHeight);
            if (!writeFrameRows(*movement->frame, topHeight, movement->advance)) {
                return false;
            }
        }
    }
    if (!writeCommitted()) {
        return false;
    }
    if (pendingDirection == ScrollDirection::Down) {
        for (const auto& movement : implementation_->pending) {
            const int bottomHeight = movement.bottomDecision
                    == Implementation::BandDecision::Ordinary
                ? 0
                : (implementation_->fixedBottomConfirmed
                        ? implementation_->fixedBottomHeight
                        : implementation_->fixedBottomRunHeight);
            const int firstRow = movement.frame->height - movement.advance - bottomHeight;
            if (!writeFrameRows(*movement.frame, firstRow, movement.advance)) {
                return false;
            }
        }
    }
    if (outputRow != composedHeight) {
        return false;
    }
    if (implementation_->config.seamWhiteCoverage == 0.0) {
        repairIsolatedNearWhiteSeamRows(
            destinationPixels,
            composedWidth,
            composedHeight,
            destinationBytesPerRow,
            seamRows,
            bottomUp);
    }
    return true;
}

ScrollFrame ScrollStitchSession::finalize() const
{
    if (implementation_->segments.empty()) {
        return {};
    }
    const int composedWidth = outputWidth();
    if (!imageBytes(composedWidth, implementation_->height).has_value()) {
        return {};
    }
    ScrollFrame output(composedWidth, implementation_->height);
    if (!output.isValid()) {
        return {};
    }
    return copyFinalPixels(
               output.pixels.data(),
               output.pixels.size(),
               static_cast<std::size_t>(output.bytesPerRow),
               false)
        ? output
        : ScrollFrame{};
}

ScrollFrame ScrollStitchSession::finalizeIncludingPending() const
{
    if (implementation_->segments.empty()) {
        return {};
    }
    const int composedWidth = outputWidth();
    const int composedHeight = previewOutputHeight();
    if (!imageBytes(composedWidth, composedHeight).has_value()) {
        return {};
    }
    ScrollFrame output(composedWidth, composedHeight);
    if (!output.isValid()) {
        return {};
    }
    return copyFinalPixels(
               output.pixels.data(),
               output.pixels.size(),
               static_cast<std::size_t>(output.bytesPerRow),
               true)
        ? output
        : ScrollFrame{};
}

ScrollFrame ScrollStitchSession::preview(int maximumHeight) const
{
    if (implementation_->segments.empty() || maximumHeight <= 0) {
        return {};
    }
    const int composedWidth = implementation_->width - implementation_->scrollbar.confirmedWidth;
    const int sourceHeight = previewOutputHeight();
    const int previewHeight = std::min(maximumHeight, sourceHeight);
    const int previewWidth = previewHeight == sourceHeight
        ? composedWidth
        : std::max(1, static_cast<int>(std::lround(
              static_cast<double>(composedWidth) * previewHeight / sourceHeight)));
    return previewWithSize(previewWidth, previewHeight);
}

ScrollFrame ScrollStitchSession::previewForWidth(int maximumWidth) const
{
    if (implementation_->segments.empty() || maximumWidth <= 0) {
        return {};
    }
    const int composedWidth = implementation_->width - implementation_->scrollbar.confirmedWidth;
    const int previewWidth = std::min(maximumWidth, composedWidth);
    const int sourceHeight = previewOutputHeight();
    const double scaledHeight = static_cast<double>(sourceHeight)
        * previewWidth / composedWidth;
    if (!std::isfinite(scaledHeight)
        || scaledHeight > std::numeric_limits<int>::max()) {
        return {};
    }
    const int previewHeight = previewWidth == composedWidth
        ? sourceHeight
        : std::max(1, static_cast<int>(std::lround(scaledHeight)));
    return previewWithSize(previewWidth, previewHeight);
}

ScrollFrame ScrollStitchSession::previewWithSize(int previewWidth, int previewHeight) const
{
    const int leftCrop = implementation_->scrollbar.confirmedSide < 0
        ? implementation_->scrollbar.confirmedWidth
        : 0;
    const int composedWidth = implementation_->width - implementation_->scrollbar.confirmedWidth;
    if (!imageBytes(previewWidth, previewHeight).has_value()) {
        return {};
    }
    ScrollFrame output(previewWidth, previewHeight);
    if (!output.isValid()) {
        return {};
    }

    const int committedHeight = implementation_->height;
    const int sourceHeight = previewOutputHeight();
    int pendingHeight = sourceHeight - committedHeight;
    const auto storedRowBytes = static_cast<std::size_t>(implementation_->width) * 4U;
    std::vector<std::uint8_t> storedRow(storedRowBytes);
    const ScrollDirection pendingDirection = implementation_->pending.empty()
        ? ScrollDirection::Undetermined
        : implementation_->pending.front().candidate;
    for (int y = 0; y < output.height; ++y) {
        int sourceY = static_cast<int>(
            static_cast<std::int64_t>(y) * sourceHeight / output.height);
        const ScrollFrame* sourceFrame = nullptr;
        const Implementation::Segment* sourceSegment = nullptr;
        int sourceRow = 0;

        if (pendingDirection == ScrollDirection::Up && sourceY < pendingHeight) {
            int pendingStart = 0;
            for (auto movement = implementation_->pending.crbegin();
                 movement != implementation_->pending.crend(); ++movement) {
                if (sourceY < pendingStart + movement->advance) {
                    sourceFrame = movement->frame.get();
                    const int topHeight = movement->topDecision
                            == Implementation::BandDecision::Ordinary
                        ? 0
                        : (implementation_->fixedTopConfirmed
                                  ? implementation_->fixedTopHeight
                                  : implementation_->fixedTopRunHeight);
                    sourceRow = topHeight + sourceY - pendingStart;
                    break;
                }
                pendingStart += movement->advance;
            }
        } else {
            if (pendingDirection == ScrollDirection::Up) {
                sourceY -= pendingHeight;
            }
            if (sourceY < committedHeight) {
                sourceSegment = implementation_->segmentAtOutputRow(sourceY, sourceRow);
            } else if (pendingDirection == ScrollDirection::Down) {
                const int pendingY = sourceY - committedHeight;
                int pendingStart = 0;
                for (const auto& movement : implementation_->pending) {
                    if (pendingY < pendingStart + movement.advance) {
                        sourceFrame = movement.frame.get();
                        const int bottomHeight = movement.bottomDecision
                                == Implementation::BandDecision::Ordinary
                            ? 0
                            : (implementation_->fixedBottomConfirmed
                                      ? implementation_->fixedBottomHeight
                                      : implementation_->fixedBottomRunHeight);
                        sourceRow = movement.frame->height - movement.advance - bottomHeight
                            + pendingY - pendingStart;
                        break;
                    }
                    pendingStart += movement.advance;
                }
            }
        }
        if (sourceSegment != nullptr) {
            if (!implementation_->segmentStore.readRow(
                    *sourceSegment, sourceRow, storedRow.data(), storedRowBytes)) {
                return {};
            }
        } else if (sourceFrame == nullptr || sourceRow < 0 || sourceRow >= sourceFrame->height) {
            return {};
        }
        const auto* sourcePixels = sourceSegment != nullptr
            ? storedRow.data()
            : sourceFrame->pixels.data()
                + static_cast<std::size_t>(sourceRow)
                    * static_cast<std::size_t>(sourceFrame->bytesPerRow);
        for (int x = 0; x < output.width; ++x) {
            const int sourceX = leftCrop + static_cast<int>(
                static_cast<std::int64_t>(x) * composedWidth / output.width);
            const auto sourceOffset = static_cast<std::size_t>(sourceX) * 4U;
            const auto destinationOffset = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(output.bytesPerRow)
                + static_cast<std::size_t>(x) * 4U;
            std::memcpy(
                output.pixels.data() + destinationOffset,
                sourcePixels + sourceOffset,
                4U);
        }
    }
    const auto sourceSeams = implementation_->seamRows(true, sourceHeight);
    if (implementation_->config.seamWhiteCoverage > 0.0) {
        int previousPreviewY = -1;
        for (const int sourceSeam : sourceSeams) {
            const int previewY = std::min(
                output.height - 1,
                static_cast<int>(
                    static_cast<std::int64_t>(sourceSeam) * output.height / sourceHeight));
            if (previewY == previousPreviewY) {
                continue;
            }
            blendWhite(
                output.pixels.data()
                    + static_cast<std::size_t>(previewY)
                        * static_cast<std::size_t>(output.bytesPerRow),
                output.width,
                implementation_->config.seamWhiteCoverage);
            previousPreviewY = previewY;
        }
    } else {
        std::vector<int> previewSeams;
        previewSeams.reserve(sourceSeams.size());
        for (const int sourceSeam : sourceSeams) {
            const int previewY = std::min(
                output.height - 1,
                static_cast<int>(
                    static_cast<std::int64_t>(sourceSeam) * output.height / sourceHeight));
            if (previewSeams.empty() || previewSeams.back() != previewY) {
                previewSeams.push_back(previewY);
            }
        }
        repairIsolatedNearWhiteSeamRows(
            output.pixels.data(),
            output.width,
            output.height,
            static_cast<std::size_t>(output.bytesPerRow),
            previewSeams);
    }
    return output;
}

} // namespace snipory::core::scroll
