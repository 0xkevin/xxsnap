#include "snipory/core/scroll/VerticalOverlapMatcher.h"

#include <QElapsedTimer>
#include <QTest>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace {

using snipory::core::scroll::OverlapConfig;
using snipory::core::scroll::OverlapKind;
using snipory::core::scroll::ScrollFrame;
using snipory::core::scroll::VerticalOverlapMatcher;

void setGray(ScrollFrame& frame, int x, int y, std::uint8_t value)
{
    const auto offset = static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    frame.pixels[offset] = value;
    frame.pixels[offset + 1U] = value;
    frame.pixels[offset + 2U] = value;
    frame.pixels[offset + 3U] = 255;
}

ScrollFrame stripedDocument(int width, int height)
{
    ScrollFrame frame(width, height);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            auto valueBits = static_cast<std::uint32_t>(y) * 0x9e3779b9U
                ^ static_cast<std::uint32_t>(x) * 0x85ebca6bU;
            valueBits ^= valueBits >> 16U;
            valueBits *= 0x7feb352dU;
            valueBits ^= valueBits >> 15U;
            const auto value = static_cast<std::uint8_t>(valueBits & 0xffU);
            setGray(frame, x, y, value);
        }
    }
    return frame;
}

ScrollFrame repeatedRows(int width, int height, int period)
{
    ScrollFrame frame(width, height);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const auto value = static_cast<std::uint8_t>(((y % period) * 19 + x * 7) & 0xff);
            setGray(frame, x, y, value);
        }
    }
    return frame;
}

ScrollFrame sparseChatWithStationaryWatermark(int documentY)
{
    ScrollFrame frame(240, 240);
    for (int y = 0; y < frame.height; ++y) {
        const int sourceY = documentY + y;
        for (int x = 0; x < frame.width; ++x) {
            std::uint8_t value = 255;
            if (sourceY >= 190 && sourceY < 225 && x >= 24 && x < 132) {
                value = static_cast<std::uint8_t>(72 + (sourceY * 7 + x * 11) % 96);
            }
            if ((x + y * 2) % 72 < 12) {
                value = static_cast<std::uint8_t>(
                    static_cast<unsigned>(value) * 232U / 255U);
            }
            setGray(frame, x, y, value);
        }
    }
    return frame;
}

ScrollFrame sparseVirtualList(int contentPhase)
{
    ScrollFrame frame(240, 240);
    for (int y = 0; y < frame.height; ++y) {
        const int row = y / 20;
        const int rowInItem = y % 20;
        for (int x = 0; x < frame.width; ++x) {
            std::uint8_t value = 248;
            const bool icon = x >= 8 && x < 18 && rowInItem >= 5 && rowInItem < 15;
            const bool title = x >= 28 && x < 118 + row * 3
                && rowInItem >= 6 && rowInItem < 9;
            const bool metadata = x >= 150 && x < 190
                && rowInItem >= 7 && rowInItem < 9;
            if (icon || title || metadata) {
                value = static_cast<std::uint8_t>(60 + contentPhase * 20);
            }
            setGray(frame, x, y, value);
        }
    }
    return frame;
}

ScrollFrame sparseListDocument(int width, int height)
{
    ScrollFrame frame(width, height);
    for (int y = 0; y < height; ++y) {
        const int item = y / 48;
        const int rowInItem = y % 48;
        const int titleWidth = 90 + (item * 53) % 360;
        const int metadataStart = width - 150 - (item * 17) % 80;
        for (int x = 0; x < width; ++x) {
            std::uint8_t value = 250;
            const bool icon = x >= 12 && x < 38 && rowInItem >= 11 && rowInItem < 37;
            const bool title = x >= 56 && x < 56 + titleWidth
                && rowInItem >= 15 && rowInItem < 20;
            const bool metadata = x >= metadataStart && x < width - 20
                && rowInItem >= 17 && rowInItem < 21;
            if (icon) {
                value = static_cast<std::uint8_t>(50 + (item * 29) % 150);
            } else if (title || metadata) {
                value = static_cast<std::uint8_t>(35 + (item * 11) % 80);
            }
            setGray(frame, x, y, value);
        }
    }
    return frame;
}

