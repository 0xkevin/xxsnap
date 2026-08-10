#include "snipory/core/scroll/ScrollStitchSession.h"

#include "snipory/core/scroll/FrameFingerprint.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
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
constexpr int MaximumStationaryColumnSamples = 256;
constexpr int MaximumStationaryRowSamples = 256;

[[nodiscard]] int samplingStride(int count, int maximumSamples)
{
    return std::max(1, (count + maximumSamples - 1) / maximumSamples);
}

[[nodiscard]] bool validUnit(double value)
{
    return std::isfinite(value) && value >= 0.0 && value <= 1.0;
}

[[nodiscard]] bool validConfig(const ScrollStitchConfig& config)
{
    const auto& matcher = config.matcher;
    const bool matcherIsValid = std::isfinite(matcher.minimumOverlapRatio)
        && std::isfinite(matcher.maximumAdvanceRatio)
        && std::isfinite(matcher.maximumReliableAdvanceRatio)
        && std::isfinite(matcher.maximumNormalizedError)
        && std::isfinite(matcher.minimumWinnerMargin)
        && std::isfinite(matcher.minimumReliableConfidence)
        && matcher.minimumOverlapRatio > 0.0
        && matcher.minimumOverlapRatio <= 1.0
        && matcher.maximumAdvanceRatio >= 0.0
        && matcher.maximumAdvanceRatio <= 1.0
        && validUnit(matcher.maximumReliableAdvanceRatio)
        && matcher.maximumNormalizedError >= 0.0
        && matcher.minimumWinnerMargin >= 0.0
        && validUnit(matcher.minimumReliableConfidence)
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

[[nodiscard]] std::optional<std::shared_ptr<const ScrollFrame>> takeFrame(ScrollFrame&& frame)
{
    if (!frame.isValid()) {
        return std::nullopt;
    }
    try {
        return std::make_shared<const ScrollFrame>(std::move(frame));
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

        [[nodiscard]] bool overwriteRows(
            const Segment& segment,
            int firstSegmentRow,
            const ScrollFrame& frame,
            int firstFrameRow,
            int rowCount)
        {
            if (file_ == nullptr || firstSegmentRow < 0 || firstFrameRow < 0
                || rowCount <= 0
                || firstSegmentRow > segment.outputRows - rowCount
                || firstFrameRow > frame.height - rowCount) {
                return false;
            }
            const auto rowBytes = checkedProduct(
                static_cast<std::size_t>(frame.width), 4U);
            const auto rowOffset = rowBytes.has_value()
                ? checkedProduct(static_cast<std::size_t>(firstSegmentRow), *rowBytes)
                : std::nullopt;
            if (!rowBytes.has_value() || !rowOffset.has_value()
                || *rowOffset > std::numeric_limits<std::uint64_t>::max()
                    - segment.fileOffset
                || !seek(segment.fileOffset + *rowOffset)) {
                return false;
            }
            for (int row = 0; row < rowCount; ++row) {
                const auto sourceOffset = static_cast<std::size_t>(firstFrameRow + row)
                    * static_cast<std::size_t>(frame.bytesPerRow);
                if (std::fwrite(frame.pixels.data() + sourceOffset, 1U, *rowBytes, file_)
                    != *rowBytes) {
                    return false;
                }
            }
            return std::fflush(file_) == 0;
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
        bool allowHighConfidenceAmbiguous,
        double minimumReliableConfidence = 0.0)
    {
        constexpr double MinimumUsableAmbiguousConfidence = 0.80;
        return value.verticalAdvance > 0
            && ((value.kind == OverlapKind::Reliable
                    && value.confidence >= minimumReliableConfidence)
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
        const double minimumMovementConfidence = matcherConfig.minimumReliableConfidence;
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
            auto preferredMatcherConfig = matcherConfig;
            preferredMatcherConfig.allowChangedPixelFallback = true;
            auto preferredOverlap = matchInDirection(
                previous, current, preferredMatcherConfig, preferred);
            const bool preferredUsable = usableMovement(
                preferredOverlap, true, minimumMovementConfidence);
            if (preferredUsable) {
                return makeMovement(preferred, std::move(preferredOverlap));
            }
            if (matcherConfig.expectedAdvance > 0) {
                DirectionalMatch result;
                result.confidence = preferredOverlap.confidence;
                return result;
            }
            const Direction opposite = preferred == Direction::Down
                ? Direction::Up
                : Direction::Down;
            auto oppositeOverlap = matchInDirection(
                previous, current, matcherConfig, opposite);
            const bool oppositeUsable = usableMovement(
                oppositeOverlap, true, minimumMovementConfidence);
            if (oppositeUsable) {
                return makeMovement(opposite, std::move(oppositeOverlap));
            }
            DirectionalMatch result;
            result.confidence = std::max(
                preferredOverlap.confidence, oppositeOverlap.confidence);
            return result;
        }
        if (expected != Direction::Undetermined
            && matcherConfig.expectedAdvance > 0) {
            auto expectedOverlap = matchInDirection(
                previous, current, matcherConfig, expected);
            if (usableMovement(expectedOverlap, true, minimumMovementConfidence)) {
                return makeMovement(expected, std::move(expectedOverlap));
            }
        }
        const auto down = matchInDirection(
            previous, current, matcherConfig, Direction::Down);
        const auto up = matchInDirection(
            previous, current, matcherConfig, Direction::Up);
        const bool downReliable = usableMovement(
            down, false, minimumMovementConfidence);
        const bool upReliable = usableMovement(
            up, false, minimumMovementConfidence);
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

    [[nodiscard]] bool overwriteComposedBack(
        const ScrollFrame& frame,
        int firstFrameRow,
        int rowCount)
    {
        int remaining = rowCount;
        int sourceEnd = firstFrameRow + rowCount;
        for (auto segment = segments.rbegin(); segment != segments.rend() && remaining > 0;
             ++segment) {
            const int written = std::min(remaining, segment->outputRows);
            sourceEnd -= written;
            if (!segmentStore.overwriteRows(
                    *segment,
                    segment->outputRows - written,
                    frame,
                    sourceEnd,
                    written)) {
                return false;
            }
            remaining -= written;
        }
        return remaining == 0;
    }

    [[nodiscard]] bool overwriteComposedFront(
        const ScrollFrame& frame,
        int firstFrameRow,
        int rowCount)
    {
        int remaining = rowCount;
        int sourceRow = firstFrameRow;
        for (auto segment = segments.begin(); segment != segments.end() && remaining > 0;
             ++segment) {
            const int written = std::min(remaining, segment->outputRows);
            if (!segmentStore.overwriteRows(
                    *segment, 0, frame, sourceRow, written)) {
                return false;
            }
            sourceRow += written;
            remaining -= written;
        }
        return remaining == 0;
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
        const int rowStride = samplingStride(rowCount, MaximumStationaryRowSamples);
        for (int offset = 0; offset < budget; ++offset) {
            const int x = left ? offset : current.width - 1 - offset;
            int equal = 0;
            int sampledRows = 0;
            for (int y = firstRow; y < lastRow; y += rowStride) {
                equal += pixelStationary(previous, current, x, y) ? 1 : 0;
                ++sampledRows;
            }
            const double ratio = static_cast<double>(equal)
                / static_cast<double>(sampledRows);
            if (ratio < config.fixedSideStationaryThreshold) {
                break;
            }
            ++stationaryColumns;
        }
        return stationaryColumns;
    }

    [[nodiscard]] OverlapConfig effectiveMatcherConfig(
        const ScrollFrame* previous = nullptr,
        const ScrollFrame* current = nullptr,
        bool includeUnconfirmedFixedBands = false) const
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
        if (previous != nullptr && current != nullptr
            && config.enableFixedBandDetection && includeUnconfirmedFixedBands) {
            const int transientTop = fixedTopConfirmed
                ? 0
                : stationaryBandHeight(*previous, *current, true);
            const int transientBottom = fixedBottomConfirmed
                ? 0
                : stationaryBandHeight(*previous, *current, false);
            const int minimumScrollingRows = std::max(1, static_cast<int>(std::ceil(
                static_cast<double>(current->height) * config.matcher.minimumOverlapRatio)));
            if (transientTop + transientBottom
                <= current->height - minimumScrollingRows) {
                result.excludedBands.top = std::max(result.excludedBands.top, transientTop);
                result.excludedBands.bottom = std::max(
                    result.excludedBands.bottom, transientBottom);
            }
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
        std::size_t total = 0U;
        const int rowStride = samplingStride(rowCount, MaximumStationaryRowSamples);
        const int columnStride = samplingStride(width, MaximumStationaryColumnSamples);
        for (int y = firstRow; y < firstRow + rowCount; y += rowStride) {
            for (int x = 0; x < width; x += columnStride) {
                equal += pixelStationary(previous, current, x, y) ? 1U : 0U;
                ++total;
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
        const int columnStride = samplingStride(
            columnCount, MaximumStationaryColumnSamples);
        for (int offset = 0; offset < budget; ++offset) {
            const int y = top ? offset : current.height - 1 - offset;
            int equal = 0;
            int sampledColumns = 0;
            for (int x = firstColumn; x < firstColumn + columnCount; x += columnStride) {
                equal += pixelStationary(previous, current, x, y) ? 1 : 0;
                ++sampledColumns;
            }
            const double ratio = static_cast<double>(equal)
                / static_cast<double>(sampledColumns);
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
        Direction establishedDirection,
        const OverlapConfig& baseMatcherConfig,
        const DirectionalMatch* knownMovement = nullptr) const
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
        auto matcherConfig = baseMatcherConfig;
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
        if (knownMovement != nullptr
            && knownMovement->decision == DirectionalDecision::Movement) {
            directional = *knownMovement;
        } else if (establishedDirection == Direction::Undetermined) {
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
                auto singleBandConfig = baseMatcherConfig;
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
            std::size_t sameSamples = 0U;
            std::size_t alignedSamples = 0U;
            const int rowStride = samplingStride(height, MaximumStationaryRowSamples);
            const int columnStride = samplingStride(
                columnCount, MaximumStationaryColumnSamples);
            std::size_t sampledColumns = 0U;
            for (int x = firstColumn; x < firstColumn + columnCount; x += columnStride) {
                ++sampledColumns;
            }
            for (int row = 0; row < height; row += rowStride) {
                const int y = top ? row : current.height - height + row;
                int previousValue = -1;
                for (int x = firstColumn; x < firstColumn + columnCount; x += columnStride) {
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
                    ++sameSamples;

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
            const double edgeRatio = horizontalPairs > 0U
                ? static_cast<double>(horizontalEdges) / static_cast<double>(horizontalPairs)
                : 0.0;
            if (maximumValue - minimumValue < 8 || edgeRatio < 0.05
                || alignedSamples < sampledColumns) {
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
            matcherConfig = baseMatcherConfig;
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
            if (knownMovement == nullptr
                || knownMovement->decision != DirectionalDecision::Movement) {
                const auto refined = matchInDirection(
                    previous, current, matcherConfig, evidence.candidate);
                if (!reliableMovement(refined)) {
                    evidence.top = false;
                    evidence.bottom = false;
                } else {
                    evidence.overlap = refined;
                }
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
    ScrollFrame frame,
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
        const auto storedSegment = implementation_->segmentStore.appendRows(
            frame, 0, frame.height);
        const auto storedFrame = takeFrame(std::move(frame));
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
        implementation_->width = (*storedFrame)->width;
        implementation_->viewportHeight = (*storedFrame)->height;
        implementation_->height = (*storedFrame)->height;
        implementation_->persistentBytes = *projected;
        result.kind = AppendKind::AcceptedInitial;
        result.appendedHeight = implementation_->viewportHeight;
        result.outputHeight = implementation_->height;
        result.confidence = 1.0;
        return result;
    }

    if (frame.width != implementation_->width
        || frame.height != implementation_->viewportHeight) {
        return result;
    }
    const auto matchingAnchor = implementation_->matchingAnchor(fingerprint);
    const auto matchingPending = implementation_->matchingPending(fingerprint);
    const bool matchesLatestAnchor = matchingAnchor.has_value()
        && implementation_->pending.empty()
        && *matchingAnchor + 1U == implementation_->anchors.size();
    const bool matchesLatestPending = matchingPending.has_value()
        && *matchingPending + 1U == implementation_->pending.size();
    const auto fingerprintClassifiedDiscard = [&]() {
        auto classified = result;
        if (matchingAnchor.has_value()) {
            classified.kind = matchesLatestAnchor
                ? AppendKind::DuplicateDiscarded
                : AppendKind::ReviewDiscarded;
            classified.confidence = 1.0;
        } else if (matchingPending.has_value()) {
            classified.kind = matchesLatestPending
                ? AppendKind::DuplicateDiscarded
                : AppendKind::ReviewDiscarded;
            classified.confidence = 1.0;
        }
        return classified;
    };
    const auto framesEqual = [&frame](const ScrollFrame& stored) {
        return stored.width == frame.width
            && stored.height == frame.height
            && stored.bytesPerRow == frame.bytesPerRow
            && stored.pixels == frame.pixels;
    };
    const bool exactLatestAnchor = matchesLatestAnchor
        && implementation_->tail != nullptr
        && framesEqual(*implementation_->tail);
    const bool exactPending = matchingPending.has_value()
        && *matchingPending < implementation_->pending.size()
        && framesEqual(*implementation_->pending[*matchingPending].frame);
    if (exactLatestAnchor || exactPending) {
        return fingerprintClassifiedDiscard();
    }

    const ScrollFrame* evidenceTail = implementation_->pending.empty()
        ? implementation_->tail.get()
        : implementation_->pending.back().frame.get();
    auto matcherConfig = implementation_->effectiveMatcherConfig(
        evidenceTail, &frame, expectedAdvance > 0);
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
            *evidenceTail, frame, pendingDirectionConfig, expectedDirection, preferredDirection);
        if (pendingDirectional.decision == DirectionalDecision::Opposite) {
            const Direction restartedCandidate = pendingDirectional.candidate;
            implementation_->clearPending();
            evidenceTail = implementation_->tail.get();
            expectedDirection = Direction::Undetermined;
            directional = implementation_->directionalMatch(
                *evidenceTail, frame, matcherConfig, expectedDirection, preferredDirection);
            if (directional.decision != DirectionalDecision::Movement
                || directional.candidate != restartedCandidate) {
                auto restartedMatcherConfig = implementation_->effectiveMatcherConfig(
                    evidenceTail, &frame, expectedAdvance > 0);
                if (expectedAdvance > 0) {
                    restartedMatcherConfig.expectedAdvance = expectedAdvance;
                    restartedMatcherConfig.expectedAdvanceTolerance = std::min(
                        16, std::max(2, static_cast<int>(
                            std::ceil(expectedAdvance * 0.03))));
                }
                const auto restartedEvidence = implementation_->fixedBandEvidence(
                    *evidenceTail,
                    frame,
                    Direction::Undetermined,
                    restartedMatcherConfig);
                if ((!restartedEvidence.top && !restartedEvidence.bottom)
                    || restartedEvidence.candidate != restartedCandidate
                    || (preferredDirection != Direction::Undetermined
                        && expectedAdvance > 0
                        && restartedCandidate != preferredDirection)) {
                    result.kind = directional.decision == DirectionalDecision::Ambiguous
                        ? AppendKind::LowConfidenceDiscarded
                        : AppendKind::ReviewDiscarded;
                    result.confidence = std::max(
                        pendingDirectional.confidence, directional.confidence);
                    return fingerprintClassifiedDiscard();
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
            return fingerprintClassifiedDiscard();
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
        *evidenceTail,
        frame,
        establishedDirection,
        matcherConfig,
        directional.decision == DirectionalDecision::Movement ? &directional : nullptr);
    const bool evidenceFollowsExplicitMotion = preferredDirection == Direction::Undetermined
        || expectedAdvance <= 0
        || evidence.candidate == preferredDirection;
    const bool acceptedFixedBandEvidence = (evidence.top || evidence.bottom)
        && evidenceFollowsExplicitMotion;
    if (acceptedFixedBandEvidence) {
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
                return fingerprintClassifiedDiscard();
            }
        }
    }
    const bool topEvidenceBroke = !implementation_->fixedTopConfirmed
        && implementation_->fixedTopAgreement > 0 && !evidence.top;
    const bool bottomEvidenceBroke = !implementation_->fixedBottomConfirmed
        && implementation_->fixedBottomAgreement > 0 && !evidence.bottom;
    auto movementOverlap = acceptedFixedBandEvidence
        ? evidence.overlap
        : overlap;
    if (!implementation_->pending.empty() && (topEvidenceBroke || bottomEvidenceBroke)) {
        auto transitionConfig = matcherConfig;
        if ((acceptedFixedBandEvidence && evidence.top) || topEvidenceBroke) {
            transitionConfig.excludedBands.top = std::max(
                transitionConfig.excludedBands.top,
                std::max(evidence.topHeight, implementation_->fixedTopRunHeight));
        }
        if ((acceptedFixedBandEvidence && evidence.bottom) || bottomEvidenceBroke) {
            transitionConfig.excludedBands.bottom = std::max(
                transitionConfig.excludedBands.bottom,
                std::max(evidence.bottomHeight, implementation_->fixedBottomRunHeight));
        }
        const auto transition = implementation_->directionalMatch(
            *evidenceTail, frame, transitionConfig, expectedDirection, preferredDirection);
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
        return fingerprintClassifiedDiscard();
    }

    const bool continuePending = !implementation_->pending.empty()
        || acceptedFixedBandEvidence;
    if (continuePending) {
        if (!Implementation::usableMovement(
                movementOverlap,
                preferredDirection != Direction::Undetermined,
                matcherConfig.minimumReliableConfidence)) {
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
                    return fingerprintClassifiedDiscard();
                }
            }
            return fingerprintClassifiedDiscard();
        }
        const auto contribution = checkedSum(*fullFrameBytes, fingerprintBytes);
        const auto projected = contribution.has_value()
            ? checkedSum(implementation_->persistentBytes, *contribution)
            : std::nullopt;
        if (!projected.has_value() || *projected >= config.maximumAcceptedBytes) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        const auto storedPendingFrame = takeFrame(std::move(frame));
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
            overlap,
            preferredDirection != Direction::Undetermined,
            matcherConfig.minimumReliableConfidence)) {
        implementation_->clearPending();
        return fingerprintClassifiedDiscard();
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

    const int overlapRefresh = std::min({
        overlap.overlapHeight,
        frame.height / 2,
        prepend
            ? frame.height - excludedBottom - appendedHeight
            : firstNewRow - excludedTop,
    });
    const auto storedSegment = implementation_->segmentStore.appendRows(
        frame, firstNewRow, appendedHeight);
    if (!storedSegment.has_value()) {
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
    const bool contacted = prepend
        ? implementation_->overwriteComposedFront(
            frame, firstNewRow + appendedHeight, overlapRefresh)
        : implementation_->overwriteComposedBack(
            frame, firstNewRow - overlapRefresh, overlapRefresh);
    if (!contacted) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }
    const auto storedTail = takeFrame(std::move(frame));
    if (!storedTail.has_value()) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }
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

bool ScrollStitchSession::visitFinalRows(
    bool includePending,
    const FinalRowVisitor& visitor) const
{
    if (implementation_->segments.empty() || !visitor) {
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
    if (!rowBytes.has_value() || composedHeight <= 0) {
        return false;
    }
    try {
        const auto storedRowBytes = static_cast<std::size_t>(implementation_->width) * 4U;
        std::vector<std::uint8_t> storedRow(storedRowBytes);
        std::vector<std::uint8_t> directRow(*rowBytes);
        std::vector<std::uint8_t> beforeRow(*rowBytes);
        std::vector<std::uint8_t> candidateRow(*rowBytes);
        std::vector<std::uint8_t> nextRow(*rowBytes);
        const auto seamRows = implementation_->seamRows(includePending, composedHeight);
        std::size_t seamIndex = 0U;
        int sourceRow = 0;
        int emittedRow = 0;
        int bufferedRows = 0;
        const auto emit = [&](const std::vector<std::uint8_t>& row) {
            if (emittedRow >= composedHeight
                || !visitor(row.data(), *rowBytes, emittedRow, composedHeight)) {
                return false;
            }
            ++emittedRow;
            return true;
        };
        const auto repairCandidateIfNeeded = [&]() {
            const int candidateLogicalRow = sourceRow - 2;
            if (candidateLogicalRow <= 0 || candidateLogicalRow >= composedHeight - 1
                || !std::binary_search(
                    seamRows.cbegin(), seamRows.cend(), candidateLogicalRow)
                || nearWhitePixelRatio(candidateRow.data(), composedWidth) < 0.98
                || nearWhitePixelRatio(beforeRow.data(), composedWidth) > 0.90
                || nearWhitePixelRatio(nextRow.data(), composedWidth) > 0.90) {
                return;
            }
            for (int x = 0; x < composedWidth; ++x) {
                const auto offset = static_cast<std::size_t>(x) * 4U;
                for (std::size_t channel = 0; channel < 4U; ++channel) {
                    candidateRow[offset + channel] = static_cast<std::uint8_t>(
                        (static_cast<unsigned>(beforeRow[offset + channel])
                            + static_cast<unsigned>(nextRow[offset + channel])
                            + 1U)
                        / 2U);
                }
            }
        };
        const auto acceptSourceRow = [&](const std::uint8_t* pixels) {
            if (pixels == nullptr || sourceRow >= composedHeight) {
                return false;
            }
            const auto* cropped = pixels + static_cast<std::size_t>(leftCrop) * 4U;
            if (implementation_->config.seamWhiteCoverage > 0.0) {
                std::memcpy(directRow.data(), cropped, *rowBytes);
                if (seamIndex < seamRows.size() && sourceRow == seamRows[seamIndex]) {
                    blendWhite(
                        directRow.data(),
                        composedWidth,
                        implementation_->config.seamWhiteCoverage);
                    ++seamIndex;
                }
                ++sourceRow;
                return emit(directRow);
            }
            auto* destination = bufferedRows == 0
                ? beforeRow.data()
                : (bufferedRows == 1 ? candidateRow.data() : nextRow.data());
            std::memcpy(destination, cropped, *rowBytes);
            ++sourceRow;
            if (bufferedRows < 2) {
                ++bufferedRows;
                return true;
            }
            repairCandidateIfNeeded();
            if (!emit(beforeRow)) {
                return false;
            }
            beforeRow.swap(candidateRow);
            candidateRow.swap(nextRow);
            return true;
        };
        const auto acceptFrameRows = [&](const ScrollFrame& frame, int firstRow, int rowCount) {
            if (firstRow < 0 || rowCount <= 0 || firstRow > frame.height - rowCount) {
                return false;
            }
            for (int row = 0; row < rowCount; ++row) {
                const auto* pixels = frame.pixels.data()
                    + static_cast<std::size_t>(firstRow + row)
                        * static_cast<std::size_t>(frame.bytesPerRow);
                if (!acceptSourceRow(pixels)) {
                    return false;
                }
            }
            return true;
        };
        const auto acceptCommitted = [&]() {
            for (const auto& segment : implementation_->segments) {
                for (int row = 0; row < segment.outputRows; ++row) {
                    if (!implementation_->segmentStore.readRow(
                            segment, row, storedRow.data(), storedRowBytes)
                        || !acceptSourceRow(storedRow.data())) {
                        return false;
                    }
                }
            }
            return true;
        };
        const ScrollDirection pendingDirection = includePending
                && !implementation_->pending.empty()
            ? implementation_->pending.front().candidate
            : ScrollDirection::Undetermined;
        if (pendingDirection == ScrollDirection::Up) {
            for (auto movement = implementation_->pending.crbegin();
                 movement != implementation_->pending.crend(); ++movement) {
                const int topHeight = movement->topDecision
                        == Implementation::BandDecision::Ordinary
                    ? 0
                    : (implementation_->fixedTopConfirmed
                            ? implementation_->fixedTopHeight
                            : implementation_->fixedTopRunHeight);
                if (!acceptFrameRows(*movement->frame, topHeight, movement->advance)) {
                    return false;
                }
            }
        }
        if (!acceptCommitted()) {
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
                const int firstRow = movement.frame->height
                    - movement.advance - bottomHeight;
                if (!acceptFrameRows(*movement.frame, firstRow, movement.advance)) {
                    return false;
                }
            }
        }
        if (sourceRow != composedHeight) {
            return false;
        }
        if (implementation_->config.seamWhiteCoverage == 0.0) {
            if (bufferedRows >= 1 && !emit(beforeRow)) {
                return false;
            }
            if (bufferedRows == 2 && !emit(candidateRow)) {
                return false;
            }
        }
        return emittedRow == composedHeight;
    } catch (...) {
        return false;
    }
}

bool ScrollStitchSession::copyFinalPixels(
    void* destination,
    std::size_t destinationBytes,
    std::size_t destinationBytesPerRow,
    bool includePending,
    bool bottomUp) const
{
    if (destination == nullptr) {
        return false;
    }
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
    auto* destinationPixels = static_cast<std::uint8_t*>(destination);
    return visitFinalRows(
        includePending,
        [&](const std::uint8_t* pixels, std::size_t bytes, int row, int totalRows) {
            const int destinationRow = bottomUp ? totalRows - 1 - row : row;
            auto* destinationRowPixels = destinationPixels
                + static_cast<std::size_t>(destinationRow) * destinationBytesPerRow;
            std::memcpy(destinationRowPixels, pixels, bytes);
            return true;
        });
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
