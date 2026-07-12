#include "snipory/core/scroll/ScrollStitchSession.h"

#include <QTest>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace {

using snipory::core::scroll::AppendKind;
using snipory::core::scroll::OverlapKind;
using snipory::core::scroll::ScrollFrame;
using snipory::core::scroll::ScrollStitchConfig;
using snipory::core::scroll::ScrollStitchSession;
using snipory::core::scroll::VerticalOverlapMatcher;

void setPixel(ScrollFrame& frame, int x, int y, std::uint8_t value)
{
    const auto offset = static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    frame.pixels[offset] = value;
    frame.pixels[offset + 1U] = static_cast<std::uint8_t>(value ^ 0x35U);
    frame.pixels[offset + 2U] = static_cast<std::uint8_t>(value ^ 0xa7U);
    frame.pixels[offset + 3U] = 255;
}

void setBgra(
    ScrollFrame& frame,
    int x,
    int y,
    std::uint8_t blue,
    std::uint8_t green,
    std::uint8_t red)
{
    const auto offset = static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U;
    frame.pixels[offset] = blue;
    frame.pixels[offset + 1U] = green;
    frame.pixels[offset + 2U] = red;
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

ScrollFrame viewportWithChangingFixedEdgeBlock(int documentY, std::uint8_t blockValue)
{
    auto frame = documentViewport(documentY);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = frame.width - 4; x < frame.width; ++x) {
            setPixel(frame, x, y, 220);
        }
    }
    for (int y = 35; y < 60; ++y) {
        for (int x = frame.width - 4; x < frame.width; ++x) {
            setPixel(frame, x, y, blockValue);
        }
    }
    return frame;
}

ScrollFrame viewportWithThumbPosition(int documentY, int thumbTop)
{
    auto frame = documentViewport(documentY);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = frame.width - 4; x < frame.width; ++x) {
            setPixel(frame, x, y, y >= thumbTop && y < thumbTop + 22 ? 45 : 220);
        }
    }
    return frame;
}

ScrollFrame viewportWithScrollbarSides(int documentY, bool left, bool right)
{
    auto frame = documentViewport(documentY);
    const int thumbTop = 12 + documentY / 3;
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            if ((left && x < 4) || (right && x >= frame.width - 4)) {
                setPixel(frame, x, y, y >= thumbTop && y < thumbTop + 22 ? 45 : 220);
            }
        }
    }
    return frame;
}

ScrollFrame tallViewportWithFixedHeader(int documentY)
{
    ScrollFrame frame(120, 240);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            const auto value = y < 60
                ? static_cast<std::uint8_t>(31 + x % 17)
                : documentPixel(x, documentY + y);
            setPixel(frame, x, y, value);
        }
    }
    return frame;
}

std::uint8_t whiteGapDocumentPixel(int x, int documentY)
{
    return documentY >= 120 && documentY < 180 ? 250 : documentPixel(x, documentY);
}

ScrollFrame viewportAcrossWhiteDocumentGap(int documentY)
{
    ScrollFrame frame(120, 140);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            setPixel(frame, x, y, whiteGapDocumentPixel(x, documentY + y));
        }
    }
    return frame;
}

ScrollFrame viewportWithLowInformationBottomGradient(int documentY)
{
    auto frame = documentViewport(documentY);
    for (int y = frame.height - 20; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            setPixel(frame, x, y, static_cast<std::uint8_t>(80 + y - (frame.height - 20)));
        }
    }
    return frame;
}

ScrollFrame tallViewportWithHeaderVariant(int documentY, int variant)
{
    ScrollFrame frame(120, 240);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            auto value = documentPixel(x, documentY + y);
            if (y < 60 && (variant != 2 || y < 30)) {
                value = y == 0
                    ? static_cast<std::uint8_t>(31 + x % 17)
                    : static_cast<std::uint8_t>(31 + x % 17 + (variant != 0 && y == 1 ? 40 : 0));
            }
            setPixel(frame, x, y, value);
        }
    }
    return frame;
}

ScrollFrame viewportWithConstantBlueTexturedFixedBands(int documentY)
{
    auto frame = documentViewport(documentY);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            if (y < 12 || y >= frame.height - 8) {
                setBgra(frame, x, y, 80,
                    static_cast<std::uint8_t>((x & 1) == 0 ? 25 : 220),
                    static_cast<std::uint8_t>(40 + x % 23));
            }
        }
    }
    return frame;
}

ScrollFrame viewportWithConstantBlueScrollingChroma(int documentY)
{
    ScrollFrame frame(120, 140);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            const int documentRow = documentY + y;
            setBgra(frame, x, y, 80,
                static_cast<std::uint8_t>((documentRow * 17 + x * 5) & 0xff),
                static_cast<std::uint8_t>((documentRow * 29 + x * 11) & 0xff));
        }
    }
    return frame;
}

ScrollFrame viewportWithIndependentFixedBands(int documentY, bool fixedTop, bool fixedBottom)
{
    auto frame = documentViewport(documentY);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            if (fixedTop && y < 12) {
                setPixel(frame, x, y, static_cast<std::uint8_t>(31 + x % 17));
            } else if (fixedBottom && y >= frame.height - 8) {
                setPixel(frame, x, y, static_cast<std::uint8_t>(61 + x % 11));
            }
        }
    }
    return frame;
}