ScrollFrame detailSkippedByAspectScalingDocument(
    int width,
    int viewportHeight,
    int documentHeight)
{
    constexpr int matchingHeight = 512;
    const int scaledWidth = std::max(1, static_cast<int>(std::lround(
        static_cast<double>(width) * matchingHeight / viewportHeight)));
    std::vector<bool> sampledColumns(static_cast<std::size_t>(width), false);
    const double sourceColumnsPerTarget = static_cast<double>(width) / scaledWidth;
    for (int targetX = 0; targetX < scaledWidth; ++targetX) {
        const double sourcePosition = (static_cast<double>(targetX) + 0.5)
                * sourceColumnsPerTarget
            - 0.5;
        const int first = std::clamp(
            static_cast<int>(std::floor(sourcePosition)), 0, width - 1);
        sampledColumns[static_cast<std::size_t>(first)] = true;
        sampledColumns[static_cast<std::size_t>(std::min(width - 1, first + 1))] = true;
    }

    ScrollFrame frame(width, documentHeight);
    for (int y = 0; y < documentHeight; ++y) {
        for (int x = 0; x < width; ++x) {
            std::uint8_t value = 250;
            if (!sampledColumns[static_cast<std::size_t>(x)]) {
                auto bits = static_cast<std::uint32_t>(y) * 0x9e3779b9U
                    ^ static_cast<std::uint32_t>(x) * 0x85ebca6bU;
                bits ^= bits >> 16U;
                value = static_cast<std::uint8_t>(32U + bits % 176U);
            }
            setGray(frame, x, y, value);
        }
    }
    return frame;
}

ScrollFrame verticalGradient(int width, int height)
{
    ScrollFrame frame(width, height);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            setGray(frame, x, y, static_cast<std::uint8_t>(y & 0xff));
        }
    }
    return frame;
}

ScrollFrame aliasedHighFrequencyDocument(int width, int height)
{
    constexpr std::array<std::uint8_t, 6> base{20, 70, 130, 210, 160, 90};
    ScrollFrame frame(width, height);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            auto detail = static_cast<std::uint32_t>(y) * 0x9e3779b9U
                ^ static_cast<std::uint32_t>(x) * 0x85ebca6bU;
            detail ^= detail >> 16U;
            setGray(frame, x, y, static_cast<std::uint8_t>(base[static_cast<std::size_t>(y % 6)] + detail % 32U));
        }
    }
    return frame;
}

ScrollFrame aliasedSamplingFrame(int width, int height, int documentY, int coarseColumnStep)
{
    ScrollFrame frame(width, height);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            auto bits = static_cast<std::uint32_t>(y + documentY) * 0x9e3779b9U
                ^ static_cast<std::uint32_t>(x) * 0x85ebca6bU;
            bits ^= bits >> 16U;
            const auto value = (y + documentY) % 4 == 0 && x % coarseColumnStep == 0
                ? std::uint8_t{0}
                : static_cast<std::uint8_t>(bits & 0xffU);
            setGray(frame, x, y, value);
        }
    }
    return frame;
}

ScrollFrame cancellingPatternFrame(int width, int height, int amplitude)
{
    ScrollFrame frame(width, height);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const bool positive = ((x & 1) ^ (y & 1)) != 0;
            const auto value = static_cast<std::uint8_t>(100 + (positive ? amplitude : -amplitude));
            setGray(frame, x, y, value);
        }
    }
    return frame;
}

ScrollFrame commonNullspaceFrame(int height, int documentY)
{
    ScrollFrame frame(512, height);
    for (int y = 0; y < height; ++y) {
        const auto coefficient = static_cast<int>(
            (static_cast<std::uint32_t>(y + documentY) * 37U) % 81U) - 40;
        for (int x = 0; x < frame.width; ++x) {
            int value = 128;
            if (x == 509) {
                value += coefficient;
            } else if (x == 511) {
                value -= coefficient;
            }
            setGray(frame, x, y, static_cast<std::uint8_t>(value));
        }
    }
    return frame;
}

ScrollFrame crop(const ScrollFrame& source, int x, int y, int width, int height)
{
    ScrollFrame result(width, height);
    for (int row = 0; row < height; ++row) {
        const auto sourceOffset = static_cast<std::size_t>(y + row)
                * static_cast<std::size_t>(source.bytesPerRow)
            + static_cast<std::size_t>(x) * 4U;
        const auto destinationOffset = static_cast<std::size_t>(row)
            * static_cast<std::size_t>(result.bytesPerRow);
        std::copy_n(
            source.pixels.cbegin() + static_cast<std::ptrdiff_t>(sourceOffset),
            static_cast<std::size_t>(width) * 4U,
            result.pixels.begin() + static_cast<std::ptrdiff_t>(destinationOffset));
    }
    return result;
}

