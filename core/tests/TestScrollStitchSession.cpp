#include "snipory/core/scroll/ScrollStitchSession.h"

#include <QTest>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace {

using snipory::core::scroll::AppendKind;
using snipory::core::scroll::ScrollFrame;
using snipory::core::scroll::ScrollStitchConfig;
using snipory::core::scroll::ScrollStitchSession;

void setPixel(ScrollFrame& frame, int x, int y, std::uint8_t value)
{
    const auto offset = static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    frame.pixels[offset] = value;
    frame.pixels[offset + 1U] = static_cast<std::uint8_t>(value ^ 0x35U);
    frame.pixels[offset + 2U] = static_cast<std::uint8_t>(value ^ 0xa7U);
    frame.pixels[offset + 3U] = 255;
}

std::uint8_t documentPixel(int x, int documentY)
{
    auto bits = static_cast<std::uint32_t>(documentY) * 0x9e3779b9U
        ^ static_cast<std::uint32_t>(x) * 0x85ebca6bU;
    bits ^= bits >> 16U;
    bits *= 0x7feb352dU;
    bits ^= bits >> 15U;
    return static_cast<std::uint8_t>(bits & 0xffU);
}

ScrollFrame documentViewport(int documentY, bool fixedBands = false, bool scrollbar = false)
{
    ScrollFrame frame(120, 140);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            auto value = documentPixel(x, documentY + y);
            if (fixedBands && y < 12) {
                value = static_cast<std::uint8_t>(31 + x % 17);
            } else if (fixedBands && y >= frame.height - 8) {
                value = static_cast<std::uint8_t>(61 + x % 11);
            }
            if (scrollbar && x >= frame.width - 4) {
                value = 220;
                const int thumbTop = 12 + documentY / 3;
                if (y >= thumbTop && y < thumbTop + 22) {
                    value = 45;
                }
            }
            setPixel(frame, x, y, value);
        }
    }
    return frame;
}

ScrollFrame viewportWithSparseAnimatedEdge(int documentY)
{
    auto frame = documentViewport(documentY);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = frame.width - 4; x < frame.width; ++x) {
            setPixel(frame, x, y, 220);
        }
    }
    for (int i = 0; i < 8; ++i) {
        const int y = (i * 17 + documentY / 30) % frame.height;
        for (int x = frame.width - 4; x < frame.width; ++x) {
            setPixel(frame, x, y, 240);
        }
    }
    return frame;
}

std::vector<ScrollFrame> makeDocumentViewports(std::initializer_list<int> offsets)
{
    std::vector<ScrollFrame> frames;
    for (const int offset : offsets) {
        frames.push_back(documentViewport(offset));
    }
    return frames;
}

ScrollStitchConfig defaultConfig()
{
    ScrollStitchConfig config;
    config.matcher.minimumOverlapRatio = 0.10;
    config.matcher.maximumAdvanceRatio = 0.90;
    config.matcher.maximumNormalizedError = 0.01;
    config.matcher.minimumWinnerMargin = 0.005;
    config.matcher.maximumFullResolutionCandidates = 24;
    config.duplicateThreshold = 0.0;
    config.maximumAcceptedBytes = 64U * 1024U * 1024U;
    return config;
}

std::uint8_t blueAt(const ScrollFrame& frame, int x, int y)
{
    return frame.pixels[static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U];
}

class TestScrollStitchSession final : public QObject
{
    Q_OBJECT

private slots:
    void acceptsInitialAndAppendsOnlyNewBottomStrip();
    void exactDuplicateDoesNotMutateOutput();
    void reverseReviewDoesNotMutateAcceptedContent();
    void lowConfidenceDoesNotMutateOutput();
    void fixedHeaderAndFooterAreRetainedOnce();
    void confirmedScrollbarIsCroppedButAmbiguousEdgeIsPreserved();
    void sparseAnimatedEdgeIsNotMistakenForScrollbarThumb();
    void resourceLimitLeavesFinalImageSaveable();
    void previewDownsamplesWithoutMutatingFinalImage();
    void rejectsInvalidAndDimensionMismatchedFrames();
    void invalidConfigurationNeverAcceptsContent();
};

void TestScrollStitchSession::acceptsInitialAndAppendsOnlyNewBottomStrip()
{
    ScrollStitchSession session(defaultConfig());
    const auto frames = makeDocumentViewports({0, 60});

    QCOMPARE(session.append(frames[0]).kind, AppendKind::AcceptedInitial);
    const auto result = session.append(frames[1]);
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 60);
    QCOMPARE(result.outputHeight, 200);
    QCOMPARE(session.outputHeight(), 200);

    const auto final = session.finalize();
    QCOMPARE(final.width, 120);
    QCOMPARE(final.height, 200);
    QCOMPARE(blueAt(final, 37, 139), documentPixel(37, 139));
    QCOMPARE(blueAt(final, 37, 140), documentPixel(37, 140));
    QCOMPARE(blueAt(final, 37, 199), documentPixel(37, 199));
}

void TestScrollStitchSession::exactDuplicateDoesNotMutateOutput()
{
    ScrollStitchSession session(defaultConfig());
    const auto frame = documentViewport(0);
    QCOMPARE(session.append(frame).kind, AppendKind::AcceptedInitial);
    const auto before = session.finalize();

    const auto result = session.append(frame);
    QCOMPARE(result.kind, AppendKind::DuplicateDiscarded);
    QCOMPARE(result.appendedHeight, 0);
    QCOMPARE(session.finalize().pixels, before.pixels);
}

