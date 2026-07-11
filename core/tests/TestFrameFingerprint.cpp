#include "snipory/core/scroll/FrameFingerprint.h"

#include <QTest>

#include <algorithm>
#include <cstdint>

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

} // namespace

class TestFrameFingerprint final : public QObject
{
    Q_OBJECT

private slots:
    void identicalFramesHaveZeroDistance();
    void onePixelPerturbationHasNonZeroDistance();
    void differentFramesExceedDuplicateThreshold();
    void invalidAndMismatchedFingerprintsCannotBeCompared();
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

QTEST_MAIN(TestFrameFingerprint)
#include "TestFrameFingerprint.moc"