void fillRows(ScrollFrame& frame, int firstRow, int rowCount, std::uint8_t value)
{
    for (int y = firstRow; y < firstRow + rowCount; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            setGray(frame, x, y, value);
        }
    }
}

void fillColumns(ScrollFrame& frame, int firstColumn, int columnCount, std::uint8_t value)
{
    for (int y = 0; y < frame.height; ++y) {
        for (int x = firstColumn; x < firstColumn + columnCount; ++x) {
            setGray(frame, x, y, value);
        }
    }
}

void addBrightness(ScrollFrame& frame, std::uint8_t amount)
{
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            const auto offset = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(frame.bytesPerRow)
                + static_cast<std::size_t>(x) * 4U;
            const auto value = static_cast<std::uint8_t>(
                std::min(255, static_cast<int>(frame.pixels[offset]) + static_cast<int>(amount)));
            setGray(frame, x, y, value);
        }
    }
}

void corruptQuarterGrid(ScrollFrame& frame)
{
    for (int y = 0; y < frame.height; y += 4) {
        for (int x = 0; x < frame.width; x += 4) {
            const auto offset = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(frame.bytesPerRow)
                + static_cast<std::size_t>(x) * 4U;
            setGray(frame, x, y, static_cast<std::uint8_t>(255U - frame.pixels[offset]));
        }
    }
}

void paintFixedHeader(ScrollFrame& frame, int height)
{
    for (int y = 0; y < std::min(height, frame.height); ++y) {
        for (int x = 0; x < frame.width; ++x) {
            setGray(frame, x, y, static_cast<std::uint8_t>(32 + (x * 13 + y * 7) % 160));
        }
    }
}

void paintFixedMiddleBand(ScrollFrame& frame, int firstColumn, int columnCount)
{
    const int lastColumn = std::min(frame.width, firstColumn + columnCount);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = std::max(0, firstColumn); x < lastColumn; ++x) {
            setGray(frame, x, y, static_cast<std::uint8_t>(32 + (x * 13 + y * 7) % 160));
        }
    }
}

} // namespace

class TestVerticalOverlapMatcher final : public QObject
{
    Q_OBJECT

private slots:
    void findsDownwardOffset();
    void rejectsRepeatedPatternWithAmbiguousPlacement();
    void rejectsUnrelatedFramesAsInsufficient();
    void respectsMinimumOverlapRatio();
    void masksChangingFixedHeader();
    void findsNonMultipleOfFourHighFrequencyOffset();
    void comparesDistinctPeaksForAmbiguity();
    void matchesWhenScoringRegionIsNarrowerThanCoarseBlock();
    void masksLeftRightAndBottomBands();
    void respectsMaximumAdvanceRatio();
    void defaultRejectsAdvanceBeyondTwoThirdsOfViewport();
    void expectedAdvanceCannotBypassTwoThirdsSafetyLimit();
    void respectsMaximumNormalizedError();
    void respectsMinimumWinnerMargin();
    void rejectsInvalidInputsAndConfig();
    void matchesOnePixelWideScoringRegion();
    void recallsNonZeroErrorPeakBeyondFixedCandidateLimit();
    void detectsShortPeriodIndependentPeaks();
    void avoidsQuadraticFullResolutionFallback();
    void ignoresAdvancesWithEmptyMaskedIntersection();
    void detectsIndependentPeaksHiddenByFlatSignature();
    void usesExpectedAdvanceToResolveStationaryWatermarkAmbiguity();
    void expectedAdvanceDoesNotPromoteNearThresholdVisualMismatch();
    void expectedAdvanceRejectsLowConfidenceVirtualListReplacement();
    void matchesLargeViewportAtFullResolutionAdvance();
    void preservesHorizontalDetailWhenReducingLargeViewportHeight();
    void isolatesChangedScrollingRegionFromLargeFixedHeader();
    void ignoresStationaryPixelsInsideChangedRegion();
    void avoidsFlatSignatureFullResolutionDegeneration();
    void returnsConservativeResultWhenEvaluationBudgetIsExhausted();
    void sufficientBudgetResolvesSmallCommonNullspaceInput();
    void validatesFullResolutionCandidateBudget();
    void budgetExhaustionTakesPriorityOverProvisionalError();
};

