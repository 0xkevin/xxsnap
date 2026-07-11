#include "snipory/core/scroll/FrameFingerprint.h"

#include <QTest>

#include <algorithm>
#include <cstdint>
#include <limits>

namespace {

using snipory::core::scroll::Fingerprint;
using snipory::core::scroll::FingerprintSize;
using snipory::core::scroll::FrameFingerprint;
using snipory::core::scroll::ScrollFrame;

ScrollFrame solidFrame(int width, int height, std::uint8_t value)
{
    ScrollFrame frame(width, height);
    std::fill(frame.pixels.begin(), frame.pixels.end(), value);
    return frame;
}

void setBgra(
    ScrollFrame& frame,
    int x,
    int y,
    std::uint8_t blue,
    std::uint8_t green,
    std::uint8_t red,
    std::uint8_t alpha = 255)
{
    const auto offset = static_cast<std::size_t>(y * frame.bytesPerRow + x * 4);
    frame.pixels[offset] = blue;
    frame.pixels[offset + 1] = green;
    frame.pixels[offset + 2] = red;
    frame.pixels[offset + 3] = alpha;
}

} // namespace

class TestFrameFingerprint final : public QObject
{
    Q_OBJECT

private slots:
    void identicalFramesHaveZeroDistance();
    void onePixelPerturbationHasNonZeroDistance();
    void differentFramesExceedDuplicateThreshold();
    void invalidAndMismatchedFingerprintsCannotBeCompared();
    void frameValidationRejectsOverflowedBufferSize();
    void constructorRejectsUnrepresentableRowSize();
    void tallFingerprintDoesNotOverflowSourceBounds();
    void wideFingerprintDoesNotOverflowSourceBounds();
    void luminanceAndSpatialBinsHaveExactValues();
    void distanceUsesFullByteRange();
};

void TestFrameFingerprint::identicalFramesHaveZeroDistance()
{
    const auto frame = solidFrame(64, 48, 40);
    const auto left = FrameFingerprint::make(frame, FingerprintSize{16, 12});
    const auto right = FrameFingerprint::make(frame, FingerprintSize{16, 12});
    const auto distance = FrameFingerprint::meanAbsoluteDistance(left, right);

    QVERIFY(distance.has_value());
    QCOMPARE(*distance, 0.0);
}

void TestFrameFingerprint::onePixelPerturbationHasNonZeroDistance()
{
    auto changedFrame = solidFrame(64, 48, 0);
    const auto pixelOffset = static_cast<std::size_t>(10 * changedFrame.bytesPerRow + 10 * 4);
    changedFrame.pixels[pixelOffset] = 255;
    changedFrame.pixels[pixelOffset + 1] = 255;
    changedFrame.pixels[pixelOffset + 2] = 255;

    const auto original = FrameFingerprint::make(solidFrame(64, 48, 0), FingerprintSize{16, 12});
    const auto changed = FrameFingerprint::make(changedFrame, FingerprintSize{16, 12});
    const auto distance = FrameFingerprint::meanAbsoluteDistance(original, changed);

    QVERIFY(distance.has_value());
    QVERIFY(*distance > 0.0);
}

void TestFrameFingerprint::differentFramesExceedDuplicateThreshold()
{
    const auto dark = FrameFingerprint::make(solidFrame(64, 48, 20), FingerprintSize{16, 12});
    const auto light = FrameFingerprint::make(solidFrame(64, 48, 220), FingerprintSize{16, 12});
    const auto distance = FrameFingerprint::meanAbsoluteDistance(dark, light);

    QVERIFY(distance.has_value());
    QVERIFY(*distance > 0.5);
}

void TestFrameFingerprint::invalidAndMismatchedFingerprintsCannotBeCompared()
{
    const Fingerprint empty{FingerprintSize{1, 1}, {}};
    const Fingerprint oneByOne{FingerprintSize{1, 1}, {0}};
    const Fingerprint twoByOne{FingerprintSize{2, 1}, {0, 0}};

    QVERIFY(!FrameFingerprint::meanAbsoluteDistance(empty, oneByOne).has_value());
    QVERIFY(!FrameFingerprint::meanAbsoluteDistance(oneByOne, twoByOne).has_value());
}

void TestFrameFingerprint::frameValidationRejectsOverflowedBufferSize()
{
    ScrollFrame frame;
    frame.width = 1;
    frame.height = std::numeric_limits<int>::max();
    frame.bytesPerRow = std::numeric_limits<int>::max();
    frame.pixels.resize(1);

    QVERIFY(!frame.isValid());
}

void TestFrameFingerprint::constructorRejectsUnrepresentableRowSize()
{
    const ScrollFrame frame(std::numeric_limits<int>::max(), 1);

    QVERIFY(!frame.isValid());
    QCOMPARE(frame.bytesPerRow, 0);
    QVERIFY(frame.pixels.empty());
}

void TestFrameFingerprint::tallFingerprintDoesNotOverflowSourceBounds()
{
    const auto fingerprint = FrameFingerprint::make(
        solidFrame(1, 50'000, 40),
        FingerprintSize{1, 50'000});

    QCOMPARE(fingerprint.luminance.size(), std::size_t{50'000});
    QVERIFY(std::all_of(fingerprint.luminance.cbegin(), fingerprint.luminance.cend(), [](auto value) {
        return value == 40;
    }));
}

void TestFrameFingerprint::wideFingerprintDoesNotOverflowSourceBounds()
{
    const auto fingerprint = FrameFingerprint::make(
        solidFrame(50'000, 1, 40),
        FingerprintSize{50'000, 1});

    QCOMPARE(fingerprint.luminance.size(), std::size_t{50'000});
    QVERIFY(std::all_of(fingerprint.luminance.cbegin(), fingerprint.luminance.cend(), [](auto value) {
        return value == 40;
    }));
}

void TestFrameFingerprint::luminanceAndSpatialBinsHaveExactValues()
{
    ScrollFrame frame(4, 2);
    setBgra(frame, 0, 0, 255, 0, 0);
    setBgra(frame, 1, 0, 0, 255, 0);
    setBgra(frame, 2, 0, 0, 0, 255);
    setBgra(frame, 3, 0, 255, 255, 255);
    setBgra(frame, 0, 1, 0, 0, 0);
    setBgra(frame, 1, 1, 0, 0, 255);
    setBgra(frame, 2, 1, 0, 255, 0);
    setBgra(frame, 3, 1, 255, 0, 0);

    const auto oneBin = FrameFingerprint::make(frame, FingerprintSize{1, 1});
    const auto twoBins = FrameFingerprint::make(frame, FingerprintSize{2, 1});

    QCOMPARE(oneBin.luminance, std::vector<std::uint8_t>({96}));
    QCOMPARE(twoBins.luminance, std::vector<std::uint8_t>({64, 128}));
}

void TestFrameFingerprint::distanceUsesFullByteRange()
{
    const Fingerprint zero{FingerprintSize{1, 1}, {0}};
    const Fingerprint one{FingerprintSize{1, 1}, {1}};
    const Fingerprint maximum{FingerprintSize{1, 1}, {255}};

    QCOMPARE(*FrameFingerprint::meanAbsoluteDistance(zero, one), 1.0 / 255.0);
    QCOMPARE(*FrameFingerprint::meanAbsoluteDistance(zero, maximum), 1.0);
}

QTEST_MAIN(TestFrameFingerprint)
#include "TestFrameFingerprint.moc"
