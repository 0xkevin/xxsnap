#include "snipory/core/scroll/ScrollStitchSession.h"

#include "snipory/core/scroll/FrameFingerprint.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <optional>
#include <unordered_map>
#include <utility>
#include <vector>

namespace snipory::core::scroll {
namespace {

constexpr FingerprintSize AnchorFingerprintSize{16, 12};
constexpr std::size_t RecentAnchorCount = 8;

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
        && matcher.maximumFullResolutionCandidates > 0
        && matcher.maximumFullResolutionCandidates <= 1'000'000
        && matcher.excludedBands.left >= 0
        && matcher.excludedBands.right >= 0
        && matcher.excludedBands.top >= 0
        && matcher.excludedBands.bottom >= 0;
    return matcherIsValid
        && validUnit(config.duplicateThreshold)
        && config.maximumAcceptedBytes > 0U
        && config.fixedTopCandidateHeight >= 0
        && config.fixedBottomCandidateHeight >= 0
        && config.fixedBandConfirmationMovements >= 3
        && config.fixedBandConfirmationMovements <= 32
        && validUnit(config.fixedBandStationaryThreshold)
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
        std::shared_ptr<const ScrollFrame> pixels;
        int firstRow = 0;
        int outputRows = 0;
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

    struct PendingMovement final
    {
        std::shared_ptr<const ScrollFrame> frame;
        Fingerprint fingerprint;
        int advance = 0;
        double confidence = 0.0;
        std::size_t persistentBytes = 0U;
        BandDecision topDecision = BandDecision::Ordinary;
        BandDecision bottomDecision = BandDecision::Ordinary;
    };

    struct FixedBandEvidence final
    {
        OverlapResult overlap;
        bool top = false;
        bool bottom = false;
        int topHeight = 0;
        int bottomHeight = 0;
    };

    ScrollStitchConfig config;
    bool configIsValid = false;
    std::vector<Segment> segments;
    std::vector<Fingerprint> anchors;
    std::vector<PendingMovement> pending;
    std::shared_ptr<const ScrollFrame> tail;
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

    [[nodiscard]] bool duplicateFingerprint(const Fingerprint& left, const Fingerprint& right) const
    {
        const auto distance = FrameFingerprint::meanAbsoluteDistance(left, right);
        return distance.has_value() && *distance <= config.duplicateThreshold;
    }