void TestVerticalOverlapMatcher::findsDownwardOffset()
{
    const ScrollFrame document = stripedDocument(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    const ScrollFrame current = crop(document, 0, 72, 120, 180);

    const auto result = VerticalOverlapMatcher().match(previous, current, {});

    QVERIFY2(result.kind == OverlapKind::Reliable,
        qPrintable(QStringLiteral("advance=%1 confidence=%2 error=%3")
            .arg(result.verticalAdvance)
            .arg(result.confidence)
            .arg(result.normalizedError)));
    QCOMPARE(result.verticalAdvance, 72);
    QCOMPARE(result.overlapHeight, 108);
    QVERIFY(result.confidence >= 0.8);
}

void TestVerticalOverlapMatcher::usesExpectedAdvanceToResolveStationaryWatermarkAmbiguity()
{
    const auto previous = sparseChatWithStationaryWatermark(80);
    const auto current = sparseChatWithStationaryWatermark(160);
    OverlapConfig config;
    config.expectedAdvance = 80;
    config.expectedAdvanceTolerance = 8;
    config.minimumReliableConfidence = 0.30;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QVERIFY2(result.kind == OverlapKind::Reliable,
        qPrintable(QStringLiteral("advance=%1 confidence=%2 error=%3")
            .arg(result.verticalAdvance)
            .arg(result.confidence)
            .arg(result.normalizedError)));
    QCOMPARE(result.verticalAdvance, 80);
    QVERIFY(result.normalizedError <= config.maximumNormalizedError);
}

void TestVerticalOverlapMatcher::expectedAdvanceDoesNotPromoteNearThresholdVisualMismatch()
{
    ScrollFrame previous(120, 180);
    ScrollFrame current(120, 180);
    std::fill(previous.pixels.begin(), previous.pixels.end(), 100);
    std::fill(current.pixels.begin(), current.pixels.end(), 109);
    OverlapConfig config;
    config.expectedAdvance = 60;
    config.expectedAdvanceTolerance = 2;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QVERIFY(result.kind != OverlapKind::Reliable);
}

void TestVerticalOverlapMatcher::expectedAdvanceRejectsLowConfidenceVirtualListReplacement()
{
    const auto previous = sparseVirtualList(0);
    const auto replaced = sparseVirtualList(1);
    OverlapConfig config;
    config.expectedAdvance = 80;
    config.expectedAdvanceTolerance = 2;

    const auto result = VerticalOverlapMatcher().match(previous, replaced, config);

    QVERIFY2(result.kind != OverlapKind::Reliable,
        qPrintable(QStringLiteral("advance=%1 confidence=%2 error=%3")
            .arg(result.verticalAdvance)
            .arg(result.confidence)
            .arg(result.normalizedError)));
}

void TestVerticalOverlapMatcher::matchesLargeViewportAtFullResolutionAdvance()
{
    constexpr int viewportWidth = 1'482;
    constexpr int viewportHeight = 3'491;
    constexpr int advance = 620;
    const ScrollFrame document = sparseListDocument(
        viewportWidth, viewportHeight + advance);
    const ScrollFrame previous = crop(
        document, 0, 0, viewportWidth, viewportHeight);
    const ScrollFrame current = crop(
        document, 0, advance, viewportWidth, viewportHeight);

    QElapsedTimer timer;
    timer.start();
    const auto result = VerticalOverlapMatcher().match(previous, current, {});
    const auto elapsed = timer.elapsed();

    QVERIFY2(result.kind == OverlapKind::Reliable,
        qPrintable(QStringLiteral("advance=%1 confidence=%2 error=%3")
            .arg(result.verticalAdvance)
            .arg(result.confidence)
            .arg(result.normalizedError)));
    QCOMPARE(result.verticalAdvance, advance);
    QCOMPARE(result.overlapHeight, viewportHeight - advance);
    // The live pipeline samples every 100 ms. Matching must stay below that
    // budget or the FIFO eventually loses the continuous overlap chain.
    QVERIFY2(elapsed < 100,
        qPrintable(QStringLiteral("large viewport match took %1 ms").arg(elapsed)));
}

void TestVerticalOverlapMatcher::preservesHorizontalDetailWhenReducingLargeViewportHeight()
{
    constexpr int viewportWidth = 1'482;
    constexpr int viewportHeight = 3'491;
    constexpr int advance = 620;
    const ScrollFrame document = detailSkippedByAspectScalingDocument(
        viewportWidth, viewportHeight, viewportHeight + advance);
    const ScrollFrame previous = crop(
        document, 0, 0, viewportWidth, viewportHeight);
    const ScrollFrame current = crop(
        document, 0, advance, viewportWidth, viewportHeight);

    const auto result = VerticalOverlapMatcher().match(previous, current, {});

    QVERIFY2(result.kind == OverlapKind::Reliable,
        qPrintable(QStringLiteral("advance=%1 confidence=%2 error=%3")
            .arg(result.verticalAdvance)
            .arg(result.confidence)
            .arg(result.normalizedError)));
    QCOMPARE(result.verticalAdvance, advance);
}

void TestVerticalOverlapMatcher::isolatesChangedScrollingRegionFromLargeFixedHeader()
{
    constexpr int viewportWidth = 1'482;
    constexpr int viewportHeight = 3'491;
    constexpr int fixedHeaderHeight = 1'500;
    constexpr int advance = 620;
    const ScrollFrame document = sparseListDocument(
        viewportWidth, viewportHeight + advance);
    ScrollFrame previous = crop(document, 0, 0, viewportWidth, viewportHeight);
    ScrollFrame current = crop(document, 0, advance, viewportWidth, viewportHeight);
    paintFixedHeader(previous, fixedHeaderHeight);
    paintFixedHeader(current, fixedHeaderHeight);

    const auto result = VerticalOverlapMatcher().match(previous, current, {});

    QVERIFY2(result.kind == OverlapKind::Reliable,
        qPrintable(QStringLiteral("advance=%1 confidence=%2 error=%3")
            .arg(result.verticalAdvance)
            .arg(result.confidence)
            .arg(result.normalizedError)));
    QCOMPARE(result.verticalAdvance, advance);
}

void TestVerticalOverlapMatcher::ignoresStationaryPixelsInsideChangedRegion()
{
    constexpr int viewportWidth = 900;
    constexpr int viewportHeight = 800;
    constexpr int advance = 100;
    const ScrollFrame document = sparseListDocument(
        viewportWidth, viewportHeight + advance);
    ScrollFrame previous = crop(document, 0, 0, viewportWidth, viewportHeight);
    ScrollFrame current = crop(document, 0, advance, viewportWidth, viewportHeight);

    // A fixed browser/sidebar surface sits inside the outer bounds of the
    // moving article. PixPin's changed-pixel mask excludes it from scoring.
    paintFixedMiddleBand(previous, 190, 520);
    paintFixedMiddleBand(current, 190, 520);

    OverlapConfig config;
    config.allowChangedPixelFallback = true;
    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QVERIFY2(result.kind == OverlapKind::Reliable,
        qPrintable(QStringLiteral("advance=%1 confidence=%2 error=%3")
            .arg(result.verticalAdvance)
            .arg(result.confidence)
            .arg(result.normalizedError)));
    QCOMPARE(result.verticalAdvance, advance);
}

void TestVerticalOverlapMatcher::rejectsRepeatedPatternWithAmbiguousPlacement()
{
    const ScrollFrame repeated = repeatedRows(120, 180, 12);

    const auto result = VerticalOverlapMatcher().match(repeated, repeated, {});

    QCOMPARE(result.kind, OverlapKind::Ambiguous);
}

void TestVerticalOverlapMatcher::rejectsUnrelatedFramesAsInsufficient()
{
    const ScrollFrame previous = stripedDocument(120, 180);
    ScrollFrame current(120, 180);
    fillRows(current, 0, current.height, 255);
    OverlapConfig config;
    config.maximumFullResolutionCandidates = 200;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Insufficient);
    QVERIFY(result.normalizedError > 0.08);
}

