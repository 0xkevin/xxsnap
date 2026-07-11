#include "snipory/core/scroll/ScrollStitchSession.h"

#include "snipory/core/scroll/FrameFingerprint.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
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
        int ordinaryFirstRow = 0;
        int fixedBottomFirstRow = 0;
        int outputRows = 0;
    };

    struct ScrollbarObservation final
    {
        int width = 0;
        int thumbTop = 0;
        int thumbBottom = 0;
        double trackPersistence = 0.0;
    };

    ScrollStitchConfig config;
    bool configIsValid = false;
    std::vector<Segment> segments;
    std::vector<Fingerprint> anchors;
    std::shared_ptr<const ScrollFrame> tail;
    bool tailHasSeparateStorage = false;
    std::size_t persistentBytes = 0;
    int height = 0;
    int width = 0;
    int viewportHeight = 0;
    int fixedTopAgreements = 0;
    int fixedBottomAgreements = 0;
    bool fixedTopConfirmed = false;
    bool fixedBottomConfirmed = false;
    std::optional<ScrollbarObservation> lastScrollbar;
    int scrollbarObservedMovements = 0;
    int scrollbarMovingMovements = 0;
    double scrollbarMinimumPersistence = 1.0;
    int scrollbarWidth = 0;

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

    [[nodiscard]] OverlapConfig effectiveMatcherConfig() const
    {
        auto result = config.matcher;
        if (fixedTopConfirmed) {
            result.excludedBands.top = std::max(
                result.excludedBands.top, config.fixedTopCandidateHeight);
        }
        if (fixedBottomConfirmed) {
            result.excludedBands.bottom = std::max(
                result.excludedBands.bottom, config.fixedBottomCandidateHeight);
        }
        result.excludedBands.right = std::max(
            result.excludedBands.right, config.scrollbarMaximumWidth);
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

    void observeFixedBands(const ScrollFrame& previous, const ScrollFrame& current)
    {
        const bool centerMoved = centralDocumentMoved(previous, current);
        if (!fixedTopConfirmed && config.fixedTopCandidateHeight > 0) {
            const bool stationary = stationaryRatio(
                previous, current, 0, config.fixedTopCandidateHeight)
                >= config.fixedBandStationaryThreshold;
            fixedTopAgreements = stationary && centerMoved ? fixedTopAgreements + 1 : 0;
            fixedTopConfirmed = fixedTopAgreements >= config.fixedBandConfirmationMovements;
        }
        if (!fixedBottomConfirmed && config.fixedBottomCandidateHeight > 0) {
            const bool stationary = stationaryRatio(
                previous,
                current,
                current.height - config.fixedBottomCandidateHeight,
                config.fixedBottomCandidateHeight)
                >= config.fixedBandStationaryThreshold;
            fixedBottomAgreements = stationary && centerMoved ? fixedBottomAgreements + 1 : 0;
            fixedBottomConfirmed = fixedBottomAgreements >= config.fixedBandConfirmationMovements;
        }
    }

    [[nodiscard]] std::optional<ScrollbarObservation> detectScrollbar(
        const ScrollFrame& frame) const
    {
        const int budget = std::min(config.scrollbarMaximumWidth, frame.width / 8);
        if (budget <= 0) {
            return std::nullopt;
        }

        ScrollbarObservation result;
        double minimumPersistence = 1.0;
        for (int x = frame.width - 1; x >= frame.width - budget; --x) {
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

    void observeScrollbar(const ScrollFrame& previous, const ScrollFrame& current)
    {
        if (config.scrollbarMaximumWidth <= 0 || scrollbarWidth > 0) {
            return;
        }
        if (!lastScrollbar.has_value()) {
            lastScrollbar = detectScrollbar(previous);
        }
        const auto observation = detectScrollbar(current);
        if (!lastScrollbar.has_value() || !observation.has_value()
            || lastScrollbar->width != observation->width) {
            lastScrollbar = observation;
            scrollbarObservedMovements = 0;
            scrollbarMovingMovements = 0;
            scrollbarMinimumPersistence = 1.0;
            return;
        }

        ++scrollbarObservedMovements;
        const double normalizedMotion = static_cast<double>(
            std::abs(observation->thumbTop - lastScrollbar->thumbTop))
            / static_cast<double>(current.height);
        if (normalizedMotion >= config.scrollbarMotionThreshold) {
            ++scrollbarMovingMovements;
        }
        scrollbarMinimumPersistence = std::min(
            scrollbarMinimumPersistence,
            std::min(lastScrollbar->trackPersistence, observation->trackPersistence));
        lastScrollbar = observation;

        const double movingRatio = static_cast<double>(scrollbarMovingMovements)
            / static_cast<double>(scrollbarObservedMovements);
        const double confidence = movingRatio * scrollbarMinimumPersistence;
        if (scrollbarObservedMovements >= config.scrollbarConfirmationMovements
            && confidence >= config.scrollbarConfidenceThreshold) {
            scrollbarWidth = observation->width;
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
{
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

    auto fingerprint = FrameFingerprint::make(frame, AnchorFingerprintSize);
    if (fingerprint.luminance.empty()) {
        return result;
    }
    const std::size_t fingerprintBytes = fingerprint.luminance.capacity();
    const auto fullFrameBytes = imageBytes(frame.width, frame.height);
    if (!fullFrameBytes.has_value()) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }

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
            implementation_->segments.push_back({*storedFrame, 0, 0, frame.height});
            implementation_->anchors.push_back(std::move(fingerprint));
        } catch (...) {
            implementation_->segments.clear();
            implementation_->anchors.clear();
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
        result.kind = *match + 1U == implementation_->anchors.size()
            ? AppendKind::DuplicateDiscarded
            : AppendKind::ReviewDiscarded;
        result.confidence = 1.0;
        return result;
    }

    const auto matcherConfig = implementation_->effectiveMatcherConfig();
    VerticalOverlapMatcher matcher;
    const auto& tail = *implementation_->tail;
    const auto reverse = matcher.match(frame, tail, matcherConfig);
    if (reverse.kind == OverlapKind::Reliable && reverse.verticalAdvance > 0) {
        result.kind = AppendKind::ReviewDiscarded;
        result.confidence = reverse.confidence;
        return result;
    }
    const auto overlap = matcher.match(tail, frame, matcherConfig);
    result.confidence = overlap.confidence;
    if (overlap.kind != OverlapKind::Reliable || overlap.verticalAdvance <= 0) {
        return result;
    }

    const int appendedHeight = overlap.verticalAdvance;
    const int bottomCandidate = config.fixedBottomCandidateHeight;
    if (appendedHeight > std::numeric_limits<int>::max() - implementation_->height
        || appendedHeight > frame.height - bottomCandidate - config.fixedTopCandidateHeight) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }
    const int rawRows = appendedHeight + bottomCandidate;
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

    auto rawSegment = copyRows(frame, frame.height - rawRows, rawRows);
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

    implementation_->observeFixedBands(tail, frame);
    implementation_->observeScrollbar(tail, frame);
    implementation_->segments.push_back({
        *storedSegment,
        bottomCandidate,
        0,
        appendedHeight,
    });
    implementation_->anchors.push_back(std::move(fingerprint));
    implementation_->tail = *storedTail;
    implementation_->tailHasSeparateStorage = true;
    implementation_->persistentBytes = projected;
    implementation_->height += appendedHeight;
    result.kind = AppendKind::AcceptedAppend;
    result.appendedHeight = appendedHeight;
    result.outputHeight = implementation_->height;
    return result;
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
    const int outputWidth = implementation_->width - implementation_->scrollbarWidth;
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
        const int firstRow = implementation_->fixedBottomConfirmed
            ? segment.fixedBottomFirstRow
            : segment.ordinaryFirstRow;
        if (!segment.pixels || firstRow < 0 || segment.outputRows <= 0
            || firstRow > segment.pixels->height - segment.outputRows) {
            return {};
        }
        for (int row = 0; row < segment.outputRows; ++row, ++outputRow) {
            const auto sourceOffset = static_cast<std::size_t>(firstRow + row)
                * static_cast<std::size_t>(segment.pixels->bytesPerRow);
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
    const auto full = finalize();
    if (!full.isValid() || maximumHeight <= 0) {
        return {};
    }
    if (full.height <= maximumHeight) {
        return full;
    }
    const int previewWidth = std::max(1, static_cast<int>(
        std::lround(static_cast<double>(full.width) * maximumHeight / full.height)));
    if (!imageBytes(previewWidth, maximumHeight).has_value()) {
        return {};
    }
    ScrollFrame output(previewWidth, maximumHeight);
    if (!output.isValid()) {
        return {};
    }
    for (int y = 0; y < output.height; ++y) {
        const int sourceY = static_cast<int>(
            static_cast<std::int64_t>(y) * full.height / output.height);
        for (int x = 0; x < output.width; ++x) {
            const int sourceX = static_cast<int>(
                static_cast<std::int64_t>(x) * full.width / output.width);
            const auto sourceOffset = static_cast<std::size_t>(sourceY)
                    * static_cast<std::size_t>(full.bytesPerRow)
                + static_cast<std::size_t>(sourceX) * 4U;
            const auto destinationOffset = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(output.bytesPerRow)
                + static_cast<std::size_t>(x) * 4U;
            std::memcpy(output.pixels.data() + destinationOffset, full.pixels.data() + sourceOffset, 4U);
        }
    }
    return output;
}

} // namespace snipory::core::scroll
