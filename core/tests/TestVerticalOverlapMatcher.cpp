#include "snipory/core/scroll/VerticalOverlapMatcher.h"

#include <QTest>

#include <algorithm>
#include <array>
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
    void respectsMaximumNormalizedError();
    void respectsMinimumWinnerMargin();
    void rejectsInvalidInputsAndConfig();
    void matchesOnePixelWideScoringRegion();
};

void TestVerticalOverlapMatcher::findsDownwardOffset()
{
    const ScrollFrame document = stripedDocument(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    const ScrollFrame current = crop(document, 0, 72, 120, 180);

    const auto result = VerticalOverlapMatcher().match(previous, current, {});

    QCOMPARE(result.kind, OverlapKind::Reliable);
    QCOMPARE(result.verticalAdvance, 72);
    QCOMPARE(result.overlapHeight, 108);
    QVERIFY(result.confidence >= 0.8);
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

    const auto result = VerticalOverlapMatcher().match(previous, current, {});

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
    const ScrollFrame document = verticalGradient(120, 480);
    const ScrollFrame previous = crop(document, 0, 0, 120, 180);
    const ScrollFrame current = crop(document, 0, 72, 120, 180);
    OverlapConfig config;
    config.minimumWinnerMargin = 0.02;

    const auto result = VerticalOverlapMatcher().match(previous, current, config);

    QCOMPARE(result.kind, OverlapKind::Ambiguous);
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

QTEST_MAIN(TestVerticalOverlapMatcher)
#include "TestVerticalOverlapMatcher.moc"