void TestVerticalOverlapMatcher::respectsMinimumOverlapRatio()
{
    const ScrollFrame document = stripedDocument(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    const ScrollFrame current = crop(document, 0, 120, 120, 180);
    OverlapConfig config;
    config.minimumOverlapRatio = 0.50;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Insufficient);
}

void TestVerticalOverlapMatcher::masksChangingFixedHeader()
{
    const ScrollFrame document = stripedDocument(120, 480);
    const ScrollFrame cleanPrevious = crop(document, 0, 0, 120, 180);
    const ScrollFrame cleanCurrent = crop(document, 0, 72, 120, 180);
    ScrollFrame previous = cleanPrevious;
    ScrollFrame current = cleanCurrent;
    fillRows(previous, 0, 24, 15);
    fillRows(current, 0, 24, 240);

    OverlapConfig config;
    config.excludedBands.top = 24;
    const auto clean = VerticalOverlapMatcher().match(cleanPrevious, cleanCurrent, config);
    const auto changedHeader = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(clean.kind, OverlapKind::Reliable);
    QCOMPARE(changedHeader.kind, OverlapKind::Reliable);
    QCOMPARE(changedHeader.verticalAdvance, clean.verticalAdvance);
    QCOMPARE(changedHeader.verticalAdvance, 72);
}