void copyBottomBand(const ScrollFrame& source, ScrollFrame& destination, int rows = 8)
{
    for (int y = destination.height - rows; y < destination.height; ++y) {
        for (int x = 0; x < destination.width; ++x) {
            const auto sourceOffset = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(source.bytesPerRow)
                + static_cast<std::size_t>(x) * 4U;
            const auto destinationOffset = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(destination.bytesPerRow)
                + static_cast<std::size_t>(x) * 4U;
            std::copy_n(source.pixels.cbegin() + static_cast<std::ptrdiff_t>(sourceOffset), 4,
                destination.pixels.begin() + static_cast<std::ptrdiff_t>(destinationOffset));
        }
    }
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
    void unrelatedFrameIsDiscardedAsLowConfidence();
    void fixedHeaderAndFooterAreRetainedOnce();
    void scrollingCandidateBandIsNeverConfirmedOrDropped();
    void fixedBandConfirmationIsAwaitingEvidence();
    void reliableOrdinaryMatchStillDefersStationaryFixedBands();
    void fixedTopConfirmsWhenBottomCandidateScrolls();
    void fixedBottomConfirmsWhenTopCandidateScrolls();
    void topConfirmationDoesNotRetroactivelyCropLaterBottomEvidence();
    void interruptedLateBottomEvidenceReprocessesWithoutGaps();
    void lateBottomConfirmationCropsOnlyItsEvidenceRun();
    void topOnlyConfirmationAllowsLargeAdvanceWithScrollingBottom();
    void bottomOnlyConfirmationAllowsLargeAdvanceWithScrollingTop();
    void topBreakDoesNotPreventBottomConfirmation();
    void bottomBreakDoesNotPreventTopConfirmation();
    void evidenceBreakFlushesPerMovementBeyondOldTailAdvanceBudget();
    void nonAnchorReverseReviewPreservesPendingEvidence();
    void nonAnchorReverseReviewInsideAcceptedContentDoesNotMutate();
    void deepPendingReverseReviewSearchesRecentFrames();
    void unknownLowConfidenceFramePreservesPendingProgress();
    void discardedFramesDoNotAdvanceFixedBandConfirmation();
    void unknownFramePreservesFixedEvidence();
    void pendingFixedFramesCountTowardResourceLimit();
    void confirmedScrollbarIsCroppedButAmbiguousEdgeIsPreserved();
    void changingFixedPositionEdgeBlockIsNotCropped();
    void lowConfidenceThumbMotionDoesNotCrop();
    void sparseAnimatedEdgeIsNotMistakenForScrollbarThumb();
    void defaultScrollbarThresholdCropsRightMovingThumb();
    void leftMovingThumbCropsLeftAndPreservesSourcePixels();
    void simultaneousEdgeCandidatesArePreservedAsAmbiguous();
    void resourceLimitLeavesFinalImageSaveable();
    void currentTailPixelsCountTowardResourceLimit();
    void lightweightAnchorHistoryDoesNotConsumeViewportPerAcceptance();
    void previewDownsamplesWithoutMutatingFinalImage();
    void smallPreviewSamplesLongNearLimitCompositionDirectly();
    void automaticFixedBandDetectionWorksWithProductionDefaults();
    void automaticFixedBandDetectionFindsHeaderLargerThan32Pixels();
    void automaticFixedBandDetectionDoesNotDelayScrollingEdges();
    void automaticFixedBandDetectionRejectsWhiteDocumentGap();
    void automaticFixedBandDetectionRejectsLowInformationGradient();
    void inconsistentBandHeightsRestartEvidenceRun();
    void constantBlueTexturedFixedBandsStillConfirm();
    void constantBlueScrollingChromaDoesNotBecomeFixed();
    void maximumPendingRunSearchesAllFramesForReverseReview();
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

void TestScrollStitchSession::unrelatedFrameIsDiscardedAsLowConfidence()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::AcceptedInitial);
    ScrollFrame unrelated(120, 140);
    std::fill(unrelated.pixels.begin(), unrelated.pixels.end(), 127);
    const auto before = session.finalize();

    const auto result = session.append(unrelated);
    QCOMPARE(result.kind, AppendKind::LowConfidenceDiscarded);
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

    QCOMPARE(session.append(documentViewport(0, true)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(documentViewport(40, true)).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(documentViewport(80, true)).kind, AppendKind::AwaitingEvidence);
    const auto confirmation = session.append(documentViewport(120, true));
    QCOMPARE(confirmation.kind, AppendKind::AcceptedAppend);
    QCOMPARE(confirmation.appendedHeight, 120);
    QCOMPARE(session.append(documentViewport(160, true)).kind, AppendKind::AcceptedAppend);

    const auto final = session.finalize();
    QCOMPARE(final.height, 300);
    QCOMPARE(blueAt(final, 20, 2), static_cast<std::uint8_t>(31 + 20 % 17));
    // The first frame's fixed footer occupies rows 132..139 once. New document
    // pixels continue below it without accepting a later footer copy.
    QCOMPARE(blueAt(final, 20, 150), documentPixel(20, 142));
}