    [[nodiscard]] std::optional<std::size_t> matchingAnchor(const Fingerprint& fingerprint) const
    {
        const std::size_t recentStart = anchors.size() > RecentAnchorCount
            ? anchors.size() - RecentAnchorCount
            : 0U;
        for (std::size_t i = anchors.size(); i > recentStart; --i) {
            if (duplicateFingerprint(anchors[i - 1U], fingerprint)) {
                return i - 1U;
            }
        }
        for (std::size_t i = recentStart; i > 0U; --i) {
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

    [[nodiscard]] OverlapConfig effectiveMatcherConfig() const
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
                equal += pixelEqual(previous, current, x, y) ? 1U : 0U;
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
        const int budget = configuredBudget > 0
            ? configuredBudget
            : std::min(96, current.height / 4);
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
                equal += pixelEqual(previous, current, x, y) ? 1 : 0;
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
        const ScrollFrame& current) const
    {
        FixedBandEvidence evidence;
        evidence.topHeight = stationaryBandHeight(previous, current, true);
        evidence.bottomHeight = stationaryBandHeight(previous, current, false);
        evidence.top = evidence.topHeight > 0;
        evidence.bottom = evidence.bottomHeight > 0;
        if ((!evidence.top && !evidence.bottom) || !centralDocumentMoved(previous, current)) {
            evidence.top = false;
            evidence.bottom = false;
            return evidence;
        }
        auto matcherConfig = effectiveMatcherConfig();
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
        VerticalOverlapMatcher matcher;
        evidence.overlap = matcher.match(previous, current, matcherConfig);
        if (evidence.overlap.kind != OverlapKind::Reliable
            || evidence.overlap.verticalAdvance <= 0) {
            evidence.top = false;
            evidence.bottom = false;
            return evidence;
        }

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

                    const int alignedPreviousY = top
                        ? y + evidence.overlap.verticalAdvance
                        : y;
                    const int alignedCurrentY = top
                        ? y
                        : y - evidence.overlap.verticalAdvance;
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
            matcherConfig = effectiveMatcherConfig();
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
            evidence.overlap = matcher.match(previous, current, matcherConfig);
            if (evidence.overlap.kind != OverlapKind::Reliable
                || evidence.overlap.verticalAdvance <= 0) {
                evidence.top = false;
                evidence.bottom = false;
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

AppendResult ScrollStitchSession::append(const ScrollFrame& frame)
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
        if (!storedFrame.has_value()) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        try {
            implementation_->segments.reserve(1U);
            implementation_->anchors.reserve(1U);
            implementation_->segments.push_back({*storedFrame, 0, frame.height});
            implementation_->anchors.push_back(std::move(fingerprint));
        } catch (...) {
            implementation_->segments.clear();
            implementation_->anchors.clear();
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        implementation_->tail = *storedFrame;
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

    VerticalOverlapMatcher matcher;
    const auto& evidenceTail = implementation_->pending.empty()
        ? *implementation_->tail
        : *implementation_->pending.back().frame;
    const auto matcherConfig = implementation_->effectiveMatcherConfig();
    auto overlap = matcher.match(evidenceTail, frame, matcherConfig);
    result.confidence = overlap.confidence;
    const auto evidence = implementation_->fixedBandEvidence(evidenceTail, frame);
    if (!evidence.top && !evidence.bottom && implementation_->pending.empty()) {
        const auto reverse = matcher.match(frame, evidenceTail, matcherConfig);
        if (reverse.kind == OverlapKind::Reliable && reverse.verticalAdvance > 0) {
            result.kind = AppendKind::ReviewDiscarded;
            result.confidence = reverse.confidence;
            return result;
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
        const auto transition = matcher.match(evidenceTail, frame, transitionConfig);
        if (transition.kind == OverlapKind::Reliable && transition.verticalAdvance > 0) {
            movementOverlap = transition;
            result.confidence = transition.confidence;
        }
    }

    const bool continuePending = !implementation_->pending.empty()
        || evidence.top || evidence.bottom;
    if (continuePending) {
        if (movementOverlap.kind != OverlapKind::Reliable
            || movementOverlap.verticalAdvance <= 0) {
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
                const auto reverse = matcher.match(frame, *movement->frame, reviewConfig);
                if (reverse.kind == OverlapKind::Reliable && reverse.verticalAdvance > 0) {
                    result.kind = AppendKind::ReviewDiscarded;
                    result.confidence = reverse.confidence;
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
            result.outputHeight = implementation_->height;
            result.confidence = movementOverlap.confidence;
            return result;
        }

        std::vector<Implementation::Segment> preparedSegments;
        preparedSegments.reserve(safePrefix);
        int flushedHeight = 0;
        auto preparedScrollbar = implementation_->scrollbar;
        const ScrollFrame* previous = implementation_->tail.get();
        auto prepareMovement = [&](
                                   const Implementation::PendingMovement& movement,
                                   BandDecision bottomDecision) {
            if (movement.advance > std::numeric_limits<int>::max() - flushedHeight) {
                return false;
            }
            const bool excludeBottom = bottomDecision == BandDecision::Fixed;
            const int bottomHeight = implementation_->fixedBottomConfirmed
                ? implementation_->fixedBottomHeight
                : nextBottomRunHeight;
            const int firstRow = movement.frame->height - movement.advance
                - (excludeBottom ? bottomHeight : 0);
            auto pixels = copyRows(*movement.frame, firstRow, movement.advance);
            if (!pixels.isValid()) {
                return false;
            }
            auto stored = std::make_shared<const ScrollFrame>(std::move(pixels));
            preparedSegments.push_back({stored, 0, movement.advance});
            preparedScrollbar = implementation_->nextScrollbarState(
                std::move(preparedScrollbar), *previous, *movement.frame);
            previous = movement.frame.get();
            flushedHeight += movement.advance;
            return true;
        };
        for (std::size_t i = 0; i < safePrefix; ++i) {
            const auto& movement = i < implementation_->pending.size()
                ? implementation_->pending[i]
                : newMovement;
            if (!prepareMovement(movement, decisions[i].second)) {
                result.kind = AppendKind::ResourceLimit;
                return result;
            }
        }
        if (flushedHeight > std::numeric_limits<int>::max() - implementation_->height) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }

        std::size_t flushedPersistent = *projected;
        const auto pendingFrameBytes = checkedProduct(*fullFrameBytes, safePrefix);
        const auto segmentBytes = imageBytes(frame.width, flushedHeight);
        if (!pendingFrameBytes.has_value() || !segmentBytes.has_value()
            || flushedPersistent < *pendingFrameBytes) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        flushedPersistent -= *pendingFrameBytes;
        if (implementation_->tailHasSeparateStorage) {
            if (flushedPersistent < *fullFrameBytes) {
                result.kind = AppendKind::ResourceLimit;
                return result;
            }
            flushedPersistent -= *fullFrameBytes;
        }
        for (const auto bytes : {*segmentBytes, *fullFrameBytes}) {
            const auto sum = checkedSum(flushedPersistent, bytes);
            if (!sum.has_value()) {
                result.kind = AppendKind::ResourceLimit;
                return result;
            }
            flushedPersistent = *sum;
        }
        if (flushedPersistent >= config.maximumAcceptedBytes) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }

        implementation_->segments.reserve(
            implementation_->segments.size() + preparedSegments.size());
        implementation_->anchors.reserve(
            implementation_->anchors.size() + safePrefix);
        implementation_->pending.reserve(implementation_->pending.size() + 1U);
        for (std::size_t i = 0; i < implementation_->pending.size(); ++i) {
            implementation_->pending[i].topDecision = decisions[i].first;
            implementation_->pending[i].bottomDecision = decisions[i].second;
        }
        implementation_->pending.push_back(std::move(newMovement));
        for (auto& segment : preparedSegments) {
            implementation_->segments.push_back(std::move(segment));
        }
        const auto newTail = implementation_->pending[safePrefix - 1U].frame;
        for (std::size_t i = 0; i < safePrefix; ++i) {
            implementation_->anchors.push_back(std::move(implementation_->pending[i].fingerprint));
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
        result.kind = AppendKind::AcceptedAppend;
        result.appendedHeight = flushedHeight;
        result.outputHeight = implementation_->height;
        result.confidence = movementOverlap.confidence;
        return result;
    }

    if (overlap.kind != OverlapKind::Reliable || overlap.verticalAdvance <= 0) {
        implementation_->clearPending();
        return result;
    }

    const int appendedHeight = overlap.verticalAdvance;
    const int excludedTop = implementation_->fixedTopConfirmed
        ? implementation_->fixedTopHeight
        : 0;
    const int excludedBottom = implementation_->fixedBottomConfirmed
        ? implementation_->fixedBottomHeight
        : 0;
    const int firstNewRow = frame.height - excludedBottom - appendedHeight;
    if (appendedHeight > std::numeric_limits<int>::max() - implementation_->height
        || firstNewRow < excludedTop) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }
    const int rawRows = appendedHeight;
    const auto rawBytes = imageBytes(frame.width, rawRows);
    if (!rawBytes.has_value()) {
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
    for (const auto bytes : {*rawBytes, *fullFrameBytes, fingerprintBytes}) {
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

    auto rawSegment = copyRows(frame, firstNewRow, rawRows);
    const auto storedTail = copyFrame(frame);
    if (!rawSegment.isValid() || !storedTail.has_value()) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }
    std::optional<std::shared_ptr<const ScrollFrame>> storedSegment;
    try {
        storedSegment = std::make_shared<const ScrollFrame>(std::move(rawSegment));
        implementation_->segments.reserve(implementation_->segments.size() + 1U);
        implementation_->anchors.reserve(implementation_->anchors.size() + 1U);
    } catch (...) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }

    const auto preparedScrollbar = implementation_->nextScrollbarState(
        implementation_->scrollbar, *implementation_->tail, frame);
    implementation_->segments.push_back({
        *storedSegment,
        0,
        appendedHeight,
    });
    implementation_->anchors.push_back(std::move(fingerprint));
    implementation_->tail = *storedTail;
    implementation_->tailHasSeparateStorage = true;
    implementation_->persistentBytes = projected;
    implementation_->scrollbar = preparedScrollbar;
    implementation_->height += appendedHeight;
    result.kind = AppendKind::AcceptedAppend;
    result.appendedHeight = appendedHeight;
    result.outputHeight = implementation_->height;
    return result;
} catch (const std::bad_alloc&) {
    AppendResult failure;
    failure.kind = AppendKind::ResourceLimit;
    failure.outputHeight = implementation_->height;
    return failure;
}

int ScrollStitchSession::outputHeight() const noexcept
{
    return implementation_->height;
}

ScrollFrame ScrollStitchSession::finalize() const
{
    if (implementation_->segments.empty()) {
        return {};
    }
    const int leftCrop = implementation_->scrollbar.confirmedSide < 0
        ? implementation_->scrollbar.confirmedWidth
        : 0;
    const int outputWidth = implementation_->width - implementation_->scrollbar.confirmedWidth;
    if (!imageBytes(outputWidth, implementation_->height).has_value()) {
        return {};
    }
    ScrollFrame output(outputWidth, implementation_->height);
    if (!output.isValid()) {
        return {};
    }
    const auto rowBytes = static_cast<std::size_t>(outputWidth) * 4U;
    int outputRow = 0;
    for (const auto& segment : implementation_->segments) {
        const int firstRow = segment.firstRow;
        if (!segment.pixels || firstRow < 0 || segment.outputRows <= 0
            || firstRow > segment.pixels->height - segment.outputRows) {
            return {};
        }
        for (int row = 0; row < segment.outputRows; ++row, ++outputRow) {
            const auto sourceOffset = static_cast<std::size_t>(firstRow + row)
                    * static_cast<std::size_t>(segment.pixels->bytesPerRow)
                + static_cast<std::size_t>(leftCrop) * 4U;
            const auto destinationOffset = static_cast<std::size_t>(outputRow)
                * static_cast<std::size_t>(output.bytesPerRow);
            std::memcpy(
                output.pixels.data() + destinationOffset,
                segment.pixels->pixels.data() + sourceOffset,
                rowBytes);
        }
    }
    return outputRow == output.height ? output : ScrollFrame{};
}

ScrollFrame ScrollStitchSession::preview(int maximumHeight) const
{
    if (implementation_->segments.empty() || maximumHeight <= 0) {
        return {};
    }
    const int leftCrop = implementation_->scrollbar.confirmedSide < 0
        ? implementation_->scrollbar.confirmedWidth
        : 0;
    const int composedWidth = implementation_->width - implementation_->scrollbar.confirmedWidth;
    const int previewHeight = std::min(maximumHeight, implementation_->height);
    const int previewWidth = previewHeight == implementation_->height
        ? composedWidth
        : std::max(1, static_cast<int>(std::lround(
              static_cast<double>(composedWidth) * previewHeight / implementation_->height)));
    if (!imageBytes(previewWidth, previewHeight).has_value()) {
        return {};
    }
    ScrollFrame output(previewWidth, previewHeight);
    if (!output.isValid()) {
        return {};
    }

    std::size_t segmentIndex = 0U;
    int segmentStart = 0;
    for (int y = 0; y < output.height; ++y) {
        const int sourceY = static_cast<int>(
            static_cast<std::int64_t>(y) * implementation_->height / output.height);
        while (segmentIndex < implementation_->segments.size()
            && sourceY >= segmentStart + implementation_->segments[segmentIndex].outputRows) {
            segmentStart += implementation_->segments[segmentIndex].outputRows;
            ++segmentIndex;
        }
        if (segmentIndex >= implementation_->segments.size()) {
            return {};
        }
        const auto& segment = implementation_->segments[segmentIndex];
        const int segmentRow = segment.firstRow + sourceY - segmentStart;
        for (int x = 0; x < output.width; ++x) {
            const int sourceX = leftCrop + static_cast<int>(
                static_cast<std::int64_t>(x) * composedWidth / output.width);
            const auto sourceOffset = static_cast<std::size_t>(segmentRow)
                    * static_cast<std::size_t>(segment.pixels->bytesPerRow)
                + static_cast<std::size_t>(sourceX) * 4U;
            const auto destinationOffset = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(output.bytesPerRow)
                + static_cast<std::size_t>(x) * 4U;
            std::memcpy(
                output.pixels.data() + destinationOffset,
                segment.pixels->pixels.data() + sourceOffset,
                4U);
        }
    }
    return output;
}

} // namespace snipory::core::scroll