void TestVerticalOverlapMatcher::findsNonMultipleOfFourHighFrequencyOffset()
{
    const ScrollFrame document = aliasedHighFrequencyDocument(120, 360);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    const ScrollFrame current = crop(document, 0, 2, 120, 180);

    const auto result = VerticalOverlapMatcher().match(previous, current, {});

    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, 2);
    QCOMPARE(result.normalizedError, 0.0);
}

void TestVerticalOverlapMatcher::comparesDistinctPeaksForAmbiguity()
{
    const ScrollFrame document = verticalGradient(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    const ScrollFrame current = crop(document, 0, 72, 120, 180);

    const auto result = VerticalOverlapMatcher().match(previous, current, {});

    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, 72);
}

void TestVerticalOverlapMatcher::matchesWhenScoringRegionIsNarrowerThanCoarseBlock()
{
    const ScrollFrame document = stripedDocument(3, 240);
    const ScrollFrame previous = crop(document, 0, 0, 3, 100);
    const ScrollFrame current = crop(document, 0, 50, 3, 100);

    const auto result = VerticalOverlapMatcher().match(previous, current, {});

    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, 50);
}

void TestVerticalOverlapMatcher::masksLeftRightAndBottomBands()
{
    const ScrollFrame document = stripedDocument(120, 480);
    ScrollFrame previous = crop(document, 0, 0, 120, 180);
    ScrollFrame current = crop(document, 0, 72, 120, 180);
    fillColumns(previous, 0, 48, 0);
    fillColumns(current, 0, 48, 255);
    fillColumns(previous, 72, 48, 0);
    fillColumns(current, 72, 48, 255);
    fillRows(previous, 132, 48, 0);
    fillRows(current, 132, 48, 255);
    OverlapConfig config;
    config.excludedBands.left = 48;
    config.excludedBands.right = 48;
    config.excludedBands.bottom = 48;

    const auto unmasked = VerticalOverlapMatcher().match(previous, current, {});
    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QVERIFY(unmasked.kind != OverlapKind::Reliable || unmasked.verticalAdvance != 72);
    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, 72);
}

void TestVerticalOverlapMatcher::respectsMaximumAdvanceRatio()
{
    const ScrollFrame document = stripedDocument(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    const ScrollFrame current = crop(document, 0, 72, 120, 180);
    OverlapConfig config;
    config.maximumAdvanceRatio = 0.30;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Insufficient);
}