void TestScrollStitchSession::scrollingCandidateBandIsNeverConfirmedOrDropped()
{
    auto config = defaultConfig();
    config.fixedBottomCandidateHeight = 8;
    config.fixedBandConfirmationMovements = 3;
    config.fixedBandStationaryThreshold = 0.98;
    ScrollStitchSession session(config);
    for (const int offset : {0, 40, 80, 120, 160}) {
        const auto result = session.append(documentViewport(offset));
        QVERIFY(result.kind == AppendKind::AcceptedInitial || result.kind == AppendKind::AcceptedAppend);
    }

    const auto final = session.finalize();
    QCOMPARE(final.height, 300);
    for (int y : {139, 140, 179, 180, 259, 299}) {
        QCOMPARE(blueAt(final, 20, y), documentPixel(20, y));
    }
}

void TestScrollStitchSession::fixedBandConfirmationIsAwaitingEvidence()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    config.fixedBandConfirmationMovements = 3;
    ScrollStitchSession session(config);
    const auto initial = documentViewport(0, true);
    const auto movement1 = documentViewport(40, true);
    const auto movement2 = documentViewport(80, true);
    QCOMPARE(session.append(initial).kind, AppendKind::AcceptedInitial);
    const auto initialPixels = session.finalize().pixels;
    auto movementMatcherConfig = config.matcher;
    movementMatcherConfig.excludedBands.top = 12;
    movementMatcherConfig.excludedBands.bottom = 8;
    movementMatcherConfig.excludedBands.left = config.scrollbarMaximumWidth;
    movementMatcherConfig.excludedBands.right = config.scrollbarMaximumWidth;
    const auto expected1 = VerticalOverlapMatcher().match(initial, movement1, movementMatcherConfig);
    QCOMPARE(expected1.kind, OverlapKind::Reliable);
    QVERIFY(expected1.confidence > 0.0);
    const auto pending1 = session.append(movement1);
    QCOMPARE(pending1.kind, AppendKind::AwaitingEvidence);
    QCOMPARE(pending1.outputHeight, 140);
    QCOMPARE(pending1.confidence, expected1.confidence);
    QCOMPARE(session.outputHeight(), 140);
    QCOMPARE(session.finalize().height, 140);
    QCOMPARE(session.finalize().pixels, initialPixels);
    const auto expected2 = VerticalOverlapMatcher().match(movement1, movement2, movementMatcherConfig);
    QCOMPARE(expected2.kind, OverlapKind::Reliable);
    QVERIFY(expected2.confidence > 0.0);
    const auto pending2 = session.append(movement2);
    QCOMPARE(pending2.kind, AppendKind::AwaitingEvidence);
    QCOMPARE(pending2.outputHeight, 140);
    QCOMPARE(pending2.confidence, expected2.confidence);
    QCOMPARE(session.outputHeight(), 140);
    QCOMPARE(session.finalize().height, 140);
    QCOMPARE(session.finalize().pixels, initialPixels);

    const auto result = session.append(documentViewport(120, true));
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 120);
    QCOMPARE(result.outputHeight, 260);
    QCOMPARE(blueAt(session.finalize(), 20, 139), static_cast<std::uint8_t>(61 + 20 % 11));
    QCOMPARE(blueAt(session.finalize(), 20, 140), documentPixel(20, 132));
    QCOMPARE(blueAt(session.finalize(), 20, 259), documentPixel(20, 251));
}

void TestScrollStitchSession::reliableOrdinaryMatchStillDefersStationaryFixedBands()
{
    auto config = defaultConfig();
    config.matcher.maximumNormalizedError = 0.20;
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(documentViewport(0, true)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(documentViewport(40, true)).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(documentViewport(80, true)).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.outputHeight(), 140);
    const auto result = session.append(documentViewport(120, true));
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 120);
    QCOMPARE(session.outputHeight(), 260);
    QCOMPARE(blueAt(session.finalize(), 20, 140), documentPixel(20, 132));
    QCOMPARE(blueAt(session.finalize(), 20, 259), documentPixel(20, 251));
}

void TestScrollStitchSession::fixedTopConfirmsWhenBottomCandidateScrolls()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(0, true, false)).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(40, true, false)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(80, true, false)).kind,
        AppendKind::AwaitingEvidence);
    const auto result = session.append(viewportWithIndependentFixedBands(120, true, false));
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 120);
    const auto final = session.finalize();
    QCOMPARE(final.height, 260);
    QCOMPARE(blueAt(final, 20, 2), static_cast<std::uint8_t>(31 + 20 % 17));
    QCOMPARE(blueAt(final, 20, 139), documentPixel(20, 139));
    QCOMPARE(blueAt(final, 20, 140), documentPixel(20, 140));
    QCOMPARE(blueAt(final, 20, 259), documentPixel(20, 259));
}

void TestScrollStitchSession::fixedBottomConfirmsWhenTopCandidateScrolls()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(0, false, true)).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(40, false, true)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(80, false, true)).kind,
        AppendKind::AwaitingEvidence);
    const auto result = session.append(viewportWithIndependentFixedBands(120, false, true));
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 120);
    const auto final = session.finalize();
    QCOMPARE(final.height, 260);
    QCOMPARE(blueAt(final, 20, 131), documentPixel(20, 131));
    QCOMPARE(blueAt(final, 20, 139), static_cast<std::uint8_t>(61 + 20 % 11));
    QCOMPARE(blueAt(final, 20, 140), documentPixel(20, 132));
    QCOMPARE(blueAt(final, 20, 259), documentPixel(20, 251));
}

