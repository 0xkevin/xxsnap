#include "snipory/core/scroll/VerticalOverlapMatcher.h"

#include <QTest>

#include <algorithm>
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

QTEST_MAIN(TestVerticalOverlapMatcher)
#include "TestVerticalOverlapMatcher.moc"