void TestVerticalOverlapMatcher::defaultRejectsAdvanceBeyondTwoThirdsOfViewport()
{
    const ScrollFrame document = stripedDocument(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    const ScrollFrame current = crop(document, 0, 130, 120, 180);

    const auto result = VerticalOverlapMatcher().match(previous, current, {});

    QCOMPARE(result.kind, OverlapKind::Insufficient);
}

void TestVerticalOverlapMatcher::expectedAdvanceCannotBypassTwoThirdsSafetyLimit()
{
    const ScrollFrame document = stripedDocument(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    const ScrollFrame current = crop(document, 0, 130, 120, 180);
    OverlapConfig config;
    config.expectedAdvance = 130;
    config.expectedAdvanceTolerance = 2;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Insufficient);
}

void TestVerticalOverlapMatcher::respectsMaximumNormalizedError()
{
    const ScrollFrame document = stripedDocument(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    ScrollFrame current = crop(document, 0, 72, 120, 180);
    addBrightness(current, 5);
    OverlapConfig config;
    config.maximumNormalizedError = 0.01;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Insufficient);
    QVERIFY(result.normalizedError > config.maximumNormalizedError);
}

void TestVerticalOverlapMatcher::respectsMinimumWinnerMargin()
{
    const ScrollFrame repeated = repeatedRows(120, 180, 12);
    OverlapConfig config;
    config.minimumWinnerMargin = 0.0;

    const auto result = VerticalOverlapMatcher().match(repeated, repeated, config);

    QCOMPARE(result.kind, OverlapKind::Reliable);
}

void TestVerticalOverlapMatcher::rejectsInvalidInputsAndConfig()
{
    const ScrollFrame valid = stripedDocument(12, 20);
    ScrollFrame invalid;
    QCOMPARE(VerticalOverlapMatcher().match(invalid, valid, {}).kind, OverlapKind::Insufficient);
    QCOMPARE(
        VerticalOverlapMatcher().match(valid, stripedDocument(11, 20), {}).kind,
        OverlapKind::Insufficient);

    OverlapConfig config;
    config.minimumOverlapRatio = 0.0;
    QCOMPARE(VerticalOverlapMatcher().match(valid, valid, config).kind, OverlapKind::Insufficient);
    config = {};
    config.maximumAdvanceRatio = 1.1;
    QCOMPARE(VerticalOverlapMatcher().match(valid, valid, config).kind, OverlapKind::Insufficient);
    config = {};
    config.maximumNormalizedError = -0.1;
    QCOMPARE(VerticalOverlapMatcher().match(valid, valid, config).kind, OverlapKind::Insufficient);
    config = {};
    config.minimumWinnerMargin = -0.1;
    QCOMPARE(VerticalOverlapMatcher().match(valid, valid, config).kind, OverlapKind::Insufficient);
    config = {};
    config.expectedAdvance = -1;
    QCOMPARE(VerticalOverlapMatcher().match(valid, valid, config).kind, OverlapKind::Insufficient);
    config = {};
    config.expectedAdvanceTolerance = -1;
    QCOMPARE(VerticalOverlapMatcher().match(valid, valid, config).kind, OverlapKind::Insufficient);
    config = {};
    config.excludedBands.left = -1;
    QCOMPARE(VerticalOverlapMatcher().match(valid, valid, config).kind, OverlapKind::Insufficient);
}

void TestVerticalOverlapMatcher::matchesOnePixelWideScoringRegion()
{
    const ScrollFrame document = stripedDocument(8, 240);
    const ScrollFrame previous = crop(document, 0, 0, 8, 100);
    const ScrollFrame current = crop(document, 0, 50, 8, 100);
    OverlapConfig config;
    config.excludedBands.left = 3;
    config.excludedBands.right = 4;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, 50);
}

void TestVerticalOverlapMatcher::recallsNonZeroErrorPeakBeyondFixedCandidateLimit()
{
    const ScrollFrame document = stripedDocument(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    ScrollFrame current = crop(document, 0, 72, 120, 180);
    corruptQuarterGrid(current);

    const auto result = VerticalOverlapMatcher().match(previous, current, {});

    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, 72);
    QVERIFY(result.normalizedError > 0.02);
    QVERIFY(result.normalizedError < 0.08);
}

void TestVerticalOverlapMatcher::detectsShortPeriodIndependentPeaks()
{
    OverlapConfig config;
    config.maximumAdvanceRatio = 0.02;
    for (const int period : {2, 3}) {
        const ScrollFrame repeated = repeatedRows(120, 180, period);

        const auto result = VerticalOverlapMatcher().match(repeated, repeated, config);

        QCOMPARE(result.kind, OverlapKind::Ambiguous);
    }
}

void TestVerticalOverlapMatcher::avoidsQuadraticFullResolutionFallback()
{
    constexpr int width = 1920;
    constexpr int height = 1080;
    constexpr int advance = 432;
    constexpr int coarseColumnStep = 30;
    const ScrollFrame previous = aliasedSamplingFrame(width, height, 0, coarseColumnStep);
    const ScrollFrame current = aliasedSamplingFrame(width, height, advance, coarseColumnStep);
    OverlapConfig config;
    config.maximumAdvanceRatio = 0.5;
    QElapsedTimer timer;
    timer.start();

    const auto result = VerticalOverlapMatcher().match(previous, current, config);
    const auto elapsed = timer.elapsed();

    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, advance);
    QVERIFY2(elapsed < 400, qPrintable(QStringLiteral("elapsed %1 ms").arg(elapsed)));
}