void TestScrollStitchSession::topConfirmationDoesNotRetroactivelyCropLaterBottomEvidence()
{
    auto config = defaultConfig();
    config.matcher.maximumNormalizedError = 0.20;
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    auto initial = viewportWithIndependentFixedBands(0, true, false);
    auto movement1 = viewportWithIndependentFixedBands(40, true, false);
    auto movement2 = viewportWithIndependentFixedBands(80, true, false);
    auto movement3 = viewportWithIndependentFixedBands(120, true, false);
    copyBottomBand(movement1, movement2);
    copyBottomBand(movement1, movement3);

    QCOMPARE(session.append(initial).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(movement1).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(movement2).kind, AppendKind::AwaitingEvidence);
    const auto result = session.append(movement3);
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 80);
    QCOMPARE(session.outputHeight(), 220);
    QCOMPARE(blueAt(session.finalize(), 20, 179), documentPixel(20, 179));
}

void TestScrollStitchSession::interruptedLateBottomEvidenceReprocessesWithoutGaps()
{
    auto config = defaultConfig();
    config.matcher.maximumNormalizedError = 0.20;
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    auto initial = viewportWithIndependentFixedBands(0, true, false);
    auto movement1 = viewportWithIndependentFixedBands(40, true, false);
    auto movement2 = viewportWithIndependentFixedBands(80, true, false);
    auto movement3 = viewportWithIndependentFixedBands(120, true, false);
    copyBottomBand(movement1, movement2);
    copyBottomBand(movement1, movement3);
    QCOMPARE(session.append(initial).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(movement1).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(movement2).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(movement3).kind, AppendKind::AcceptedAppend);

    const auto result = session.append(viewportWithIndependentFixedBands(160, true, false));
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 80);
    QCOMPARE(session.outputHeight(), 300);
    QCOMPARE(blueAt(session.finalize(), 20, 179), documentPixel(20, 179));
    QCOMPARE(blueAt(session.finalize(), 20, 180), documentPixel(20, 180));
    QCOMPARE(blueAt(session.finalize(), 20, 299), documentPixel(20, 299));
}

void TestScrollStitchSession::lateBottomConfirmationCropsOnlyItsEvidenceRun()
{
    auto config = defaultConfig();
    config.matcher.maximumNormalizedError = 0.20;
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    auto initial = viewportWithIndependentFixedBands(0, true, false);
    auto movement1 = viewportWithIndependentFixedBands(40, true, false);
    auto movement2 = viewportWithIndependentFixedBands(80, true, false);
    auto movement3 = viewportWithIndependentFixedBands(120, true, false);
    auto movement4 = viewportWithIndependentFixedBands(160, true, false);
    auto movement5 = viewportWithIndependentFixedBands(200, true, false);
    copyBottomBand(movement1, movement2);
    copyBottomBand(movement1, movement3);
    copyBottomBand(movement1, movement4);
    copyBottomBand(movement1, movement5);
    QCOMPARE(session.append(initial).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(movement1).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(movement2).kind, AppendKind::AwaitingEvidence);
    const auto topConfirmation = session.append(movement3);
    QCOMPARE(topConfirmation.appendedHeight, 80);

    QCOMPARE(session.append(movement4).kind, AppendKind::AwaitingEvidence);
    const auto result = session.append(movement5);
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 120);
    QCOMPARE(session.outputHeight(), 340);
    QCOMPARE(blueAt(session.finalize(), 20, 179), documentPixel(20, 179));
    QCOMPARE(blueAt(session.finalize(), 20, 180), documentPixel(20, 180));
    QCOMPARE(blueAt(session.finalize(), 20, 211), documentPixel(20, 211));
    QCOMPARE(blueAt(session.finalize(), 20, 220), documentPixel(20, 212));
    QCOMPARE(blueAt(session.finalize(), 20, 339), documentPixel(20, 331));
}

void TestScrollStitchSession::topOnlyConfirmationAllowsLargeAdvanceWithScrollingBottom()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    for (const int offset : {0, 40, 80, 120}) {
        const auto result = session.append(viewportWithIndependentFixedBands(offset, true, false));
        QVERIFY(result.kind == AppendKind::AcceptedInitial
            || result.kind == AppendKind::AwaitingEvidence
            || result.kind == AppendKind::AcceptedAppend);
    }
    const auto result = session.append(viewportWithIndependentFixedBands(245, true, false));
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 125);
}

void TestScrollStitchSession::bottomOnlyConfirmationAllowsLargeAdvanceWithScrollingTop()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    for (const int offset : {0, 40, 80, 120}) {
        const auto result = session.append(viewportWithIndependentFixedBands(offset, false, true));
        QVERIFY(result.kind == AppendKind::AcceptedInitial
            || result.kind == AppendKind::AwaitingEvidence
            || result.kind == AppendKind::AcceptedAppend);
    }
    const auto result = session.append(viewportWithIndependentFixedBands(245, false, true));
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 125);
}

void TestScrollStitchSession::topBreakDoesNotPreventBottomConfirmation()
{
    auto config = defaultConfig();
    config.matcher.maximumNormalizedError = 0.20;
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(0, true, true)).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(40, true, true)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(80, true, true)).kind,
        AppendKind::AwaitingEvidence);
    const auto confirmation = session.append(viewportWithIndependentFixedBands(120, false, true));
    QCOMPARE(confirmation.kind, AppendKind::AcceptedAppend);
    QCOMPARE(confirmation.appendedHeight, 120);
    QCOMPARE(session.outputHeight(), 260);
    QCOMPARE(blueAt(session.finalize(), 20, 140), documentPixel(20, 132));
    QCOMPARE(blueAt(session.finalize(), 20, 259), documentPixel(20, 251));
    QCOMPARE(session.append(viewportWithIndependentFixedBands(160, false, true)).kind,
        AppendKind::AcceptedAppend);
}

