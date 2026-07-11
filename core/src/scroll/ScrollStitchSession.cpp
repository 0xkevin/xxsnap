#include "snipory/core/scroll/ScrollStitchSession.h"

#include "snipory/core/scroll/FrameFingerprint.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <optional>
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
        && config.fixedBandConfirmationMovements >= 1
        && validUnit(config.fixedBandStationaryThreshold)
        && config.scrollbarMaximumWidth >= 0
        && config.scrollbarConfirmationMovements >= 1
        && validUnit(config.scrollbarPersistenceThreshold)
        && validUnit(config.scrollbarMotionThreshold);
}

[[nodiscard]] std::optional<std::size_t> imageBytes(int width, int height)
{
    if (width <= 0 || height <= 0) {
        return std::nullopt;
    }
    const auto w = static_cast<std::size_t>(width);
    const auto h = static_cast<std::size_t>(height);
    if (w > std::numeric_limits<std::size_t>::max() / 4U
        || h > std::numeric_limits<std::size_t>::max() / (w * 4U)) {
        return std::nullopt;
    }
    return w * h * 4U;
}

[[nodiscard]] bool pixelEqual(const ScrollFrame& left, const ScrollFrame& right, int x, int y)
{
    const auto leftOffset = static_cast<std::size_t>(y) * static_cast<std::size_t>(left.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    const auto rightOffset = static_cast<std::size_t>(y) * static_cast<std::size_t>(right.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    return std::memcmp(left.pixels.data() + leftOffset, right.pixels.data() + rightOffset, 3U) == 0;
}

[[nodiscard]] ScrollFrame copyRows(const ScrollFrame& source, int firstRow, int rowCount)
{
    ScrollFrame copy(source.width, rowCount);
    if (!copy.isValid() || firstRow < 0 || rowCount <= 0 || firstRow > source.height - rowCount) {
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

} // namespace

class ScrollStitchSession::Implementation final
{
public:
    explicit Implementation(ScrollStitchConfig value)
        : config(std::move(value))
        , configIsValid(validConfig(config))
    {
    }

    struct Anchor final
    {
        ScrollFrame frame;
        Fingerprint fingerprint;
    };

    ScrollStitchConfig config;
    bool configIsValid = false;
    std::vector<ScrollFrame> segments;
    std::vector<Anchor> anchors;
    int height = 0;
    int width = 0;
    int fixedTopAgreements = 0;
    int fixedBottomAgreements = 0;
    int scrollbarAgreements = 0;
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
            if (duplicateFingerprint(anchors[i - 1U].fingerprint, fingerprint)) {
                return i - 1U;
            }
        }
        for (std::size_t i = recentStart; i > 0U; --i) {
            if (duplicateFingerprint(anchors[i - 1U].fingerprint, fingerprint)) {
                return i - 1U;
            }
        }
        return std::nullopt;
    }

    [[nodiscard]] OverlapConfig effectiveMatcherConfig() const
    {
        auto result = config.matcher;
        result.excludedBands.top = std::max(result.excludedBands.top, config.fixedTopCandidateHeight);
        result.excludedBands.bottom = std::max(result.excludedBands.bottom, config.fixedBottomCandidateHeight);
        result.excludedBands.right = std::max(result.excludedBands.right, config.scrollbarMaximumWidth);
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
        std::size_t equal = 0;
        const auto total = static_cast<std::size_t>(rowCount) * static_cast<std::size_t>(width);
        for (int y = firstRow; y < firstRow + rowCount; ++y) {
            for (int x = 0; x < width; ++x) {
                equal += pixelEqual(previous, current, x, y) ? 1U : 0U;
            }
        }
        return static_cast<double>(equal) / static_cast<double>(total);
    }

    void observeFixedBands(const ScrollFrame& previous, const ScrollFrame& current)
    {
        if (config.fixedTopCandidateHeight > 0) {
            fixedTopAgreements = stationaryRatio(previous, current, 0, config.fixedTopCandidateHeight)
                    >= config.fixedBandStationaryThreshold
                ? fixedTopAgreements + 1
                : 0;
        }
        if (config.fixedBottomCandidateHeight > 0) {
            fixedBottomAgreements = stationaryRatio(
                                        previous,
                                        current,
                                        current.height - config.fixedBottomCandidateHeight,
                                        config.fixedBottomCandidateHeight)
                    >= config.fixedBandStationaryThreshold
                ? fixedBottomAgreements + 1
                : 0;
        }
    }

    void observeScrollbar(const ScrollFrame& previous, const ScrollFrame& current)
    {
        if (config.scrollbarMaximumWidth <= 0) {
            return;
        }
        const int budget = std::min(config.scrollbarMaximumWidth, width / 8);
        int qualifyingWidth = 0;
        for (int x = width - 1; x >= width - budget; --x) {
            int equal = 0;
            int longestChangedRun = 0;
            int changedRun = 0;
            for (int y = 0; y < current.height; ++y) {
                if (pixelEqual(previous, current, x, y)) {
                    ++equal;
                    changedRun = 0;
                } else {
                    ++changedRun;
                    longestChangedRun = std::max(longestChangedRun, changedRun);
                }
            }
            const double persistence = static_cast<double>(equal) / static_cast<double>(current.height);
            const double motion = 1.0 - persistence;
            const int changed = current.height - equal;
            const bool thumbShapedMotion = changed >= 4 && longestChangedRun * 3 >= changed;
            if (persistence < config.scrollbarPersistenceThreshold
                || motion < config.scrollbarMotionThreshold || !thumbShapedMotion) {
                break;
            }
            ++qualifyingWidth;
        }
        if (qualifyingWidth > 0) {
            ++scrollbarAgreements;
            if (scrollbarAgreements >= config.scrollbarConfirmationMovements) {
                scrollbarWidth = qualifyingWidth;
            }
        } else {
            scrollbarAgreements = 0;
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

    const auto fingerprint = FrameFingerprint::make(frame, AnchorFingerprintSize);
    if (fingerprint.luminance.empty()) {
        return result;
    }

    if (implementation_->anchors.empty()) {
        const auto bytes = imageBytes(frame.width, frame.height);
        if (!bytes.has_value() || *bytes >= implementation_->config.maximumAcceptedBytes) {
            result.kind = AppendKind::ResourceLimit;
            return result;
        }
        implementation_->width = frame.width;
        implementation_->height = frame.height;
        implementation_->segments.push_back(copyRows(frame, 0, frame.height));
        implementation_->anchors.push_back({frame, fingerprint});
        result.kind = AppendKind::AcceptedInitial;
        result.appendedHeight = frame.height;
        result.outputHeight = frame.height;
        result.confidence = 1.0;
        return result;
    }

    if (frame.width != implementation_->width
        || frame.height != implementation_->anchors.front().frame.height) {
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
    const auto& tail = implementation_->anchors.back().frame;
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
    if (appendedHeight > std::numeric_limits<int>::max() - implementation_->height) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }
    const int projectedHeight = implementation_->height + appendedHeight;
    const auto projectedBytes = imageBytes(implementation_->width, projectedHeight);
    if (!projectedBytes.has_value()
        || *projectedBytes >= implementation_->config.maximumAcceptedBytes) {
        result.kind = AppendKind::ResourceLimit;
        return result;
    }

    const int bottomBand = implementation_->config.fixedBottomCandidateHeight;
    const int firstNewRow = frame.height - bottomBand - appendedHeight;
    if (firstNewRow < implementation_->config.fixedTopCandidateHeight) {
        return result;
    }
    auto segment = copyRows(frame, firstNewRow, appendedHeight);
    if (!segment.isValid()) {
        return result;
    }

    implementation_->observeFixedBands(tail, frame);
    implementation_->observeScrollbar(tail, frame);
    implementation_->segments.push_back(std::move(segment));
    implementation_->anchors.push_back({frame, fingerprint});
    implementation_->height = projectedHeight;
    result.kind = AppendKind::AcceptedAppend;
    result.appendedHeight = appendedHeight;
    result.outputHeight = projectedHeight;
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
    ScrollFrame output(outputWidth, implementation_->height);
    if (!output.isValid()) {
        return {};
    }
    const auto rowBytes = static_cast<std::size_t>(outputWidth) * 4U;
    int outputRow = 0;
    for (const auto& segment : implementation_->segments) {
        for (int row = 0; row < segment.height; ++row, ++outputRow) {
            const auto sourceOffset = static_cast<std::size_t>(row)
                * static_cast<std::size_t>(segment.bytesPerRow);
            const auto destinationOffset = static_cast<std::size_t>(outputRow)
                * static_cast<std::size_t>(output.bytesPerRow);
            std::memcpy(output.pixels.data() + destinationOffset, segment.pixels.data() + sourceOffset, rowBytes);
        }
    }
    return output;
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