void TestVerticalOverlapMatcher::ignoresAdvancesWithEmptyMaskedIntersection()
{
    const ScrollFrame document = stripedDocument(120, 220);
    const ScrollFrame previous = crop(document, 0, 0, 120, 100);
    const ScrollFrame current = crop(document, 0, 2, 120, 100);
    OverlapConfig config;
    config.maximumAdvanceRatio = 0.5;
    config.excludedBands.top = 45;
    config.excludedBands.bottom = 45;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, 2);
    QVERIFY(std::isfinite(result.normalizedError));
}

void TestVerticalOverlapMatcher::detectsIndependentPeaksHiddenByFlatSignature()
{
    const ScrollFrame previous = cancellingPatternFrame(128, 180, 20);
    const ScrollFrame current = cancellingPatternFrame(128, 180, 10);
    OverlapConfig config;
    config.maximumAdvanceRatio = 0.025;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Ambiguous);
    QCOMPARE(result.normalizedError, 10.0 / 255.0);
}

void TestVerticalOverlapMatcher::avoidsFlatSignatureFullResolutionDegeneration()
{
    const ScrollFrame previous = cancellingPatternFrame(1920, 1080, 20);
    const ScrollFrame current = cancellingPatternFrame(1920, 1080, 10);
    OverlapConfig config;
    config.maximumAdvanceRatio = 0.5;
    QElapsedTimer timer;
    timer.start();

    const auto result = VerticalOverlapMatcher().match(previous, current, config);
    const auto elapsed = timer.elapsed();

    QCOMPARE(result.kind, OverlapKind::Ambiguous);
    QVERIFY2(elapsed < 400, qPrintable(QStringLiteral("elapsed %1 ms").arg(elapsed)));
}

void TestVerticalOverlapMatcher::returnsConservativeResultWhenEvaluationBudgetIsExhausted()
{
    constexpr int advance = 432;
    const ScrollFrame previous = commonNullspaceFrame(1080, 0);
    const ScrollFrame current = commonNullspaceFrame(1080, advance);
    OverlapConfig config;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Ambiguous);
    QCOMPARE(result.confidence, 0.0);
}

void TestVerticalOverlapMatcher::sufficientBudgetResolvesSmallCommonNullspaceInput()
{
    const ScrollFrame previous = commonNullspaceFrame(20, 0);
    const ScrollFrame current = commonNullspaceFrame(20, 4);
    OverlapConfig config;
    config.maximumAdvanceRatio = 0.4;
    config.maximumFullResolutionCandidates = 32;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, 4);
    QVERIFY(result.normalizedError < config.maximumNormalizedError);
}

void TestVerticalOverlapMatcher::validatesFullResolutionCandidateBudget()
{
    const ScrollFrame frame = stripedDocument(12, 20);
    OverlapConfig config;
    QCOMPARE(config.maximumFullResolutionCandidates, 32);
    config.maximumFullResolutionCandidates = 0;
    QCOMPARE(VerticalOverlapMatcher().match(frame, frame, config).kind, OverlapKind::Insufficient);
    config.maximumFullResolutionCandidates = 1'000'001;
    QCOMPARE(VerticalOverlapMatcher().match(frame, frame, config).kind, OverlapKind::Insufficient);
    config.maximumFullResolutionCandidates = 1'000'000;
    QVERIFY(VerticalOverlapMatcher().match(frame, frame, config).kind != OverlapKind::Insufficient);
}

void TestVerticalOverlapMatcher::budgetExhaustionTakesPriorityOverProvisionalError()
{
    const ScrollFrame previous = commonNullspaceFrame(100, 0);
    const ScrollFrame current = commonNullspaceFrame(100, 20);
    OverlapConfig config;
    config.maximumAdvanceRatio = 0.5;
    config.maximumNormalizedError = 0.0001;
    config.maximumFullResolutionCandidates = 1;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Ambiguous);
    QCOMPARE(result.confidence, 0.0);
}

QTEST_MAIN(TestVerticalOverlapMatcher)
#include "TestVerticalOverlapMatcher.moc"