void TestScrollStitchSession::bottomBreakDoesNotPreventTopConfirmation()
{
    auto config = defaultConfig();
    config.matcher.maximumNormalizedError = 0.20;
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(0, true, true)).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(40, true, true)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(80, true, true)).kind,
        AppendKind::AwaitingEvidence);
    const auto confirmation = session.append(viewportWithIndependentFixedBands(120, true, false));
    QCOMPARE(confirmation.kind, AppendKind::AcceptedAppend);
    QCOMPARE(confirmation.appendedHeight, 120);
    QCOMPARE(session.outputHeight(), 260);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(160, true, false)).kind,
        AppendKind::AcceptedAppend);
}

void TestScrollStitchSession::evidenceBreakFlushesPerMovementBeyondOldTailAdvanceBudget()
{
    auto config = defaultConfig();
    config.matcher.maximumAdvanceRatio = 0.50;
    config.matcher.maximumNormalizedError = 0.20;
    config.fixedTopCandidateHeight = 12;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(0, true, false)).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(50, true, false)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(100, true, false)).kind,
        AppendKind::AwaitingEvidence);

    const auto flush = session.append(viewportWithIndependentFixedBands(150, false, false));
    QCOMPARE(flush.kind, AppendKind::AcceptedAppend);
    QCOMPARE(flush.appendedHeight, 150);
    QCOMPARE(session.outputHeight(), 290);
    QCOMPARE(blueAt(session.finalize(), 20, 140), documentPixel(20, 140));
    QCOMPARE(blueAt(session.finalize(), 20, 289), documentPixel(20, 289));

    const auto resumed = session.append(viewportWithIndependentFixedBands(200, false, false));
    QCOMPARE(resumed.kind, AppendKind::AcceptedAppend);
    QCOMPARE(resumed.appendedHeight, 50);
    QCOMPARE(session.outputHeight(), 340);
    QCOMPARE(blueAt(session.finalize(), 20, 339), documentPixel(20, 339));
}

void TestScrollStitchSession::nonAnchorReverseReviewPreservesPendingEvidence()
{
    auto config = defaultConfig();
    config.matcher.maximumNormalizedError = 0.20;
    config.fixedTopCandidateHeight = 12;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(0, true, false)).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(60, true, false)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(120, true, false)).kind,
        AppendKind::AwaitingEvidence);
    const auto acceptedPixels = session.finalize().pixels;

    QCOMPARE(session.append(viewportWithIndependentFixedBands(90, true, false)).kind,
        AppendKind::ReviewDiscarded);
    QCOMPARE(session.outputHeight(), 140);
    QCOMPARE(session.finalize().pixels, acceptedPixels);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(120, true, false)).kind,
        AppendKind::DuplicateDiscarded);

    const auto resumed = session.append(viewportWithIndependentFixedBands(180, true, false));
    QCOMPARE(resumed.kind, AppendKind::AcceptedAppend);
    QCOMPARE(resumed.appendedHeight, 180);
    QCOMPARE(session.outputHeight(), 320);
    QCOMPARE(blueAt(session.finalize(), 20, 319), documentPixel(20, 319));
}

void TestScrollStitchSession::nonAnchorReverseReviewInsideAcceptedContentDoesNotMutate()
{
    ScrollStitchSession session(defaultConfig());
    for (const int offset : {0, 60, 120}) {
        const auto result = session.append(documentViewport(offset));
        QVERIFY(result.kind == AppendKind::AcceptedInitial || result.kind == AppendKind::AcceptedAppend);
    }
    const auto before = session.finalize();
    QCOMPARE(session.append(documentViewport(90)).kind, AppendKind::ReviewDiscarded);
    QCOMPARE(session.outputHeight(), 260);
    QCOMPARE(session.finalize().pixels, before.pixels);
    QCOMPARE(session.append(documentViewport(180)).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.outputHeight(), 320);
}

void TestScrollStitchSession::deepPendingReverseReviewSearchesRecentFrames()
{
    auto config = defaultConfig();
    config.matcher.maximumAdvanceRatio = 0.50;
    config.matcher.maximumNormalizedError = 0.20;
    config.fixedTopCandidateHeight = 12;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(0, true, false)).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(50, true, false)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(100, true, false)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(10, true, false)).kind,
        AppendKind::ReviewDiscarded);
    QCOMPARE(session.outputHeight(), 140);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(100, true, false)).kind,
        AppendKind::DuplicateDiscarded);
    const auto resumed = session.append(viewportWithIndependentFixedBands(150, true, false));
    QCOMPARE(resumed.kind, AppendKind::AcceptedAppend);
    QCOMPARE(resumed.appendedHeight, 150);
    QCOMPARE(session.outputHeight(), 290);
}