void TestScrollStitchSession::reverseReviewDoesNotMutateAcceptedContent()
{
    ScrollStitchSession session(defaultConfig());
    const auto frames = makeDocumentViewports({0, 60, 120, 60, 120, 180});
    QCOMPARE(session.append(frames[0]).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(frames[1]).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.append(frames[2]).kind, AppendKind::AcceptedAppend);
    const int h = session.outputHeight();
    const auto pixels = session.finalize().pixels;
    QCOMPARE(session.append(frames[3]).kind, AppendKind::ReviewDiscarded);
    QCOMPARE(session.append(frames[4]).kind, AppendKind::DuplicateDiscarded);
    QCOMPARE(session.outputHeight(), h);
    QCOMPARE(session.finalize().pixels, pixels);
    QCOMPARE(session.append(frames[5]).kind, AppendKind::AcceptedAppend);
}

void TestScrollStitchSession::lowConfidenceDoesNotMutateOutput()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::AcceptedInitial);
    ScrollFrame unrelated(120, 140);
    std::fill(unrelated.pixels.begin(), unrelated.pixels.end(), 127);
    const auto before = session.finalize();

    const auto result = session.append(unrelated);
    QCOMPARE(result.kind, AppendKind::PausedLowConfidence);
    QCOMPARE(session.outputHeight(), 140);
    QCOMPARE(session.finalize().pixels, before.pixels);
}

void TestScrollStitchSession::fixedHeaderAndFooterAreRetainedOnce()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    config.fixedBandConfirmationMovements = 3;
    ScrollStitchSession session(config);

    bool first = true;
    for (const int offset : {0, 40, 80, 120, 160}) {
        const auto result = session.append(documentViewport(offset, true));
        QCOMPARE(result.kind, first ? AppendKind::AcceptedInitial : AppendKind::AcceptedAppend);
        first = false;
    }

    const auto final = session.finalize();
    QCOMPARE(final.height, 300);
    QCOMPARE(blueAt(final, 20, 2), static_cast<std::uint8_t>(31 + 20 % 17));
    // The first frame's fixed footer occupies rows 132..139 once. New document
    // pixels continue below it without accepting a later footer copy.
    QCOMPARE(blueAt(final, 20, 150), documentPixel(20, 142));
}

void TestScrollStitchSession::confirmedScrollbarIsCroppedButAmbiguousEdgeIsPreserved()
{
    auto config = defaultConfig();
    config.scrollbarMaximumWidth = 6;
    config.scrollbarConfirmationMovements = 3;
    config.scrollbarPersistenceThreshold = 0.70;
    config.scrollbarMotionThreshold = 0.01;
    ScrollStitchSession confirmed(config);
    ScrollStitchSession ambiguous(config);
    for (const int offset : {0, 30, 60, 90, 120}) {
        const auto confirmedResult = confirmed.append(documentViewport(offset, false, true));
        const auto ambiguousResult = ambiguous.append(documentViewport(offset));
        QVERIFY(confirmedResult.kind == AppendKind::AcceptedInitial
            || confirmedResult.kind == AppendKind::AcceptedAppend);
        QVERIFY(ambiguousResult.kind == AppendKind::AcceptedInitial
            || ambiguousResult.kind == AppendKind::AcceptedAppend);
    }

    QCOMPARE(confirmed.finalize().width, 116);
    QCOMPARE(ambiguous.finalize().width, 120);
}

void TestScrollStitchSession::sparseAnimatedEdgeIsNotMistakenForScrollbarThumb()
{
    auto config = defaultConfig();
    config.scrollbarMaximumWidth = 6;
    config.scrollbarConfirmationMovements = 3;
    config.scrollbarPersistenceThreshold = 0.70;
    config.scrollbarMotionThreshold = 0.01;
    ScrollStitchSession session(config);
    for (const int offset : {0, 30, 60, 90, 120}) {
        const auto result = session.append(viewportWithSparseAnimatedEdge(offset));
        QVERIFY(result.kind == AppendKind::AcceptedInitial || result.kind == AppendKind::AcceptedAppend);
    }

    QCOMPARE(session.finalize().width, 120);
}

void TestScrollStitchSession::resourceLimitLeavesFinalImageSaveable()
{
    auto config = defaultConfig();
    config.maximumAcceptedBytes = 120U * 260U * 4U;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(documentViewport(120)).kind, AppendKind::ResourceLimit);
    QCOMPARE(session.outputHeight(), 140);
    const auto final = session.finalize();
    QVERIFY(final.isValid());
    QCOMPARE(final.height, 140);
}

void TestScrollStitchSession::previewDownsamplesWithoutMutatingFinalImage()
{
    ScrollStitchSession session(defaultConfig());
    for (const int offset : {0, 60, 120}) {
        const auto result = session.append(documentViewport(offset));
        QVERIFY(result.kind == AppendKind::AcceptedInitial || result.kind == AppendKind::AcceptedAppend);
    }
    const auto preview = session.preview(100);
    QVERIFY(preview.isValid());
    QCOMPARE(preview.height, 100);
    QCOMPARE(preview.width, 46);
    QCOMPARE(session.finalize().height, 260);
}

void TestScrollStitchSession::rejectsInvalidAndDimensionMismatchedFrames()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append({}).kind, AppendKind::PausedLowConfidence);
    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(ScrollFrame(121, 140)).kind, AppendKind::PausedLowConfidence);
    QCOMPARE(session.outputHeight(), 140);
}

void TestScrollStitchSession::invalidConfigurationNeverAcceptsContent()
{
    auto config = defaultConfig();
    config.matcher.maximumFullResolutionCandidates = 0;
    ScrollStitchSession session(config);

    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::PausedLowConfidence);
    QCOMPARE(session.outputHeight(), 0);
    QVERIFY(!session.finalize().isValid());
}

} // namespace

QTEST_MAIN(TestScrollStitchSession)
#include "TestScrollStitchSession.moc"