void TestScrollStitchSession::unknownLowConfidenceFramePreservesPendingProgress()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(0, true, false)).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(50, true, false)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(100, true, false)).kind,
        AppendKind::AwaitingEvidence);
    ScrollFrame unknown(120, 140);
    std::fill(unknown.pixels.begin(), unknown.pixels.end(), 127);
    QCOMPARE(session.append(unknown).kind, AppendKind::LowConfidenceDiscarded);
    QCOMPARE(session.outputHeight(), 140);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(100, true, false)).kind,
        AppendKind::DuplicateDiscarded);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(150, true, false)).kind,
        AppendKind::AcceptedAppend);
    QCOMPARE(session.outputHeight(), 290);
}

void TestScrollStitchSession::discardedFramesDoNotAdvanceFixedBandConfirmation()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    config.fixedBandConfirmationMovements = 3;
    ScrollStitchSession session(config);
    const auto frames = std::vector<ScrollFrame>{
        documentViewport(0, true), documentViewport(40, true), documentViewport(80, true),
        documentViewport(40, true), documentViewport(80, true), documentViewport(120, true)};
    QCOMPARE(session.append(frames[0]).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(frames[1]).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(frames[2]).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(frames[3]).kind, AppendKind::ReviewDiscarded);
    QCOMPARE(session.append(frames[4]).kind, AppendKind::DuplicateDiscarded);
    QCOMPARE(session.outputHeight(), 140);
    const auto result = session.append(frames[5]);
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 120);
    QCOMPARE(blueAt(session.finalize(), 20, 259), documentPixel(20, 251));
}

void TestScrollStitchSession::unknownFramePreservesFixedEvidence()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(documentViewport(0, true)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(documentViewport(40, true)).kind, AppendKind::AwaitingEvidence);

    ScrollFrame unrelated(120, 140);
    std::fill(unrelated.pixels.begin(), unrelated.pixels.end(), 127);
    QCOMPARE(session.append(unrelated).kind, AppendKind::LowConfidenceDiscarded);
    QCOMPARE(session.outputHeight(), 140);
    QCOMPARE(session.append(documentViewport(80, true)).kind, AppendKind::AwaitingEvidence);
    const auto confirmation = session.append(documentViewport(120, true));
    QCOMPARE(confirmation.kind, AppendKind::AcceptedAppend);
    QCOMPARE(confirmation.appendedHeight, 120);
    QCOMPARE(session.outputHeight(), 260);
    QCOMPARE(session.append(documentViewport(160, true)).kind, AppendKind::AcceptedAppend);
}

void TestScrollStitchSession::pendingFixedFramesCountTowardResourceLimit()
{
    auto config = defaultConfig();
    config.fixedTopCandidateHeight = 12;
    config.fixedBottomCandidateHeight = 8;
    config.maximumAcceptedBytes = 120U * 220U * 4U;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(documentViewport(0, true)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(documentViewport(40, true)).kind, AppendKind::ResourceLimit);
    QCOMPARE(session.outputHeight(), 140);
    QCOMPARE(session.finalize().height, 140);
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

void TestScrollStitchSession::defaultScrollbarThresholdCropsRightMovingThumb()
{
    auto config = defaultConfig();
    config.scrollbarMaximumWidth = 6;
    ScrollStitchSession session(config);
    for (const int offset : {0, 30, 60, 90, 120}) {
        const auto result = session.append(viewportWithScrollbarSides(offset, false, true));
        QVERIFY(result.kind == AppendKind::AcceptedInitial || result.kind == AppendKind::AcceptedAppend);
    }
    QCOMPARE(session.finalize().width, 116);
}

void TestScrollStitchSession::leftMovingThumbCropsLeftAndPreservesSourcePixels()
{
    auto config = defaultConfig();
    config.scrollbarMaximumWidth = 6;
    ScrollStitchSession session(config);
    for (const int offset : {0, 30, 60, 90, 120}) {
        const auto result = session.append(viewportWithScrollbarSides(offset, true, false));
        QVERIFY(result.kind == AppendKind::AcceptedInitial || result.kind == AppendKind::AcceptedAppend);
    }
    const auto final = session.finalize();
    QCOMPARE(final.width, 116);
    QCOMPARE(blueAt(final, 0, 100), documentPixel(4, 100));
}

void TestScrollStitchSession::simultaneousEdgeCandidatesArePreservedAsAmbiguous()
{
    auto config = defaultConfig();
    config.scrollbarMaximumWidth = 6;
    ScrollStitchSession session(config);
    for (const int offset : {0, 30, 60, 90, 120}) {
        const auto result = session.append(viewportWithScrollbarSides(offset, true, true));
        QVERIFY(result.kind == AppendKind::AcceptedInitial || result.kind == AppendKind::AcceptedAppend);
    }
    QCOMPARE(session.finalize().width, 120);
}

void TestScrollStitchSession::changingFixedPositionEdgeBlockIsNotCropped()
{
    auto config = defaultConfig();
    config.scrollbarMaximumWidth = 6;
    config.scrollbarConfirmationMovements = 3;
    config.scrollbarPersistenceThreshold = 0.70;
    config.scrollbarMotionThreshold = 0.01;
    ScrollStitchSession session(config);
    int index = 0;
    for (const int offset : {0, 30, 60, 90, 120}) {
        const auto result = session.append(viewportWithChangingFixedEdgeBlock(
            offset, static_cast<std::uint8_t>(30 + index++ * 20)));
        QVERIFY(result.kind == AppendKind::AcceptedInitial || result.kind == AppendKind::AcceptedAppend);
    }
    QCOMPARE(session.finalize().width, 120);
}

void TestScrollStitchSession::lowConfidenceThumbMotionDoesNotCrop()
{
    auto config = defaultConfig();
    config.scrollbarMaximumWidth = 6;
    config.scrollbarConfirmationMovements = 3;
    config.scrollbarPersistenceThreshold = 0.70;
    config.scrollbarConfidenceThreshold = 0.75;
    ScrollStitchSession session(config);
    const int offsets[] = {0, 30, 60, 90, 120};
    const int positions[] = {10, 10, 10, 20, 20};
    for (int i = 0; i < 5; ++i) {
        const auto result = session.append(viewportWithThumbPosition(offsets[i], positions[i]));
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

void TestScrollStitchSession::currentTailPixelsCountTowardResourceLimit()
{
    auto config = defaultConfig();
    // The 200-row composed output would fit. The immutable 60-row segment plus
    // the full 140-row matcher tail are both persistent and must also fit.
    config.maximumAcceptedBytes = 120U * 300U * 4U;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(documentViewport(60)).kind, AppendKind::ResourceLimit);
    QCOMPARE(session.outputHeight(), 140);
    QVERIFY(session.finalize().isValid());
}

void TestScrollStitchSession::lightweightAnchorHistoryDoesNotConsumeViewportPerAcceptance()
{
    auto config = defaultConfig();
    config.maximumAcceptedBytes = 120U * 900U * 4U;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::AcceptedInitial);
    for (int offset = 20; offset <= 600; offset += 20) {
        QCOMPARE(session.append(documentViewport(offset)).kind, AppendKind::AcceptedAppend);
    }
    QCOMPARE(session.outputHeight(), 740);
    QVERIFY(session.finalize().isValid());
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

void TestScrollStitchSession::smallPreviewSamplesLongNearLimitCompositionDirectly()
{
    auto config = defaultConfig();
    config.maximumAcceptedBytes = 120U * 900U * 4U;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::AcceptedInitial);
    for (int offset = 20; offset <= 600; offset += 20) {
        QCOMPARE(session.append(documentViewport(offset)).kind, AppendKind::AcceptedAppend);
    }
    const auto preview = session.preview(74);
    QCOMPARE(preview.height, 74);
    QCOMPARE(preview.width, 12);
    QCOMPARE(blueAt(preview, 0, 0), documentPixel(0, 0));
    const int sourceY = 73 * 740 / 74;
    QCOMPARE(blueAt(preview, 11, 73), documentPixel(110, sourceY));
    QCOMPARE(session.outputHeight(), 740);
}

void TestScrollStitchSession::automaticFixedBandDetectionWorksWithProductionDefaults()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append(documentViewport(0, true)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(documentViewport(40, true)).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(documentViewport(80, true)).kind, AppendKind::AwaitingEvidence);
    const auto result = session.append(documentViewport(120, true));
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 120);
    QCOMPARE(session.outputHeight(), 260);
    QCOMPARE(blueAt(session.finalize(), 20, 140), documentPixel(20, 132));
}

void TestScrollStitchSession::automaticFixedBandDetectionFindsHeaderLargerThan32Pixels()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append(tallViewportWithFixedHeader(0)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(tallViewportWithFixedHeader(60)).kind, AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(tallViewportWithFixedHeader(120)).kind, AppendKind::AwaitingEvidence);
    const auto result = session.append(tallViewportWithFixedHeader(180));
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 180);
    QCOMPARE(session.outputHeight(), 420);
    QCOMPARE(blueAt(session.finalize(), 20, 2), static_cast<std::uint8_t>(31 + 20 % 17));
    QCOMPARE(blueAt(session.finalize(), 20, 419), documentPixel(20, 419));
}

void TestScrollStitchSession::automaticFixedBandDetectionDoesNotDelayScrollingEdges()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(documentViewport(40)).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.append(documentViewport(80)).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.outputHeight(), 220);
}

void TestScrollStitchSession::automaticFixedBandDetectionRejectsWhiteDocumentGap()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append(viewportAcrossWhiteDocumentGap(0)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportAcrossWhiteDocumentGap(20)).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.append(viewportAcrossWhiteDocumentGap(40)).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.append(viewportAcrossWhiteDocumentGap(60)).kind, AppendKind::AcceptedAppend);
    QCOMPARE(session.outputHeight(), 200);
    const auto final = session.finalize();
    QCOMPARE(blueAt(final, 20, 179), whiteGapDocumentPixel(20, 179));
    QCOMPARE(blueAt(final, 20, 180), whiteGapDocumentPixel(20, 180));
    QCOMPARE(blueAt(final, 20, 199), whiteGapDocumentPixel(20, 199));
}

void TestScrollStitchSession::automaticFixedBandDetectionRejectsLowInformationGradient()
{
    auto config = defaultConfig();
    config.matcher.maximumNormalizedError = 0.20;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(viewportWithLowInformationBottomGradient(0)).kind,
        AppendKind::AcceptedInitial);
    for (const int offset : {40, 80, 120}) {
        const auto result = session.append(viewportWithLowInformationBottomGradient(offset));
        QVERIFY(result.kind == AppendKind::LowConfidenceDiscarded
            || result.kind == AppendKind::ReviewDiscarded);
    }
    QCOMPARE(session.outputHeight(), 140);
    QCOMPARE(session.finalize().width, 120);
}

void TestScrollStitchSession::inconsistentBandHeightsRestartEvidenceRun()
{
    auto config = defaultConfig();
    config.matcher.maximumNormalizedError = 1.0;
    config.matcher.minimumWinnerMargin = 0.0;
    config.fixedTopCandidateHeight = 60;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(tallViewportWithHeaderVariant(0, 0)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(tallViewportWithHeaderVariant(60, 0)).kind,
        AppendKind::AwaitingEvidence);
    const auto restarted = session.append(tallViewportWithHeaderVariant(120, 2));
    QCOMPARE(restarted.kind, AppendKind::AcceptedAppend);
    QCOMPARE(restarted.appendedHeight, 60);
    QCOMPARE(session.append(tallViewportWithHeaderVariant(180, 0)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.outputHeight(), 300);

    const auto stableRestart = session.append(tallViewportWithHeaderVariant(240, 0));
    QCOMPARE(stableRestart.kind, AppendKind::AcceptedAppend);
    QCOMPARE(stableRestart.appendedHeight, 120);
    QCOMPARE(session.outputHeight(), 420);
    QCOMPARE(session.append(tallViewportWithHeaderVariant(300, 0)).kind,
        AppendKind::AwaitingEvidence);
    const auto confirmation = session.append(tallViewportWithHeaderVariant(360, 0));
    QCOMPARE(confirmation.kind, AppendKind::AcceptedAppend);
    QCOMPARE(confirmation.appendedHeight, 180);
    QCOMPARE(session.outputHeight(), 600);
}

void TestScrollStitchSession::constantBlueTexturedFixedBandsStillConfirm()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append(viewportWithConstantBlueTexturedFixedBands(0)).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportWithConstantBlueTexturedFixedBands(40)).kind,
        AppendKind::AwaitingEvidence);
    QCOMPARE(session.append(viewportWithConstantBlueTexturedFixedBands(80)).kind,
        AppendKind::AwaitingEvidence);
    const auto result = session.append(viewportWithConstantBlueTexturedFixedBands(120));
    QCOMPARE(result.kind, AppendKind::AcceptedAppend);
    QCOMPARE(result.appendedHeight, 120);
    QCOMPARE(session.outputHeight(), 260);
}

void TestScrollStitchSession::constantBlueScrollingChromaDoesNotBecomeFixed()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append(viewportWithConstantBlueScrollingChroma(0)).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(viewportWithConstantBlueScrollingChroma(40)).kind,
        AppendKind::AcceptedAppend);
    QCOMPARE(session.append(viewportWithConstantBlueScrollingChroma(80)).kind,
        AppendKind::AcceptedAppend);
    QCOMPARE(session.append(viewportWithConstantBlueScrollingChroma(120)).kind,
        AppendKind::AcceptedAppend);
    QCOMPARE(session.outputHeight(), 260);
}

void TestScrollStitchSession::maximumPendingRunSearchesAllFramesForReverseReview()
{
    auto config = defaultConfig();
    config.matcher.maximumAdvanceRatio = 0.15;
    config.fixedTopCandidateHeight = 12;
    config.fixedBandConfirmationMovements = 32;
    ScrollStitchSession session(config);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(0, true, false)).kind,
        AppendKind::AcceptedInitial);
    for (int offset = 10; offset <= 200; offset += 10) {
        QCOMPARE(session.append(viewportWithIndependentFixedBands(offset, true, false)).kind,
            AppendKind::AwaitingEvidence);
    }
    auto reviewMatcherConfig = config.matcher;
    reviewMatcherConfig.excludedBands.top = 12;
    reviewMatcherConfig.excludedBands.left = 8;
    reviewMatcherConfig.excludedBands.right = 8;
    const auto directReverse = VerticalOverlapMatcher().match(
        viewportWithIndependentFixedBands(5, true, false),
        viewportWithIndependentFixedBands(20, true, false),
        reviewMatcherConfig);
    QCOMPARE(directReverse.kind, OverlapKind::Reliable);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(5, true, false)).kind,
        AppendKind::ReviewDiscarded);
    QCOMPARE(session.outputHeight(), 140);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(200, true, false)).kind,
        AppendKind::DuplicateDiscarded);
    QCOMPARE(session.append(viewportWithIndependentFixedBands(210, true, false)).kind,
        AppendKind::AwaitingEvidence);
}

void TestScrollStitchSession::rejectsInvalidAndDimensionMismatchedFrames()
{
    ScrollStitchSession session(defaultConfig());
    QCOMPARE(session.append({}).kind, AppendKind::LowConfidenceDiscarded);
    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::AcceptedInitial);
    QCOMPARE(session.append(ScrollFrame(121, 140)).kind, AppendKind::LowConfidenceDiscarded);
    QCOMPARE(session.outputHeight(), 140);
}

void TestScrollStitchSession::invalidConfigurationNeverAcceptsContent()
{
    auto config = defaultConfig();
    config.matcher.maximumFullResolutionCandidates = 0;
    ScrollStitchSession session(config);

    QCOMPARE(session.append(documentViewport(0)).kind, AppendKind::LowConfidenceDiscarded);
    QCOMPARE(session.outputHeight(), 0);
    QVERIFY(!session.finalize().isValid());
}

} // namespace

QTEST_MAIN(TestScrollStitchSession)
#include "TestScrollStitchSession.moc"
