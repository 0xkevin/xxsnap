import AppKit
import XCTest
@testable import xxsnap

@MainActor
private final class FakePinnedWindow: PinnedImageWindowPresenting {
    let image: NSImage
    let screenRect: NSRect
    var onHide: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var showCount = 0
    var didShow: Bool { showCount > 0 }

    init(image: NSImage, screenRect: NSRect) {
        self.image = image
        self.screenRect = screenRect
    }

    func show() {
        showCount += 1
    }

    func simulateHide() {
        onHide?()
    }

    func simulateClose() {
        onClose?()
    }
}

@MainActor
private final class FakeScrollCaptureSession: ScrollCaptureSessionRunning {
    enum Failure: Error, Equatable { case start, finish }

    let seed: ScrollCaptureSeed
    var startError: Error?
    var suspendsStart = false
    var startContinuation: CheckedContinuation<Void, Error>?
    var finishError: Error?
    var finishErrors: [Error] = []
    var finishedImage = NSImage(size: NSSize(width: 20, height: 40))
    var suspendsFinish = false
    var finishContinuation: CheckedContinuation<NSImage, Error>?
    private(set) var startCount = 0
    private(set) var finishCount = 0
    private(set) var cancelCount = 0
    private(set) var stepDirections: [ScrollCaptureDirection] = []

    init(seed: ScrollCaptureSeed) { self.seed = seed }

    func start() async throws {
        startCount += 1
        if let startError { throw startError }
        if suspendsStart {
            try await withCheckedThrowingContinuation { startContinuation = $0 }
        }
    }

    func finish() async throws -> NSImage {
        finishCount += 1
        if !finishErrors.isEmpty { throw finishErrors.removeFirst() }
        if let finishError { throw finishError }
        if suspendsFinish {
            return try await withCheckedThrowingContinuation { finishContinuation = $0 }
        }
        return finishedImage
    }

    func performStep(direction: ScrollCaptureDirection) async throws {
        stepDirections.append(direction)
    }

    func cancel() -> ScrollCaptureSeed {
        cancelCount += 1
        return seed
    }
}

@MainActor
private final class FakeScrollCapturePresentation: ScrollCapturePresenting {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var previews: [NSImage] = []
    private(set) var previewEdges: [ScrollCapturePreviewEdge] = []
    private(set) var previewViewports: [ScrollCapturePreviewViewport] = []
    private(set) var scrollActivities: [ScrollCaptureScrollActivity] = []
    private(set) var warnings: [String] = []
    private(set) var clearWarningCount = 0
    private(set) var placements: [(NSRect, NSRect)] = []
    private(set) var resetTerminalCount = 0
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var onStep: ((ScrollCaptureDirection) -> Void)?
    var onStart: (() -> Void)?

    func start() {
        startCount += 1
        onStart?()
    }
    func stop() { stopCount += 1 }
    func updatePreview(
        _ image: NSImage,
        following edge: ScrollCapturePreviewEdge,
        viewport: ScrollCapturePreviewViewport
    ) {
        previews.append(image)
        previewEdges.append(edge)
        previewViewports.append(viewport)
    }
    func moveViewportIndicator(_ activity: ScrollCaptureScrollActivity) {
        scrollActivities.append(activity)
    }
    func setWarning(_ text: String) { warnings.append(text) }
    func clearWarning() { clearWarningCount += 1 }
    func updatePlacement(selectionFrame: NSRect, visibleFrame: NSRect) {
        placements.append((selectionFrame, visibleFrame))
    }
    func resetTerminalActionsForRetry() { resetTerminalCount += 1 }
}

@MainActor
private final class FakeScrollCaptureTargetDetector: ScrollCaptureTargetDetecting {
    struct Call: Equatable {
        let selection: NSRect
        let processIdentifier: pid_t
    }

    private var immediateResults: [NSRect?]
    private var continuations: [CheckedContinuation<NSRect?, Never>?] = []
    let suspendsRequests: Bool
    private(set) var calls: [Call] = []

    init(results: [NSRect?] = [nil], suspendsRequests: Bool = false) {
        immediateResults = results
        self.suspendsRequests = suspendsRequests
    }

    func scrollableRegion(in selection: NSRect, processIdentifier: pid_t) async -> NSRect? {
        calls.append(Call(selection: selection, processIdentifier: processIdentifier))
        if suspendsRequests {
            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        return immediateResults.isEmpty ? nil : immediateResults.removeFirst()
    }

    var pendingRequestCount: Int {
        continuations.compactMap { $0 }.count
    }

    func resumeRequest(at index: Int, returning result: NSRect?) {
        guard continuations.indices.contains(index), let continuation = continuations[index] else {
            return
        }
        continuations[index] = nil
        continuation.resume(returning: result)
    }
}

@MainActor
private final class FakeLongImageEditor: LongImageEditorPresenting {
    var onClose: (() -> Void)?
    var onShow: (() -> Void)?
    private(set) var showCount = 0
    func show() { showCount += 1; onShow?() }
    func simulateClose() { onClose?() }
}

@MainActor
private final class ResourceLimitCoordinatorStitcher: ScrollStitching {
    let acceptedImage: NSImage
    private var appendCount = 0
    init(acceptedImage: NSImage) { self.acceptedImage = acceptedImage }
    func append(_ image: NSImage) async throws -> ScrollCaptureAppendUpdate {
        appendCount += 1
        return .testValue(kind: appendCount == 1 ? .acceptedInitial : .resourceLimit)
    }
    func preview(maximumHeight: Int) async throws -> NSImage { acceptedImage }
    func finalImage() async throws -> NSImage { acceptedImage }
}

@MainActor
private struct ResourceLimitCoordinatorCapturer: ScrollRegionCapturing {
    let image: NSImage
    func captureImage(in selectionRect: NSRect) async throws -> NSImage { image }
}

@MainActor
private struct ResourceLimitCoordinatorClock: ScrollCaptureClock {
    func sleep(for duration: Duration) async throws { throw CancellationError() }
}

@MainActor
private final class ResourceLimitCoordinatorMonitor: ScrollActivityMonitoring {
    func start(_ callback: @escaping @MainActor () -> Void) {}
    func stop() {}
}

final class SelectionToolbarStateTests: XCTestCase {
    func testBeginScrollCaptureFreezesSeedAndEntersPassiveModeWithoutOrdinaryCompletion() throws {
        let image = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        var ordinaryCompletionCount = 0
        var request: ScrollCaptureSeed?
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in ordinaryCompletionCount += 1 }
        window.onScrollCaptureRequested = { request = $0 }
        let selection = NSRect(x: 80, y: 60, width: 300, height: 220)
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 10, y: 10, width: 40, height: 30),
            style: CaptureAnnotationStyle()
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        let toolbarBefore = try XCTUnwrap(window.test_mainToolbarRect())
        let scrollBefore = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .scroll))
        let cancelBefore = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .cancel))
        XCTAssertNotNil(window.test_measurementControlPoint(.cornerStyle))
        XCTAssertNotNil(window.test_measurementControlPoint(.aspectRatioLock))
        XCTAssertNotNil(window.test_measurementControlPoint(.refresh))

        window.test_beginScrollCapture()

        let seed = try XCTUnwrap(request)
        XCTAssertEqual(seed.snapshotRect, selection)
        XCTAssertEqual(seed.screenRect, window.convertToScreen(selection).standardized)
        XCTAssertEqual(seed.annotations.count, 1)
        XCTAssertEqual(seed.frozenImage.size, selection.size)
        XCTAssertEqual(ordinaryCompletionCount, 0)
        XCTAssertEqual(window.scrollCaptureOverlayState, .capturing)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertEqual(window.test_mainToolbarRect(), toolbarBefore)
        let geometry = try XCTUnwrap(window.scrollCaptureControlGeometry)
        XCTAssertEqual(geometry.toolbarFrame, window.convertToScreen(toolbarBefore))
        XCTAssertEqual(geometry.finishButtonFrame, window.convertToScreen(scrollBefore))
        XCTAssertEqual(geometry.cancelButtonFrame, window.convertToScreen(cancelBefore))
        XCTAssertTrue(window.test_toolbarButtonIsSelected(.scroll))
        XCTAssertFalse(window.test_toolbarButtonIsEnabled(.rectangle))
        XCTAssertTrue(window.test_toolbarButtonIsEnabled(.scroll))
        XCTAssertTrue(window.test_toolbarButtonIsEnabled(.cancel))
        XCTAssertEqual(window.test_tooltipText(for: .scroll), L10n(language: .zhHans).text(.finishScrollCapture))
        XCTAssertNil(window.test_measurementControlPoint(.cornerStyle))
        XCTAssertNil(window.test_measurementControlPoint(.aspectRatioLock))
        XCTAssertNil(window.test_measurementControlPoint(.refresh))
        XCTAssertEqual(window.test_measurementLabelText, "300 x 220  px")
    }

    func testBeginScrollCapturePreservesBoundaryCrossingOverlayContentInOriginalSeed() throws {
        let image = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        var request: ScrollCaptureSeed?
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.onScrollCaptureRequested = { request = $0 }
        let selection = NSRect(x: 80, y: 60, width: 300, height: 220)
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 0, y: 24, width: 44, height: 32),
            style: CaptureAnnotationStyle(strokeWidth: 8)
        )
        let mask = EraserMask(
            rect: NSRect(x: -3, y: 28, width: 18, height: 12),
            affectedAnnotationIDs: [annotation.id]
        )
        XCTAssertLessThan(CaptureAnnotationRenderer.longImageVisualBounds(for: annotation).minX, 0)
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_setEraserMasks([mask])

        window.test_beginScrollCapture()

        let seed = try XCTUnwrap(request)
        XCTAssertEqual(seed.snapshotRect, selection)
        XCTAssertEqual(seed.annotations, [annotation])
        XCTAssertEqual(seed.eraserMasks, [mask])
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertTrue(window.test_selectionBorderColor.isEqual(window.test_defaultSelectionColor))
        XCTAssertTrue(window.test_selectionHandleColor.isEqual(window.test_defaultSelectionColor))
    }

    func testResolvedScrollCaptureTargetTightensSelectionAndKeepsOverlayContentFixed() throws {
        let image = coordinateRedBlueImage(width: 640, height: 420)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let originalSelection = NSRect(x: 80, y: 60, width: 300, height: 220)
        let resolvedSelection = NSRect(x: 118, y: 84, width: 210, height: 164)
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 24, y: 28, width: 48, height: 36),
            style: CaptureAnnotationStyle()
        )
        let mask = EraserMask(
            rect: NSRect(x: 34, y: 38, width: 12, height: 10),
            affectedAnnotationIDs: [annotation.id]
        )
        window.test_setLockedSelectionRect(originalSelection)
        window.test_setAnnotations([annotation])
        window.test_setEraserMasks([mask])
        let annotationOverlayRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        let maskOverlayRect = try XCTUnwrap(window.test_eraserMaskOverlayRect(at: 0))
        window.test_beginScrollCapture()

        let seed = try XCTUnwrap(window.test_applyScrollCaptureTargetLocalRect(resolvedSelection))

        XCTAssertEqual(window.test_lockedSelectionRect, resolvedSelection)
        XCTAssertEqual(seed.snapshotRect, resolvedSelection)
        XCTAssertEqual(seed.screenRect, window.convertToScreen(resolvedSelection).standardized)
        XCTAssertEqual(seed.frozenImage.size, resolvedSelection.size)
        XCTAssertEqual(window.test_annotationOverlayRect(at: 0), annotationOverlayRect)
        XCTAssertEqual(window.test_eraserMaskOverlayRect(at: 0), maskOverlayRect)
        XCTAssertTrue(window.test_selectionBorderColor.isEqual(NSColor.systemGreen))
        XCTAssertTrue(window.test_selectionHandleColor.isEqual(NSColor.systemGreen))
    }

    func testResolvedScrollCaptureSeedFiltersUnsafeAnnotationsAndClipsMasksWithoutMutatingOverlay() throws {
        let image = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let originalSelection = NSRect(x: 40, y: 40, width: 400, height: 300)
        let resolvedSelection = NSRect(x: 140, y: 90, width: 240, height: 180)
        let inside = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 140, y: 80, width: 40, height: 30),
            style: CaptureAnnotationStyle(strokeWidth: 2)
        )
        let outside = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 10, y: 80, width: 40, height: 30),
            style: CaptureAnnotationStyle(strokeWidth: 2)
        )
        let crossingArrowLine = CaptureArrowLine(
            start: NSPoint(x: 80, y: 120),
            end: NSPoint(x: 160, y: 120),
            control: NSPoint(x: 120, y: 140),
            startArrowType: .none,
            endArrowType: .normal
        )
        let crossingArrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: crossingArrowLine.boundingRect,
            style: CaptureAnnotationStyle(strokeWidth: 2),
            arrowLine: crossingArrowLine
        )
        let crossingBrushPath = CaptureBrushPath(points: [
            NSPoint(x: 200, y: 150),
            NSPoint(x: 280, y: 165),
            NSPoint(x: 360, y: 150),
        ])
        let crossingBrush = CaptureAnnotation(
            kind: .brush,
            rect: crossingBrushPath.boundingRect,
            style: CaptureAnnotationStyle(strokeWidth: 2),
            brushPath: crossingBrushPath
        )
        let annotations = [inside, outside, crossingArrow, crossingBrush]
        let insideMask = EraserMask(
            rect: NSRect(x: 135, y: 85, width: 20, height: 12),
            affectedAnnotationIDs: [inside.id, outside.id]
        )
        let crossingMask = EraserMask(
            rect: NSRect(x: 90, y: 90, width: 70, height: 20),
            affectedAnnotationIDs: [inside.id]
        )
        let outsideMask = EraserMask(
            rect: NSRect(x: 10, y: 90, width: 20, height: 20),
            affectedAnnotationIDs: [outside.id]
        )
        let masks = [insideMask, crossingMask, outsideMask]
        window.test_setLockedSelectionRect(originalSelection)
        window.test_setAnnotations(annotations)
        window.test_setEraserMasks(masks)
        window.test_beginScrollCapture()

        let seed = try XCTUnwrap(window.test_applyScrollCaptureTargetLocalRect(resolvedSelection))
        let seedInside = try XCTUnwrap(seed.annotations.first)

        XCTAssertEqual(seed.annotations.map(\.id), [inside.id])
        XCTAssertEqual(seedInside.rect, NSRect(x: 40, y: 30, width: 40, height: 30))
        XCTAssertTrue(NSRect(origin: .zero, size: seed.snapshotRect.size).contains(
            CaptureAnnotationRenderer.longImageVisualBounds(for: seedInside)
        ))
        XCTAssertEqual(seed.eraserMasks.count, 2)
        XCTAssertEqual(seed.eraserMasks[0].affectedAnnotationIDs, [inside.id])
        XCTAssertEqual(seed.eraserMasks[0].rect, NSRect(x: 35, y: 35, width: 20, height: 12))
        XCTAssertEqual(seed.eraserMasks[1].affectedAnnotationIDs, [inside.id])
        XCTAssertEqual(seed.eraserMasks[1].rect, NSRect(x: 0, y: 40, width: 60, height: 20))
        XCTAssertEqual(
            (0..<annotations.count).compactMap(window.test_annotation(at:)).map(\.id),
            annotations.map(\.id)
        )
        XCTAssertEqual((0..<masks.count).compactMap(window.test_eraserMask(at:)).count, masks.count)

        window.restoreAfterScrollCaptureCancellation()

        XCTAssertEqual((0..<annotations.count).compactMap(window.test_annotation(at:)), annotations)
        XCTAssertEqual((0..<masks.count).compactMap(window.test_eraserMask(at:)), masks)
    }

    func testScrollCaptureTargetFallbackKeepsOriginalSelectionAndBlueChrome() {
        let image = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 80, y: 60, width: 300, height: 220)
        let expectedBlue = NSColor(
            calibratedRed: 83 / 255,
            green: 120 / 255,
            blue: 232 / 255,
            alpha: 1
        )
        window.test_setLockedSelectionRect(selection)
        window.test_beginScrollCapture()

        window.test_markScrollCaptureTargetFallback()

        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertTrue(window.test_selectionBorderColor.isEqual(expectedBlue))
        XCTAssertTrue(window.test_selectionHandleColor.isEqual(expectedBlue))
    }

    func testCancellingResolvedScrollCaptureTargetRestoresSelectionAndOverlayContent() throws {
        let image = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let originalSelection = NSRect(x: 70, y: 50, width: 320, height: 240)
        let resolvedSelection = NSRect(x: 105, y: 78, width: 230, height: 170)
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 22, y: 26, width: 52, height: 38),
            style: CaptureAnnotationStyle()
        )
        let mask = EraserMask(
            rect: NSRect(x: 30, y: 34, width: 16, height: 12),
            affectedAnnotationIDs: [annotation.id]
        )
        window.test_setLockedSelectionRect(originalSelection)
        window.test_setAnnotations([annotation])
        window.test_setEraserMasks([mask])
        let annotationOverlayRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        let maskOverlayRect = try XCTUnwrap(window.test_eraserMaskOverlayRect(at: 0))
        window.test_beginScrollCapture()
        XCTAssertNotNil(window.test_applyScrollCaptureTargetLocalRect(resolvedSelection))

        window.restoreAfterScrollCaptureCancellation()

        XCTAssertEqual(window.test_lockedSelectionRect, originalSelection)
        XCTAssertEqual(window.test_annotationOverlayRect(at: 0), annotationOverlayRect)
        XCTAssertEqual(window.test_eraserMaskOverlayRect(at: 0), maskOverlayRect)
        XCTAssertTrue(window.test_selectionBorderColor.isEqual(window.test_defaultSelectionColor))
        XCTAssertTrue(window.test_selectionHandleColor.isEqual(window.test_defaultSelectionColor))
    }

    func testScrollCaptureTargetRejectsNullTinyAndOutOfBoundsRegions() {
        let image = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 80, y: 60, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_beginScrollCapture()

        let invalidTargets = [
            NSRect.null,
            NSRect(x: 100, y: 100, width: 7, height: 40),
            NSRect(x: 100, y: 100, width: 40, height: 7),
            NSRect(x: 0, y: 100, width: 70, height: 60),
            NSRect(x: 390, y: 100, width: 80, height: 60),
            NSRect(x: 75, y: 100, width: 12, height: 40),
        ]
        for target in invalidTargets {
            XCTAssertNil(window.test_applyScrollCaptureTargetLocalRect(target))
            XCTAssertEqual(window.test_lockedSelectionRect, selection)
            XCTAssertTrue(window.test_selectionBorderColor.isEqual(window.test_defaultSelectionColor))
            XCTAssertTrue(window.test_selectionHandleColor.isEqual(window.test_defaultSelectionColor))
        }
        window.test_markScrollCaptureTargetFallback()
        XCTAssertTrue(window.test_selectionBorderColor.isEqual(window.test_defaultSelectionColor))
        XCTAssertTrue(window.test_selectionHandleColor.isEqual(window.test_defaultSelectionColor))
    }

    func testResolvedScrollCaptureTargetClipsOutwardOriginalSeedEnvelopeBeforeInwardAlignment() throws {
        let imageSize = NSSize(width: 640, height: 420)
        let original = NSRect(x: 80.25, y: 60.25, width: 300.5, height: 220.5)
        let canonical = NSRect(x: 80.5, y: 60.5, width: 300, height: 220)
        var configuration = SelectionOverlayConfiguration.default
        configuration.windowFrame = NSRect(x: 137, y: 83, width: imageSize.width, height: imageSize.height)
        var originalSeed: ScrollCaptureSeed?
        let window = SelectionOverlayWindow(
            backgroundImage: retinaSolidImage(size: imageSize, color: .white),
            configuration: configuration
        ) { _ in }
        window.onScrollCaptureRequested = { originalSeed = $0 }
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 60, y: 70, width: 40, height: 30),
            style: CaptureAnnotationStyle(strokeWidth: 2)
        )
        let mask = EraserMask(
            rect: NSRect(x: 65, y: 75, width: 12, height: 10),
            affectedAnnotationIDs: [annotation.id]
        )
        window.test_setLockedSelectionRect(original)
        window.test_setAnnotations([annotation])
        window.test_setEraserMasks([mask])
        let annotationOverlayRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        let maskOverlayRect = try XCTUnwrap(window.test_eraserMaskOverlayRect(at: 0))

        window.test_beginScrollCapture()

        let outwardSeed = try XCTUnwrap(originalSeed)
        let outwardWindowRect = window.convertFromScreen(outwardSeed.screenRect)
        let outwardLocalRect = try XCTUnwrap(window.contentView).convert(outwardWindowRect, from: nil)
        XCTAssertEqual(outwardLocalRect, NSRect(x: 80, y: 60, width: 301, height: 221))

        let resolvedSeed = try XCTUnwrap(window.applyScrollCaptureTarget(screenRect: outwardSeed.screenRect))
        let frozenPixels = try XCTUnwrap(
            resolvedSeed.frozenImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )

        XCTAssertEqual(window.test_lockedSelectionRect, canonical)
        XCTAssertEqual(resolvedSeed.snapshotRect, canonical)
        XCTAssertEqual(resolvedSeed.screenRect, window.convertToScreen(canonical))
        XCTAssertEqual(resolvedSeed.frozenImage.size, canonical.size)
        XCTAssertEqual(frozenPixels.width, 600)
        XCTAssertEqual(frozenPixels.height, 440)
        XCTAssertTrue(original.contains(canonical))
        XCTAssertEqual(window.test_annotationOverlayRect(at: 0), annotationOverlayRect)
        XCTAssertEqual(window.test_eraserMaskOverlayRect(at: 0), maskOverlayRect)
        XCTAssertTrue(window.test_selectionBorderColor.isEqual(NSColor.systemGreen))
        XCTAssertTrue(window.test_selectionHandleColor.isEqual(NSColor.systemGreen))
    }

    func testResolvedScrollCaptureTargetClipsOneRetinaPixelOutsideOriginalSelection() throws {
        let image = retinaSolidImage(size: NSSize(width: 640, height: 420), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let original = NSRect(x: 80, y: 60, width: 300, height: 220)
        let onePixelOutside = NSRect(x: 79.5, y: 90.25, width: 120.5, height: 80.5)
        let canonical = NSRect(x: 80, y: 90.5, width: 120, height: 80)
        window.test_setLockedSelectionRect(original)
        window.test_beginScrollCapture()

        let seed = try XCTUnwrap(window.test_applyScrollCaptureTargetLocalRect(onePixelOutside))
        let frozenPixels = try XCTUnwrap(
            seed.frozenImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )

        XCTAssertEqual(window.test_lockedSelectionRect, canonical)
        XCTAssertEqual(seed.snapshotRect, canonical)
        XCTAssertEqual(seed.screenRect, window.convertToScreen(canonical))
        XCTAssertEqual(seed.frozenImage.size, canonical.size)
        XCTAssertEqual(frozenPixels.width, 240)
        XCTAssertEqual(frozenPixels.height, 160)
        XCTAssertTrue(original.contains(canonical))
        XCTAssertTrue(window.test_selectionBorderColor.isEqual(NSColor.systemGreen))
        XCTAssertTrue(window.test_selectionHandleColor.isEqual(NSColor.systemGreen))
    }

    func testResolvedScrollCaptureTargetUsesOneInwardRetinaCanonicalRectAcrossWindowOrigins() throws {
        let imageSize = NSSize(width: 640, height: 420)
        let original = NSRect(x: 80.25, y: 60.25, width: 300.5, height: 220.5)
        let fractionalTarget = NSRect(x: 80.3, y: 60.3, width: 300.4, height: 220.4)
        let canonical = NSRect(x: 80.5, y: 60.5, width: 300, height: 220)

        for windowOrigin in [NSPoint(x: 137, y: 83), NSPoint(x: -480, y: -220)] {
            var configuration = SelectionOverlayConfiguration.default
            configuration.windowFrame = NSRect(origin: windowOrigin, size: imageSize)
            let window = SelectionOverlayWindow(
                backgroundImage: retinaSolidImage(size: imageSize, color: .white),
                configuration: configuration
            ) { _ in }
            let annotation = CaptureAnnotation(
                kind: .rectangle,
                rect: NSRect(x: 60, y: 70, width: 40, height: 30),
                style: CaptureAnnotationStyle(strokeWidth: 2)
            )
            let mask = EraserMask(
                rect: NSRect(x: 65, y: 75, width: 12, height: 10),
                affectedAnnotationIDs: [annotation.id]
            )
            window.test_setLockedSelectionRect(original)
            window.test_setAnnotations([annotation])
            window.test_setEraserMasks([mask])
            let annotationOverlayRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
            let maskOverlayRect = try XCTUnwrap(window.test_eraserMaskOverlayRect(at: 0))
            window.test_beginScrollCapture()

            let seed = try XCTUnwrap(window.test_applyScrollCaptureTargetLocalRect(fractionalTarget))
            let frozenPixels = try XCTUnwrap(
                seed.frozenImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            )

            XCTAssertEqual(window.test_lockedSelectionRect, canonical)
            XCTAssertEqual(seed.snapshotRect, canonical)
            XCTAssertEqual(seed.screenRect, window.convertToScreen(canonical))
            XCTAssertTrue(original.contains(seed.snapshotRect))
            XCTAssertEqual(seed.frozenImage.size, canonical.size)
            XCTAssertEqual(frozenPixels.width, 600)
            XCTAssertEqual(frozenPixels.height, 440)
            XCTAssertEqual(CGFloat(frozenPixels.width) / 2, seed.snapshotRect.width)
            XCTAssertEqual(CGFloat(frozenPixels.height) / 2, seed.snapshotRect.height)
            XCTAssertEqual(window.test_annotationOverlayRect(at: 0), annotationOverlayRect)
            XCTAssertEqual(window.test_eraserMaskOverlayRect(at: 0), maskOverlayRect)
        }
    }

    func testScrollCaptureTargetRejectsRectThatBecomesSubminimumAfterInwardPixelAlignment() {
        let image = retinaSolidImage(size: NSSize(width: 640, height: 420), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let original = NSRect(x: 80, y: 60, width: 300, height: 220)
        let fractionalTarget = NSRect(x: 100.1, y: 90.1, width: 8.1, height: 40.2)
        window.test_setLockedSelectionRect(original)
        window.test_beginScrollCapture()

        XCTAssertNil(window.test_applyScrollCaptureTargetLocalRect(fractionalTarget))
        XCTAssertEqual(window.test_lockedSelectionRect, original)
        XCTAssertTrue(window.test_selectionBorderColor.isEqual(window.test_defaultSelectionColor))
    }

    func testBeginScrollCaptureClearsAndSuppressesColorSamplerLayer() {
        let image = solidImage(size: NSSize(width: 640, height: 420), color: .systemBlue)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 80, y: 60, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        let samplePoint = NSPoint(x: selection.midX, y: selection.midY)
        window.test_updateColorSampler(at: samplePoint)
        XCTAssertTrue(window.test_isColorSamplerVisible)

        window.test_beginScrollCapture()

        XCTAssertFalse(window.test_isColorSamplerVisible)
        XCTAssertNil(window.test_sampledColorHex)
        window.test_updateColorSampler(at: samplePoint)
        XCTAssertFalse(window.test_isColorSamplerVisible)
        XCTAssertNil(window.test_sampledColorHex)
    }

    func testScrollToolbarKeepsScrollIconWhileCapturing() {
        let image = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 60, width: 300, height: 220))
        XCTAssertEqual(window.test_symbolName(for: .scroll), "toolbar-scroll-screen2")

        window.test_beginScrollCapture()
        XCTAssertEqual(window.test_symbolName(for: .scroll), "toolbar-scroll-screen2")

        window.endScrollCapturePassiveMode()
        XCTAssertEqual(window.test_symbolName(for: .scroll), "toolbar-scroll-screen2")
    }

    func testScrollCaptureSelectedIconIsBlue() throws {
        let image = solidImage(size: NSSize(width: 900, height: 520), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        window.test_beginScrollCapture()

        let button = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .scroll))
        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let iconPixel = try XCTUnwrap(firstBlueDominantPixel(in: overlayImage, rect: button))
        XCTAssertGreaterThan(iconPixel.blue, iconPixel.red)
        XCTAssertGreaterThan(iconPixel.blue, iconPixel.green)
    }

    func testBeginScrollCaptureAlignsLiveScreenRectToFrozenSeedPixels() throws {
        let background = retinaSolidImage(
            size: NSSize(width: 640, height: 420),
            color: .white
        )
        var request: ScrollCaptureSeed?
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.onScrollCaptureRequested = { request = $0 }
        let selection = NSRect(x: 80.2, y: 60.3, width: 300.1, height: 220.1)
        window.test_setLockedSelectionRect(selection)

        window.test_beginScrollCapture()

        let seed = try XCTUnwrap(request)
        let frozenPixels = try XCTUnwrap(
            seed.frozenImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        XCTAssertEqual(seed.snapshotRect, selection)
        XCTAssertEqual(seed.screenRect.width * 2, CGFloat(frozenPixels.width), accuracy: 0.001)
        XCTAssertEqual(seed.screenRect.height * 2, CGFloat(frozenPixels.height), accuracy: 0.001)
    }

    func testScrollCapturePassiveModeShowsLiveContentInsideSelection() throws {
        let image = solidImage(size: desktopImageSize(), color: .systemRed)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 160, y: 140, width: 420, height: 260)
        window.test_setLockedSelectionRect(selection)

        let before = try XCTUnwrap(window.test_renderedOverlayImage())
        let beforePixel = try XCTUnwrap(rgbaRenderPixel(in: before, at: NSPoint(x: selection.midX, y: selection.midY)))
        XCTAssertGreaterThan(beforePixel.alpha, 240)

        window.test_beginScrollCapture()

        let after = try XCTUnwrap(window.test_renderedOverlayImage())
        let afterPixel = try XCTUnwrap(rgbaRenderPixel(in: after, at: NSPoint(x: selection.midX, y: selection.midY)))
        XCTAssertLessThan(afterPixel.alpha, 10, "the selection must reveal the live scrolling application")
    }

    func testEscapeRequestsScrollCaptureCancelWithoutLeavingPassiveMode() {
        for paused in [false, true] {
            var ordinaryCompletionCount = 0
            var cancelCount = 0
            let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 500, height: 400), color: .white)) { _ in
                ordinaryCompletionCount += 1
            }
            window.onScrollCaptureRequested = { _ in }
            window.onScrollCaptureCancelRequested = { cancelCount += 1 }
            window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 260, height: 200))
            window.test_activateShapeTool(.rectangle)
            window.test_beginScrollCapture()
            if paused { window.setScrollCapturePaused(message: "Paused") }

            window.test_keyDown(keyCode: 53)
            XCTAssertEqual(cancelCount, 1)
            XCTAssertEqual(ordinaryCompletionCount, 0)
            XCTAssertNotEqual(window.scrollCaptureOverlayState, .inactive)
            XCTAssertTrue(window.ignoresMouseEvents)
            XCTAssertTrue(window.test_toolbarButtonIsSelected(.rectangle))
            window.test_keyDown(keyCode: 53)
            XCTAssertEqual(cancelCount, 1)
            XCTAssertEqual(ordinaryCompletionCount, 0)
        }
    }

    func testEnterFinishesCapturingAndPausedScrollCaptureExactlyOnce() {
        for (paused, keyCode) in [(false, UInt16(36)), (true, UInt16(76))] {
            var ordinaryCompletionCount = 0
            var finishCount = 0
            var cancelCount = 0
            let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 500, height: 400), color: .white)) { _ in
                ordinaryCompletionCount += 1
            }
            window.onScrollCaptureRequested = { _ in }
            window.onScrollCaptureFinishRequested = { finishCount += 1 }
            window.onScrollCaptureCancelRequested = { cancelCount += 1 }
            window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 260, height: 200))
            window.test_beginScrollCapture()
            if paused { window.setScrollCapturePaused(message: "Paused") }

            window.test_keyDown(keyCode: keyCode)
            window.test_keyDown(keyCode: keyCode)
            window.test_keyDown(keyCode: 53)

            XCTAssertEqual(finishCount, 1)
            XCTAssertEqual(cancelCount, 0)
            XCTAssertEqual(ordinaryCompletionCount, 0)
            XCTAssertNotEqual(window.scrollCaptureOverlayState, .inactive)
            XCTAssertTrue(window.ignoresMouseEvents)
        }
    }

    func testEndingPassiveModeRestoresMouseAndOrdinaryFlow() throws {
        var requestCount = 0
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 500, height: 400), color: .white)) { _ in }
        window.onScrollCaptureRequested = { _ in requestCount += 1 }
        window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 260, height: 200))
        window.test_activateShapeTool(.rectangle)
        window.test_beginScrollCapture()
        window.endScrollCapturePassiveMode()
        XCTAssertEqual(window.scrollCaptureOverlayState, .inactive)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertTrue(window.test_toolbarButtonIsSelected(.rectangle))
        window.test_beginScrollCapture()
        XCTAssertEqual(requestCount, 2)
    }

    func testPassiveScrollCaptureConsumesOverlayCommandsAndPreservesGeometry() throws {
        var ordinaryCompletionCount = 0
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 700, height: 500), color: .white)) { _ in
            ordinaryCompletionCount += 1
        }
        window.onScrollCaptureRequested = { _ in }
        let selection = NSRect(x: 80, y: 80, width: 360, height: 260)
        window.test_setLockedSelectionRect(selection)
        let toolbar = try XCTUnwrap(window.test_mainToolbarRect())
        let screenToolbar = try XCTUnwrap(window.scrollCaptureToolbarScreenFrame)
        XCTAssertEqual(screenToolbar, window.convertToScreen(toolbar))
        window.test_beginScrollCapture()

        XCTAssertTrue(window.test_handleKeyDown(keyCode: 8, charactersIgnoringModifiers: "c", modifierFlags: [.command]))
        window.test_mouseDown(at: NSPoint(x: selection.midX, y: selection.midY))
        window.test_mouseDragged(to: NSPoint(x: selection.midX + 50, y: selection.midY + 50))
        window.test_mouseUp(at: NSPoint(x: selection.midX + 50, y: selection.midY + 50))
        XCTAssertEqual(ordinaryCompletionCount, 0)
        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertEqual(window.test_mainToolbarRect(), toolbar)

        window.setScrollCapturePaused(message: "Paused")
        XCTAssertEqual(window.scrollCaptureOverlayState, .paused(message: "Paused"))
        XCTAssertTrue(window.ignoresMouseEvents)
    }
    func testEyedropperSamplesVisibleAnnotationAndCopiesOnlyColor() throws {
        let background = solidImage(size: NSSize(width: 240, height: 160), color: NSColor(srgbRed: 0.95, green: 0.8, blue: 0.1, alpha: 1))
        let expectedOverlayColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 10, width: 80, height: 50),
            style: {
                var style = CaptureAnnotationStyle()
                style.strokeColor = expectedOverlayColor
                style.fillEnabled = true
                style.fillColor = expectedOverlayColor
                return style
            }()
        )
        let point = NSPoint(x: 90, y: 60)
        let selection = NSRect(x: 40, y: 30, width: 120, height: 80)

        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])

        guard let eyedropperPoint = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        window.test_mouseMoved(to: point)
        XCTAssertTrue(window.test_isColorSamplerVisible)
        let sampledOverlayHex = try XCTUnwrap(window.test_sampledColorHex)
        XCTAssertNotEqual(sampledOverlayHex, SelectionToolbarState.colorSamplerHexString(for: NSColor(srgbRed: 0.95, green: 0.8, blue: 0.1, alpha: 1)))
        XCTAssertEqual(window.test_magnifierSampleColorHex(at: point), sampledOverlayHex)

        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "c")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), sampledOverlayHex)

        var copyResult: CaptureSelectionResult?
        let copyExpectation = expectation(description: "copy action")
        let copiedWindow = SelectionOverlayWindow(backgroundImage: background) { result in
            copyResult = result
            copyExpectation.fulfill()
        }
        copiedWindow.test_setLockedSelectionRect(selection)
        copiedWindow.test_setAnnotations([annotation])
        copiedWindow.test_mouseDown(at: eyedropperPoint)
        copiedWindow.test_mouseUp(at: eyedropperPoint)
        copiedWindow.test_keyDown(keyCode: 8, charactersIgnoringModifiers: "c", modifierFlags: [.command])
        wait(for: [copyExpectation], timeout: 2)
        XCTAssertEqual(copyResult?.action, .copy)

        window.test_updateColorSampler(at: NSPoint(x: selection.maxX + 12, y: selection.midY))
        XCTAssertFalse(window.test_isColorSamplerVisible)
    }

    func testEyedropperSamplesVisibleMarkerLineOnBlackBackground() throws {
        let background = solidImage(size: NSSize(width: 500, height: 400), color: .black)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)

        let blackSwatch = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 2))
        window.test_mouseDown(at: blackSwatch)
        window.test_mouseUp(at: blackSwatch)
        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 260, y: 150))
        window.test_mouseUp(at: NSPoint(x: 260, y: 150))

        let eyedropperPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eyedropper))
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)
        window.test_mouseMoved(to: NSPoint(x: 200, y: 150))

        let sampledHex = try XCTUnwrap(window.test_sampledColorHex)
        XCTAssertEqual(sampledHex, "#FFFFFF")
        XCTAssertEqual(window.test_magnifierSampleColorHex(at: NSPoint(x: 200, y: 150)), sampledHex)
    }

    func testEyedropperSamplesColoredMarkerLineOnBlackBackground() throws {
        let background = solidImage(size: NSSize(width: 500, height: 400), color: .black)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)

        let redSwatch = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 0))
        window.test_mouseDown(at: redSwatch)
        window.test_mouseUp(at: redSwatch)
        window.test_mouseDown(at: NSPoint(x: 140, y: 170))
        window.test_mouseDragged(to: NSPoint(x: 260, y: 170))
        window.test_mouseUp(at: NSPoint(x: 260, y: 170))

        let eyedropperPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eyedropper))
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)
        window.test_mouseMoved(to: NSPoint(x: 200, y: 170))

        let sampledHex = try XCTUnwrap(window.test_sampledColorHex)
        XCTAssertEqual(sampledHex, "#FF001A")
        XCTAssertEqual(window.test_magnifierSampleColorHex(at: NSPoint(x: 200, y: 170)), sampledHex)
    }

    func testEyedropperClickMoveClickShowsPixelMeasurementLine() throws {
        let background = solidImage(size: NSSize(width: 500, height: 400), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        let eyedropperPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eyedropper))
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        let start = NSPoint(x: 150, y: 150)
        let end = NSPoint(x: 153, y: 154)
        window.test_mouseDown(at: start)
        window.test_mouseUp(at: start)
        window.test_mouseMoved(to: end)
        window.test_mouseDown(at: end)
        window.test_mouseUp(at: end)

        let line = try XCTUnwrap(window.test_eyedropperMeasurementLine)
        XCTAssertEqual(line.start, start)
        XCTAssertEqual(line.end, end)
        XCTAssertEqual(window.test_eyedropperMeasurementLabel, "5 px")
        XCTAssertTrue(window.test_isColorSamplerVisible)
    }

    func testEyedropperShiftDragSnapsMeasurementLineToStraightAxis() throws {
        let background = solidImage(size: NSSize(width: 500, height: 400), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        let eyedropperPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eyedropper))
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        let start = NSPoint(x: 150, y: 150)
        window.test_mouseDown(at: start)
        window.test_mouseUp(at: start)
        window.test_mouseMoved(to: NSPoint(x: 214, y: 170), modifierFlags: [.shift])
        window.test_mouseDown(at: NSPoint(x: 214, y: 170), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: 214, y: 170), modifierFlags: [.shift])

        let line = try XCTUnwrap(window.test_eyedropperMeasurementLine)
        XCTAssertEqual(line.start, start)
        XCTAssertEqual(line.end.x, 214, accuracy: 0.1)
        XCTAssertEqual(line.end.y, 150, accuracy: 0.1)
        XCTAssertEqual(window.test_eyedropperMeasurementLabel, "64 px")
    }

    func testEyedropperSamplesFromTipPointAndMagnifierMatchesTipPixel() throws {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let green = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let cyan = NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1)
        let magenta = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        let yellow = NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let image = pixelImage(
            width: 3,
            height: 3,
            pixels: [
                [red, green, blue],
                [cyan, magenta, yellow],
                [black, white, blue],
            ]
        )
        let selection = NSRect(x: 0, y: 0, width: 3, height: 3)
        let mousePoint = NSPoint(x: 1.5, y: 1.5)
        let samplePoint = NSPoint(
            x: mousePoint.x + SelectionToolbarState.eyedropperSampleOffset.width,
            y: mousePoint.y + SelectionToolbarState.eyedropperSampleOffset.height
        )
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)

        guard let eyedropperPoint = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        window.test_mouseMoved(to: mousePoint)

        XCTAssertEqual(window.test_sampledPointerPoint, samplePoint)
        XCTAssertEqual(window.test_sampledColorHex, "#FF00FF")
        XCTAssertEqual(window.test_magnifierSampleColorHex(at: samplePoint), "#FF00FF")
        XCTAssertEqual(window.test_magnifierSampleColorHex(at: samplePoint, columnOffset: -1, rowOffset: -1), "#FF0000")
        XCTAssertEqual(window.test_magnifierSampleColorHex(at: samplePoint, columnOffset: 1, rowOffset: 1), "#0000FF")
    }

    func testEyedropperMagnifierRendersAboveMainToolbarWhenOverlapping() throws {
        let backgroundColor = NSColor(srgbRed: 0, green: 0.82, blue: 0.13, alpha: 1)
        let image = solidImage(size: desktopImageSize(), color: backgroundColor)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let bounds = window.test_overlayBounds
        let selection = NSRect(x: bounds.midX - 180, y: bounds.midY - 80, width: 360, height: 220)
        window.test_setLockedSelectionRect(selection)

        guard let eyedropperPoint = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        let toolbarButtonRects = window.test_mainToolbarButtonRects()
        let toolbarButtonUnion = toolbarButtonRects.reduce(NSRect.null) { partial, rect in
            partial.union(rect)
        }
        let sampleAnchor = NSPoint(x: selection.midX, y: toolbarButtonUnion.midY + 56)
        XCTAssertTrue(selection.contains(sampleAnchor))
        XCTAssertFalse(toolbarButtonUnion.contains(sampleAnchor))

        let samplerRect = SelectionToolbarState.colorSamplerRect(
            size: NSSize(width: 184, height: 188),
            pointer: sampleAnchor,
            inside: bounds
        )
        let magnifierCenter = NSPoint(x: samplerRect.midX, y: samplerRect.maxY - 48)
        XCTAssertTrue(toolbarButtonUnion.contains(magnifierCenter))

        window.test_mouseMoved(to: sampleAnchor)
        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let renderedMagnifierCenter = NSPoint(
            x: magnifierCenter.x,
            y: overlayImage.size.height - magnifierCenter.y
        )
        let pixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: renderedMagnifierCenter))

        XCTAssertGreaterThan(pixel.green, 180)
        XCTAssertGreaterThan(Int(pixel.green), Int(pixel.red) + 60)
        XCTAssertGreaterThan(Int(pixel.green), Int(pixel.blue) + 60)
    }

    func testEyedropperCursorHotSpotAlignsWithSvgTip() {
        XCTAssertEqual(SelectionToolbarState.eyedropperCursorHotSpot.x, 3.6, accuracy: 0.2)
        XCTAssertEqual(SelectionToolbarState.eyedropperCursorHotSpot.y, 20.4, accuracy: 0.2)
    }

    func testMainToolbarPlacesEyedropperImmediatelyBeforeMosaic() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))

        guard
            let markerRect = window.test_mainToolbarButtonRect(for: .marker),
            let eyedropperRect = window.test_mainToolbarButtonRect(for: .eyedropper),
            let mosaicRect = window.test_mainToolbarButtonRect(for: .mosaic)
        else {
            return XCTFail("Expected marker, eyedropper, and mosaic toolbar buttons")
        }

        XCTAssertLessThan(markerRect.midX, eyedropperRect.midX)
        XCTAssertLessThan(eyedropperRect.midX, mosaicRect.midX)
        XCTAssertEqual(eyedropperRect.minX - markerRect.minX, mosaicRect.minX - eyedropperRect.minX, accuracy: 0.5)
        XCTAssertEqual(window.test_symbolName(for: .eyedropper), "toolbar-straw-ranging")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "eyedropper"), "取色 ｜ 测距")
    }

    func testEyedropperResourcesAreBundledAndReadableByMacTarget() {
        let originalUrl = Bundle.main.url(forResource: "eyedropper", withExtension: "svg")
        let toolbarUrl = Bundle.main.url(forResource: "straw-ranging", withExtension: "svg")

        XCTAssertNotNil(originalUrl)
        XCTAssertGreaterThan((try? Data(contentsOf: XCTUnwrap(originalUrl)).count) ?? 0, 0)
        XCTAssertNotNil(toolbarUrl)
        XCTAssertGreaterThan((try? Data(contentsOf: XCTUnwrap(toolbarUrl)).count) ?? 0, 0)
    }

    func testClickingEyedropperTogglesExplicitModeAndSelectedState() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))

        guard let point = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }

        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)
        XCTAssertTrue(window.test_isEyedropperToolActive)
        XCTAssertTrue(window.test_eyedropperToolbarButtonIsSelected)
        XCTAssertNil(window.test_optionsToolbarRect)
        XCTAssertNil(window.test_optionsToolbarMode)
        XCTAssertNil(window.test_currentShapeKind)

        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)
        XCTAssertFalse(window.test_isEyedropperToolActive)
        XCTAssertFalse(window.test_eyedropperToolbarButtonIsSelected)
    }

    func testClickingTextToolTogglesTextModeAndSelectedState() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))

        guard let point = window.test_mainToolbarButtonPoint(for: .text) else {
            return XCTFail("Expected text toolbar button")
        }

        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)
        XCTAssertTrue(window.test_isTextToolActive)
        XCTAssertTrue(window.test_textToolbarButtonIsSelected)
        XCTAssertEqual(window.test_optionsToolbarMode, .text)
        XCTAssertNil(window.test_currentShapeKind)

        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)
        XCTAssertFalse(window.test_isTextToolActive)
        XCTAssertFalse(window.test_textToolbarButtonIsSelected)
        XCTAssertNil(window.test_optionsToolbarMode)
    }

    func testTextToolCreatesEditableAnnotationAndCommitsTypedText() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertTrue(window.test_isEditingTextAnnotation)
        XCTAssertTrue(window.test_textEditorIsFirstResponder)
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "")
        let emptyTextRect = window.test_annotationRect(at: 0)
        XCTAssertEqual(emptyTextRect?.width ?? 0, 17, accuracy: 0.1)

        window.firstResponder?.insertText("Hi")
        let typedTextRect = window.test_annotationRect(at: 0)
        let typedStyle = window.test_annotationStyle(at: 0) ?? CaptureAnnotationStyle()
        let measuredTextWidth = NSAttributedString(
            string: "Hi",
            attributes: CaptureAnnotationRenderer.textAttributes(style: typedStyle)
        ).boundingRect(
            with: NSSize(width: 10_000, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).width
        XCTAssertGreaterThan(typedTextRect?.width ?? 0, emptyTextRect?.width ?? 0)
        XCTAssertGreaterThanOrEqual(typedTextRect?.width ?? 0, ceil(measuredTextWidth) + 16)
        window.test_commitTextEditing()

        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertFalse(window.test_isEditingTextAnnotation)
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "Hi")
        XCTAssertGreaterThan(window.test_annotationRect(at: 0)?.width ?? 0, emptyTextRect?.width ?? 0)
    }

    func testEmptyTextCaretStartsAtMouseClickPoint() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let clickPoint = NSPoint(x: 180, y: 150)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: clickPoint)
        window.test_mouseUp(at: clickPoint)

        let contentOrigin = try XCTUnwrap(window.test_textEditorContentOrigin())
        let insertionRect = try XCTUnwrap(window.test_textEditorInsertionRect())
        let emptyTextRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertEqual(contentOrigin.x, clickPoint.x, accuracy: 0.1)
        XCTAssertEqual(insertionRect.minX, clickPoint.x, accuracy: 0.1)
        XCTAssertEqual(emptyTextRect.midY, clickPoint.y - selection.minY, accuracy: 0.1)
        XCTAssertEqual(
            emptyTextRect.minX,
            clickPoint.x - selection.minX - CaptureAnnotationRenderer.textHorizontalPadding,
            accuracy: 0.1
        )
        XCTAssertEqual(emptyTextRect.width, CaptureAnnotationRenderer.textHorizontalPadding * 2 + 1, accuracy: 0.1)
    }

    func testTextToolAcceptsInsertedTextFromAppKitTextInput() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        XCTAssertTrue(window.test_textEditorIsFirstResponder)
        window.firstResponder?.insertText("Hello")
        window.firstResponder?.insertText(NSAttributedString(string: " 输入"))
        window.test_commitTextEditing()

        XCTAssertFalse(window.test_isEditingTextAnnotation)
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "Hello 输入")
    }

    func testTextEditorDoesNotBreakMarkedTextReplacementRange() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let markedRange = editor.markedRange()
        XCTAssertEqual(editor.string, "ni")
        XCTAssertNotEqual(markedRange.location, NSNotFound)

        editor.insertText("你", replacementRange: markedRange)

        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "你")
        XCTAssertEqual(editor.selectedRange().location, editor.string.count)
    }

    func testTextEditorDirectImeCommitReplacesMarkedPinyin() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.setMarkedText("zhong guo", selectedRange: NSRange(location: 9, length: 0), replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(editor.string, "zhong guo")
        XCTAssertEqual(editor.markedRange().location, 0)
        XCTAssertEqual(editor.markedRange().length, 9)

        editor.insertText("中国")

        XCTAssertEqual(editor.string, "中国")
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "中国")
    }

    func testTextEditorKeepsMarkedTextTransparentWhileTyping() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        let marked = NSAttributedString(
            string: "zhong",
            attributes: [.foregroundColor: NSColor.white]
        )
        editor.setMarkedText(marked, selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: 0, length: 0))

        let color = try XCTUnwrap(editor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(color.alphaComponent, 0)
        XCTAssertTrue(window.test_textEditorUsesTransparentText)
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "zhong")
    }

    func testTextEditingLowersOverlayBelowInputCandidateWindows() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        XCTAssertLessThan(window.level.rawValue, NSWindow.Level.popUpMenu.rawValue)
        XCTAssertTrue(window.test_textEditorIsFirstResponder)
    }

    func testFirstTextInputKeepsTextSelectionFrameVisibleWhileEditing() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("第一段")

        let localRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let overlayRect = NSRect(
            x: selection.minX + localRect.minX,
            y: selection.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let framePixel = try firstPixel(in: image, rect: overlayRect.insetBy(dx: -2, dy: -2)) { pixel in
            pixel.red < 120 && pixel.green > 80 && pixel.blue > 180 && pixel.alpha > 120
        }

        XCTAssertNotNil(framePixel)
    }

    func testSelectedTextAnnotationUsesInputMoveResizeAndRotationCursorsInTextTool() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("Resize me")
        window.test_commitTextEditing()

        let textRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let bodyPoint = NSPoint(x: selection.minX + textRect.midX, y: selection.minY + textRect.midY)
        window.test_mouseDown(at: bodyPoint)
        window.test_mouseUp(at: bodyPoint)

        XCTAssertEqual(window.test_cursorStyle(at: bodyPoint), .textInput)

        let expected: [(SelectionToolbarState.OverlayResizeHandle, SelectionToolbarState.OverlayCursorStyle)] = [
            (.topLeft, .resizeTopLeft),
            (.top, .resizeUpDown),
            (.left, .resizeLeftRight),
            (.right, .resizeLeftRight),
            (.bottomLeft, .resizeBottomLeft),
            (.bottom, .resizeUpDown),
            (.bottomRight, .resizeBottomRight),
        ]
        for (handle, cursor) in expected {
            let point = try XCTUnwrap(window.test_shapeResizeHandlePoint(handle))
            XCTAssertEqual(window.test_cursorStyle(at: point), cursor)
        }
        let closePoint = try XCTUnwrap(window.test_shapeResizeHandlePoint(.topRight))
        XCTAssertEqual(window.test_cursorStyle(at: closePoint), .arrow)

        let borderPoint = NSPoint(x: selection.minX + textRect.minX + textRect.width * 0.25, y: selection.minY + textRect.minY)
        XCTAssertEqual(window.test_cursorStyle(at: borderPoint), .move)

        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        XCTAssertEqual(window.test_cursorStyle(at: rotationPoint), .rotationHandle)
    }

    func testDraggingTextBorderAtSelectionEdgeMovesTextNotSelection() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .text,
                rect: NSRect(x: 80, y: 0, width: 160, height: 36),
                style: CaptureAnnotationStyle(),
                text: "贴边文字"
            )
        ])
        window.test_selectAnnotation(at: 0)

        let beforeSelection = try XCTUnwrap(window.test_lockedSelectionRect)
        let beforeTextRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let borderPoint = NSPoint(
            x: selection.minX + beforeTextRect.minX + beforeTextRect.width * 0.25,
            y: selection.minY + beforeTextRect.minY
        )

        window.test_mouseDown(at: borderPoint)
        window.test_mouseDragged(to: NSPoint(x: borderPoint.x + 42, y: borderPoint.y + 18))
        window.test_mouseUp(at: NSPoint(x: borderPoint.x + 42, y: borderPoint.y + 18))

        let afterSelection = try XCTUnwrap(window.test_lockedSelectionRect)
        let afterTextRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertEqual(afterSelection, beforeSelection)
        XCTAssertNotEqual(afterTextRect.origin.x, beforeTextRect.origin.x)
        XCTAssertNotEqual(afterTextRect.origin.y, beforeTextRect.origin.y)
    }

    func testTextToolStillAllowsSelectionBorderResizeOnEveryEdge() throws {
        struct EdgeCase {
            let start: (NSRect) -> NSPoint
            let end: (NSRect) -> NSPoint
            let expectedCursor: SelectionToolbarState.OverlayCursorStyle
            let assertResized: (NSRect, NSRect) -> Void
        }

        let cases: [EdgeCase] = [
            EdgeCase(
                start: { NSPoint(x: $0.minX + 2, y: $0.midY) },
                end: { NSPoint(x: $0.minX - 34, y: $0.midY) },
                expectedCursor: .resizeLeftRight,
                assertResized: { before, after in
                    XCTAssertEqual(after.minX, before.minX - 34, accuracy: 0.5)
                    XCTAssertEqual(after.maxX, before.maxX, accuracy: 0.5)
                }
            ),
            EdgeCase(
                start: { NSPoint(x: $0.maxX - 2, y: $0.midY) },
                end: { NSPoint(x: $0.maxX + 34, y: $0.midY) },
                expectedCursor: .resizeLeftRight,
                assertResized: { before, after in
                    XCTAssertEqual(after.minX, before.minX, accuracy: 0.5)
                    XCTAssertEqual(after.maxX, before.maxX + 34, accuracy: 0.5)
                }
            ),
            EdgeCase(
                start: { NSPoint(x: $0.midX, y: $0.maxY - 2) },
                end: { NSPoint(x: $0.midX, y: $0.maxY + 34) },
                expectedCursor: .resizeUpDown,
                assertResized: { before, after in
                    XCTAssertEqual(after.minY, before.minY, accuracy: 0.5)
                    XCTAssertEqual(after.maxY, before.maxY + 34, accuracy: 0.5)
                }
            ),
            EdgeCase(
                start: { NSPoint(x: $0.midX, y: $0.minY + 2) },
                end: { NSPoint(x: $0.midX, y: $0.minY - 34) },
                expectedCursor: .resizeUpDown,
                assertResized: { before, after in
                    XCTAssertEqual(after.minY, before.minY - 34, accuracy: 0.5)
                    XCTAssertEqual(after.maxY, before.maxY, accuracy: 0.5)
                }
            ),
        ]

        for edgeCase in cases {
            let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
            let selection = NSRect(x: 100, y: 100, width: 220, height: 140)
            window.test_setLockedSelectionRect(selection)
            window.test_activateTextTool()

            let start = edgeCase.start(selection)
            XCTAssertEqual(window.test_cursorStyle(at: start), edgeCase.expectedCursor)

            window.test_mouseDown(at: start)
            window.test_mouseDragged(to: edgeCase.end(selection))
            window.test_mouseUp(at: edgeCase.end(selection))

            let resized = try XCTUnwrap(window.test_lockedSelectionRect)
            edgeCase.assertResized(selection, resized)
            XCTAssertEqual(window.test_annotationCount, 0)
        }
    }

    func testDraggingActiveTextEditorMovesTextNotSelectionAndEndsEditing() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 180, y: selection.minY + 40))
        window.test_mouseUp(at: NSPoint(x: 180, y: selection.minY + 40))
        window.firstResponder?.insertText("正在编辑")

        XCTAssertTrue(window.test_textEditorIsFirstResponder)
        let beforeSelection = try XCTUnwrap(window.test_lockedSelectionRect)
        let beforeTextRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let start = NSPoint(
            x: selection.minX + beforeTextRect.minX + beforeTextRect.width * 0.25,
            y: selection.minY + beforeTextRect.minY + beforeTextRect.height * 0.5
        )
        let end = NSPoint(x: start.x + 46, y: start.y + 22)

        window.test_textEditorDragSequence(from: start, to: end)

        let afterSelection = try XCTUnwrap(window.test_lockedSelectionRect)
        let afterTextRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertEqual(afterSelection, beforeSelection)
        XCTAssertFalse(window.test_textEditorIsFirstResponder)
        XCTAssertEqual(window.level, .floating)
        XCTAssertEqual(window.test_annotationText(at: 0), "正在编辑")
        XCTAssertNotEqual(afterTextRect.origin.x, beforeTextRect.origin.x)
        XCTAssertNotEqual(afterTextRect.origin.y, beforeTextRect.origin.y)
    }

    func testTextEditorDragKeepsEditorAliveBeforeDragStarts() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 180, y: selection.minY + 40))
        window.test_mouseUp(at: NSPoint(x: 180, y: selection.minY + 40))
        window.firstResponder?.insertText("正在拖动")

        XCTAssertTrue(window.test_textEditorIsFirstResponder)
        XCTAssertEqual(window.level, .floating)

        let textRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let start = NSPoint(
            x: selection.minX + textRect.midX,
            y: selection.minY + textRect.midY
        )
        window.test_textEditorMouseDown(at: start)

        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.test_textEditorIsFirstResponder)
        XCTAssertTrue(window.test_isEditingTextAnnotation)
    }

    func testTextEditorDragKeepsWindowLevelStable() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 180, y: selection.minY + 40))
        window.test_mouseUp(at: NSPoint(x: 180, y: selection.minY + 40))
        window.firstResponder?.insertText("拖动中")

        let textRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let start = NSPoint(
            x: selection.minX + textRect.midX,
            y: selection.minY + textRect.midY
        )
        let end = NSPoint(x: start.x + 30, y: start.y + 18)
        window.test_textEditorMouseDownAndDragged(
            from: start,
            to: end
        )

        XCTAssertEqual(window.level, .floating)

        window.test_mouseUp(at: end)

        XCTAssertEqual(window.level, .floating)
    }

    func testForwardedTextEditorDragContinuesAfterMoveStarts() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 180, y: selection.minY + 40))
        window.test_mouseUp(at: NSPoint(x: 180, y: selection.minY + 40))
        window.firstResponder?.insertText("连续拖动")

        let beforeTextRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let start = NSPoint(
            x: selection.minX + beforeTextRect.midX,
            y: selection.minY + beforeTextRect.midY
        )
        let mid = NSPoint(x: start.x + 18, y: start.y + 8)
        let end = NSPoint(x: start.x + 72, y: start.y + 26)

        window.test_textEditorMouseDown(at: start)
        window.test_textEditorMouseDragged(to: mid)
        window.test_textEditorMouseDragged(to: end)
        window.test_mouseUp(at: end)

        let afterTextRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertEqual(afterTextRect.minX, beforeTextRect.minX + 72, accuracy: 0.1)
        XCTAssertEqual(afterTextRect.minY, beforeTextRect.minY + 26, accuracy: 0.1)
        XCTAssertFalse(window.test_textEditorIsFirstResponder)
    }

    func testDraggingCommittedTextBodyWithTextToolMovesTextNotSelection() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 180, y: selection.minY + 40))
        window.test_mouseUp(at: NSPoint(x: 180, y: selection.minY + 40))
        window.firstResponder?.insertText("拖动文字")
        window.test_commitTextEditing()

        let beforeSelection = try XCTUnwrap(window.test_lockedSelectionRect)
        let beforeTextRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let start = NSPoint(
            x: selection.minX + beforeTextRect.midX,
            y: selection.minY + beforeTextRect.midY
        )
        let firstDragBelowThreshold = NSPoint(x: start.x + 1, y: start.y + 1)
        let end = NSPoint(x: start.x + 54, y: start.y + 24)

        window.test_mouseDown(at: start)
        window.test_mouseDragged(to: firstDragBelowThreshold)
        window.test_mouseDragged(to: end)
        window.test_mouseUp(at: end)

        let afterSelection = try XCTUnwrap(window.test_lockedSelectionRect)
        let afterTextRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertEqual(afterSelection, beforeSelection)
        XCTAssertFalse(window.test_isEditingTextAnnotation)
        XCTAssertEqual(window.test_annotationText(at: 0), "拖动文字")
        XCTAssertEqual(afterTextRect.minX, beforeTextRect.minX + 54, accuracy: 0.1)
        XCTAssertEqual(afterTextRect.minY, beforeTextRect.minY + 24, accuracy: 0.1)
    }

    func testClickingFinishedTextReopensEditorAndKeepsDragOnMoveGesture() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 180, y: selection.minY + 40))
        window.test_mouseUp(at: NSPoint(x: 180, y: selection.minY + 40))
        window.firstResponder?.insertText("已完成")
        window.test_commitTextEditing()

        let textRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let appendPoint = NSPoint(x: selection.minX + textRect.maxX - 2, y: selection.minY + textRect.midY)
        window.test_mouseDown(at: appendPoint)
        window.test_mouseUp(at: appendPoint)

        XCTAssertTrue(window.test_textEditorIsFirstResponder)
        XCTAssertEqual(window.test_annotationText(at: 0), "已完成")

        window.firstResponder?.insertText("x")

        XCTAssertEqual(window.test_annotationText(at: 0), "已完成x")

        let textRectAfterAppend = try XCTUnwrap(window.test_annotationRect(at: 0))
        let movedBodyPoint = NSPoint(x: selection.minX + textRectAfterAppend.midX, y: selection.minY + textRectAfterAppend.midY)
        let dragEnd = NSPoint(x: movedBodyPoint.x + 40, y: movedBodyPoint.y + 18)
        window.test_textEditorDragSequence(from: movedBodyPoint, to: dragEnd)

        let movedRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertFalse(window.test_textEditorIsFirstResponder)
        XCTAssertEqual(movedRect.minX, textRectAfterAppend.minX + 40, accuracy: 0.1)
        XCTAssertEqual(movedRect.minY, textRectAfterAppend.minY + 18, accuracy: 0.1)
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
    }

    func testClickingFinishedTextPlacesCaretAtClickedPositionForContinuedTyping() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 180, y: selection.minY + 40))
        window.test_mouseUp(at: NSPoint(x: 180, y: selection.minY + 40))
        window.firstResponder?.insertText("Hello")
        window.test_commitTextEditing()

        let textRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let leadingPoint = NSPoint(x: selection.minX + textRect.minX + 1, y: selection.minY + textRect.midY)
        window.test_mouseDown(at: leadingPoint)
        window.test_mouseUp(at: leadingPoint)

        XCTAssertTrue(window.test_textEditorIsFirstResponder)
        window.firstResponder?.insertText("X")

        XCTAssertEqual(window.test_annotationText(at: 0), "XHello")
    }

    func testTextAnnotationExpandsPastPreviousMeasureWidthWhileTyping() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 1_200, height: 260)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 120, y: 150))
        window.test_mouseUp(at: NSPoint(x: 120, y: 150))
        window.firstResponder?.insertText(String(repeating: "中国", count: 28))

        XCTAssertTrue(window.test_isEditingTextAnnotation)
        XCTAssertGreaterThan(window.test_annotationRect(at: 0)?.width ?? 0, 520)
        XCTAssertEqual((window.firstResponder as? NSTextView)?.selectedRange().location, (window.firstResponder as? NSTextView)?.string.count)
    }

    func testTextEditorReturnInsertsLineBreakInsteadOfCommitting() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 500, height: 300)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("第一行")
        window.firstResponder?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        window.firstResponder?.insertText("第二行")

        XCTAssertTrue(window.test_isEditingTextAnnotation)
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "第一行\n第二行")
        XCTAssertGreaterThan(window.test_annotationRect(at: 0)?.height ?? 0, 44)

        window.test_commitTextEditing()
        XCTAssertFalse(window.test_isEditingTextAnnotation)
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "第一行\n第二行")
    }

    func testTextEditorReceivesOrdinaryKeyEventsWhileEditing() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        XCTAssertTrue(window.test_textEditorIsFirstResponder)
        XCTAssertFalse(window.test_handleKeyDown(keyCode: 0, charactersIgnoringModifiers: "a"))
        XCTAssertTrue(window.test_isEditingTextAnnotation)
    }

    func testTextOptionsToolbarMatchesShapeToolbarHeightAndOrdersControls() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()

        XCTAssertEqual(window.test_optionsToolbarMode, .text)
        XCTAssertEqual(
            SelectionToolbarState.optionsToolbarHeight(paletteCount: 12, mode: .text),
            SelectionToolbarState.optionsToolbarHeight(paletteCount: 12, mode: .shape)
        )

        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)
        let layout = SelectionToolbarState.optionsToolbarLayout(in: optionsRect, paletteCount: 12, mode: .text)
        let firstSwatch = try XCTUnwrap(layout.colorSwatches.first)
        XCTAssertLessThan(layout.textBold.minX, layout.textItalic.minX)
        XCTAssertLessThan(layout.textItalic.minX, layout.textOutline.minX)
        XCTAssertLessThan(layout.textOutline.minX, layout.textFont.minX)
        XCTAssertLessThan(layout.textFont.minX, layout.textSize.minX)
        XCTAssertLessThan(layout.textSize.minX, firstSwatch.minX)
        XCTAssertEqual(layout.textFont.minX - layout.textOutline.maxX, 20)
        XCTAssertEqual(layout.textSize.minX - layout.textFont.maxX, 20)
        XCTAssertEqual(firstSwatch.minX - layout.textSize.maxX, 20)

        let originalColor = SelectionToolbarState.colorSamplerHexString(for: try XCTUnwrap(window.test_currentStyle?.strokeColor))
        XCTAssertEqual(originalColor, "#FF001A")

        let colorPoint = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 1))
        window.test_mouseDown(at: colorPoint)
        window.test_mouseUp(at: colorPoint)

        XCTAssertNotEqual(SelectionToolbarState.colorSamplerHexString(for: try XCTUnwrap(window.test_currentStyle?.strokeColor)), originalColor)
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: try XCTUnwrap(window.test_currentStyle?.strokeColor)), "#8A8A8A")
    }

    func testTextToolDefaultsToOutlineAndShowsTextOptionTooltips() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()

        let style = try XCTUnwrap(window.test_currentStyle)
        XCTAssertTrue(style.textOutlineEnabled)
        XCTAssertEqual(style.textSize, 8)
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#FF001A")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "textBold"), "加粗")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "textItalic"), "斜体")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "textOutline"), "描边")

        let boldPoint = try XCTUnwrap(window.test_optionsTextBoldPoint())
        window.test_mouseMoved(to: boldPoint)
        XCTAssertEqual(window.test_hoveredTooltipText, "加粗")

        let italicPoint = try XCTUnwrap(window.test_optionsTextItalicPoint())
        window.test_mouseMoved(to: italicPoint)
        XCTAssertEqual(window.test_hoveredTooltipText, "斜体")

        let outlinePoint = try XCTUnwrap(window.test_optionsTextOutlinePoint())
        window.test_mouseMoved(to: outlinePoint)
        XCTAssertEqual(window.test_hoveredTooltipText, "描边")
    }

    func testTextSizeUsesScreenshotAnnotationDisplayScale() {
        var style = CaptureAnnotationStyle()
        style.textSize = 15

        XCTAssertGreaterThanOrEqual(CaptureAnnotationRenderer.textFont(style: style).pointSize, 44)
    }

    func testTextItalicStyleUsesItalicFontTrait() throws {
        var style = CaptureAnnotationStyle()
        style.textSize = 12
        style.textItalic = true

        let attributes = CaptureAnnotationRenderer.textAttributes(style: style)
        let font = CaptureAnnotationRenderer.textFont(style: style)
        let obliqueness = try XCTUnwrap(attributes[.obliqueness] as? CGFloat)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
        XCTAssertGreaterThan(obliqueness, 0)
    }

    func testTextAnnotationHeightTracksRenderedTextBounds() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 360, height: 240)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("这是")

        let style = try XCTUnwrap(window.test_annotationStyle(at: 0))
        let measured = NSAttributedString(
            string: "这是",
            attributes: CaptureAnnotationRenderer.textAttributes(style: style)
        ).boundingRect(
            with: NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let rect = try XCTUnwrap(window.test_annotationRect(at: 0))

        XCTAssertGreaterThanOrEqual(rect.height, ceil(measured.height))
    }

    func testLongTextAnnotationDoesNotWrapWhenDrawnInNarrowRect() {
        var style = CaptureAnnotationStyle()
        style.textSize = 72
        let text = "这是一段很长很长的文字用于验证文本框缩小后不会换行吞字"
        let measured = NSAttributedString(
            string: text,
            attributes: CaptureAnnotationRenderer.textAttributes(style: style)
        ).boundingRect(
            with: NSSize(width: 80, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        XCTAssertLessThanOrEqual(ceil(measured.height), CaptureAnnotationRenderer.textLineHeight(style: style) + 1)
    }

    func testEditingTextAnnotationDrawsLiveOutlinedEffectInOverlay() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("重影")

        let localRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let overlayRect = NSRect(
            x: selection.minX + localRect.minX,
            y: selection.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        ).insetBy(dx: -8, dy: -8)
        let image = try XCTUnwrap(window.test_renderedOverlayImage())

        let redTextPixel = try firstPixel(in: image, rect: overlayRect) { pixel in
            pixel.red > 180 && pixel.green < 120 && pixel.blue < 120 && pixel.alpha > 80
        }
        let outlinePixel = try firstPixel(in: image, rect: overlayRect) { pixel in
            pixel.red > 230 && pixel.green > 230 && pixel.blue > 230 && pixel.alpha > 80
        }
        let redFillPixels = try matchingPixelCount(in: image, rect: overlayRect) { pixel in
            pixel.red > 200 && pixel.green < 80 && pixel.blue < 80 && pixel.alpha > 120
        }
        XCTAssertNotNil(redTextPixel)
        XCTAssertNotNil(outlinePixel)
        XCTAssertGreaterThan(redFillPixels, 240)
        XCTAssertTrue(window.test_textEditorUsesTransparentText)
    }

    func testArialHebrewTextAnnotationHeightFitsRenderedBounds() throws {
        guard NSFontManager.shared.availableFontFamilies.contains("Arial Hebrew") else {
            throw XCTSkip("Arial Hebrew is not available on this machine")
        }

        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 360, height: 240)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_selectTextFont("Arial Hebrew")

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("Arial Hebrew")

        let style = try XCTUnwrap(window.test_annotationStyle(at: 0))
        let measured = NSAttributedString(
            string: "Arial Hebrew",
            attributes: CaptureAnnotationRenderer.textAttributes(style: style)
        ).boundingRect(
            with: NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let rect = try XCTUnwrap(window.test_annotationRect(at: 0))

        XCTAssertGreaterThanOrEqual(rect.height, ceil(measured.height))
    }

    func testTextDropdownsAreEmbeddedAndScrollable() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 420, height: 260))
        window.test_activateTextTool()

        XCTAssertEqual(SelectionToolbarState.textDropdownBackgroundColor, NSColor.white)
        XCTAssertEqual(SelectionToolbarState.textDropdownScrollbarTrackColor, NSColor.black.withAlphaComponent(0.14))
        XCTAssertEqual(SelectionToolbarState.textDropdownScrollbarThumbColor, NSColor.black.withAlphaComponent(0.46))

        let fontPoint = try XCTUnwrap(window.test_optionsTextFontPoint())
        window.test_mouseDown(at: fontPoint)
        window.test_mouseUp(at: fontPoint)
        let fontDropdown = try XCTUnwrap(window.test_textDropdownRect)
        XCTAssertTrue(window.test_isTextFontDropdownVisible)
        XCTAssertLessThan(fontDropdown.height, CGFloat(window.test_textFontOptions.count) * 22)
        XCTAssertTrue(fontDropdown.height <= 184)

        let before = window.test_textDropdownScrollOffset
        window.test_scrollWheel(at: NSPoint(x: fontDropdown.midX, y: fontDropdown.midY), deltaY: -18)
        XCTAssertGreaterThan(window.test_textDropdownScrollOffset, before)

        let sizePoint = try XCTUnwrap(window.test_optionsTextSizePoint())
        window.test_mouseDown(at: sizePoint)
        window.test_mouseUp(at: sizePoint)
        let sizeDropdown = try XCTUnwrap(window.test_textDropdownRect)
        XCTAssertTrue(window.test_isTextSizeDropdownVisible)
        XCTAssertLessThan(sizeDropdown.height, CGFloat(window.test_textSizeOptionsCount) * 22)
        XCTAssertTrue(sizeDropdown.height <= 184)
    }

    func testTextOptionsToolbarAppliesFontSizeFamilyBoldItalicAndOutline() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 360, height: 240)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        XCTAssertEqual(window.test_textSizeOptions.first, 3)
        XCTAssertEqual(window.test_textSizeOptions.last, 72)
        XCTAssertEqual(window.test_textSizeOptionsCount, 70)
        XCTAssertTrue(window.test_textFontOptions.contains(NSFont.systemFont(ofSize: 12).familyName ?? ".AppleSystemUIFont"))

        window.test_selectTextSize(48)
        window.test_selectTextFont(NSFont.systemFont(ofSize: 12).familyName ?? ".AppleSystemUIFont")
        window.test_mouseDown(at: try XCTUnwrap(window.test_optionsTextBoldPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_optionsTextBoldPoint()))
        window.test_mouseDown(at: try XCTUnwrap(window.test_optionsTextItalicPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_optionsTextItalicPoint()))

        window.test_mouseDown(at: NSPoint(x: selection.minX + 40, y: selection.minY + 50))
        window.test_mouseUp(at: NSPoint(x: selection.minX + 40, y: selection.minY + 50))
        for character in "Styled" {
            window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: String(character))
        }
        window.test_keyDown(keyCode: 36, charactersIgnoringModifiers: "\r")

        let style = try XCTUnwrap(window.test_annotationStyle(at: 0))
        XCTAssertEqual(style.textSize, 48)
        XCTAssertTrue(style.textBold)
        XCTAssertTrue(style.textItalic)
        XCTAssertTrue(style.textOutlineEnabled)
        XCTAssertNotNil(style.textFontFamily)

        let attributes = CaptureAnnotationRenderer.textAttributes(style: style)
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        XCTAssertGreaterThanOrEqual(font.pointSize, 47)
        XCTAssertNotNil(attributes[.strokeColor])
        XCTAssertEqual(attributes[.strokeWidth] as? CGFloat, -6)
        XCTAssertNil(attributes[.shadow])
    }

    func testTextFontDropdownDisplayNamesLocalizeChineseFontsOnly() {
        XCTAssertEqual(SelectionToolbarState.textFontDisplayName(for: "PingFang SC"), "苹方-简")
        XCTAssertEqual(SelectionToolbarState.textFontDisplayName(for: "Songti SC"), "宋体-简")
        XCTAssertEqual(SelectionToolbarState.textFontDisplayName(for: "Helvetica Neue"), "Helvetica Neue")
    }

    func testTextFontFamiliesPrioritizeChineseFontsForChinesePreferredLanguage() {
        let sorted = SelectionToolbarState.sortedTextFontFamilies(
            ["Helvetica Neue", "Songti SC", "Arial", "PingFang SC", "Times New Roman"],
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(Array(sorted.prefix(2)), ["PingFang SC", "Songti SC"])
        XCTAssertEqual(Array(sorted.suffix(3)), ["Arial", "Helvetica Neue", "Times New Roman"])
    }

    func testTextFontFamiliesKeepAlphabeticalOrderForNonChinesePreferredLanguage() {
        let sorted = SelectionToolbarState.sortedTextFontFamilies(
            ["Helvetica Neue", "Songti SC", "Arial", "PingFang SC", "Times New Roman"],
            preferredLanguages: ["en-US"]
        )

        XCTAssertEqual(sorted, ["Arial", "Helvetica Neue", "Times New Roman", "PingFang SC", "Songti SC"])
    }

    func testTextAnnotationResizeScalesFontSizeProportionally() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 360, height: 240)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("Scale")
        window.test_commitTextEditing()

        let originalRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let originalStyle = try XCTUnwrap(window.test_annotationStyle(at: 0))
        let resizePoint = try XCTUnwrap(window.test_shapeResizeHandlePoint(.bottomRight))

        window.test_mouseDown(at: resizePoint)
        window.test_mouseDragged(to: NSPoint(x: resizePoint.x + originalRect.width * 0.5, y: resizePoint.y - originalRect.height * 0.5))
        window.test_mouseUp(at: NSPoint(x: resizePoint.x + originalRect.width * 0.5, y: resizePoint.y - originalRect.height * 0.5))

        let resizedRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let resizedStyle = try XCTUnwrap(window.test_annotationStyle(at: 0))
        let expectedSize = expectedTextAnnotationSize(text: "Scale", style: resizedStyle)
        XCTAssertGreaterThan(resizedRect.width, originalRect.width)
        XCTAssertGreaterThan(resizedRect.height, originalRect.height)
        XCTAssertEqual(resizedRect.midX, originalRect.midX, accuracy: 0.1)
        XCTAssertEqual(resizedRect.midY, originalRect.midY, accuracy: 0.1)
        XCTAssertEqual(resizedRect.width, expectedSize.width, accuracy: 1.0)
        XCTAssertEqual(resizedRect.height, expectedSize.height, accuracy: 1.0)
        XCTAssertGreaterThan(resizedStyle.textSize, originalStyle.textSize)
    }

    func testTextAnnotationCornerResizeScalesAroundCenterAndUsesLongestLineWidth() throws {
        struct CornerCase {
            let handle: SelectionToolbarState.OverlayResizeHandle
            let drag: (NSRect) -> NSSize
        }

        let text = "短\nLongest line"
        let cases: [CornerCase] = [
            CornerCase(handle: .topLeft, drag: { NSSize(width: -$0.width * 0.5, height: $0.height * 0.5) }),
            CornerCase(handle: .bottomLeft, drag: { NSSize(width: -$0.width * 0.5, height: -$0.height * 0.5) }),
            CornerCase(handle: .bottomRight, drag: { NSSize(width: $0.width * 0.5, height: -$0.height * 0.5) }),
        ]

        for cornerCase in cases {
            let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
            let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
            var style = CaptureAnnotationStyle()
            style.textSize = 24
            let tightSize = expectedTextAnnotationSize(text: text, style: style)
            let looseRect = NSRect(x: 56, y: 64, width: tightSize.width + 120, height: tightSize.height)
            window.test_setLockedSelectionRect(selection)
            window.test_activateTextTool()
            window.test_setAnnotations([
                CaptureAnnotation(kind: .text, rect: looseRect, style: style, text: text)
            ])
            window.test_selectAnnotation(at: 0)

            let before = try XCTUnwrap(window.test_annotationRect(at: 0))
            let start = try XCTUnwrap(window.test_shapeResizeHandlePoint(cornerCase.handle))
            let drag = cornerCase.drag(before)
            let end = NSPoint(x: start.x + drag.width, y: start.y + drag.height)

            window.test_mouseDown(at: start)
            window.test_mouseDragged(to: end)
            window.test_mouseUp(at: end)

            let after = try XCTUnwrap(window.test_annotationRect(at: 0))
            let afterStyle = try XCTUnwrap(window.test_annotationStyle(at: 0))
            let expectedSize = expectedTextAnnotationSize(text: text, style: afterStyle)

            XCTAssertEqual(after.midX, before.midX, accuracy: 0.1)
            XCTAssertEqual(after.midY, before.midY, accuracy: 0.1)
            XCTAssertGreaterThan(afterStyle.textSize, style.textSize)
            XCTAssertEqual(after.width, expectedSize.width, accuracy: 1.0)
            XCTAssertEqual(after.height, expectedSize.height, accuracy: 1.0)
            XCTAssertLessThan(after.width, before.width * 1.5)
        }
    }

    func testTextAnnotationCornerResizeClampsFontSizeToDropdownRange() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        var style = CaptureAnnotationStyle()
        style.textSize = 70
        let text = "Clamp"
        let size = expectedTextAnnotationSize(text: text, style: style)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(kind: .text, rect: NSRect(x: 80, y: 90, width: size.width, height: size.height), style: style, text: text)
        ])
        window.test_selectAnnotation(at: 0)

        let before = try XCTUnwrap(window.test_annotationRect(at: 0))
        let start = try XCTUnwrap(window.test_shapeResizeHandlePoint(.bottomRight))
        let end = NSPoint(x: start.x + before.width * 2, y: start.y - before.height * 2)
        window.test_mouseDown(at: start)
        window.test_mouseDragged(to: end)
        window.test_mouseUp(at: end)

        let afterStyle = try XCTUnwrap(window.test_annotationStyle(at: 0))
        XCTAssertEqual(afterStyle.textSize, SelectionToolbarState.textSizeValues.last)
    }

    func testFullscreenTextAnnotationCanShrinkProportionallyFromEveryEdge() throws {
        struct EdgeCase {
            let start: (NSRect) -> NSPoint
            let end: (NSRect) -> NSPoint
            let expectedCursor: SelectionToolbarState.OverlayCursorStyle
        }

        let cases: [EdgeCase] = [
            EdgeCase(
                start: { NSPoint(x: $0.minX + $0.width * 0.25, y: $0.maxY - 1) },
                end: { NSPoint(x: $0.minX + $0.width * 0.25, y: $0.maxY - 64) },
                expectedCursor: .resizeUpDown
            ),
            EdgeCase(
                start: { NSPoint(x: $0.maxX - 1, y: $0.minY + $0.height * 0.25) },
                end: { NSPoint(x: $0.maxX - 64, y: $0.minY + $0.height * 0.25) },
                expectedCursor: .resizeLeftRight
            ),
            EdgeCase(
                start: { NSPoint(x: $0.minX + $0.width * 0.75, y: $0.minY + 1) },
                end: { NSPoint(x: $0.minX + $0.width * 0.75, y: $0.minY + 64) },
                expectedCursor: .resizeUpDown
            ),
            EdgeCase(
                start: { NSPoint(x: $0.minX + 1, y: $0.minY + $0.height * 0.75) },
                end: { NSPoint(x: $0.minX + 64, y: $0.minY + $0.height * 0.75) },
                expectedCursor: .resizeLeftRight
            ),
        ]

        for edgeCase in cases {
            let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
            let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
            window.test_setLockedSelectionRect(selection)
            window.test_activateTextTool()
            var style = CaptureAnnotationStyle()
            style.textSize = 72
            window.test_setAnnotations([
                CaptureAnnotation(
                    kind: .text,
                    rect: NSRect(origin: .zero, size: selection.size),
                    style: style,
                    text: "全屏文字"
                )
            ])
            window.test_selectAnnotation(at: 0)

            let before = try XCTUnwrap(window.test_annotationRect(at: 0))
            let start = edgeCase.start(selection)
            let end = edgeCase.end(selection)
            XCTAssertEqual(window.test_cursorStyle(at: start), edgeCase.expectedCursor)

            window.test_mouseDown(at: start)
            window.test_mouseDragged(to: end)
            window.test_mouseUp(at: end)

            let after = try XCTUnwrap(window.test_annotationRect(at: 0))
            XCTAssertLessThan(after.width, before.width)
            XCTAssertLessThan(after.height, before.height)
            XCTAssertEqual(after.width / after.height, before.width / before.height, accuracy: 0.02)
            XCTAssertEqual(after.midX, before.midX, accuracy: 0.1)
            XCTAssertEqual(after.midY, before.midY, accuracy: 0.1)
            XCTAssertGreaterThan(after.minX, before.minX)
            XCTAssertLessThan(after.maxX, before.maxX)
            XCTAssertGreaterThan(after.minY, before.minY)
            XCTAssertLessThan(after.maxY, before.maxY)
        }
    }

    func testTextAnnotationCanRotateWithMosaicRotationHandle() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 240))
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("Rotate")
        window.test_commitTextEditing()

        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 32, y: rotationPoint.y + 24))
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 32, y: rotationPoint.y + 24))

        XCTAssertGreaterThan(abs(window.test_annotationRotationAngle(at: 0) ?? 0), 0.05)
        XCTAssertEqual(window.test_mosaicRectangleRotationHandleGlyph(), .refreshDot)
    }

    func testRotatedTextAnnotationReopensEditorWithRotatedCaretAndAccurateInsertionPoint() throws {
        struct RotationCase {
            let angle: CGFloat
            let expectedDegrees: CGFloat
        }

        let cases: [RotationCase] = [
            RotationCase(angle: .pi / 2, expectedDegrees: 90),
            RotationCase(angle: .pi, expectedDegrees: 180),
        ]

        for rotationCase in cases {
            let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
            let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
            var style = CaptureAnnotationStyle()
            style.textSize = 24
            let text = "AB"
            let size = expectedTextAnnotationSize(text: text, style: style)
            let rect = NSRect(x: 140, y: 90, width: size.width, height: size.height)
            let clickPoint = rotatedPoint(
                NSPoint(
                    x: selection.minX + rect.minX + CaptureAnnotationRenderer.textHorizontalPadding + measuredTextWidth("A", style: style),
                    y: selection.minY + rect.midY
                ),
                around: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY),
                angle: rotationCase.angle
            )

            window.test_setLockedSelectionRect(selection)
            window.test_activateTextTool()
            window.test_setAnnotations([
                CaptureAnnotation(
                    kind: .text,
                    rect: rect,
                    style: style,
                    rotationAngle: rotationCase.angle,
                    text: text
                )
            ])
            window.test_selectAnnotation(at: 0)

            window.test_mouseDown(at: clickPoint)
            window.test_mouseUp(at: clickPoint)

            XCTAssertTrue(window.test_isEditingTextAnnotation)
            XCTAssertEqual(window.test_textEditorFrameCenterRotation() ?? 0, rotationCase.expectedDegrees, accuracy: 0.1)
            XCTAssertEqual(window.test_textEditorSelectedRange()?.location, 1)
            XCTAssertTrue(window.test_textEditorIsFirstResponder)
            window.firstResponder?.insertText("X")
            window.test_commitTextEditing()
            XCTAssertEqual(window.test_annotationText(at: 0), "AXB")
        }
    }

    func testRotatedTextAnnotationDrawsBlackEditingCaretInsideRotatedFrame() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        var style = CaptureAnnotationStyle()
        style.textSize = 24
        style.strokeColor = .systemRed
        let rect = NSRect(
            x: 140,
            y: 90,
            width: CaptureAnnotationRenderer.textHorizontalPadding * 2 + 1,
            height: CaptureAnnotationRenderer.textLineHeight(style: style)
        )
        let overlayRect = NSRect(
            x: selection.minX + rect.minX,
            y: selection.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        let center = NSPoint(x: overlayRect.midX, y: overlayRect.midY)
        let rotatedBounds = boundingRect(
            of: [
                NSPoint(x: overlayRect.minX, y: overlayRect.minY),
                NSPoint(x: overlayRect.maxX, y: overlayRect.minY),
                NSPoint(x: overlayRect.maxX, y: overlayRect.maxY),
                NSPoint(x: overlayRect.minX, y: overlayRect.maxY),
            ].map { rotatedPoint($0, around: center, angle: .pi / 2) }
        )

        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .text,
                rect: rect,
                style: style,
                rotationAngle: .pi / 2,
                text: ""
            )
        ])
        window.test_selectAnnotation(at: 0)
        window.test_mouseDown(at: center)
        window.test_mouseUp(at: center)

        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let caretPixel = try firstPixel(in: image, rect: rotatedBounds.insetBy(dx: -1, dy: -1)) { pixel in
            pixel.red < 80 && pixel.green < 80 && pixel.blue < 80 && pixel.alpha > 120
        }
        XCTAssertNotNil(caretPixel)
    }

    func testTextAnnotationDrawsWhiteEditingCaretOnBlackBackground() throws {
        let background = solidImage(size: NSSize(width: 500, height: 400), color: .black)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 320, height: 220)
        var style = CaptureAnnotationStyle()
        style.textSize = 24
        let rect = NSRect(
            x: 120,
            y: 90,
            width: CaptureAnnotationRenderer.textHorizontalPadding * 2 + 1,
            height: CaptureAnnotationRenderer.textLineHeight(style: style)
        )
        let overlayRect = NSRect(
            x: selection.minX + rect.minX,
            y: selection.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )

        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .text,
                rect: rect,
                style: style,
                text: ""
            )
        ])
        window.test_selectAnnotation(at: 0)
        window.test_mouseDown(at: NSPoint(x: overlayRect.midX, y: overlayRect.midY))
        window.test_mouseUp(at: NSPoint(x: overlayRect.midX, y: overlayRect.midY))

        let caretColor = try XCTUnwrap(window.test_editingTextCaretColor()?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(caretColor.redComponent, 0.9)
        XCTAssertGreaterThan(caretColor.greenComponent, 0.9)
        XCTAssertGreaterThan(caretColor.blueComponent, 0.9)
        let insertionRect = try XCTUnwrap(window.test_editingTextCaretDrawRect())
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let caretPixel = try XCTUnwrap(firstPixel(
            in: image,
            rect: insertionRect.insetBy(dx: -1, dy: -1)
        ) { pixel in
            pixel.red > 220 && pixel.green > 220 && pixel.blue > 220 && pixel.alpha > 120
        })
        XCTAssertGreaterThan(caretPixel.red, 220)
        XCTAssertGreaterThan(caretPixel.green, 220)
        XCTAssertGreaterThan(caretPixel.blue, 220)
        XCTAssertGreaterThan(caretPixel.alpha, 120)
    }

    func testTextAnnotationUsesOverallSelectionBrightnessForCaretColor() throws {
        let selection = NSRect(x: 100, y: 100, width: 320, height: 220)
        var style = CaptureAnnotationStyle()
        style.textSize = 24
        let rect = NSRect(
            x: 120,
            y: 90,
            width: CaptureAnnotationRenderer.textHorizontalPadding * 2 + 1,
            height: CaptureAnnotationRenderer.textLineHeight(style: style)
        )
        let overlayRect = NSRect(
            x: selection.minX + rect.minX,
            y: selection.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        let background = blackImageWithWhitePatch(
            size: NSSize(width: 500, height: 400),
            centeredAt: NSPoint(x: overlayRect.midX, y: overlayRect.midY),
            patchSize: NSSize(width: 48, height: 48)
        )
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }

        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .text,
                rect: rect,
                style: style,
                text: ""
            )
        ])
        window.test_selectAnnotation(at: 0)
        window.test_mouseDown(at: NSPoint(x: overlayRect.midX, y: overlayRect.midY))
        window.test_mouseUp(at: NSPoint(x: overlayRect.midX, y: overlayRect.midY))

        let caretColor = try XCTUnwrap(window.test_editingTextCaretColor()?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(caretColor.redComponent, 0.9)
        XCTAssertGreaterThan(caretColor.greenComponent, 0.9)
        XCTAssertGreaterThan(caretColor.blueComponent, 0.9)
    }

    func testRotatedTextAnnotationKeepsLineBreaksAtSelectedInsertionPoints() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 620, height: 420)
        var style = CaptureAnnotationStyle()
        style.textSize = 24
        let original = "阿斯顿发送里看见水电费水地方水电费水电费短发的沙发"
        let size = expectedTextAnnotationSize(text: original, style: style)
        let rect = NSRect(x: 80, y: 140, width: size.width, height: size.height)

        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .text,
                rect: rect,
                style: style,
                rotationAngle: .pi / 2,
                text: original
            )
        ])
        window.test_selectAnnotation(at: 0)
        window.test_mouseDown(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))
        window.test_mouseUp(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        editor.insertText("第一段")
        editor.setSelectedRange(NSRange(location: 16, length: 0))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        editor.insertText("第二段")

        XCTAssertEqual(window.test_annotationText(at: 0), "阿斯顿发送\n第一段里看见水电费水\n第二段地方水电费水电费短发的沙发")
        window.test_commitTextEditing()
        XCTAssertEqual(window.test_annotationText(at: 0)?.components(separatedBy: "\n").filter(\.isEmpty).count, 0)
    }

    func testRotatedTextAnnotationClickingDifferentLinesKeepsReturnInsertionStable() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 2_000, height: 900)
        var style = CaptureAnnotationStyle()
        style.textSize = 24
        let original = "阿斯顿发送里看见水电费水地方水电费水电费短发的沙发"
        let size = expectedTextAnnotationSize(text: original, style: style)
        let rect = NSRect(x: 140, y: 220, width: size.width, height: size.height)

        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .text,
                rect: rect,
                style: style,
                rotationAngle: .pi / 2,
                text: original
            )
        ])
        window.test_selectAnnotation(at: 0)
        window.test_mouseDown(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))
        window.test_mouseUp(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))

        try clickTextInsertionPoint(in: window, annotationIndex: 0, characterIndex: 5)
        window.firstResponder?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        window.firstResponder?.insertText("第一段")
        try clickTextInsertionPoint(in: window, annotationIndex: 0, characterIndex: 16)
        window.firstResponder?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        window.firstResponder?.insertText("第二段")

        XCTAssertEqual(window.test_annotationText(at: 0), "阿斯顿发送\n第一段里看见水电费水\n第二段地方水电费水电费短发的沙发")
        XCTAssertEqual(window.test_annotationText(at: 0)?.components(separatedBy: "\n").filter(\.isEmpty).count, 0)
    }

    func testTextAnnotationReturnShrinksToLongestLineAndMovesCaretToNextLineStart() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 900, height: 500)
        var style = CaptureAnnotationStyle()
        style.textSize = 24
        let original = "阿斯顿发送里看见水电费水地方水电费水电费短发的沙发"
        let size = expectedTextAnnotationSize(text: original, style: style)
        let rect = NSRect(x: 120, y: 180, width: size.width, height: size.height)

        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .text,
                rect: rect,
                style: style,
                text: original
            )
        ])
        window.test_selectAnnotation(at: 0)
        window.test_mouseDown(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))
        window.test_mouseUp(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        let updatedRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let insertionRect = try XCTUnwrap(window.test_textEditorInsertionRect())
        let contentOrigin = try XCTUnwrap(window.test_textEditorContentOrigin())
        XCTAssertEqual(window.test_annotationText(at: 0), "阿斯顿发送里看见水电\n费水地方水电费水电费短发的沙发")
        XCTAssertEqual(window.test_textEditorSelectedRange()?.location, 11)
        let expectedSize = expectedTextAnnotationSize(
            text: "阿斯顿发送里看见水电\n费水地方水电费水电费短发的沙发",
            style: style
        )
        XCTAssertEqual(updatedRect.width, expectedSize.width, accuracy: 1)
        XCTAssertLessThan(updatedRect.width, rect.width)
        XCTAssertGreaterThan(updatedRect.height, rect.height)
        XCTAssertLessThanOrEqual(updatedRect.height, rect.height * 2)
        XCTAssertEqual(insertionRect.minX, contentOrigin.x, accuracy: 2)
    }

    func testTextEditingFallbackReturnUsesCurrentCaretInsteadOfAppending() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 1_400, height: 500)
        var style = CaptureAnnotationStyle()
        style.textSize = 24
        let original = "阿斯顿发送里看见水电费水地方水电费水电费短发的沙发"
        let size = expectedTextAnnotationSize(text: original, style: style)
        let rect = NSRect(x: 120, y: 180, width: size.width, height: size.height)

        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .text,
                rect: rect,
                style: style,
                text: original
            )
        ])
        window.test_selectAnnotation(at: 0)
        window.test_mouseDown(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))
        window.test_mouseUp(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        window.makeFirstResponder(window.contentView)

        XCTAssertTrue(window.test_handleKeyDown(keyCode: 36, charactersIgnoringModifiers: "\r"))

        XCTAssertEqual(window.test_annotationText(at: 0), "阿斯顿发送里看见水电\n费水地方水电费水电费短发的沙发")
        XCTAssertEqual((editor.string as NSString).length, (window.test_annotationText(at: 0)! as NSString).length)
        XCTAssertEqual(editor.selectedRange().location, 11)
    }

    func testTextEditingFallbackReturnKeepsTwoLineParagraphCompact() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 700, height: 500)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 180, y: 420))
        window.test_mouseUp(at: NSPoint(x: 180, y: 420))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.insertText("中", replacementRange: editor.selectedRange())
        editor.insertText("华", replacementRange: editor.selectedRange())
        window.makeFirstResponder(window.contentView)
        window.test_keyDown(keyCode: 36, charactersIgnoringModifiers: "\r")
        for character in "人民共和国" {
            window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: String(character))
        }

        let text = try XCTUnwrap(window.test_annotationText(at: 0))
        XCTAssertEqual(text, "中华\n人民共和国")
        XCTAssertEqual(text.filter(\.isNewline).count, 1)
        XCTAssertEqual((editor.string as NSString).length, 8)
        XCTAssertEqual(editor.selectedRange().location, 8)

        let rect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let lineHeight = CaptureAnnotationRenderer.textLineHeight(style: window.test_annotationStyle(at: 0)!)
        XCTAssertGreaterThan(rect.height, lineHeight)
        XCTAssertLessThanOrEqual(rect.height, lineHeight * 2 + 2)
    }

    func testTextEditingFallbackArrowKeysMoveCaretInsideMultilineText() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 700, height: 500)
        var style = CaptureAnnotationStyle()
        style.textSize = 24
        let text = "中华\n人民共和国"
        let size = expectedTextAnnotationSize(text: text, style: style)
        let rect = NSRect(x: 120, y: 260, width: size.width, height: size.height)

        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(kind: .text, rect: rect, style: style, text: text)
        ])
        window.test_selectAnnotation(at: 0)
        window.test_mouseDown(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))
        window.test_mouseUp(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        window.makeFirstResponder(window.contentView)

        XCTAssertTrue(window.test_handleKeyDown(keyCode: 123, charactersIgnoringModifiers: ""))
        XCTAssertEqual(editor.selectedRange().location, 7)

        window.makeFirstResponder(window.contentView)
        XCTAssertTrue(window.test_handleKeyDown(keyCode: 126, charactersIgnoringModifiers: ""))
        XCTAssertLessThan(editor.selectedRange().location, 3)

        XCTAssertEqual(window.test_annotationText(at: 0), text)
    }

    func testTextClickBeforeLastCharacterInsertsReturnAtClickedCharacter() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 900, height: 500)
        var style = CaptureAnnotationStyle()
        style.textSize = 36
        let text = "中华人民共和国"
        let size = expectedTextAnnotationSize(text: text, style: style)
        let rect = NSRect(x: 120, y: 260, width: size.width, height: size.height)

        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(kind: .text, rect: rect, style: style, text: text)
        ])
        window.test_selectAnnotation(at: 0)

        let prefixBeforeLastCharacter = "中华人民共和"
        let clickPoint = NSPoint(
            x: selection.minX + rect.minX + CaptureAnnotationRenderer.textHorizontalPadding + measuredTextWidth(prefixBeforeLastCharacter, style: style),
            y: selection.minY + rect.midY
        )
        window.test_mouseDown(at: clickPoint)
        window.test_mouseUp(at: clickPoint)

        XCTAssertEqual(window.test_textEditorSelectedRange()?.location, 6)
        window.firstResponder?.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(window.test_annotationText(at: 0), "中华人民共和\n国")
        XCTAssertEqual(window.test_annotationText(at: 0)?.filter(\.isNewline).count, 1)
        let updatedRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let expectedSize = expectedTextAnnotationSize(text: "中华人民共和\n国", style: style)
        XCTAssertEqual(updatedRect.width, expectedSize.width, accuracy: 1)
        XCTAssertLessThan(updatedRect.width, rect.width)
    }

    func testTextArrowKeysMoveCaretInVisualDirectionForMultilineText() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 700, height: 500)
        var style = CaptureAnnotationStyle()
        style.textSize = 36
        let text = "中华\n人民共和国"
        let size = expectedTextAnnotationSize(text: text, style: style)
        let rect = NSRect(x: 120, y: 260, width: size.width, height: size.height)

        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()
        window.test_setAnnotations([
            CaptureAnnotation(kind: .text, rect: rect, style: style, text: text)
        ])
        window.test_selectAnnotation(at: 0)
        window.test_mouseDown(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))
        window.test_mouseUp(at: NSPoint(x: selection.minX + rect.midX, y: selection.minY + rect.midY))

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        let endCaret = try XCTUnwrap(window.test_textEditorInsertionRect())

        window.makeFirstResponder(window.contentView)
        XCTAssertTrue(window.test_handleKeyDown(keyCode: 123, charactersIgnoringModifiers: ""))
        let leftCaret = try XCTUnwrap(window.test_textEditorInsertionRect())
        XCTAssertLessThan(leftCaret.midX, endCaret.midX)

        editor.setSelectedRange(NSRange(location: 8, length: 0))
        window.makeFirstResponder(window.contentView)
        XCTAssertTrue(window.test_handleKeyDown(keyCode: 126, charactersIgnoringModifiers: ""))
        let upCaret = try XCTUnwrap(window.test_textEditorInsertionRect())
        XCTAssertGreaterThan(upCaret.midY, endCaret.midY)

        XCTAssertEqual(window.test_annotationText(at: 0), text)
    }

    func testTextAnnotationCanMoveDeleteAndChangeColor() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 360, height: 240)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("Hello text")
        window.test_commitTextEditing()

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertFalse(window.test_isEditingTextAnnotation)

        let originalRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let moveStart = NSPoint(x: selection.minX + originalRect.midX, y: selection.minY + originalRect.midY)
        let moveEnd = NSPoint(x: moveStart.x + 36, y: moveStart.y + 24)
        window.test_mouseDown(at: moveStart)
        window.test_mouseDragged(to: moveEnd)
        window.test_mouseUp(at: moveEnd)

        let movedRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertEqual(movedRect.minX, originalRect.minX + 36, accuracy: 0.1)
        XCTAssertEqual(movedRect.minY, originalRect.minY + 24, accuracy: 0.1)

        let colorPoint = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 0))
        window.test_mouseDown(at: colorPoint)
        window.test_mouseUp(at: colorPoint)

        var style = try XCTUnwrap(window.test_annotationStyle(at: 0))
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#FF001A")

        window.test_selectTextSize(32)

        style = try XCTUnwrap(window.test_annotationStyle(at: 0))
        let resizedRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertEqual(style.textSize, 32)
        XCTAssertGreaterThanOrEqual(resizedRect.width, movedRect.width)
        XCTAssertGreaterThan(resizedRect.height, movedRect.height)

        window.test_keyDown(keyCode: 51)
        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertNil(window.test_selectedAnnotationKind)
    }

    func testCommittedTextCanMoveResizeAndRotateAfterBodySelection() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 420, height: 280)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("Edit me")
        window.test_commitTextEditing()

        window.test_activateShapeTool(.rectangle)
        window.test_activateTextTool()
        let originalRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let bodyPoint = NSPoint(x: selection.minX + originalRect.midX, y: selection.minY + originalRect.midY)
        window.test_mouseDown(at: bodyPoint)
        window.test_mouseUp(at: bodyPoint)

        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertTrue(window.test_isEditingTextAnnotation)

        let moveEnd = NSPoint(x: bodyPoint.x + 44, y: bodyPoint.y + 28)
        window.test_mouseDown(at: bodyPoint)
        window.test_mouseDragged(to: moveEnd)
        window.test_mouseUp(at: moveEnd)

        let movedRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertEqual(movedRect.minX, originalRect.minX + 44, accuracy: 0.1)
        XCTAssertEqual(movedRect.minY, originalRect.minY + 28, accuracy: 0.1)

        let originalStyle = try XCTUnwrap(window.test_annotationStyle(at: 0))
        let resizePoint = try XCTUnwrap(window.test_shapeResizeHandlePoint(.bottomRight))
        window.test_mouseDown(at: resizePoint)
        window.test_mouseDragged(to: NSPoint(x: resizePoint.x + movedRect.width * 0.4, y: resizePoint.y - movedRect.height * 0.4))
        window.test_mouseUp(at: NSPoint(x: resizePoint.x + movedRect.width * 0.4, y: resizePoint.y - movedRect.height * 0.4))

        let resizedRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let resizedStyle = try XCTUnwrap(window.test_annotationStyle(at: 0))
        XCTAssertGreaterThan(resizedRect.width, movedRect.width)
        XCTAssertGreaterThan(resizedRect.height, movedRect.height)
        XCTAssertGreaterThan(resizedStyle.textSize, originalStyle.textSize)

        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 40, y: rotationPoint.y + 26))
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 40, y: rotationPoint.y + 26))

        XCTAssertGreaterThan(abs(window.test_annotationRotationAngle(at: 0) ?? 0), 0.05)
    }

    func testTextAnnotationCanBeDeletedWithForwardDelete() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 240))
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("Forward delete")
        window.test_commitTextEditing()

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertFalse(window.test_isEditingTextAnnotation)

        window.test_keyDown(keyCode: 117)

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertNil(window.test_selectedAnnotationKind)
    }

    func testTextAnnotationTopRightCloseHandleDeletesAnnotation() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 240))
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("Delete from handle")
        window.test_commitTextEditing()

        let closePoint = try XCTUnwrap(window.test_shapeResizeHandlePoint(.topRight))
        window.test_mouseDown(at: closePoint)
        window.test_mouseUp(at: closePoint)

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertNil(window.test_selectedAnnotationKind)
        XCTAssertFalse(window.test_isEditingTextAnnotation)
    }

    func testTextAnnotationTopRightCloseHandleDrawsBlueCircleWithWhiteX() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 240))
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("Close")
        window.test_commitTextEditing()

        let closePoint = try XCTUnwrap(window.test_shapeResizeHandlePoint(.topRight))
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let iconRect = NSRect(x: closePoint.x - 7, y: closePoint.y - 7, width: 14, height: 14)
        let centerRect = NSRect(x: closePoint.x - 2, y: closePoint.y - 2, width: 4, height: 4)

        XCTAssertNotNil(Bundle.main.url(forResource: "x-circle-fill", withExtension: "svg"))
        let bluePixel = try firstPixel(in: image, rect: iconRect) { pixel in
            pixel.red < 80 && pixel.green > 90 && pixel.blue > 180 && pixel.alpha > 180
        }
        let whiteCenterPixel = try firstPixel(in: image, rect: centerRect) { pixel in
            pixel.red > 220 && pixel.green > 220 && pixel.blue > 220 && pixel.alpha > 180
        }

        XCTAssertNotNil(bluePixel)
        XCTAssertNotNil(whiteCenterPixel)
    }

    func testTextToolReopensExistingAnnotationFromBodyClick() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("H")
        window.test_commitTextEditing()

        guard let textRect = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected text annotation")
        }

        window.test_mouseDown(at: NSPoint(x: 100 + textRect.midX, y: 100 + textRect.midY))
        window.test_mouseUp(at: NSPoint(x: 100 + textRect.midX, y: 100 + textRect.midY))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertTrue(window.test_isEditingTextAnnotation)
        XCTAssertEqual(window.test_textAnnotation(at: 0)?.text, "H")
    }

    func testDeleteRemovesTextAnnotationSelectedFromBorderClick() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 360, height: 240)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("Delete me")
        window.test_commitTextEditing()

        let textRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        let borderPoint = NSPoint(x: selection.minX + textRect.midX, y: selection.minY + textRect.minY)
        window.test_mouseDown(at: borderPoint)
        window.test_mouseUp(at: borderPoint)

        XCTAssertEqual(window.test_selectedAnnotationKind, .text)
        XCTAssertFalse(window.test_isEditingTextAnnotation)

        window.test_keyDown(keyCode: 51)

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertNil(window.test_selectedAnnotationKind)
    }

    func testEmptyTextDraftIsDiscardedOnEscape() {
        var completions = 0
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in completions += 1 }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertTrue(window.test_isEditingTextAnnotation)

        window.test_keyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}")

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertFalse(window.test_isEditingTextAnnotation)
        XCTAssertFalse(window.test_isTextToolActive)
        XCTAssertNil(window.test_selectedAnnotationKind)
        XCTAssertEqual(completions, 0)
    }

    func testEscapeDiscardsShapeDraftWithoutClosingCapture() {
        var completions = 0
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in completions += 1 }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.rectangle)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 210))

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_currentShapeKind, .rectangle)

        window.test_keyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}")

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertNil(window.test_currentShapeKind)
        XCTAssertEqual(completions, 0)
    }

    func testWhitespaceOnlyTextDraftIsDiscardedOnEscape() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.test_keyDown(keyCode: 49, charactersIgnoringModifiers: " ")
        window.test_keyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}")

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertFalse(window.test_isEditingTextAnnotation)
        XCTAssertNil(window.test_selectedAnnotationKind)
    }

    func testFinishingCaptureCommitsOrDiscardsActiveTextEdit() {
        var emptyResult: CaptureSelectionResult?
        let emptyExpectation = expectation(description: "empty text draft result")
        let emptyWindow = SelectionOverlayWindow(backgroundImage: nil) { result in
            emptyResult = result
            emptyExpectation.fulfill()
        }
        emptyWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        emptyWindow.test_activateTextTool()
        emptyWindow.test_mouseDown(at: NSPoint(x: 140, y: 150))
        emptyWindow.test_mouseUp(at: NSPoint(x: 140, y: 150))
        emptyWindow.test_keyDown(keyCode: 8, charactersIgnoringModifiers: "c", modifierFlags: [.command])
        wait(for: [emptyExpectation], timeout: 0.5)
        XCTAssertEqual(emptyResult?.annotations.count, 0)

        var textResult: CaptureSelectionResult?
        let textExpectation = expectation(description: "non-empty text result")
        let textWindow = SelectionOverlayWindow(backgroundImage: nil) { result in
            textResult = result
            textExpectation.fulfill()
        }
        textWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        textWindow.test_activateTextTool()
        textWindow.test_mouseDown(at: NSPoint(x: 140, y: 150))
        textWindow.test_mouseUp(at: NSPoint(x: 140, y: 150))
        textWindow.firstResponder?.insertText("x")
        textWindow.test_keyDown(keyCode: 8, charactersIgnoringModifiers: "c", modifierFlags: [.command])
        wait(for: [textExpectation], timeout: 0.5)
        XCTAssertEqual(textResult?.annotations.count, 1)
        XCTAssertEqual(textResult?.annotations.first?.kind, .text)
        XCTAssertEqual(textResult?.annotations.first?.text, "x")
    }

    func testPinToolbarCompletesSelectionAndCommitsActiveTextEdit() throws {
        var result: CaptureSelectionResult?
        let expectation = expectation(description: "pin action")
        let window = SelectionOverlayWindow(backgroundImage: nil) { selectionResult in
            result = selectionResult
            expectation.fulfill()
        }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()
        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))
        window.firstResponder?.insertText("pinned")

        let pinPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .pin))
        window.test_mouseDown(at: pinPoint)
        window.test_mouseUp(at: pinPoint)
        wait(for: [expectation], timeout: 0.5)

        XCTAssertEqual(result?.action, .pin)
        XCTAssertEqual(result?.annotations.count, 1)
        XCTAssertEqual(result?.annotations.first?.kind, .text)
        XCTAssertEqual(result?.annotations.first?.text, "pinned")
    }

    func testCommandOneCompletesSelectionAsPin() {
        var result: CaptureSelectionResult?
        let expectation = expectation(description: "pin shortcut")
        let window = SelectionOverlayWindow(backgroundImage: nil) { selectionResult in
            result = selectionResult
            expectation.fulfill()
        }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        window.test_keyDown(keyCode: 18, charactersIgnoringModifiers: "1", modifierFlags: [.command])
        wait(for: [expectation], timeout: 0.5)

        XCTAssertEqual(result?.action, .pin)
    }

    func testToolbarToolShortcutsSelectMatchingButtonForLowercaseAndShiftUppercase() {
        let shortcuts: [(key: String, button: TestToolbarButton)] = [
            ("s", .rectangle),
            ("a", .arrow),
            ("b", .pen),
            ("h", .marker),
            ("p", .eyedropper),
            ("m", .mosaic),
            ("t", .text),
            ("n", .number),
            ("g", .magnifier),
            ("e", .eraser),
        ]

        for shortcut in shortcuts {
            let lowercaseWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
            lowercaseWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

            XCTAssertTrue(
                lowercaseWindow.test_handleKeyDown(
                    keyCode: 0,
                    charactersIgnoringModifiers: shortcut.key
                ),
                shortcut.key
            )
            XCTAssertTrue(lowercaseWindow.test_toolbarButtonIsSelected(shortcut.button), shortcut.key)

            let uppercaseWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
            uppercaseWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

            XCTAssertTrue(
                uppercaseWindow.test_handleKeyDown(
                    keyCode: 0,
                    charactersIgnoringModifiers: shortcut.key.uppercased(),
                    modifierFlags: [.shift]
                ),
                shortcut.key.uppercased()
            )
            XCTAssertTrue(uppercaseWindow.test_toolbarButtonIsSelected(shortcut.button), shortcut.key.uppercased())
        }
    }

    func testModifiedToolLettersDoNotSwitchAnnotationTools() {
        for modifiers: NSEvent.ModifierFlags in [[.command], [.control], [.option]] {
            let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
            window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

            XCTAssertFalse(
                window.test_handleKeyDown(
                    keyCode: 0,
                    charactersIgnoringModifiers: "a",
                    modifierFlags: modifiers
                )
            )
            XCTAssertFalse(window.test_toolbarButtonIsSelected(.arrow))
        }
    }

    func testActiveTextEditorKeepsToolShortcutLettersAsTextInput() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()
        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        XCTAssertTrue(window.test_textEditorIsFirstResponder)
        XCTAssertFalse(window.test_handleKeyDown(keyCode: 1, charactersIgnoringModifiers: "s"))
        window.firstResponder?.insertText("s")

        XCTAssertEqual(window.test_annotationText(at: 0), "s")
        XCTAssertTrue(window.test_toolbarButtonIsSelected(.text))
        XCTAssertFalse(window.test_toolbarButtonIsSelected(.rectangle))
    }

    func testActiveTextEditorKeepsToolShortcutLetterOwnedByMarkedTextInput() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateTextTool()
        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.setMarkedText(
            "sh",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let markedRange = editor.markedRange()
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(markedRange, NSRange(location: 0, length: 2))

        XCTAssertFalse(window.test_handleKeyDown(keyCode: 1, charactersIgnoringModifiers: "s"))

        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.markedRange(), markedRange)
        XCTAssertEqual(window.test_annotationText(at: 0), "sh")
        XCTAssertTrue(window.test_toolbarButtonIsSelected(.text))
        XCTAssertFalse(window.test_toolbarButtonIsSelected(.rectangle))
    }

    func testDisabledUndoAndRedoShortcutsAreConsumedWithoutChangingAnnotations() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        XCTAssertTrue(
            window.test_handleKeyDown(
                keyCode: 6,
                charactersIgnoringModifiers: "z",
                modifierFlags: [.command]
            )
        )
        XCTAssertTrue(
            window.test_handleKeyDown(
                keyCode: 6,
                charactersIgnoringModifiers: "z",
                modifierFlags: [.command, .shift]
            )
        )
        XCTAssertEqual(window.test_annotationCount, 0)
    }

    func testCommandCopyAndSaveDispatchThroughVisibleToolbarButtons() {
        let shortcuts: [(key: String, keyCode: UInt16, action: CaptureCompletionAction)] = [
            ("c", 8, .copy),
            ("s", 1, .save),
        ]

        for shortcut in shortcuts {
            var result: CaptureSelectionResult?
            let completion = expectation(description: "\(shortcut.action) shortcut")
            let window = SelectionOverlayWindow(backgroundImage: nil) { selectionResult in
                result = selectionResult
                completion.fulfill()
            }
            window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

            window.test_keyDown(
                keyCode: shortcut.keyCode,
                charactersIgnoringModifiers: shortcut.key,
                modifierFlags: [.command]
            )
            wait(for: [completion], timeout: 0.5)

            XCTAssertEqual(result?.action, shortcut.action)
        }
    }

    func testNormalCaptureEscapeCancelsSelection() {
        var didComplete = false
        var result: CaptureSelectionResult?
        let completion = expectation(description: "cancel shortcut")
        let window = SelectionOverlayWindow(backgroundImage: nil) { selectionResult in
            didComplete = true
            result = selectionResult
            completion.fulfill()
        }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        window.test_keyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}")
        wait(for: [completion], timeout: 0.5)

        XCTAssertTrue(didComplete)
        XCTAssertNil(result)
    }

    func testActivePrimaryToolsRequireTwoEscapesToCloseCapture() {
        for key in ["s", "a", "b", "h", "p", "m", "t", "n", "g", "e"] {
            var completions = 0
            var result: CaptureSelectionResult?
            let completion = expectation(description: "cancel after leaving \(key) tool")
            let window = SelectionOverlayWindow(backgroundImage: nil) {
                completions += 1
                result = $0
                completion.fulfill()
            }
            window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
            window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: key)

            window.test_keyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}")
            XCTAssertEqual(completions, 0, key)

            window.test_keyDown(keyCode: 53, charactersIgnoringModifiers: "\u{1b}")
            wait(for: [completion], timeout: 0.5)
            XCTAssertEqual(completions, 1, key)
            XCTAssertNil(result, key)
        }
    }

    @MainActor
    func testPinnedImageEditorBaseEscapeFinishesEditingWithoutClosingPin() {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        var closeCount = 0
        controller.onClose = { closeCount += 1 }
        controller.show()
        controller.test_showEditingToolbar()

        controller.test_editingOverlayKeyDown(
            keyCode: 53,
            charactersIgnoringModifiers: "\u{1b}",
            modifierFlags: []
        )

        XCTAssertEqual(closeCount, 0)
        XCTAssertFalse(controller.test_isToolbarVisible)
        XCTAssertEqual(controller.window?.isVisible, true)
        controller.window?.close()
    }

    @MainActor
    func testPinnedTallLongImageFitsVisibleFrameWithoutChangingSource() {
        let source = solidImage(size: NSSize(width: 1_200, height: 12_000), color: .white)
        let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let controller = PinnedImageWindowController(image: source, visibleFrame: visible)

        let initial = controller.test_imageFrameInScreen
        XCTAssertTrue(controller.image === source)
        XCTAssertEqual(controller.image.size, NSSize(width: 1_200, height: 12_000))
        XCTAssertLessThanOrEqual(initial.height, visible.height)
        XCTAssertLessThanOrEqual(controller.window?.frame.height ?? .infinity, visible.height)
        XCTAssertEqual(initial.width / initial.height, 0.1, accuracy: 0.003)

        controller.scale(by: 1.2)
        XCTAssertGreaterThan(controller.test_imageFrameInScreen.height, initial.height)
        XCTAssertTrue(controller.image === source)
        XCTAssertEqual(controller.image.size, NSSize(width: 1_200, height: 12_000))
        controller.window?.close()
    }

    @MainActor
    func testPinnedImageActivePrimaryToolsEscapeThenFinishEditing() {
        for key in ["s", "a", "b", "h", "p", "m", "t", "n", "g", "e"] {
            let controller = PinnedImageWindowController(
                image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
                screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
            )
            var hideCount = 0
            var closeCount = 0
            controller.onHide = { hideCount += 1 }
            controller.onClose = { closeCount += 1 }
            controller.show()
            controller.test_showEditingToolbar()
            controller.test_editingOverlayKeyDown(
                keyCode: 0,
                charactersIgnoringModifiers: key,
                modifierFlags: []
            )

            controller.test_editingOverlayKeyDown(
                keyCode: 53,
                charactersIgnoringModifiers: "\u{1b}",
                modifierFlags: []
            )
            XCTAssertEqual(closeCount, 0, key)
            XCTAssertTrue(controller.test_isToolbarVisible, key)

            controller.test_editingOverlayKeyDown(
                keyCode: 53,
                charactersIgnoringModifiers: "\u{1b}",
                modifierFlags: []
            )
            XCTAssertEqual(closeCount, 0, key)
            XCTAssertFalse(controller.test_isToolbarVisible, key)
            XCTAssertEqual(controller.window?.isVisible, true, key)
            controller.test_keyDown(keyCode: 53)
            XCTAssertEqual(hideCount, 1, key)
            XCTAssertEqual(closeCount, 0, key)
            XCTAssertEqual(controller.window?.isVisible, false, key)
            controller.window?.close()
        }
    }

    @MainActor
    func testPinnedImageEditorEscapeFinishBakesAnnotations() throws {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        style.fillEnabled = true
        style.fillColor = .red
        let rectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 20, width: 50, height: 30),
            style: style
        )
        controller.show()
        controller.test_showEditingToolbar()
        controller.test_setEditingOverlayState(annotations: [rectangle], eraserMasks: [])

        controller.test_editingOverlayKeyDown(
            keyCode: 53,
            charactersIgnoringModifiers: "\u{1b}",
            modifierFlags: []
        )

        let pixel = try XCTUnwrap(rgbaRenderPixel(in: controller.image, at: NSPoint(x: 30, y: 30)))
        XCTAssertGreaterThan(pixel.red, 220)
        XCTAssertLessThan(pixel.green, 40)
        XCTAssertLessThan(pixel.blue, 40)
        XCTAssertFalse(controller.test_isToolbarVisible)
        controller.window?.close()
    }

    func testMonitoredKeyEventIsOwnedOnlyByItsPinnedEditorWindow() throws {
        let selection = NSRect(x: 40, y: 40, width: 240, height: 160)
        let firstWindow = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        let secondWindow = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        firstWindow.orderFront(nil)
        secondWindow.orderFront(nil)
        defer {
            firstWindow.orderOut(nil)
            secondWindow.orderOut(nil)
        }

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: firstWindow.windowNumber,
            context: nil,
            characters: "s",
            charactersIgnoringModifiers: "s",
            isARepeat: false,
            keyCode: 1
        ))

        XCTAssertTrue(event.window === firstWindow)
        XCTAssertTrue(firstWindow.test_ownsMonitoredKeyEvent(event))
        XCTAssertFalse(secondWindow.test_ownsMonitoredKeyEvent(event))
    }

    func testMonitoredToolShortcutChangesOnlyItsTargetPinnedEditor() throws {
        let selection = NSRect(x: 40, y: 40, width: 240, height: 160)
        let targetWindow = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        let otherWindow = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        targetWindow.orderFront(nil)
        otherWindow.orderFront(nil)
        defer {
            targetWindow.orderOut(nil)
            otherWindow.orderOut(nil)
        }

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: targetWindow.windowNumber,
            context: nil,
            characters: "s",
            charactersIgnoringModifiers: "s",
            isARepeat: false,
            keyCode: 1
        ))

        XCTAssertNotNil(otherWindow.test_handleMonitoredKeyDown(event))
        XCTAssertFalse(otherWindow.test_toolbarButtonIsSelected(.rectangle))
        XCTAssertNil(targetWindow.test_handleMonitoredKeyDown(event))
        XCTAssertTrue(targetWindow.test_toolbarButtonIsSelected(.rectangle))
        XCTAssertFalse(otherWindow.test_toolbarButtonIsSelected(.rectangle))
    }

    func testInstalledMonitorHandlerKeepsConsumedShortcutNil() throws {
        let selection = NSRect(x: 40, y: 40, width: 240, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "s",
            charactersIgnoringModifiers: "s",
            isARepeat: false,
            keyCode: 1
        ))

        XCTAssertNil(window.test_handleInstalledKeyMonitorEvent(event))
        XCTAssertTrue(window.test_toolbarButtonIsSelected(.rectangle))
    }

    func testWindowlessMonitoredKeyEventIsRejectedByNonKeyPinnedEditors() throws {
        let selection = NSRect(x: 40, y: 40, width: 240, height: 160)
        let firstWindow = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        let secondWindow = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "s",
            charactersIgnoringModifiers: "s",
            isARepeat: false,
            keyCode: 1
        ))

        XCTAssertNil(event.window)
        XCTAssertFalse(firstWindow.isKeyWindow)
        XCTAssertFalse(secondWindow.isKeyWindow)
        XCTAssertFalse(firstWindow.test_ownsMonitoredKeyEvent(event))
        XCTAssertFalse(secondWindow.test_ownsMonitoredKeyEvent(event))
    }

    func testWindowlessMonitoredToolShortcutIsHandledOnlyByKeyPinnedEditor() throws {
        let selection = NSRect(x: 40, y: 40, width: 240, height: 160)
        let keyWindow = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        let otherWindow = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "s",
            charactersIgnoringModifiers: "s",
            isARepeat: false,
            keyCode: 1
        ))

        XCTAssertNil(event.window)
        XCTAssertNotNil(otherWindow.test_handleMonitoredKeyDown(
            event,
            treatingWindowlessEventAsKey: false
        ))
        XCTAssertFalse(otherWindow.test_toolbarButtonIsSelected(.rectangle))
        XCTAssertNil(keyWindow.test_handleMonitoredKeyDown(
            event,
            treatingWindowlessEventAsKey: true
        ))
        XCTAssertTrue(keyWindow.test_toolbarButtonIsSelected(.rectangle))
        XCTAssertFalse(otherWindow.test_toolbarButtonIsSelected(.rectangle))
    }

    func testPinnedImageGeometryFitsAndScalesWithoutChangingAspectRatio() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1000, height: 700)

        let fitted = PinnedImageWindowGeometry.fittedImageSize(
            imageSize: NSSize(width: 2000, height: 1000),
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(fitted.width, 800, accuracy: 0.1)
        XCTAssertEqual(fitted.height, 400, accuracy: 0.1)

        let tiny = PinnedImageWindowGeometry.fittedImageSize(
            imageSize: NSSize(width: 12, height: 6),
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(max(tiny.width, tiny.height), PinnedImageWindowGeometry.minLongSide, accuracy: 0.1)
        XCTAssertEqual(tiny.width / tiny.height, 2, accuracy: 0.01)

        let scaled = PinnedImageWindowGeometry.scaledSize(
            currentSize: NSSize(width: 200, height: 100),
            aspectRatio: 2,
            scaleFactor: 1.5,
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(scaled.width, 300, accuracy: 0.1)
        XCTAssertEqual(scaled.height, 150, accuracy: 0.1)

        let clamped = PinnedImageWindowGeometry.scaledSize(
            currentSize: NSSize(width: 200, height: 100),
            aspectRatio: 2,
            scaleFactor: 0.1,
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(max(clamped.width, clamped.height), PinnedImageWindowGeometry.minLongSide, accuracy: 0.1)
    }

    @MainActor
    func testPinnedImageWindowUsesSourceFrameBlueShadowAndKeyboardClose() throws {
        let sourceRect = NSRect(x: 120, y: 220, width: 160, height: 90)
        let shadowOutset = PinnedImageWindowGeometry.shadowOutset
        let controller = PinnedImageWindowController(
            image: solidImage(size: sourceRect.size, color: .white),
            screenRect: sourceRect
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.frame.origin.x, sourceRect.origin.x - shadowOutset, accuracy: 0.1)
        XCTAssertEqual(window.frame.origin.y, sourceRect.origin.y - shadowOutset, accuracy: 0.1)
        XCTAssertEqual(window.frame.size.width, sourceRect.width + shadowOutset * 2, accuracy: 0.1)
        XCTAssertEqual(window.frame.size.height, sourceRect.height + shadowOutset * 2, accuracy: 0.1)
        XCTAssertEqual(window.frame.insetBy(dx: shadowOutset, dy: shadowOutset).origin.x, sourceRect.origin.x, accuracy: 0.1)
        XCTAssertEqual(window.frame.insetBy(dx: shadowOutset, dy: shadowOutset).origin.y, sourceRect.origin.y, accuracy: 0.1)
        XCTAssertFalse(window.hasShadow)
        XCTAssertTrue(controller.test_drawsBlueShadow)
        XCTAssertFalse(controller.test_drawsCloseButton)
        let rendered = controller.test_renderedContentImage()
        XCTAssertEqual(rendered.size.width, sourceRect.width + shadowOutset * 2, accuracy: 0.1)
        XCTAssertEqual(rendered.size.height, sourceRect.height + shadowOutset * 2, accuracy: 0.1)

        let imageRect = NSRect(x: shadowOutset, y: shadowOutset, width: sourceRect.width, height: sourceRect.height)
        XCTAssertNotNil(try firstPixel(in: rendered, rect: imageRect.insetBy(dx: 2, dy: 2)) { pixel in
            pixel.red > 245 && pixel.green > 245 && pixel.blue > 245 && pixel.alpha > 245
        })
        XCTAssertNil(try firstPixel(in: rendered, rect: imageRect.insetBy(dx: 4, dy: 4)) { pixel in
            pixel.blue > pixel.red && pixel.blue > pixel.green && pixel.alpha > 40
        })

        let topGlowPixel = try XCTUnwrap(firstPixel(in: rendered, rect: NSRect(x: imageRect.minX + 12, y: imageRect.maxY + 2, width: imageRect.width - 24, height: 8)) { pixel in
            pixel.blue > pixel.red && pixel.blue > pixel.green && pixel.alpha > 30
        })
        let bottomGlowPixel = try XCTUnwrap(firstPixel(in: rendered, rect: NSRect(x: imageRect.minX + 12, y: 8, width: imageRect.width - 24, height: 8)) { pixel in
            pixel.blue > pixel.red && pixel.blue > pixel.green && pixel.alpha > 30
        })
        let leftGlowPixel = try XCTUnwrap(firstPixel(in: rendered, rect: NSRect(x: 8, y: imageRect.minY + 12, width: 8, height: imageRect.height - 24)) { pixel in
            pixel.blue > pixel.red && pixel.blue > pixel.green && pixel.alpha > 30
        })
        let rightGlowPixel = try XCTUnwrap(firstPixel(in: rendered, rect: NSRect(x: imageRect.maxX + 2, y: imageRect.minY + 12, width: 8, height: imageRect.height - 24)) { pixel in
            pixel.blue > pixel.red && pixel.blue > pixel.green && pixel.alpha > 30
        })
        XCTAssertGreaterThan(topGlowPixel.blue, topGlowPixel.red)
        XCTAssertGreaterThan(bottomGlowPixel.blue, bottomGlowPixel.red)
        XCTAssertGreaterThan(leftGlowPixel.blue, leftGlowPixel.red)
        XCTAssertGreaterThan(rightGlowPixel.blue, rightGlowPixel.red)

        var closeCount = 0
        controller.onClose = {
            closeCount += 1
        }
        controller.test_keyDown(keyCode: 117)
        XCTAssertEqual(closeCount, 1)
    }

    @MainActor
    func testPinnedImageContextMenuUsesRequestedOrder() throws {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )

        XCTAssertEqual(controller.test_contextMenuTitles, [
            "显示工具条 (⇧)",
            "复制图片",
            "保存图片",
            nil,
            "重置大小",
            "透明度",
            "置顶",
            nil,
            "关闭",
            "关闭全部贴图",
        ])
    }

    @MainActor
    func testPinnedImageContextMenuUsesApprovedKeyboardEquivalents() throws {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        let menu = controller.makeContextMenu()

        let copy = try XCTUnwrap(menu.items.first { $0.title == "复制图片" })
        XCTAssertEqual(copy.keyEquivalent, "c")
        XCTAssertEqual(copy.keyEquivalentModifierMask, [.command])

        let save = try XCTUnwrap(menu.items.first { $0.title == "保存图片" })
        XCTAssertEqual(save.keyEquivalent, "s")
        XCTAssertEqual(save.keyEquivalentModifierMask, [.command])

        let toolbar = try XCTUnwrap(menu.items.first { $0.title == "显示工具条 (⇧)" })
        XCTAssertEqual(toolbar.keyEquivalent, "")
        XCTAssertEqual(toolbar.keyEquivalentModifierMask, [])

        let reset = try XCTUnwrap(menu.items.first { $0.title == "重置大小" })
        XCTAssertEqual(reset.keyEquivalent, "r")
        XCTAssertEqual(reset.keyEquivalentModifierMask, [.command])

        let alwaysOnTop = try XCTUnwrap(menu.items.first { $0.title == "置顶" })
        XCTAssertEqual(alwaysOnTop.keyEquivalent, "t")
        XCTAssertEqual(alwaysOnTop.keyEquivalentModifierMask, [.command])

        let close = try XCTUnwrap(menu.items.first { $0.title == "关闭" })
        XCTAssertEqual(close.keyEquivalent, "w")
        XCTAssertEqual(close.keyEquivalentModifierMask, [.command])

        let closeAll = try XCTUnwrap(menu.items.first { $0.title == "关闭全部贴图" })
        XCTAssertEqual(closeAll.keyEquivalent, "w")
        XCTAssertEqual(closeAll.keyEquivalentModifierMask, [.command, .shift])
    }

    @MainActor
    func testPinnedImageKeyboardCopyAndSaveReuseImageActionsWhenToolbarIsHidden() {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        var actions: [CaptureCompletionAction] = []
        controller.test_setImageActionHandler { actions.append($0) }

        controller.test_keyDown(
            keyCode: 8,
            charactersIgnoringModifiers: "c",
            modifierFlags: [.command]
        )
        controller.test_keyDown(
            keyCode: 1,
            charactersIgnoringModifiers: "s",
            modifierFlags: [.command]
        )

        XCTAssertEqual(actions, [.copy, .save])
        XCTAssertFalse(controller.test_isToolbarVisible)
    }

    @MainActor
    func testPinnedImageEditorKeyboardCopyAndSaveReuseOverlayCompletionPath() {
        let shortcuts: [(keyCode: UInt16, key: String, action: CaptureCompletionAction)] = [
            (8, "c", .copy),
            (1, "s", .save),
        ]

        for shortcut in shortcuts {
            let controller = PinnedImageWindowController(
                image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
                screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
            )
            var actions: [CaptureCompletionAction] = []
            controller.test_setImageActionHandler { actions.append($0) }
            controller.test_showEditingToolbar()

            controller.test_editingOverlayKeyDown(
                keyCode: shortcut.keyCode,
                charactersIgnoringModifiers: shortcut.key,
                modifierFlags: [.command]
            )

            XCTAssertEqual(actions, [shortcut.action])
            XCTAssertFalse(controller.test_isToolbarVisible)
        }
    }

    @MainActor
    func testPinnedImageKeyboardCloseUsesExactModifiersWhenToolbarIsHidden() {
        let current = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        let other = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 100, height: 70), color: .white),
            screenRect: NSRect(x: 220, y: 50, width: 100, height: 70)
        )
        var currentCloseCount = 0
        var otherCloseCount = 0
        current.onClose = { currentCloseCount += 1 }
        other.onClose = { otherCloseCount += 1 }

        current.test_keyDown(
            keyCode: 13,
            charactersIgnoringModifiers: "w",
            modifierFlags: [.command]
        )

        XCTAssertEqual(currentCloseCount, 1)
        XCTAssertEqual(otherCloseCount, 0)
        other.window?.close()
    }

    @MainActor
    func testPinnedImageKeyboardCloseAllUsesCommandShiftWAndLeavesOtherWindowsOpen() {
        let first = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        let second = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 100, height: 70), color: .white),
            screenRect: NSRect(x: 220, y: 50, width: 100, height: 70)
        )
        let ordinaryWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        ordinaryWindow.isReleasedWhenClosed = false
        ordinaryWindow.orderFront(nil)
        defer { ordinaryWindow.close() }
        var firstCloseCount = 0
        var secondCloseCount = 0
        first.onClose = { firstCloseCount += 1 }
        second.onClose = { secondCloseCount += 1 }

        first.test_keyDown(
            keyCode: 13,
            charactersIgnoringModifiers: "w",
            modifierFlags: [.command, .shift]
        )

        XCTAssertEqual(firstCloseCount, 1)
        XCTAssertEqual(secondCloseCount, 1)
        XCTAssertTrue(ordinaryWindow.isVisible)
    }

    @MainActor
    func testPinnedImageKeyboardCloseRejectsInvalidModifiersWhenToolbarIsHidden() {
        let invalidModifiers: [(name: String, flags: NSEvent.ModifierFlags)] = [
            ("command-option", [.command, .option]),
            ("command-control", [.command, .control]),
            ("shift", [.shift]),
            ("command-shift-option", [.command, .shift, .option]),
        ]

        for invalid in invalidModifiers {
            let controller = PinnedImageWindowController(
                image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
                screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
            )
            var closeCount = 0
            controller.onClose = { closeCount += 1 }

            controller.test_keyDown(
                keyCode: 13,
                charactersIgnoringModifiers: "w",
                modifierFlags: invalid.flags
            )

            XCTAssertEqual(closeCount, 0, invalid.name)
            controller.window?.close()
        }
    }

    @MainActor
    func testPinnedImageEditorKeyboardCloseRoutesToOwningController() {
        let current = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        let other = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 100, height: 70), color: .white),
            screenRect: NSRect(x: 220, y: 50, width: 100, height: 70)
        )
        var currentCloseCount = 0
        var otherCloseCount = 0
        current.onClose = { currentCloseCount += 1 }
        other.onClose = { otherCloseCount += 1 }
        current.test_showEditingToolbar()

        current.test_editingOverlayKeyDown(
            keyCode: 13,
            charactersIgnoringModifiers: "w",
            modifierFlags: [.command]
        )

        XCTAssertEqual(currentCloseCount, 1)
        XCTAssertEqual(otherCloseCount, 0)
        other.window?.close()
    }

    @MainActor
    func testPinnedImageEditorKeyboardCloseAllRoutesToPinnedControllers() {
        let first = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        let second = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 100, height: 70), color: .white),
            screenRect: NSRect(x: 220, y: 50, width: 100, height: 70)
        )
        var firstCloseCount = 0
        var secondCloseCount = 0
        first.onClose = { firstCloseCount += 1 }
        second.onClose = { secondCloseCount += 1 }
        first.test_showEditingToolbar()

        first.test_editingOverlayKeyDown(
            keyCode: 13,
            charactersIgnoringModifiers: "w",
            modifierFlags: [.command, .shift]
        )

        XCTAssertEqual(firstCloseCount, 1)
        XCTAssertEqual(secondCloseCount, 1)
    }

    @MainActor
    func testPinnedImageEditorKeyboardCloseRejectsInvalidModifiers() {
        let invalidModifiers: [(name: String, flags: NSEvent.ModifierFlags)] = [
            ("command-option", [.command, .option]),
            ("command-control", [.command, .control]),
            ("shift", [.shift]),
            ("command-shift-option", [.command, .shift, .option]),
        ]

        for invalid in invalidModifiers {
            let controller = PinnedImageWindowController(
                image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
                screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
            )
            var closeCount = 0
            controller.onClose = { closeCount += 1 }
            controller.test_showEditingToolbar()

            controller.test_editingOverlayKeyDown(
                keyCode: 13,
                charactersIgnoringModifiers: "w",
                modifierFlags: invalid.flags
            )

            XCTAssertEqual(closeCount, 0, invalid.name)
            XCTAssertTrue(controller.test_isToolbarVisible, invalid.name)
            controller.window?.close()
        }
    }

    @MainActor
    func testPinnedImageEscapeHidesWithoutClosingWhenToolbarIsHidden() {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        var hideCount = 0
        var closeCount = 0
        controller.onHide = { hideCount += 1 }
        controller.onClose = { closeCount += 1 }
        controller.show()

        controller.test_keyDown(keyCode: 53)

        XCTAssertEqual(hideCount, 1)
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(controller.window?.isVisible, false)
        controller.window?.close()
    }

    @MainActor
    func testPinnedImageDeleteKeysStillCloseWhenToolbarIsHidden() {
        for keyCode in [UInt16(51), UInt16(117)] {
            let controller = PinnedImageWindowController(
                image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
                screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
            )
            var hideCount = 0
            var closeCount = 0
            controller.onHide = { hideCount += 1 }
            controller.onClose = { closeCount += 1 }

            controller.test_keyDown(keyCode: keyCode)

            XCTAssertEqual(hideCount, 0, "keyCode=\(keyCode)")
            XCTAssertEqual(closeCount, 1, "keyCode=\(keyCode)")
        }
    }

    @MainActor
    func testPinnedImageContextMenuTogglesToolbarVisibilityAndState() throws {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )

        XCTAssertFalse(controller.test_isToolbarVisible)
        XCTAssertEqual(controller.test_contextMenuToolbarItemState, .off)

        controller.test_toggleEditingToolbarFromMenu()

        XCTAssertTrue(controller.test_isToolbarVisible)
        XCTAssertEqual(controller.test_contextMenuToolbarItemState, .on)

        controller.test_toggleEditingToolbarFromMenu()

        XCTAssertFalse(controller.test_isToolbarVisible)
        XCTAssertEqual(controller.test_contextMenuToolbarItemState, .off)
    }

    @MainActor
    func testPinnedImageShiftReleaseTogglesToolbarOnAndOff() {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )

        controller.test_flagsChanged(modifierFlags: [.shift])
        XCTAssertFalse(controller.test_isToolbarVisible)

        controller.test_flagsChanged(modifierFlags: [])
        XCTAssertTrue(controller.test_isToolbarVisible)

        controller.test_flagsChanged(modifierFlags: [.shift])
        controller.test_flagsChanged(modifierFlags: [])
        XCTAssertFalse(controller.test_isToolbarVisible)
    }

    @MainActor
    func testPinnedImageShiftReleaseHidesToolbarWhenEditingOverlayOwnsFocus() {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        controller.test_showEditingToolbar()
        XCTAssertTrue(controller.test_isToolbarVisible)

        controller.test_editingOverlayFlagsChanged(modifierFlags: [.shift])
        XCTAssertTrue(controller.test_isToolbarVisible)

        controller.test_editingOverlayFlagsChanged(modifierFlags: [])
        XCTAssertFalse(controller.test_isToolbarVisible)
    }

    @MainActor
    func testPinnedImageEditingOverlayShiftShortcutCancelsForMixedModifiers() {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        controller.test_showEditingToolbar()

        controller.test_editingOverlayFlagsChanged(modifierFlags: [.shift])
        controller.test_editingOverlayFlagsChanged(modifierFlags: [.shift, .option])
        controller.test_editingOverlayFlagsChanged(modifierFlags: [])

        XCTAssertTrue(controller.test_isToolbarVisible)
    }

    @MainActor
    func testPinnedImageShiftShortcutCancelsWhenCombinedWithOtherInput() {
        let invalidSequences: [(name: String, perform: (PinnedImageWindowController) -> Void)] = [
            ("other modifier", { controller in
                controller.test_flagsChanged(modifierFlags: [.shift])
                controller.test_flagsChanged(modifierFlags: [.shift, .option])
                controller.test_flagsChanged(modifierFlags: [])
            }),
            ("keyboard", { controller in
                controller.test_flagsChanged(modifierFlags: [.shift])
                controller.test_keyDown(
                    keyCode: 0,
                    charactersIgnoringModifiers: "a",
                    modifierFlags: [.shift]
                )
                controller.test_flagsChanged(modifierFlags: [])
            }),
            ("mouse", { controller in
                controller.test_flagsChanged(modifierFlags: [.shift])
                controller.test_mouseDownForShiftShortcutCancellation()
                controller.test_flagsChanged(modifierFlags: [])
            }),
        ]

        for sequence in invalidSequences {
            let controller = PinnedImageWindowController(
                image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
                screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
            )

            sequence.perform(controller)

            XCTAssertFalse(controller.test_isToolbarVisible, sequence.name)
            controller.window?.close()
        }
    }

    @MainActor
    func testPinnedImageShiftShortcutDoesNotStartWhileDragging() throws {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 30, y: 30),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        controller.window?.contentView?.mouseDown(with: mouseDown)

        controller.test_flagsChanged(modifierFlags: [.shift])
        controller.test_flagsChanged(modifierFlags: [])

        let mouseUp = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: 42, y: 36),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        controller.window?.contentView?.mouseUp(with: mouseUp)

        XCTAssertFalse(controller.test_isToolbarVisible)
    }

    @MainActor
    func testPinnedImageResetShortcutWorksWithToolbarHiddenAndVisible() {
        for showsToolbar in [false, true] {
            let initialFrame = NSRect(x: 40, y: 50, width: 120, height: 80)
            let controller = PinnedImageWindowController(
                image: solidImage(size: initialFrame.size, color: .white),
                screenRect: initialFrame
            )
            if showsToolbar {
                controller.test_showEditingToolbar()
            }
            controller.scale(by: 1.5)
            XCTAssertNotEqual(controller.test_imageFrameInScreen.size, initialFrame.size)

            if showsToolbar {
                controller.test_editingOverlayKeyDown(
                    keyCode: 15,
                    charactersIgnoringModifiers: "r",
                    modifierFlags: [.command]
                )
            } else {
                controller.test_keyDown(
                    keyCode: 15,
                    charactersIgnoringModifiers: "r",
                    modifierFlags: [.command]
                )
            }

            XCTAssertEqual(controller.test_imageFrameInScreen, initialFrame)
            if showsToolbar {
                XCTAssertEqual(controller.test_editingOverlayImageFrameInScreen, initialFrame)
            }
            controller.window?.close()
        }
    }

    @MainActor
    func testPinnedImageResetMapsEraserMaskWithAnnotationCoordinates() throws {
        let sourceRect = NSRect(x: 120, y: 220, width: 160, height: 90)
        let controller = PinnedImageWindowController(
            image: solidImage(size: sourceRect.size, color: .white),
            screenRect: sourceRect
        )
        controller.test_showEditingToolbar()
        controller.test_scrollEditingOverlay(deltaY: 8)

        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 15, width: 60, height: 40),
            style: CaptureAnnotationStyle()
        )
        let mask = EraserMask(
            rect: NSRect(x: 30, y: 20, width: 15, height: 10),
            affectedAnnotationIDs: [annotation.id]
        )
        controller.test_setEditingOverlayState(annotations: [annotation], eraserMasks: [mask])
        let beforeAnnotation = try XCTUnwrap(controller.test_editingOverlayAnnotation(at: 0))

        controller.test_editingOverlayKeyDown(
            keyCode: 15,
            charactersIgnoringModifiers: "r",
            modifierFlags: [.command]
        )

        let afterAnnotation = try XCTUnwrap(controller.test_editingOverlayAnnotation(at: 0))
        let afterMask = try XCTUnwrap(controller.test_editingOverlayEraserMask(at: 0))
        let delta = NSPoint(
            x: afterAnnotation.rect.minX - beforeAnnotation.rect.minX,
            y: afterAnnotation.rect.minY - beforeAnnotation.rect.minY
        )
        XCTAssertNotEqual(delta, .zero)
        XCTAssertEqual(afterMask.rect.minX, mask.rect.minX + delta.x, accuracy: 0.001)
        XCTAssertEqual(afterMask.rect.minY, mask.rect.minY + delta.y, accuracy: 0.001)
        XCTAssertEqual(afterMask.rect.size, mask.rect.size)
        XCTAssertEqual(afterMask.id, mask.id)
        XCTAssertEqual(afterMask.affectedAnnotationIDs, mask.affectedAnnotationIDs)
    }

    @MainActor
    func testPinnedImageAlwaysOnTopShortcutSynchronizesEditingOverlayLevel() throws {
        for showsToolbar in [false, true] {
            let controller = PinnedImageWindowController(
                image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
                screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
            )
            if showsToolbar {
                controller.test_showEditingToolbar()
                XCTAssertEqual(controller.test_editingOverlayWindowLevel, .floating)
            }
            XCTAssertEqual(
                try XCTUnwrap(controller.makeContextMenu().items.first { $0.title == "置顶" }).state,
                .on
            )

            let sendShortcut = {
                if showsToolbar {
                    controller.test_editingOverlayKeyDown(
                        keyCode: 17,
                        charactersIgnoringModifiers: "t",
                        modifierFlags: [.command]
                    )
                } else {
                    controller.test_keyDown(
                        keyCode: 17,
                        charactersIgnoringModifiers: "t",
                        modifierFlags: [.command]
                    )
                }
            }
            sendShortcut()

            XCTAssertEqual(controller.test_windowLevel, .normal)
            XCTAssertEqual(
                try XCTUnwrap(controller.makeContextMenu().items.first { $0.title == "置顶" }).state,
                .off
            )
            if showsToolbar {
                XCTAssertEqual(controller.test_editingOverlayWindowLevel, .normal)
            }

            sendShortcut()
            XCTAssertEqual(controller.test_windowLevel, .floating)
            XCTAssertEqual(
                try XCTUnwrap(controller.makeContextMenu().items.first { $0.title == "置顶" }).state,
                .on
            )
            if showsToolbar {
                XCTAssertEqual(controller.test_editingOverlayWindowLevel, .floating)
            }
            controller.window?.close()
        }
    }

    @MainActor
    func testPinnedImageEditingOverlayInheritsCurrentWindowLevelWhenShown() {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        controller.test_keyDown(
            keyCode: 17,
            charactersIgnoringModifiers: "t",
            modifierFlags: [.command]
        )
        XCTAssertEqual(controller.test_windowLevel, .normal)

        controller.test_showEditingToolbar()

        XCTAssertEqual(controller.test_editingOverlayWindowLevel, .normal)
        controller.window?.close()
    }

    @MainActor
    func testPinnedImageResetAndAlwaysOnTopShortcutsRequireExactModifiers() {
        let invalidShortcuts: [(keyCode: UInt16, key: String, modifiers: NSEvent.ModifierFlags)] = [
            (15, "r", [.command, .shift]),
            (15, "r", [.command, .option]),
            (17, "t", [.command, .shift]),
            (17, "t", [.command, .control]),
        ]

        for showsToolbar in [false, true] {
            for shortcut in invalidShortcuts {
                let initialFrame = NSRect(x: 40, y: 50, width: 120, height: 80)
                let controller = PinnedImageWindowController(
                    image: solidImage(size: initialFrame.size, color: .white),
                    screenRect: initialFrame
                )
                controller.scale(by: 1.5)
                let scaledFrame = controller.test_imageFrameInScreen
                if showsToolbar {
                    controller.test_showEditingToolbar()
                    controller.test_editingOverlayKeyDown(
                        keyCode: shortcut.keyCode,
                        charactersIgnoringModifiers: shortcut.key,
                        modifierFlags: shortcut.modifiers
                    )
                } else {
                    controller.test_keyDown(
                        keyCode: shortcut.keyCode,
                        charactersIgnoringModifiers: shortcut.key,
                        modifierFlags: shortcut.modifiers
                    )
                }

                XCTAssertEqual(controller.test_imageFrameInScreen, scaledFrame)
                XCTAssertEqual(controller.test_windowLevel, .floating)
                controller.window?.close()
            }
        }
    }

    @MainActor
    func testPinnedImageCommandsOnlyAffectOwningPinAndNotCaptureOverlay() {
        let current = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )
        let other = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 100, height: 70), color: .white),
            screenRect: NSRect(x: 240, y: 50, width: 100, height: 70)
        )
        current.scale(by: 1.5)
        other.scale(by: 1.5)
        let otherFrame = other.test_imageFrameInScreen

        current.test_keyDown(keyCode: 15, charactersIgnoringModifiers: "r", modifierFlags: [.command])
        current.test_keyDown(keyCode: 17, charactersIgnoringModifiers: "t", modifierFlags: [.command])

        XCTAssertEqual(current.test_imageFrameInScreen, NSRect(x: 40, y: 50, width: 120, height: 80))
        XCTAssertEqual(current.test_windowLevel, .normal)
        XCTAssertEqual(other.test_imageFrameInScreen, otherFrame)
        XCTAssertEqual(other.test_windowLevel, .floating)

        let captureOverlay = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        XCTAssertFalse(captureOverlay.test_handleKeyDown(
            keyCode: 15,
            charactersIgnoringModifiers: "r",
            modifierFlags: [.command]
        ))
        XCTAssertFalse(captureOverlay.test_handleKeyDown(
            keyCode: 17,
            charactersIgnoringModifiers: "t",
            modifierFlags: [.command]
        ))
        current.window?.close()
        other.window?.close()
    }

    @MainActor
    func testPinnedImageHoverUsesMoveCursorOverImage() throws {
        let controller = PinnedImageWindowController(
            image: solidImage(size: NSSize(width: 120, height: 80), color: .white),
            screenRect: NSRect(x: 40, y: 50, width: 120, height: 80)
        )

        XCTAssertTrue(controller.test_hoverCursorAtImageCenterIsMove)
        XCTAssertTrue(controller.test_hoverCursorAtShadowIsArrow)
    }

    @MainActor
    func testPinnedImageEditorOverlayReusesMainToolbarExceptCaptureButtons() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }

        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .rectangle))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .arrow))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .pen))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .marker))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .eyedropper))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .mosaic))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .text))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .number))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .magnifier))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .eraser))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .undo))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .redo))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .save))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .copy))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .finishEditing))

        XCTAssertNil(window.test_mainToolbarButtonRect(for: .scroll))
        XCTAssertNil(window.test_mainToolbarButtonRect(for: .cancel))
        XCTAssertNil(window.test_mainToolbarButtonRect(for: .pin))
    }

    @MainActor
    func testPinnedImageEditorOverlayHidesMeasurementAndPassiveColorSampler() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }

        XCTAssertNil(window.test_measurementControlPoint(.cornerStyle))
        XCTAssertNil(window.test_measurementControlPoint(.aspectRatioLock))
        XCTAssertNil(window.test_measurementControlPoint(.refresh))

        window.test_updateColorSampler(at: NSPoint(x: selection.midX, y: selection.midY))
        XCTAssertNil(window.test_sampledColorHex)

        let eyedropperPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eyedropper))
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)
        window.test_updateColorSampler(at: NSPoint(x: selection.midX, y: selection.midY))
        XCTAssertNotNil(window.test_sampledColorHex)
    }

    @MainActor
    func testPinnedImageEyedropperMeasurementInvalidatesDashedLineArea() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        let eyedropperPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eyedropper))
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        let start = NSPoint(x: selection.minX + 36, y: selection.minY + 44)
        let end = NSPoint(x: selection.maxX - 42, y: selection.maxY - 38)
        window.test_mouseDown(at: start)
        window.test_mouseMoved(to: end)

        let line = try XCTUnwrap(window.test_eyedropperMeasurementLine)
        let invalidationRect = try XCTUnwrap(window.test_eyedropperMeasurementInvalidationRect)
        XCTAssertTrue(invalidationRect.contains(line.start))
        XCTAssertTrue(invalidationRect.contains(line.end))
    }

    @MainActor
    func testPinnedImageEyedropperMagnifierBuildsVisibleCompositeAtMostOncePerDraw() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .rectangle,
                rect: NSRect(x: 24, y: 24, width: 120, height: 72),
                style: style
            ),
        ])
        let eyedropperPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eyedropper))
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)
        let samplePoint = NSPoint(x: selection.midX, y: selection.midY)
        window.test_updateColorSampler(at: samplePoint)
        let lookupsBeforeDraw = window.test_visibleSelectionCompositeLookupCount

        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertLessThanOrEqual(window.test_visibleSelectionCompositeLookupCount - lookupsBeforeDraw, 1)
    }

    @MainActor
    func testPinnedImageEditorOverlayUsesMoveCursorInsideSelectionWhenNoToolSelected() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }

        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: selection.midX, y: selection.midY)), .move)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: selection.maxX + 12, y: selection.midY)), .arrow)
    }

    @MainActor
    func testDefaultSelectionOverlayUsesCrosshairUntilSelectionMoveBegins() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.test_setLockedSelectionRect(selection)
        let start = NSPoint(x: selection.midX, y: selection.midY)
        let end = NSPoint(x: selection.midX + 24, y: selection.midY - 16)

        window.test_updateColorSampler(at: start)
        XCTAssertTrue(window.test_isColorSamplerVisible)
        XCTAssertEqual(window.test_cursorStyle(at: start), .crosshair)

        window.test_mouseDown(at: start)
        XCTAssertEqual(window.test_cursorStyle(at: start), .move)
        window.test_mouseDragged(to: end)
        XCTAssertEqual(window.test_cursorStyle(at: end), .move)
        window.test_mouseUp(at: end)
        window.test_updateColorSampler(at: end)
        XCTAssertEqual(window.test_cursorStyle(at: end), .crosshair)

        let moved = try XCTUnwrap(window.test_lockedSelectionRect)
        XCTAssertEqual(moved.minX, selection.minX + 24, accuracy: 0.5)
        XCTAssertEqual(moved.minY, selection.minY - 16, accuracy: 0.5)
    }

    @MainActor
    func testSelectionOverlayUsesCrosshairAfterShapeToolIsToggledOff() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.rectangle)
        window.test_toggleShapeTool(.rectangle)

        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: selection.midX, y: selection.midY)), .crosshair)
    }

    @MainActor
    func testPinnedImageEditorOverlayForwardsRightClickToContextMenuHandler() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        var contextMenuPoint: NSPoint?
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(
                windowFrame: NSRect(origin: .zero, size: background.size),
                selectionRect: selection,
                pinnedImageContextMenuHandler: { point in
                    contextMenuPoint = point
                }
            )
        ) { _ in }

        window.test_rightMouseDown(at: NSPoint(x: selection.midX, y: selection.midY))

        XCTAssertNotNil(contextMenuPoint)
    }

    @MainActor
    func testPinnedImageEditorOverlayDoesNotDrawSelectionBorder() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        let rendered = try XCTUnwrap(window.test_renderedOverlayImage())

        let blueBorderPixels = try overlayPixelCount(in: rendered, rect: selection.insetBy(dx: -2, dy: -2)) { pixel in
            pixel.blue > 180 && pixel.red < 120 && pixel.green > 90 && pixel.alpha > 160
        }
        XCTAssertEqual(blueBorderPixels, 0)
    }

    @MainActor
    func testPinnedImageEditorSuppressesMosaicRectangleSelectionOutline() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }

        window.test_activateShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 160, y: 130))
        window.test_mouseDragged(to: NSPoint(x: 260, y: 190))
        window.test_mouseUp(at: NSPoint(x: 260, y: 190))

        XCTAssertEqual(window.test_selectedAnnotationKind, .mosaicRectangle)
        XCTAssertFalse(window.test_selectedAnnotationShowsOutline)
    }

    @MainActor
    func testPinnedImageMosaicPreviewKeepsExistingTextPixelAligned() throws {
        let background = checkerboardImage(size: NSSize(width: 640, height: 420), squareSize: 5)
        let selection = NSRect(x: 173.5, y: 126.5, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }

        var textStyle = CaptureAnnotationStyle()
        textStyle.textSize = 12
        textStyle.strokeColor = .systemRed
        let text = "贴图文字不会抖动"
        let textAnnotation = CaptureAnnotation(
            kind: .text,
            rect: NSRect(
                origin: NSPoint(x: 28.25, y: 34.25),
                size: expectedTextAnnotationSize(text: text, style: textStyle)
            ),
            style: textStyle,
            text: text
        )
        window.test_setAnnotations([textAnnotation])

        var mosaicStyle = CaptureAnnotationStyle()
        mosaicStyle.strokeWidth = 24
        let mosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 18.75, y: 24.75, width: 205.5, height: 82.5),
            style: mosaicStyle,
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: mosaic))
        let expected = CaptureAnnotationRenderer.render(
            image: background,
            annotations: [textAnnotation, mosaic].map { overlayAnnotation($0, selection: selection) }
        )

        try assertPreview(preview, matchesCropFrom: expected)
    }

    @MainActor
    func testPinnedImageSwitchingFromTypedTextToMosaicKeepsTextPixelsStationary() throws {
        let background = retinaSolidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 173.5, y: 126.5, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        window.test_activateTextTool()
        window.test_mouseDown(at: NSPoint(x: selection.minX + 32.25, y: selection.minY + 52.25))
        window.test_mouseUp(at: NSPoint(x: selection.minX + 32.25, y: selection.minY + 52.25))
        window.firstResponder?.insertText("贴图文字")

        let textRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        let before = try XCTUnwrap(window.test_renderedOverlayImage())
        let beforeBounds = try XCTUnwrap(overlayPixelBounds(in: before, rect: textRect) { pixel in
            Int(pixel.red) > Int(pixel.green) + 60 && Int(pixel.red) > Int(pixel.blue) + 60 && pixel.alpha > 160
        })

        window.test_toggleShapeTool(.mosaicRectangle)

        let after = try XCTUnwrap(window.test_renderedOverlayImage())
        let afterBounds = try XCTUnwrap(overlayPixelBounds(in: after, rect: textRect) { pixel in
            Int(pixel.red) > Int(pixel.green) + 60 && Int(pixel.red) > Int(pixel.blue) + 60 && pixel.alpha > 160
        })
        XCTAssertEqual(afterBounds.minX, beforeBounds.minX, accuracy: 0.1)
        XCTAssertEqual(afterBounds.minY, beforeBounds.minY, accuracy: 0.1)
        XCTAssertEqual(afterBounds.width, beforeBounds.width, accuracy: 0.1)
        XCTAssertEqual(afterBounds.height, beforeBounds.height, accuracy: 0.1)
    }

    @MainActor
    func testPinnedImageCommittingMosaicBesideTextKeepsTextPixelsStationary() throws {
        let background = retinaSolidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 173.5, y: 126.5, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        window.test_activateTextTool()
        let textPoint = NSPoint(x: selection.minX + 28.25, y: selection.minY + 48.25)
        window.test_mouseDown(at: textPoint)
        window.test_mouseUp(at: textPoint)
        window.firstResponder?.insertText("贴图文字")

        let textRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        let before = try XCTUnwrap(window.test_renderedOverlayImage())
        let beforeBounds = try XCTUnwrap(overlayPixelBounds(in: before, rect: textRect) { pixel in
            Int(pixel.red) > Int(pixel.green) + 60 && Int(pixel.red) > Int(pixel.blue) + 60 && pixel.alpha > 160
        })

        window.test_toggleShapeTool(.mosaicRectangle)
        let mosaicStart = NSPoint(x: selection.maxX - 72.25, y: selection.maxY - 48.25)
        let mosaicEnd = NSPoint(x: selection.maxX - 16.25, y: selection.maxY - 16.25)
        window.test_mouseDown(at: mosaicStart)
        window.test_mouseDragged(to: mosaicEnd)
        window.test_mouseUp(at: mosaicEnd)

        let after = try XCTUnwrap(window.test_renderedOverlayImage())
        let afterBounds = try XCTUnwrap(overlayPixelBounds(in: after, rect: textRect) { pixel in
            Int(pixel.red) > Int(pixel.green) + 60 && Int(pixel.red) > Int(pixel.blue) + 60 && pixel.alpha > 160
        })
        XCTAssertEqual(afterBounds.minX, beforeBounds.minX, accuracy: 0.1)
        XCTAssertEqual(afterBounds.minY, beforeBounds.minY, accuracy: 0.1)
        XCTAssertEqual(afterBounds.width, beforeBounds.width, accuracy: 0.1)
        XCTAssertEqual(afterBounds.height, beforeBounds.height, accuracy: 0.1)
    }

    @MainActor
    func testPinnedImageFractionalMosaicDraftMatchesFullCanvasTextRedaction() throws {
        let background = retinaSolidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 173.5, y: 126.5, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        window.test_activateTextTool()
        let textPoint = NSPoint(x: selection.minX + 42.25, y: selection.minY + 62.25)
        window.test_mouseDown(at: textPoint)
        window.test_mouseUp(at: textPoint)
        window.firstResponder?.insertText("贴图文字向左移动")
        window.test_toggleShapeTool(.mosaicRectangle)

        let start = NSPoint(x: selection.minX + 34.25, y: selection.minY + 44.25)
        let end = NSPoint(x: selection.minX + 192.75, y: selection.minY + 92.75)
        window.test_mouseDown(at: start)
        window.test_mouseDragged(to: end)

        let textAnnotation = try XCTUnwrap(window.test_annotation(at: 0))
        var draftStyle = try XCTUnwrap(window.test_currentStyle)
        draftStyle.strokeWidth = max(draftStyle.strokeWidth, 1)
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(
                x: start.x - selection.minX,
                y: start.y - selection.minY,
                width: end.x - start.x,
                height: end.y - start.y
            ),
            style: draftStyle,
            mosaicRedaction: CaptureMosaicRedaction(
                type: try XCTUnwrap(window.test_mosaicRedactionType),
                value: window.test_mosaicRedactionValue(for: .pixelMosaic) ?? 8
            )
        )
        let actual = try XCTUnwrap(window.test_renderedOverlayImage())
        let expected = CaptureAnnotationRenderer.render(
            image: background,
            annotations: [textAnnotation, draft].map { overlayAnnotation($0, selection: selection) }
        )
        let comparisonRect = NSRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
            .insetBy(dx: 4, dy: 4)
        let actualCrop = try XCTUnwrap(croppedImage(actual, to: comparisonRect))
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: comparisonRect))

        XCTAssertLessThan(try averagePixelDistance(actualCrop, expectedCrop), 2)
    }

    @MainActor
    func testMosaicStrokeDraftAcrossTypedTextKeepsRenderedTextHorizontallyAligned() throws {
        let background = retinaSolidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 80.234375, y: 80.87890625, width: 480, height: 240)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }
        window.test_activateTextTool()
        let textPoint = NSPoint(x: selection.minX + 92.6171875, y: selection.minY + 118.76171875)
        window.test_mouseDown(at: textPoint)
        window.test_mouseUp(at: textPoint)
        window.firstResponder?.insertText("文字马赛克偏移测试")
        window.test_toggleShapeTool(.mosaicStroke)

        let textAnnotation = try XCTUnwrap(window.test_annotation(at: 0))

        let start = NSPoint(x: textPoint.x - 4, y: textPoint.y)
        let end = NSPoint(x: textPoint.x + 210, y: textPoint.y + 6)
        window.test_mouseDown(at: start)
        window.test_mouseDragged(to: end)

        let localStroke = CaptureMosaicStroke(points: [
            NSPoint(x: start.x - selection.minX, y: start.y - selection.minY),
            NSPoint(x: end.x - selection.minX, y: end.y - selection.minY),
        ])
        let draft = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: localStroke.boundingRect,
            style: try XCTUnwrap(window.test_currentStyle),
            mosaicStroke: localStroke,
            mosaicRedaction: CaptureMosaicRedaction(
                type: try XCTUnwrap(window.test_mosaicRedactionType),
                value: window.test_mosaicRedactionValue(for: .pixelMosaic) ?? 8
            )
        )
        let actual = try XCTUnwrap(window.test_renderedOverlayImage())
        let expected = CaptureAnnotationRenderer.render(
            image: background,
            annotations: [textAnnotation, draft].map { overlayAnnotation($0, selection: selection) }
        )
        let comparisonRect = NSRect(
            x: textPoint.x - 20,
            y: textPoint.y - 32,
            width: 260,
            height: 64
        )
        let isTextPixel: ((red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> Bool = { pixel in
            Int(pixel.red) > Int(pixel.green) + 60
                && Int(pixel.red) > Int(pixel.blue) + 60
                && pixel.alpha > 160
        }
        let actualBounds = try XCTUnwrap(overlayPixelBounds(in: actual, rect: comparisonRect, matching: isTextPixel))
        let expectedBounds = try XCTUnwrap(overlayPixelBounds(in: expected, rect: comparisonRect, matching: isTextPixel))

        XCTAssertEqual(actualBounds.minX, expectedBounds.minX, accuracy: 0.5)
        XCTAssertEqual(actualBounds.minY, expectedBounds.minY, accuracy: 0.5)
        XCTAssertEqual(actualBounds.width, expectedBounds.width, accuracy: 0.5)
        XCTAssertEqual(actualBounds.height, expectedBounds.height, accuracy: 0.5)
    }

    @MainActor
    func testDefaultSelectionOverlayKeepsMosaicRectangleSelectionOutline() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.test_setLockedSelectionRect(selection)

        window.test_activateShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 160, y: 130))
        window.test_mouseDragged(to: NSPoint(x: 260, y: 190))
        window.test_mouseUp(at: NSPoint(x: 260, y: 190))

        XCTAssertEqual(window.test_selectedAnnotationKind, .mosaicRectangle)
        XCTAssertTrue(window.test_selectedAnnotationShowsOutline)
    }

    @MainActor
    func testPinnedImageEditorFinishCompletesSynchronously() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        var result: CaptureSelectionResult?
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { selectionResult in
            result = selectionResult
        }
        let finishPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .finishEditing))

        window.test_mouseDown(at: finishPoint)

        XCTAssertEqual(result?.action, .finishEditing)
    }

    @MainActor
    func testDefaultSelectionOverlayKeepsCaptureToolbarButtons() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 120, y: 90, width: 260, height: 160))

        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .cancel))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .pin))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .save))
        XCTAssertNotNil(window.test_mainToolbarButtonRect(for: .copy))
        XCTAssertNil(window.test_mainToolbarButtonRect(for: .finishEditing))
    }

    @MainActor
    func testDefaultSelectionOverlayKeepsMeasurementAndPassiveColorSampler() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 90, width: 260, height: 160)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.test_setLockedSelectionRect(selection)

        XCTAssertNotNil(window.test_measurementControlPoint(.cornerStyle))
        window.test_updateColorSampler(at: NSPoint(x: selection.midX, y: selection.midY))
        XCTAssertNotNil(window.test_sampledColorHex)
    }

    @MainActor
    func testPinnedImageEditorOverlayScrollWheelScalesPinnedImage() throws {
        let sourceRect = NSRect(x: 120, y: 220, width: 160, height: 90)
        let controller = PinnedImageWindowController(
            image: solidImage(size: sourceRect.size, color: .white),
            screenRect: sourceRect
        )
        controller.test_showEditingToolbar()
        let before = controller.test_imageRectInContent

        controller.test_scrollEditingOverlay(deltaY: 8)

        let after = controller.test_imageRectInContent
        XCTAssertGreaterThan(after.width, before.width)
        XCTAssertGreaterThan(after.height, before.height)
        XCTAssertTrue(controller.test_isToolbarVisible)
        XCTAssertNotNil(controller.test_editingOverlayToolbarButtonRect(for: .finishEditing))
    }

    @MainActor
    func testPinnedImageEditorScrollMapsEraserMaskWithAnnotationCoordinates() throws {
        let sourceRect = NSRect(x: 120, y: 220, width: 160, height: 90)
        let controller = PinnedImageWindowController(
            image: solidImage(size: sourceRect.size, color: .white),
            screenRect: sourceRect
        )
        controller.test_showEditingToolbar()
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 15, width: 60, height: 40),
            style: CaptureAnnotationStyle()
        )
        let mask = EraserMask(
            rect: NSRect(x: 30, y: 20, width: 15, height: 10),
            affectedAnnotationIDs: [annotation.id]
        )
        controller.test_setEditingOverlayState(annotations: [annotation], eraserMasks: [mask])
        let beforeAnnotation = try XCTUnwrap(controller.test_editingOverlayAnnotation(at: 0))

        controller.test_scrollEditingOverlay(deltaY: 8)

        let afterAnnotation = try XCTUnwrap(controller.test_editingOverlayAnnotation(at: 0))
        let afterMask = try XCTUnwrap(controller.test_editingOverlayEraserMask(at: 0))
        let delta = NSPoint(
            x: afterAnnotation.rect.minX - beforeAnnotation.rect.minX,
            y: afterAnnotation.rect.minY - beforeAnnotation.rect.minY
        )
        XCTAssertNotEqual(delta, .zero)
        XCTAssertEqual(afterMask.rect.minX, mask.rect.minX + delta.x, accuracy: 0.001)
        XCTAssertEqual(afterMask.rect.minY, mask.rect.minY + delta.y, accuracy: 0.001)
        XCTAssertEqual(afterMask.rect.size, mask.rect.size)
        XCTAssertEqual(afterMask.id, mask.id)
        XCTAssertEqual(afterMask.affectedAnnotationIDs, mask.affectedAnnotationIDs)
    }

    @MainActor
    func testPinnedImageEditorOverlayDragMovesPinnedImageAndKeepsToolbarVisible() throws {
        let sourceRect = NSRect(x: 220, y: 260, width: 160, height: 90)
        let controller = PinnedImageWindowController(
            image: solidImage(size: sourceRect.size, color: .white),
            screenRect: sourceRect
        )
        controller.test_showEditingToolbar()
        let before = controller.test_imageFrameInScreen

        let beganDrag = controller.test_dragEditingOverlayBy(dx: 24, dy: -16)

        let after = controller.test_imageFrameInScreen
        XCTAssertTrue(beganDrag)
        XCTAssertEqual(after.minX, before.minX + 24, accuracy: 0.5)
        XCTAssertEqual(after.minY, before.minY - 16, accuracy: 0.5)
        XCTAssertTrue(controller.test_isToolbarVisible)
        XCTAssertFalse(controller.test_isEditingOverlayDraggingPinnedImage)
        XCTAssertEqual(controller.test_editingOverlayAlpha, 1)
        XCTAssertNotNil(controller.test_editingOverlayToolbarButtonRect(for: .finishEditing))
    }

    @MainActor
    func testPinnedImageToolbarBakesAnnotationsInsideImageBounds() throws {
        let sourceRect = NSRect(x: 120, y: 220, width: 160, height: 90)
        let controller = PinnedImageWindowController(
            image: solidImage(size: sourceRect.size, color: .white),
            screenRect: sourceRect
        )

        XCTAssertFalse(controller.test_isToolbarVisible)
        controller.test_showEditingToolbar()
        XCTAssertTrue(controller.test_isToolbarVisible)

        XCTAssertNil(controller.test_editingOverlayToolbarButtonRect(for: .scroll))
        XCTAssertNil(controller.test_editingOverlayToolbarButtonRect(for: .cancel))
        XCTAssertNil(controller.test_editingOverlayToolbarButtonRect(for: .pin))
        XCTAssertNotNil(controller.test_editingOverlayToolbarButtonRect(for: .rectangle))
        XCTAssertNotNil(controller.test_editingOverlayToolbarButtonRect(for: .copy))
        XCTAssertNotNil(controller.test_editingOverlayToolbarButtonRect(for: .save))
        XCTAssertNotNil(controller.test_editingOverlayToolbarButtonRect(for: .finishEditing))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 6
        style.strokeColor = NSColor(calibratedRed: 245 / 255, green: 34 / 255, blue: 45 / 255, alpha: 1)
        let rectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 0, y: 0, width: sourceRect.width, height: sourceRect.height),
            style: style
        )
        controller.test_completeEditingOverlay(annotations: [rectangle])

        XCTAssertFalse(controller.test_isToolbarVisible)
        let baked = controller.image
        XCTAssertNotNil(try firstPixel(in: baked, rect: NSRect(x: 1, y: 1, width: baked.size.width - 2, height: 3)) { pixel in
            pixel.red > 180 && pixel.green < 80 && pixel.blue < 80 && pixel.alpha > 150
        })
    }

    @MainActor
    func testPinnedImageToolbarSupportsArrowPenAndMarkerBaking() throws {
        let sourceRect = NSRect(x: 120, y: 220, width: 180, height: 120)
        let controller = PinnedImageWindowController(
            image: solidImage(size: sourceRect.size, color: .white),
            screenRect: sourceRect
        )
        controller.test_showEditingToolbar()
        XCTAssertNotNil(controller.test_editingOverlayToolbarButtonRect(for: .arrow))
        XCTAssertNotNil(controller.test_editingOverlayToolbarButtonRect(for: .pen))
        XCTAssertNotNil(controller.test_editingOverlayToolbarButtonRect(for: .marker))

        var redStyle = CaptureAnnotationStyle()
        redStyle.strokeWidth = 5
        redStyle.strokeColor = .systemRed
        let arrowLine = CaptureArrowLine(
            start: NSPoint(x: 14, y: 20),
            end: NSPoint(x: sourceRect.width - 18, y: sourceRect.height - 24),
            control: NSPoint(x: sourceRect.width / 2, y: sourceRect.height / 2),
            startArrowType: .none,
            endArrowType: .normal
        )
        let arrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: arrowLine.boundingRect,
            style: redStyle,
            arrowLine: arrowLine
        )

        var markerStyle = CaptureAnnotationStyle()
        markerStyle.strokeWidth = 12
        markerStyle.strokeColor = .systemYellow
        let markerLine = CaptureMarkerLine(
            start: NSPoint(x: 18, y: 30),
            end: NSPoint(x: sourceRect.width - 18, y: 30)
        )
        let marker = CaptureAnnotation(
            kind: .marker,
            rect: markerLine.boundingRect,
            style: markerStyle,
            markerLine: markerLine
        )

        controller.test_completeEditingOverlay(annotations: [arrow, marker])

        let baked = controller.image
        XCTAssertNotNil(try firstPixel(in: baked, rect: NSRect(x: 10, y: 10, width: baked.size.width - 20, height: baked.size.height - 20)) { pixel in
            pixel.red > 180 && pixel.green < 120 && pixel.blue < 120 && pixel.alpha > 140
        })
        XCTAssertNotNil(try firstPixel(in: baked, rect: NSRect(x: 10, y: 10, width: baked.size.width - 20, height: baked.size.height - 20)) { pixel in
            pixel.red > 220 && pixel.green > 190 && pixel.blue < 90 && pixel.alpha > 120
        })
    }

    @MainActor
    func testPinnedImageToolbarIconsDoNotRenderAsSolidBlackBlocks() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 160, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }

        let rendered = try XCTUnwrap(window.test_renderedOverlayImage())
        let iconRects = window.test_mainToolbarButtonRects()
        XCTAssertGreaterThanOrEqual(iconRects.count, 12)
        for (index, iconRect) in iconRects.prefix(12).enumerated() {
            let blackPixels = try overlayPixelCount(in: rendered, rect: iconRect) { pixel in
                pixel.red < 20 && pixel.green < 20 && pixel.blue < 20 && pixel.alpha > 220
            }
            let sampledPixels = try overlayPixelCount(in: rendered, rect: iconRect) { _ in true }
            XCTAssertLessThan(
                Double(blackPixels) / Double(max(sampledPixels, 1)),
                0.5,
                "Toolbar icon \(index) rendered as a solid black block"
            )
        }
    }

    @MainActor
    func testPinnedImageFinishEditingIconUsesFullButtonCanvas() throws {
        let background = solidImage(size: NSSize(width: 640, height: 420), color: .white)
        let selection = NSRect(x: 120, y: 160, width: 260, height: 160)
        let window = SelectionOverlayWindow(
            backgroundImage: background,
            configuration: .pinnedImageEditor(selectionRect: selection)
        ) { _ in }

        let rendered = try XCTUnwrap(window.test_renderedOverlayImage())
        let buttonRect = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .finishEditing))
        let leftEdgeBand = NSRect(x: buttonRect.minX + 2, y: buttonRect.minY, width: 4, height: buttonRect.height)
        let rightEdgeBand = NSRect(x: buttonRect.maxX - 6, y: buttonRect.minY, width: 4, height: buttonRect.height)
        let isBlackIconPixel: ((red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> Bool = { pixel in
            pixel.red < 20 && pixel.green < 20 && pixel.blue < 20 && pixel.alpha > 220
        }

        XCTAssertGreaterThan(try overlayPixelCount(in: rendered, rect: leftEdgeBand, matching: isBlackIconPixel), 0)
        XCTAssertGreaterThan(try overlayPixelCount(in: rendered, rect: rightEdgeBand, matching: isBlackIconPixel), 0)
    }

    func testActivatingAnotherToolExitsEyedropperMode() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))

        guard let eyedropperPoint = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }

        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)
        XCTAssertTrue(window.test_isEyedropperToolActive)

        window.test_activateShapeTool(.marker)

        XCTAssertFalse(window.test_isEyedropperToolActive)
        XCTAssertFalse(window.test_eyedropperToolbarButtonIsSelected)
        XCTAssertEqual(window.test_currentShapeKind, .marker)
        XCTAssertEqual(window.test_optionsToolbarMode, .marker)
    }

    func testTextToolbarButtonExitsEyedropperModeAndAcceptsInput() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 240, height: 160)
        let editPoint = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        let eyedropperPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eyedropper))
        let textPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .text))

        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)
        XCTAssertTrue(window.test_isEyedropperToolActive)
        XCTAssertEqual(window.test_cursorStyle(at: editPoint), .eyedropper)

        window.test_mouseDown(at: textPoint)
        window.test_mouseUp(at: textPoint)
        XCTAssertTrue(window.test_isTextToolActive)
        XCTAssertTrue(window.test_textToolbarButtonIsSelected)
        XCTAssertFalse(window.test_isEyedropperToolActive)
        XCTAssertFalse(window.test_eyedropperToolbarButtonIsSelected)
        XCTAssertEqual(window.test_cursorStyle(at: editPoint), .textInput)

        window.test_mouseDown(at: editPoint)
        window.test_mouseUp(at: editPoint)
        XCTAssertTrue(window.test_textEditorIsFirstResponder)
        XCTAssertFalse(window.test_handleKeyDown(keyCode: 0, charactersIgnoringModifiers: "a"))

        window.firstResponder?.insertText("abc")

        XCTAssertEqual(window.test_annotationText(at: 0), "abc")
    }

    func testEyedropperCursorOverridesArrowAnnotationHoverInsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let arrowLine = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        guard let eyedropperPoint = window.test_mainToolbarButtonPoint(for: .eyedropper) else {
            return XCTFail("Expected eyedropper toolbar button")
        }

        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        let start = NSPoint(x: 100 + arrowLine.start.x, y: 100 + arrowLine.start.y)
        let end = NSPoint(x: 100 + arrowLine.end.x, y: 100 + arrowLine.end.y)
        let body = NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

        XCTAssertTrue(window.test_isEyedropperToolActive)
        XCTAssertEqual(window.test_cursorStyle(at: start), .eyedropper)
        XCTAssertEqual(window.test_cursorStyle(at: body), .eyedropper)
        XCTAssertEqual(window.test_cursorStyle(at: end), .eyedropper)
    }

    func testOverlayWindowEscCancelsBeforeSelectionIsLocked() {
        let didCancel = expectation(description: "selection cancelled")
        let window = SelectionOverlayWindow(backgroundImage: nil) { result in
            XCTAssertNil(result)
            didCancel.fulfill()
        }
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )!

        window.keyDown(with: event)

        wait(for: [didCancel], timeout: 0.5)
    }

    func testOverlayWindowResizesSelectionFromBorderWhileBrushToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: selection.maxX + 10, y: selection.midY))
        window.test_mouseDragged(to: NSPoint(x: selection.maxX + 40, y: selection.midY))
        window.test_mouseUp(at: NSPoint(x: selection.maxX + 40, y: selection.midY))

        XCTAssertEqual(window.test_lockedSelectionRect?.origin.x, selection.origin.x)
        XCTAssertEqual(window.test_lockedSelectionRect?.width, selection.width + 40)
    }

    func testOverlayWindowResizesSelectionFromBorderWhileMosaicToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        window.test_mouseDown(at: NSPoint(x: selection.maxX + 10, y: selection.midY))
        window.test_mouseDragged(to: NSPoint(x: selection.maxX + 40, y: selection.midY))
        window.test_mouseUp(at: NSPoint(x: selection.maxX + 40, y: selection.midY))

        XCTAssertEqual(window.test_lockedSelectionRect?.origin.x, selection.origin.x)
        XCTAssertEqual(window.test_lockedSelectionRect?.width, selection.width + 40)
    }

    func testOverlayWindowUsesArrowOutsideSelectionWhileShapeToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.rectangle)

        guard let toolbarPoint = window.test_mainToolbarDragPoint() else {
            return XCTFail("Expected toolbar drag point")
        }
        XCTAssertFalse(selection.contains(toolbarPoint))
        XCTAssertEqual(window.test_cursorStyle(at: toolbarPoint), .arrow)

        window.test_activateShapeTool(.arrowLine)
        XCTAssertEqual(window.test_cursorStyle(at: toolbarPoint), .arrow)
    }

    func testOverlayWindowUsesArrowCursorOnMeasurementToolbarWhileShapeToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        guard let cornerPoint = window.test_measurementControlPoint(.cornerStyle),
              let refreshPoint = window.test_measurementControlPoint(.refresh) else {
            return XCTFail("Expected measurement toolbar points")
        }

        XCTAssertEqual(window.test_cursorStyle(at: cornerPoint), .arrow)
        XCTAssertEqual(window.test_cursorStyle(at: refreshPoint), .arrow)

        window.test_activateShapeTool(.rectangle)
        XCTAssertEqual(window.test_cursorStyle(at: cornerPoint), .arrow)
        XCTAssertEqual(window.test_cursorStyle(at: refreshPoint), .arrow)
    }

    func testPassiveColorSamplerUsesCrosshairForFullScreenSelection() throws {
        let background = solidImage(size: desktopImageSize(), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let screen = try XCTUnwrap(NSScreen.main)
        let selection = NSRect(
            x: screen.frame.minX - window.frame.minX,
            y: screen.frame.minY - window.frame.minY,
            width: screen.frame.width,
            height: screen.frame.height
        )
        let point = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        window.test_updateColorSampler(at: point)

        XCTAssertTrue(window.test_isColorSamplerVisible)
        XCTAssertEqual(window.test_cursorStyle(at: point), .crosshair)
    }

    func testPassiveColorSamplerUsesCrosshairOnDarkFullScreenSelection() throws {
        let background = solidImage(size: desktopImageSize(), color: .black)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let screen = try XCTUnwrap(NSScreen.main)
        let selection = NSRect(
            x: screen.frame.minX - window.frame.minX,
            y: screen.frame.minY - window.frame.minY,
            width: screen.frame.width,
            height: screen.frame.height
        )
        let point = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        window.test_updateColorSampler(at: point)

        XCTAssertTrue(window.test_isColorSamplerVisible)
        XCTAssertEqual(window.test_cursorStyle(at: point), .crosshair)
    }

    func testFullScreenSelectionKeepsCrosshairUntilPassiveSamplerIsVisible() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let screen = try XCTUnwrap(NSScreen.main)
        let selection = NSRect(
            x: screen.frame.minX - window.frame.minX,
            y: screen.frame.minY - window.frame.minY,
            width: screen.frame.width,
            height: screen.frame.height
        )
        let point = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        XCTAssertFalse(window.test_isColorSamplerVisible)
        XCTAssertEqual(window.test_cursorStyle(at: point), .crosshair)
    }

    func testOverlayWindowUsesDrawingCursorInsideSelectionImmediatelyAfterToolSwitch() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let point = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        window.test_activateShapeTool(.rectangle)
        XCTAssertEqual(window.test_cursorStyle(at: point), .crosshair)

        window.test_activateShapeTool(.arrowLine)
        XCTAssertEqual(window.test_cursorStyle(at: point), .crosshair)
    }

    func testOverlayWindowUsesLightBrushCursorOnBlackBackground() {
        let image = solidImage(size: NSSize(width: 500, height: 400), color: .black)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let point = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.brush)

        XCTAssertEqual(window.test_cursorStyle(at: point), .brushLight)
    }

    func testOverlayWindowUsesLightEyedropperCursorOnBlackBackground() throws {
        let image = solidImage(size: NSSize(width: 500, height: 400), color: .black)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let point = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        let eyedropperPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eyedropper))
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        XCTAssertEqual(window.test_cursorStyle(at: point), .eyedropperLight)
    }

    func testOverlayWindowUsesLightMoveCursorOnBlackBackground() {
        let image = solidImage(size: NSSize(width: 500, height: 400), color: .black)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.rectangle)
        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        window.test_mouseDown(at: NSPoint(x: 160, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 150))
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 170, y: 150)), .moveLight)
        window.test_mouseUp(at: NSPoint(x: 170, y: 150))
    }

    func testOverlayWindowUsesLightSelectionResizeCursorsOnBlackBackground() {
        let image = solidImage(size: NSSize(width: 500, height: 400), color: .black)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)

        let handles: [(NSPoint, SelectionToolbarState.OverlayCursorStyle)] = [
            (NSPoint(x: selection.minX, y: selection.maxY), .resizeTopLeftLight),
            (NSPoint(x: selection.maxX, y: selection.maxY), .resizeTopRightLight),
            (NSPoint(x: selection.minX, y: selection.minY), .resizeBottomLeftLight),
            (NSPoint(x: selection.maxX, y: selection.minY), .resizeBottomRightLight),
            (NSPoint(x: selection.midX, y: selection.maxY), .resizeUpDownLight),
            (NSPoint(x: selection.maxX, y: selection.midY), .resizeLeftRightLight)
        ]

        for (point, expected) in handles {
            XCTAssertEqual(window.test_cursorStyle(at: point), expected)
        }
    }

    func testMarkerPreviewRemainsVisibleOnBlackBackgroundWithBlackMarkerColor() throws {
        let image = solidImage(size: NSSize(width: 500, height: 400), color: .black)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)

        let blackSwatch = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 2))
        window.test_mouseDown(at: blackSwatch)
        window.test_mouseUp(at: blackSwatch)
        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 240, y: 150))
        window.test_mouseUp(at: NSPoint(x: 240, y: 150))

        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let markerPixel = try firstPixel(
            in: overlayImage,
            rect: NSRect(x: 135, y: 140, width: 110, height: 20)
        ) { pixel in
            pixel.red > 180 && pixel.green > 180 && pixel.blue > 180 && pixel.alpha > 120
        }

        XCTAssertNotNil(markerPixel)
    }

    func testOverlayWindowUsesTextInputCursorForTextToolInsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let point = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        XCTAssertEqual(window.test_cursorStyle(at: point), .textInput)
    }

    func testDraggingInsideSelectionWithTextToolDoesNotMoveSelectionRegion() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 260, height: 180)
        let start = NSPoint(x: selection.midX, y: selection.midY)
        let firstDrag = NSPoint(x: start.x + 72, y: start.y + 34)
        let end = NSPoint(x: firstDrag.x + 18, y: firstDrag.y + 12)
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: start)
        window.test_mouseDragged(to: firstDrag)
        window.test_mouseDragged(to: end)
        window.test_mouseUp(at: end)

        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertTrue(window.test_isEditingTextAnnotation)
        XCTAssertEqual(window.test_annotationCount, 1)
    }

    func testOverlayWindowUsesActiveDrawingCursorOutsideSelectionAwayFromBorder() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let outsidePoint = NSPoint(x: selection.maxX + 40, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        let cases: [(CaptureAnnotationKind, SelectionToolbarState.OverlayCursorStyle)] = [
            (.rectangle, .crosshair),
            (.arrowLine, .crosshair),
            (.brush, .brush),
            (.marker, .marker)
        ]

        for (shape, expectedCursor) in cases {
            window.test_activateShapeTool(shape)
            XCTAssertEqual(window.test_cursorStyle(at: outsidePoint), expectedCursor)
        }
    }

    func testOverlayWindowActivatesMosaicTool() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        guard let point = window.test_mainToolbarButtonPoint(for: .mosaic) else {
            return XCTFail("Expected mosaic toolbar button")
        }
        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)

        XCTAssertEqual(window.test_optionsToolbarMode, .mosaic)
        XCTAssertEqual(window.test_currentShapeKind, .mosaicStroke)
        XCTAssertEqual(window.test_currentStyle?.strokeWidth, 15)
        XCTAssertEqual(window.test_mosaicRedactionType, .pixelMosaic)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .gaussianBlur), 8)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .pixelMosaic), 8)
    }

    func testOverlayWindowActivatesEraserToolWithPointModeOptionsToolbar() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))

        let point = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eraser))
        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)

        XCTAssertTrue(window.test_isEraserToolActive)
        XCTAssertTrue(window.test_eraserToolbarButtonIsSelected)
        XCTAssertEqual(window.test_optionsToolbarMode, .eraser)
        XCTAssertNotNil(window.test_eraserPointOptionPoint())
        XCTAssertNotNil(window.test_eraserRectangleOptionPoint())
        XCTAssertNotNil(window.test_eraserClearAllOptionPoint())
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 160, y: 160)), .eraser)
        XCTAssertFalse(window.test_isEyedropperToolActive)
        XCTAssertFalse(window.test_isTextToolActive)
        XCTAssertFalse(window.test_isNumberToolActive)
        XCTAssertFalse(window.test_isMagnifierToolActive)
        XCTAssertNil(window.test_currentShapeKind)
    }

    func testCaptureAnnotationsReceiveStableUniqueIDs() {
        let first = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 40, height: 30), style: CaptureAnnotationStyle())
        let second = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 40, height: 30), style: CaptureAnnotationStyle())

        XCTAssertNotEqual(first.id, second.id)

        var edited = first
        edited.rect.origin.x += 12
        XCTAssertEqual(edited.id, first.id)
    }

    func testEraserMaskStoresLocalRectAndAffectedAnnotationIDs() {
        let annotation = CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 20, y: 30, width: 80, height: 40), style: CaptureAnnotationStyle())
        let mask = EraserMask(
            rect: NSRect(x: 25, y: 35, width: 20, height: 18),
            affectedAnnotationIDs: [annotation.id]
        )

        XCTAssertEqual(mask.rect, NSRect(x: 25, y: 35, width: 20, height: 18))
        XCTAssertEqual(mask.affectedAnnotationIDs, [annotation.id])
    }

    func testExistingToolsStillCreateAnnotationsAfterUsingEraserTool() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 320, height: 240)
        window.test_setLockedSelectionRect(selection)

        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        window.test_activateShapeTool(.rectangle)
        window.test_drag(from: NSPoint(x: 130, y: 140), to: NSPoint(x: 220, y: 210))
        window.test_activateShapeTool(.arrowLine)
        window.test_drag(from: NSPoint(x: 150, y: 220), to: NSPoint(x: 280, y: 240))
        window.test_activateShapeTool(.brush)
        window.test_drag(from: NSPoint(x: 170, y: 180), to: NSPoint(x: 230, y: 190))
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_drag(from: NSPoint(x: 240, y: 130), to: NSPoint(x: 300, y: 190))

        XCTAssertEqual(window.test_annotationCount, 4)
        XCTAssertEqual(window.test_eraserMaskCount, 0)
    }

    func testCaptureResultIncludesEraserMasks() throws {
        let image = solidImage(size: NSSize(width: 240, height: 160), color: .white)
        var result: CaptureSelectionResult?
        let expectation = expectation(description: "copy")
        let window = SelectionOverlayWindow(backgroundImage: image) { selectionResult in
            result = selectionResult
            expectation.fulfill()
        }
        let selection = NSRect(x: 40, y: 30, width: 160, height: 100)
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 20, y: 20, width: 80, height: 60), style: CaptureAnnotationStyle())
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(rect: NSRect(x: 30, y: 30, width: 20, height: 20), affectedAnnotationIDs: [annotation.id]))

        window.test_keyDown(keyCode: 8, charactersIgnoringModifiers: "c", modifierFlags: [.command])
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(result?.annotations.count, 1)
        XCTAssertEqual(result?.eraserMasks.count, 1)
    }

    func testEraserToolClearsAndSuppressesColorSampler() {
        let background = solidImage(size: NSSize(width: 260, height: 160), color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 40, y: 30, width: 160, height: 100))

        window.test_updateColorSampler(at: NSPoint(x: 80, y: 80))
        XCTAssertTrue(window.test_isColorSamplerVisible)
        XCTAssertNotNil(window.test_sampledColorHex)

        window.test_activateEraserTool()
        XCTAssertFalse(window.test_isColorSamplerVisible)
        XCTAssertNil(window.test_sampledColorHex)

        window.test_mouseMoved(to: NSPoint(x: 90, y: 90))
        window.test_updateColorSampler(at: NSPoint(x: 90, y: 90))
        XCTAssertFalse(window.test_isColorSamplerVisible)
        XCTAssertNil(window.test_sampledColorHex)
    }

    func testEraserOptionsSwitchRectangleModeAndCursor() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))
        window.test_activateEraserTool()

        let rectanglePoint = try XCTUnwrap(window.test_eraserRectangleOptionPoint())
        window.test_mouseDown(at: rectanglePoint)
        window.test_mouseUp(at: rectanglePoint)

        XCTAssertEqual(window.test_optionsToolbarMode, .eraser)
        XCTAssertTrue(window.test_isEraserRectangleModeActive)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 160, y: 160)), .crosshair)

        let pointEraserPoint = try XCTUnwrap(window.test_eraserPointOptionPoint())
        window.test_mouseDown(at: pointEraserPoint)
        window.test_mouseUp(at: pointEraserPoint)

        XCTAssertFalse(window.test_isEraserRectangleModeActive)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 160, y: 160)), .eraser)
    }

    func testEraserOptionsToolbarTipsFollowOptionButtons() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))
        window.test_activateEraserTool()

        window.test_mouseMoved(to: try XCTUnwrap(window.test_eraserPointOptionPoint()))
        XCTAssertEqual(window.test_hoveredTooltipText, "橡皮擦")

        window.test_mouseMoved(to: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        XCTAssertEqual(window.test_hoveredTooltipText, "矩形擦除")

        window.test_mouseMoved(to: try XCTUnwrap(window.test_eraserClearAllOptionPoint()))
        XCTAssertEqual(window.test_hoveredTooltipText, "清除所有")
    }

    func testEraserOptionsToolbarIsCompactAndAnchoredUnderEraserButton() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))
        window.test_activateEraserTool()

        let mainEraserRect = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .eraser))
        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)
        let pointRect = try XCTUnwrap(window.test_eraserPointOptionRect)
        let rectangleRect = try XCTUnwrap(window.test_eraserRectangleOptionRect)
        let separatorRect = try XCTUnwrap(window.test_eraserClearAllSeparatorRect)
        let clearAllRect = try XCTUnwrap(window.test_eraserClearAllOptionRect)

        XCTAssertEqual(optionsRect.height, 28)
        XCTAssertEqual(pointRect.size, mainEraserRect.size)
        XCTAssertEqual(rectangleRect.size, mainEraserRect.size)
        XCTAssertEqual(clearAllRect.size, mainEraserRect.size)
        XCTAssertLessThan(rectangleRect.maxX, separatorRect.minX)
        XCTAssertLessThan(separatorRect.maxX, clearAllRect.minX)
        XCTAssertEqual(optionsRect.maxX - clearAllRect.maxX, 8, accuracy: 0.5)
        XCTAssertEqual(optionsRect.midX, mainEraserRect.midX, accuracy: 0.5)
        XCTAssertLessThan(optionsRect.maxY, mainEraserRect.minY)
    }

    func testBrushOptionsToolbarIsAnchoredUnderBrushButton() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 220))
        window.test_activateShapeTool(.brush)

        let brushRect = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .pen))
        let toolbarRect = try XCTUnwrap(window.test_mainToolbarRect())
        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)

        XCTAssertLessThan(brushRect.midX - optionsRect.width / 2, toolbarRect.minX)
        XCTAssertLessThanOrEqual(optionsRect.maxX, toolbarRect.maxX + 0.5)
        XCTAssertEqual(optionsRect.minX, toolbarRect.minX, accuracy: 0.5)
        XCTAssertLessThan(optionsRect.maxY, brushRect.minY)
    }

    func testMarkerOptionsToolbarIsAnchoredUnderMarkerButton() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 220))
        window.test_activateShapeTool(.marker)

        let markerRect = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .marker))
        let toolbarRect = try XCTUnwrap(window.test_mainToolbarRect())
        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)

        XCTAssertLessThan(markerRect.midX - optionsRect.width / 2, toolbarRect.minX)
        XCTAssertLessThanOrEqual(optionsRect.maxX, toolbarRect.maxX + 0.5)
        XCTAssertEqual(optionsRect.minX, toolbarRect.minX, accuracy: 0.5)
        XCTAssertLessThan(optionsRect.maxY, markerRect.minY)
    }

    func testMosaicOptionsToolbarIsAnchoredUnderMosaicButton() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 220))
        window.test_activateShapeTool(.mosaicStroke)

        let mosaicRect = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .mosaic))
        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)

        XCTAssertEqual(optionsRect.midX, mosaicRect.midX, accuracy: 0.5)
        XCTAssertLessThan(optionsRect.maxY, mosaicRect.minY)
    }

    func testShapeArrowAndTextOptionsToolbarsAreLeftAlignedWithMainToolbar() throws {
        let shapeWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        shapeWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 220))
        shapeWindow.test_activateShapeTool(.rectangle)
        XCTAssertEqual(
            try XCTUnwrap(shapeWindow.test_optionsToolbarRect).minX,
            try XCTUnwrap(shapeWindow.test_mainToolbarRect()).minX,
            accuracy: 0.5
        )

        let arrowWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        arrowWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 220))
        arrowWindow.test_activateShapeTool(.arrowLine)
        XCTAssertEqual(
            try XCTUnwrap(arrowWindow.test_optionsToolbarRect).minX,
            try XCTUnwrap(arrowWindow.test_mainToolbarRect()).minX,
            accuracy: 0.5
        )

        let textWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        textWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 220))
        textWindow.test_activateTextTool()
        XCTAssertEqual(
            try XCTUnwrap(textWindow.test_optionsToolbarRect).minX,
            try XCTUnwrap(textWindow.test_mainToolbarRect()).minX,
            accuracy: 0.5
        )
    }

    func testTextEraserAndMagnifierUseDrawingCursorsOutsideSelection() throws {
        let selection = NSRect(x: 100, y: 100, width: 260, height: 160)
        let outsidePoint = NSPoint(x: selection.maxX + 36, y: selection.midY)

        let textWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        textWindow.test_setLockedSelectionRect(selection)
        textWindow.test_activateTextTool()
        XCTAssertEqual(textWindow.test_cursorStyle(at: outsidePoint), .textInput)
        XCTAssertEqual(textWindow.test_cursorStyle(at: try XCTUnwrap(textWindow.test_mainToolbarButtonPoint(for: .text))), .arrow)

        let eraserWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        eraserWindow.test_setLockedSelectionRect(selection)
        eraserWindow.test_activateEraserTool()
        XCTAssertEqual(eraserWindow.test_cursorStyle(at: outsidePoint), .eraser)
        XCTAssertEqual(eraserWindow.test_cursorStyle(at: try XCTUnwrap(eraserWindow.test_mainToolbarButtonPoint(for: .eraser))), .arrow)

        let magnifierWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        magnifierWindow.test_setLockedSelectionRect(selection)
        magnifierWindow.test_activateMagnifierTool()
        XCTAssertEqual(magnifierWindow.test_cursorStyle(at: outsidePoint), .crosshair)
        XCTAssertEqual(magnifierWindow.test_cursorStyle(at: try XCTUnwrap(magnifierWindow.test_mainToolbarButtonPoint(for: .magnifier))), .arrow)
    }

    func testMagnifierKeepsCrosshairCursorInsideSelection() {
        let selection = NSRect(x: 100, y: 100, width: 260, height: 160)
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_activateMagnifierTool()

        XCTAssertEqual(
            window.test_cursorStyle(at: NSPoint(x: selection.midX, y: selection.midY)),
            .crosshair
        )
    }

    func testTextToolCreatesTextAnnotationOutsideSelection() throws {
        let selection = NSRect(x: 100, y: 100, width: 260, height: 160)
        let outsidePoint = NSPoint(x: selection.maxX + 48, y: selection.midY)
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_activateTextTool()

        window.test_mouseDown(at: outsidePoint)
        window.test_mouseUp(at: outsidePoint)

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertTrue(window.test_isEditingTextAnnotation)
        XCTAssertGreaterThan(try XCTUnwrap(window.test_annotationOverlayRect(at: 0)).minX, selection.maxX)
    }

    func testEraserClearAllDeletesAllAnnotationsAndSupportsUndoRedo() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_setAnnotations([
            CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 35, y: 45, width: 60, height: 60), style: CaptureAnnotationStyle()),
            CaptureAnnotation(
                kind: .mosaicStroke,
                rect: NSRect(x: 80, y: 80, width: 50, height: 20),
                style: CaptureAnnotationStyle(),
                mosaicStroke: CaptureMosaicStroke(points: [
                    NSPoint(x: 80, y: 80),
                    NSPoint(x: 130, y: 100),
                ]),
                mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
            ),
            CaptureAnnotation(
                kind: .arrowLine,
                rect: NSRect(x: 20, y: 20, width: 130, height: 70),
                style: CaptureAnnotationStyle(),
                arrowLine: CaptureArrowLine(
                    start: NSPoint(x: 20, y: 20),
                    end: NSPoint(x: 150, y: 90),
                    control: NSPoint(x: 85, y: 55),
                    startArrowType: .none,
                    endArrowType: .normal
                )
            ),
        ])
        window.test_activateEraserTool()

        let clearAllPoint = try XCTUnwrap(window.test_eraserClearAllOptionPoint())
        window.test_mouseDown(at: clearAllPoint)
        window.test_mouseUp(at: clearAllPoint)

        XCTAssertEqual(window.test_annotationCount, 0)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
        XCTAssertEqual(window.test_annotationCount, 3)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift])
        XCTAssertEqual(window.test_annotationCount, 0)
    }

    func testEraserClearAllRemovesAnnotationsAndMasksAndSupportsUndoRedo() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 35, y: 45, width: 60, height: 60), style: CaptureAnnotationStyle())
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(rect: NSRect(x: 40, y: 45, width: 10, height: 10), affectedAnnotationIDs: [annotation.id]))
        window.test_activateEraserTool()

        let clearAllPoint = try XCTUnwrap(window.test_eraserClearAllOptionPoint())
        window.test_mouseDown(at: clearAllPoint)
        window.test_mouseUp(at: clearAllPoint)

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_eraserMaskCount, 0)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_eraserMaskCount, 1)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift])
        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_eraserMaskCount, 0)
    }

    func testEraserClearAllRedoRemovesMasksWhenNoAnnotationsWereCleared() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let mask = EraserMask(
            rect: NSRect(x: 40, y: 45, width: 10, height: 10),
            affectedAnnotationIDs: [UUID()]
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setEraserMasks([mask])
        window.test_activateEraserTool()

        let clearAllPoint = try XCTUnwrap(window.test_eraserClearAllOptionPoint())
        window.test_mouseDown(at: clearAllPoint)
        window.test_mouseUp(at: clearAllPoint)

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_eraserMaskCount, 0)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.id, mask.id)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift])
        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_eraserMaskCount, 0)
    }

    func testEraserRectangleDragShowsBlueDashedPreview() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        let start = NSPoint(x: 150, y: 150)
        let end = NSPoint(x: 240, y: 205)
        window.test_mouseDown(at: start)
        window.test_mouseDragged(to: end)

        XCTAssertEqual(window.test_eraserRectanglePreviewRect, NSRect(x: 150, y: 150, width: 90, height: 55))
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let previewProbe = NSRect(x: start.x - 2, y: start.y - 2, width: 94, height: 59)
        XCTAssertNotNil(try firstPixel(in: image, rect: previewProbe) { pixel in
            pixel.red < 90 && pixel.green > 90 && pixel.blue > 180 && pixel.alpha > 120
        })
    }

    func testEraserRectangleDragKeepsAnnotationsStableUntilCommit() throws {
        let background = retinaSolidImage(size: NSSize(width: 620, height: 460), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let selection = NSRect(x: 100.25, y: 100.25, width: 300.5, height: 220.5)
        var redTextStyle = CaptureAnnotationStyle()
        redTextStyle.strokeColor = .systemRed
        redTextStyle.textSize = 32
        redTextStyle.textOutlineEnabled = false
        let text = CaptureAnnotation(
            kind: .text,
            rect: NSRect(x: 50, y: 80, width: 180, height: 44),
            style: redTextStyle,
            text: "Preview"
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([text])

        let textProbe = NSRect(
            x: selection.minX + text.rect.minX,
            y: selection.minY + text.rect.minY,
            width: text.rect.width,
            height: text.rect.height
        )
        let erasedInteriorProbe = NSRect(
            x: textProbe.minX + 4,
            y: textProbe.minY + 4,
            width: textProbe.width / 2 - 8,
            height: textProbe.height - 8
        )
        let beforeImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let beforeRedPixelCount = try overlayPixelCount(in: beforeImage, rect: erasedInteriorProbe) { pixel in
            pixel.red > 180 && pixel.green < 120 && pixel.blue < 120 && pixel.alpha > 120
        }
        XCTAssertGreaterThan(beforeRedPixelCount, 0)

        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseDown(at: NSPoint(x: textProbe.minX, y: textProbe.minY))
        window.test_mouseDragged(to: NSPoint(x: textProbe.midX, y: textProbe.maxY))

        XCTAssertEqual(window.test_eraserMaskCount, 0)
        let previewImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let previewRedPixelCount = try overlayPixelCount(in: previewImage, rect: erasedInteriorProbe) { pixel in
            pixel.red > 180 && pixel.green < 120 && pixel.blue < 120 && pixel.alpha > 120
        }
        XCTAssertEqual(previewRedPixelCount, beforeRedPixelCount)
    }

    func testEraserRectangleMaskKeepsFractionalRetinaBackgroundPixelsStableAfterCommit() throws {
        let background = retinaColorStripeImage(size: NSSize(width: 620, height: 460))
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let selection = NSRect(x: 100.25, y: 100.25, width: 300.5, height: 220.5)
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 8
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 32, y: 34, width: 72, height: 58),
            style: style
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        let stableProbe = NSRect(
            x: selection.minX + 176,
            y: selection.minY + 132,
            width: 48,
            height: 36
        )
        let before = try XCTUnwrap(window.test_renderedOverlayImage())
        let beforePixels = try rgbaRenderValues(in: before, rect: stableProbe)

        window.test_drag(
            from: NSPoint(x: selection.minX + 38, y: selection.minY + 40),
            to: NSPoint(x: selection.minX + 92, y: selection.minY + 82)
        )

        XCTAssertEqual(window.test_eraserMaskCount, 1)
        let after = try XCTUnwrap(window.test_renderedOverlayImage())
        let drawRect = try XCTUnwrap(window.test_eraserMaskedCompositeDrawRect)
        let pixelRect = try XCTUnwrap(window.test_eraserMaskedCompositePixelRect)
        XCTAssertEqual(drawRect.width * 2, pixelRect.width, accuracy: 0.001)
        XCTAssertEqual(drawRect.height * 2, pixelRect.height, accuracy: 0.001)
        XCTAssertEqual(drawRect.minX * 2, pixelRect.minX, accuracy: 0.001)
        XCTAssertEqual(
            (background.size.height - drawRect.maxY) * 2,
            pixelRect.minY,
            accuracy: 0.001
        )
        XCTAssertEqual(try rgbaRenderValues(in: after, rect: stableProbe), beforePixels)
    }

    func testSecondEraserRectangleDragReusesCommittedMaskedCompositeUntilMouseUp() throws {
        let background = checkerboardImage(size: NSSize(width: 620, height: 460), squareSize: 3)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let selection = NSRect(x: 100.25, y: 100.25, width: 300.5, height: 220.5)
        let first = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 30, y: 35, width: 70, height: 55),
            style: CaptureAnnotationStyle()
        )
        let second = CaptureAnnotation(
            kind: .ellipse,
            rect: NSRect(x: 180, y: 120, width: 70, height: 55),
            style: CaptureAnnotationStyle()
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([first, second])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_drag(
            from: NSPoint(x: selection.minX + 36, y: selection.minY + 40),
            to: NSPoint(x: selection.minX + 88, y: selection.minY + 82)
        )
        XCTAssertEqual(window.test_eraserMaskCount, 1)

        _ = try XCTUnwrap(window.test_renderedOverlayImage())
        let renderCountAfterWarmup = window.test_eraserMaskedCompositeRenderCount
        let cacheHitsAfterWarmup = window.test_eraserMaskedCompositeCacheHitCount
        XCTAssertEqual(renderCountAfterWarmup, 1)

        let start = NSPoint(x: selection.minX + 186, y: selection.minY + 126)
        let dragPoints = [
            NSPoint(x: selection.minX + 214, y: selection.minY + 146),
            NSPoint(x: selection.minX + 232, y: selection.minY + 160),
            NSPoint(x: selection.minX + 244, y: selection.minY + 168),
        ]
        window.test_mouseDown(at: start)
        for point in dragPoints {
            window.test_mouseDragged(to: point)
            _ = try XCTUnwrap(window.test_renderedOverlayImage())
        }

        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_eraserMaskedCompositeRenderCount, renderCountAfterWarmup)
        XCTAssertEqual(
            window.test_eraserMaskedCompositeCacheHitCount,
            cacheHitsAfterWarmup + dragPoints.count
        )

        window.test_mouseUp(at: try XCTUnwrap(dragPoints.last))
        XCTAssertEqual(window.test_eraserMaskCount, 2)
        _ = try XCTUnwrap(window.test_renderedOverlayImage())
        XCTAssertEqual(window.test_eraserMaskedCompositeRenderCount, renderCountAfterWarmup + 1)
    }

    func testSecondEraserRectangleDragReusesOutsideMaskedAnnotationUntilMouseUp() throws {
        let background = solidImage(size: NSSize(width: 720, height: 460), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        var textStyle = CaptureAnnotationStyle()
        textStyle.strokeColor = .systemRed
        textStyle.textSize = 30
        textStyle.textOutlineEnabled = false
        let crossingText = CaptureAnnotation(
            kind: .text,
            rect: NSRect(x: 270, y: 82, width: 170, height: 44),
            style: textStyle,
            text: "Crossing"
        )
        let insideRectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 38, y: 42, width: 76, height: 62),
            style: CaptureAnnotationStyle()
        )
        let existingMask = EraserMask(
            rect: NSRect(x: 282, y: 88, width: 42, height: 32),
            affectedAnnotationIDs: [crossingText.id]
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([crossingText, insideRectangle])
        window.test_setEraserMasks([existingMask])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        _ = try XCTUnwrap(window.test_renderedOverlayImage())
        let renderCountAfterWarmup = window.test_outsideMaskedAnnotationRenderCount
        let cacheHitsAfterWarmup = window.test_outsideMaskedAnnotationCacheHitCount
        XCTAssertEqual(renderCountAfterWarmup, 1)

        let start = NSPoint(x: selection.minX + 44, y: selection.minY + 48)
        let dragPoints = [
            NSPoint(x: selection.minX + 78, y: selection.minY + 72),
            NSPoint(x: selection.minX + 96, y: selection.minY + 88),
            NSPoint(x: selection.minX + 108, y: selection.minY + 98),
        ]
        window.test_mouseDown(at: start)
        for point in dragPoints {
            window.test_mouseDragged(to: point)
            _ = try XCTUnwrap(window.test_renderedOverlayImage())
        }

        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_outsideMaskedAnnotationRenderCount, renderCountAfterWarmup)
        XCTAssertEqual(
            window.test_outsideMaskedAnnotationCacheHitCount,
            cacheHitsAfterWarmup + dragPoints.count
        )

        window.test_mouseUp(at: try XCTUnwrap(dragPoints.last))
        XCTAssertEqual(window.test_eraserMaskCount, 2)
        _ = try XCTUnwrap(window.test_renderedOverlayImage())
        XCTAssertEqual(window.test_outsideMaskedAnnotationRenderCount, renderCountAfterWarmup + 1)
    }

    func testEraserMaskedCompositeInvalidatesOnceForEachRenderedStateChange() throws {
        let selection = NSRect(x: 100.25, y: 100.25, width: 300.5, height: 220.5)
        let firstBackground = retinaColorStripeImage(size: NSSize(width: 620, height: 460))
        let window = SelectionOverlayWindow(backgroundImage: firstBackground) { _ in }
        var annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 32, y: 34, width: 72, height: 58),
            style: CaptureAnnotationStyle()
        )
        var mask = EraserMask(
            rect: NSRect(x: 40, y: 42, width: 24, height: 20),
            affectedAnnotationIDs: [annotation.id]
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_setEraserMasks([mask])

        _ = try XCTUnwrap(window.test_renderedOverlayImage())
        var expectedRenderCount = window.test_eraserMaskedCompositeRenderCount
        XCTAssertEqual(expectedRenderCount, 1)
        _ = try XCTUnwrap(window.test_renderedOverlayImage())
        XCTAssertEqual(window.test_eraserMaskedCompositeRenderCount, expectedRenderCount)

        annotation.style.strokeWidth += 1
        window.test_setAnnotations([annotation])
        _ = try XCTUnwrap(window.test_renderedOverlayImage())
        expectedRenderCount += 1
        XCTAssertEqual(window.test_eraserMaskedCompositeRenderCount, expectedRenderCount)

        mask.rect.origin.x += 1
        window.test_setEraserMasks([mask])
        _ = try XCTUnwrap(window.test_renderedOverlayImage())
        expectedRenderCount += 1
        XCTAssertEqual(window.test_eraserMaskedCompositeRenderCount, expectedRenderCount)

        window.updatePinnedImageEditor(
            windowFrame: window.frame,
            backgroundImage: retinaColorStripeImage(size: NSSize(width: 620, height: 460)),
            selectionRect: selection
        )
        _ = try XCTUnwrap(window.test_renderedOverlayImage())
        expectedRenderCount += 1
        XCTAssertEqual(window.test_eraserMaskedCompositeRenderCount, expectedRenderCount)

        window.test_setLockedSelectionRect(selection.offsetBy(dx: 0.25, dy: 0.25))
        _ = try XCTUnwrap(window.test_renderedOverlayImage())
        expectedRenderCount += 1
        XCTAssertEqual(window.test_eraserMaskedCompositeRenderCount, expectedRenderCount)
    }

    func testEraserRectangleCreatesLocalMaskAndKeepsAnnotations() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let rectangle = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 35, y: 45, width: 60, height: 60), style: CaptureAnnotationStyle())
        let ellipse = CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 120, y: 75, width: 70, height: 60), style: CaptureAnnotationStyle())
        let text = CaptureAnnotation(kind: .text, rect: NSRect(x: 210, y: 125, width: 64, height: 36), style: CaptureAnnotationStyle(), text: "keep")
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([rectangle, ellipse, text])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        window.test_drag(from: NSPoint(x: 120, y: 130), to: NSPoint(x: 300, y: 225))

        XCTAssertEqual(window.test_annotationCount, 3)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.rect, NSRect(x: 20, y: 30, width: 180, height: 95))
        XCTAssertEqual(window.test_damagedAnnotationCount, 2)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.affectedAnnotationIDs, Set([rectangle.id, ellipse.id]))

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
        XCTAssertEqual(window.test_annotationCount, 3)
        XCTAssertEqual(window.test_eraserMaskCount, 0)
        XCTAssertEqual(window.test_damagedAnnotationCount, 0)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift])
        XCTAssertEqual(window.test_annotationCount, 3)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_damagedAnnotationCount, 2)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.affectedAnnotationIDs, Set([rectangle.id, ellipse.id]))
    }

    func testEraserRectangleMaskKeepsTextOutsideSelectionVisible() throws {
        let background = solidImage(size: NSSize(width: 620, height: 460), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        var redTextStyle = CaptureAnnotationStyle()
        redTextStyle.strokeColor = .systemRed
        redTextStyle.textSize = 28
        redTextStyle.textOutlineEnabled = false
        let rectangle = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 35, y: 45, width: 60, height: 60), style: CaptureAnnotationStyle())
        let outsideText = CaptureAnnotation(
            kind: .text,
            rect: NSRect(x: selection.width + 28, y: 86, width: 120, height: 36),
            style: redTextStyle,
            text: "Outside"
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([rectangle, outsideText])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        window.test_drag(from: NSPoint(x: 120, y: 130), to: NSPoint(x: 210, y: 220))

        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertFalse(window.test_damagedAnnotationIDs.contains(outsideText.id))
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let outsideTextRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 1)).insetBy(dx: -4, dy: -4)
        XCTAssertNotNil(try firstPixel(in: image, rect: outsideTextRect) { pixel in
            pixel.red > 180 && pixel.green < 120 && pixel.blue < 120 && pixel.alpha > 120
        })
    }

    func testEraserRectangleMasksTextOutsideSelection() throws {
        let background = solidImage(size: NSSize(width: 720, height: 460), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        var redTextStyle = CaptureAnnotationStyle()
        redTextStyle.strokeColor = .systemRed
        redTextStyle.textSize = 32
        redTextStyle.textOutlineEnabled = false
        let outsideText = CaptureAnnotation(
            kind: .text,
            rect: NSRect(x: selection.width + 32, y: 86, width: 180, height: 44),
            style: redTextStyle,
            text: "Outside"
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([outsideText])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        window.test_drag(from: NSPoint(x: selection.maxX + 34, y: 178), to: NSPoint(x: selection.maxX + 86, y: 236))

        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertTrue(window.test_damagedAnnotationIDs.contains(outsideText.id))
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let erasedProbe = NSRect(x: selection.maxX + 34, y: 178, width: 52, height: 58)
        XCTAssertEqual(try overlayPixelCount(in: image, rect: erasedProbe) { pixel in
            pixel.red > 180 && pixel.green < 120 && pixel.blue < 120 && pixel.alpha > 120
        }, 0)
        let remainingProbe = NSRect(x: selection.maxX + 118, y: 178, width: 90, height: 58)
        XCTAssertGreaterThan(try overlayPixelCount(in: image, rect: remainingProbe) { pixel in
            pixel.red > 180 && pixel.green < 120 && pixel.blue < 120 && pixel.alpha > 120
        }, 0)
    }

    func testTextCreatedOutsideSelectionStaysVisibleWhileEditingAfterEraserMask() throws {
        let background = solidImage(size: NSSize(width: 620, height: 460), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: background) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let rectangle = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 35, y: 45, width: 60, height: 60), style: CaptureAnnotationStyle())
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([rectangle])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_drag(from: NSPoint(x: 120, y: 130), to: NSPoint(x: 210, y: 220))
        XCTAssertEqual(window.test_eraserMaskCount, 1)

        window.test_activateTextTool()
        window.test_mouseDown(at: NSPoint(x: selection.maxX + 44, y: selection.midY))
        window.test_mouseUp(at: NSPoint(x: selection.maxX + 44, y: selection.midY))
        window.firstResponder?.insertText("Visible")

        XCTAssertTrue(window.test_isEditingTextAnnotation)
        XCTAssertTrue(window.test_textEditorUsesTransparentText)
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let outsideTextRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 1)).insetBy(dx: -4, dy: -4)
        XCTAssertNotNil(try firstPixel(in: image, rect: outsideTextRect) { pixel in
            pixel.red > 180 && pixel.green < 120 && pixel.blue < 120 && pixel.alpha > 120
        })
    }

    func testEraserRectangleOutsideSelectionDoesNotCreateEmptyMaskFromPaddedBounds() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 0, y: 40, width: 50, height: 50), style: CaptureAnnotationStyle())
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        window.test_drag(from: NSPoint(x: 94, y: 150), to: NSPoint(x: 99, y: 180))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_eraserMaskCount, 0)
        XCTAssertEqual(window.test_damagedAnnotationCount, 0)
        XCTAssertFalse(window.test_damagedAnnotationIDs.contains(annotation.id))
    }

    func testEraserRectangleTouchingOnlyVisualPaddingDoesNotCreateMask() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 50, y: 50, width: 50, height: 50), style: CaptureAnnotationStyle())
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        window.test_drag(from: NSPoint(x: 144, y: 160), to: NSPoint(x: 149, y: 180))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_eraserMaskCount, 0)
        XCTAssertEqual(window.test_damagedAnnotationCount, 0)
        XCTAssertFalse(window.test_damagedAnnotationIDs.contains(annotation.id))
    }

    func testEraserRectangleTouchingOnlyUnrotatedCornerOfRotatedTextDoesNotCreateMask() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        var annotation = CaptureAnnotation(kind: .text, rect: NSRect(x: 100, y: 100, width: 100, height: 100), style: CaptureAnnotationStyle(), text: "rotated")
        annotation.rotationAngle = .pi / 4
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        window.test_drag(from: NSPoint(x: 201, y: 291), to: NSPoint(x: 206, y: 296))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_eraserMaskCount, 0)
        XCTAssertEqual(window.test_damagedAnnotationCount, 0)
        XCTAssertFalse(window.test_damagedAnnotationIDs.contains(annotation.id))
    }

    func testEraserPointDeletePrunesDeletedIDFromSharedMaskAndUndoRedoRestoresIt() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let first = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 40, height: 40), style: CaptureAnnotationStyle())
        let second = CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 120, y: 50, width: 40, height: 40), style: CaptureAnnotationStyle())
        let mask = EraserMask(rect: NSRect(x: 20, y: 20, width: 180, height: 100), affectedAnnotationIDs: [first.id, second.id])
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([first, second])
        window.test_setEraserMasks([mask])
        window.test_activateEraserTool()

        let firstCenter = NSPoint(x: selection.minX + first.rect.midX, y: selection.minY + first.rect.midY)
        window.test_mouseDown(at: firstCenter)
        window.test_mouseUp(at: firstCenter)

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.id, mask.id)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.affectedAnnotationIDs, Set([second.id]))

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.affectedAnnotationIDs, Set([first.id, second.id]))

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift])
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.affectedAnnotationIDs, Set([second.id]))
    }

    func testDamagedAnnotationCannotBeSelectedOrDragged() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 90, height: 70), style: CaptureAnnotationStyle())
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(rect: NSRect(x: 50, y: 60, width: 20, height: 20), affectedAnnotationIDs: [annotation.id]))

        let hit = NSPoint(x: selection.minX + 80, y: selection.minY + 90)
        window.test_mouseDown(at: hit)
        window.test_mouseDragged(to: NSPoint(x: hit.x + 40, y: hit.y + 20))
        window.test_mouseUp(at: NSPoint(x: hit.x + 40, y: hit.y + 20))

        XCTAssertNil(window.test_selectedAnnotationIndex)
        XCTAssertEqual(window.test_annotation(at: 0)?.rect, annotation.rect)
    }

    func testPointEraserCanDeleteDamagedAnnotationAndItsMasks() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let annotation = CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 40, y: 50, width: 90, height: 70), style: CaptureAnnotationStyle())
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(rect: NSRect(x: 50, y: 60, width: 20, height: 20), affectedAnnotationIDs: [annotation.id]))
        window.test_activateEraserTool()

        let hit = NSPoint(x: selection.minX + 80, y: selection.minY + 90)
        window.test_mouseDown(at: hit)
        window.test_mouseUp(at: hit)

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_eraserMaskCount, 0)
    }

    func testDamagedAnnotationBlocksSelectionMoveFromBlankArea() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 90, height: 70), style: CaptureAnnotationStyle())
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(rect: NSRect(x: 50, y: 60, width: 20, height: 20), affectedAnnotationIDs: [annotation.id]))

        let blankPoint = NSPoint(x: selection.maxX - 20, y: selection.maxY - 20)
        window.test_mouseDown(at: blankPoint)
        window.test_mouseDragged(to: NSPoint(x: blankPoint.x - 40, y: blankPoint.y - 20))
        window.test_mouseUp(at: NSPoint(x: blankPoint.x - 40, y: blankPoint.y - 20))

        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertEqual(window.test_annotation(at: 0)?.rect, annotation.rect)
    }

    func testDamagedAnnotationBlocksSelectionResizeAndWheelZoom() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let annotation = CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 40, y: 50, width: 90, height: 70), style: CaptureAnnotationStyle())
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(rect: NSRect(x: 50, y: 60, width: 20, height: 20), affectedAnnotationIDs: [annotation.id]))

        let resizePoint = NSPoint(x: selection.maxX + 10, y: selection.midY)
        window.test_mouseDown(at: resizePoint)
        window.test_mouseDragged(to: NSPoint(x: resizePoint.x + 40, y: resizePoint.y))
        window.test_mouseUp(at: NSPoint(x: resizePoint.x + 40, y: resizePoint.y))

        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertEqual(window.test_annotation(at: 0)?.rect, annotation.rect)

        XCTAssertFalse(window.test_handleScrollWheel(at: NSPoint(x: selection.midX, y: selection.midY), deltaY: 12))
        window.test_completeSelectionWheelAnimation()
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertEqual(window.test_annotation(at: 0)?.rect, annotation.rect)
    }

    func testUndoPointEraserDeleteRestoresDamagedAnnotationUnselected() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 90, height: 70), style: CaptureAnnotationStyle())
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(rect: NSRect(x: 50, y: 60, width: 20, height: 20), affectedAnnotationIDs: [annotation.id]))
        window.test_activateEraserTool()

        let hit = NSPoint(x: selection.minX + 80, y: selection.minY + 90)
        window.test_mouseDown(at: hit)
        window.test_mouseUp(at: hit)
        XCTAssertEqual(window.test_annotationCount, 0)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertNil(window.test_selectedAnnotationIndex)
        XCTAssertEqual(window.test_annotation(at: 0)?.rect, annotation.rect)
    }

    func testDamagedArrowCannotBeSelectedOrDragged() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        var style = CaptureAnnotationStyle()
        style.strokeWidth = 12
        let annotation = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 40, y: 50, width: 120, height: 80),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 40, y: 50),
                end: NSPoint(x: 160, y: 90),
                control: NSPoint(x: 100, y: 130),
                startArrowType: .none,
                endArrowType: .normal
            )
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(rect: NSRect(x: 80, y: 80, width: 20, height: 20), affectedAnnotationIDs: [annotation.id]))

        let hit = NSPoint(x: selection.minX + 100, y: selection.minY + 90)
        window.test_mouseDown(at: hit)
        window.test_mouseDragged(to: NSPoint(x: hit.x + 40, y: hit.y + 20))
        window.test_mouseUp(at: NSPoint(x: hit.x + 40, y: hit.y + 20))

        XCTAssertNil(window.test_selectedAnnotationIndex)
        XCTAssertEqual(window.test_annotation(at: 0)?.rect, annotation.rect)
        XCTAssertEqual(window.test_annotation(at: 0)?.arrowLine, annotation.arrowLine)
    }

    func testDeleteManyPrunesDeletedIDsFromSharedMaskAndUndoRedoRestoresIt() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let first = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 40, height: 40), style: CaptureAnnotationStyle())
        let second = CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 100, y: 50, width: 40, height: 40), style: CaptureAnnotationStyle())
        let third = CaptureAnnotation(kind: .text, rect: NSRect(x: 160, y: 50, width: 40, height: 40), style: CaptureAnnotationStyle(), text: "keep")
        let mask = EraserMask(rect: NSRect(x: 20, y: 20, width: 220, height: 100), affectedAnnotationIDs: [first.id, second.id, third.id])
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([first, second, third])
        window.test_setEraserMasks([mask])

        XCTAssertTrue(window.test_deleteAnnotations(at: [0, 1]))
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.id, mask.id)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.affectedAnnotationIDs, Set([third.id]))

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
        XCTAssertEqual(window.test_annotationCount, 3)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.affectedAnnotationIDs, Set([first.id, second.id, third.id]))

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift])
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_eraserMask(at: 0)?.affectedAnnotationIDs, Set([third.id]))
    }

    func testEraserRectangleCreatesMaskForLineBrushAndMosaicAnnotations() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        var wideStyle = CaptureAnnotationStyle()
        wideStyle.strokeWidth = 12
        let arrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 30, y: 40, width: 110, height: 80),
            style: wideStyle,
            arrowLine: CaptureArrowLine(start: NSPoint(x: 30, y: 40), end: NSPoint(x: 140, y: 80), control: NSPoint(x: 80, y: 120), startArrowType: .none, endArrowType: .normal)
        )
        let brush = CaptureAnnotation(
            kind: .brush,
            rect: NSRect(x: 45, y: 95, width: 105, height: 45),
            style: wideStyle,
            brushPath: CaptureBrushPath(points: [NSPoint(x: 45, y: 95), NSPoint(x: 90, y: 130), NSPoint(x: 150, y: 140)])
        )
        let mosaic = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(x: 160, y: 50, width: 90, height: 80),
            style: wideStyle,
            mosaicStroke: CaptureMosaicStroke(points: [NSPoint(x: 160, y: 50), NSPoint(x: 190, y: 95), NSPoint(x: 250, y: 130)]),
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )
        let text = CaptureAnnotation(kind: .text, rect: NSRect(x: 285, y: 5, width: 8, height: 8), style: CaptureAnnotationStyle(), text: "keep")
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([arrow, brush, mosaic, text])
        window.test_activateEraserTool()
        window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
        window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

        window.test_drag(from: NSPoint(x: 120, y: 130), to: NSPoint(x: 375, y: 285))

        XCTAssertEqual(window.test_annotationCount, 4)
        XCTAssertEqual(window.test_eraserMaskCount, 1)
        XCTAssertEqual(window.test_damagedAnnotationIDs, Set([arrow.id, brush.id, mosaic.id]))
        XCTAssertFalse(window.test_damagedAnnotationIDs.contains(text.id))
    }

    func testEraserClickDeletesRectangleAnnotation() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([
            CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 80, height: 60), style: CaptureAnnotationStyle())
        ])
        window.test_activateEraserTool()

        let hit = NSPoint(x: selection.minX + 80, y: selection.minY + 80)
        window.test_mouseDown(at: hit)
        window.test_mouseUp(at: hit)

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
    }

    func testEraserClickDeletesTopmostAnnotationOnly() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([
            CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 90, height: 70), style: CaptureAnnotationStyle()),
            CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 50, y: 60, width: 90, height: 70), style: CaptureAnnotationStyle())
        ])
        window.test_activateEraserTool()

        let hit = NSPoint(x: selection.minX + 80, y: selection.minY + 90)
        window.test_mouseDown(at: hit)
        window.test_mouseUp(at: hit)

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_annotation(at: 0)?.kind, .rectangle)
    }

    func testEraserEmptyDragDoesNotMoveSelection() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([
            CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 80, height: 60), style: CaptureAnnotationStyle())
        ])
        window.test_activateEraserTool()

        let miss = NSPoint(x: selection.maxX - 20, y: selection.maxY - 20)
        window.test_mouseDown(at: miss)
        window.test_mouseDragged(to: NSPoint(x: miss.x - 80, y: miss.y - 40))
        window.test_mouseUp(at: NSPoint(x: miss.x - 80, y: miss.y - 40))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
    }

    func testEraserMissDoesNotResetMosaicPreviewCache() throws {
        let image = gradientImage(size: NSSize(width: 420, height: 300))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 260, height: 160)
        window.test_setLockedSelectionRect(selection)
        let annotation = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 20, y: 20, width: 80, height: 60),
            style: CaptureAnnotationStyle(),
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )
        window.test_setAnnotations([annotation])

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [annotation]))
        XCTAssertTrue(window.test_hasMosaicCompositeCache)
        let renderCountBeforeMiss = window.test_mosaicCompositeRenderCount
        window.test_activateEraserTool()

        let miss = NSPoint(x: selection.maxX - 16, y: selection.maxY - 16)
        window.test_mouseDown(at: miss)
        window.test_mouseDragged(to: NSPoint(x: miss.x - 40, y: miss.y - 20))
        window.test_mouseUp(at: NSPoint(x: miss.x - 40, y: miss.y - 20))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertTrue(window.test_hasMosaicCompositeCache)
        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountBeforeMiss)
    }

    func testEraserDeleteSupportsUndoAndRedo() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([
            CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 40, y: 50, width: 90, height: 70), style: CaptureAnnotationStyle()),
            CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 50, y: 60, width: 90, height: 70), style: CaptureAnnotationStyle())
        ])
        window.test_activateEraserTool()

        let hit = NSPoint(x: selection.minX + 80, y: selection.minY + 90)
        window.test_mouseDown(at: hit)
        window.test_mouseUp(at: hit)
        XCTAssertEqual(window.test_annotationCount, 1)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(window.test_annotation(at: 0)?.kind, .rectangle)
        XCTAssertEqual(window.test_annotation(at: 1)?.kind, .ellipse)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift])
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_annotation(at: 0)?.kind, .rectangle)
    }

    func testEraserDeleteOnlyAnnotationCanUndo() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 40, y: 50, width: 80, height: 60),
            style: CaptureAnnotationStyle()
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_activateEraserTool()

        let hit = NSPoint(x: selection.minX + 80, y: selection.minY + 80)
        window.test_mouseDown(at: hit)
        window.test_mouseUp(at: hit)
        XCTAssertEqual(window.test_annotationCount, 0)

        window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_annotation(at: 0)?.kind, .rectangle)
    }

    func testEraserDeletesRepresentativeAnnotationKinds() throws {
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        var wideStyle = CaptureAnnotationStyle()
        wideStyle.strokeWidth = 12
        var textStyle = CaptureAnnotationStyle()
        textStyle.strokeWidth = 0
        textStyle.textSize = 24

        let cases: [(name: String, annotation: CaptureAnnotation, hit: NSPoint)] = [
            (
                "arrow line",
                CaptureAnnotation(
                    kind: .arrowLine,
                    rect: NSRect(x: 40, y: 40, width: 120, height: 80),
                    style: wideStyle,
                    arrowLine: CaptureArrowLine(
                        start: NSPoint(x: 40, y: 40),
                        end: NSPoint(x: 140, y: 40),
                        control: NSPoint(x: 90, y: 90),
                        startArrowType: .none,
                        endArrowType: .normal
                    )
                ),
                NSPoint(x: selection.minX + 90, y: selection.minY + 65)
            ),
            (
                "brush",
                CaptureAnnotation(
                    kind: .brush,
                    rect: NSRect(x: 40, y: 50, width: 80, height: 60),
                    style: wideStyle,
                    brushPath: CaptureBrushPath(points: [NSPoint(x: 40, y: 50), NSPoint(x: 120, y: 110)])
                ),
                NSPoint(x: selection.minX + 80, y: selection.minY + 80)
            ),
            (
                "marker",
                CaptureAnnotation(
                    kind: .marker,
                    rect: NSRect(x: 40, y: 70, width: 100, height: 20),
                    style: wideStyle,
                    markerLine: CaptureMarkerLine(start: NSPoint(x: 40, y: 80), end: NSPoint(x: 140, y: 80))
                ),
                NSPoint(x: selection.minX + 90, y: selection.minY + 80)
            ),
            (
                "text",
                CaptureAnnotation(
                    kind: .text,
                    rect: NSRect(x: 60, y: 70, width: 120, height: 44),
                    style: textStyle,
                    text: "hello"
                ),
                NSPoint(x: selection.minX + 100, y: selection.minY + 90)
            ),
            (
                "number",
                CaptureAnnotation(
                    kind: .numberSequence,
                    rect: NSRect(x: 66, y: 66, width: 28, height: 28),
                    style: textStyle,
                    numberMarkType: .number,
                    numberSequenceIndex: 1
                ),
                NSPoint(x: selection.minX + 80, y: selection.minY + 80)
            ),
            (
                "mosaic stroke",
                CaptureAnnotation(
                    kind: .mosaicStroke,
                    rect: NSRect(x: 50, y: 70, width: 100, height: 40),
                    style: wideStyle,
                    mosaicStroke: CaptureMosaicStroke(points: [NSPoint(x: 50, y: 70), NSPoint(x: 150, y: 110)]),
                    mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
                ),
                NSPoint(x: selection.minX + 100, y: selection.minY + 90)
            ),
            (
                "mosaic rectangle",
                CaptureAnnotation(
                    kind: .mosaicRectangle,
                    rect: NSRect(x: 70, y: 80, width: 90, height: 50),
                    style: CaptureAnnotationStyle(),
                    mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
                ),
                NSPoint(x: selection.minX + 100, y: selection.minY + 100)
            ),
        ]

        for testCase in cases {
            XCTContext.runActivity(named: testCase.name) { _ in
                let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
                window.test_setLockedSelectionRect(selection)
                window.test_setAnnotations([testCase.annotation])
                window.test_activateEraserTool()

                window.test_mouseDown(at: testCase.hit)
                window.test_mouseUp(at: testCase.hit)

                XCTAssertEqual(window.test_annotationCount, 0)
                XCTAssertEqual(window.test_lockedSelectionRect, selection)
            }
        }
    }

    func testNumberSequenceOptionsToolbarLayoutHasTypeSizeAndColorSections() {
        let rect = NSRect(x: 10, y: 20, width: 250, height: 30)
        let layout = SelectionToolbarState.optionsToolbarLayout(in: rect, paletteCount: 8, mode: .numberSequence)

        XCTAssertFalse(layout.numberMarkType.isEmpty)
        XCTAssertFalse(layout.numberSize.isEmpty)
        XCTAssertGreaterThan(layout.colorSwatches.count, 1)
        XCTAssertLessThan(layout.numberMarkType.maxX, layout.numberSize.minX)
        XCTAssertLessThan(layout.numberSize.maxX, layout.colorSwatches[0].minX)
    }

    func testNumberSequenceSizeValuesMatchSnipastePresetList() {
        XCTAssertEqual(SelectionToolbarState.numberSizeValues, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 20, 24, 32, 40, 48, 60, 72])
    }

    func testNumberToolDefaultSizeIsThree() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        XCTAssertEqual(window.test_currentStyle?.textSize, 3)

        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))

        XCTAssertEqual(window.test_annotationStyle(at: 0)?.textSize, 3)
    }

    func testNumberDefaultVisualSizeMatchesSnipasteScaleExpectation() {
        let expectedDiameters: [Int: CGFloat] = [
            1: 15, 2: 18, 3: 21, 4: 24, 5: 27,
            6: 30, 7: 33, 8: 36, 9: 38, 10: 41,
            12: 47, 14: 47, 16: 54, 20: 70, 24: 82,
            32: 105, 40: 128, 48: 152, 60: 186, 72: 221,
        ]
        for (size, diameter) in expectedDiameters {
            XCTAssertEqual(CaptureAnnotationRenderer.numberMarkDiameter(for: CGFloat(size)), diameter, accuracy: 1)
        }
        XCTAssertEqual(CaptureAnnotationRenderer.numberMarkTextFontSize(for: 5), 19.44, accuracy: 0.8)
        XCTAssertEqual(CaptureAnnotationRenderer.numberMarkTextFontSize(for: 10), 29.52, accuracy: 0.8)
        XCTAssertEqual(CaptureAnnotationRenderer.numberMarkTextFontSize(for: 72), 159.12, accuracy: 2)
    }

    func testNumberSizeSixteenRendersLargerThanFourteen() {
        XCTAssertGreaterThan(
            CaptureAnnotationRenderer.numberMarkDiameter(for: 16),
            CaptureAnnotationRenderer.numberMarkDiameter(for: 14)
        )
        XCTAssertGreaterThan(
            CaptureAnnotationRenderer.numberMarkTextFontSize(for: 16),
            CaptureAnnotationRenderer.numberMarkTextFontSize(for: 14)
        )
    }

    func testNumberDigitRendersCenteredInCircle() throws {
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 360, height: 260), color: .white)) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 220, height: 140))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))

        let markRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let digitBounds = try XCTUnwrap(whiteDigitBounds(in: image, insideCircleRect: markRect))

        XCTAssertEqual(digitBounds.midX, markRect.midX, accuracy: 1.5)
        XCTAssertEqual(digitBounds.midY, markRect.midY, accuracy: 1.5)
    }

    func testNumberThreeDigitValueFitsInsideCircle() throws {
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 360, height: 260), color: .white)) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 220, height: 140))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))
        window.test_selectAnnotation(at: 0)
        let markRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_doubleClick(at: NSPoint(x: markRect.midX, y: markRect.midY))
        window.test_keyDown(keyCode: 51)
        for digit in ["9", "9", "9"] {
            window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: digit)
        }
        window.test_keyDown(keyCode: 36)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 999)
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let digitBounds = try XCTUnwrap(whiteDigitBounds(in: image, insideCircleRect: markRect))
        XCTAssertLessThanOrEqual(digitBounds.width, markRect.width * 0.86)
        XCTAssertLessThanOrEqual(digitBounds.height, markRect.height * 0.86)
    }

    func testNumberDoubleClickShowsBlackCaretAfterDigit() throws {
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 360, height: 260), color: .white)) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 220, height: 140))
        window.test_activateNumberTool()
        let yellowPoint = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 5))
        window.test_mouseDown(at: yellowPoint)
        window.test_mouseUp(at: yellowPoint)
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))

        let markRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_doubleClick(at: NSPoint(x: markRect.midX, y: markRect.midY))

        let text = "1"
        let fontSize = CaptureAnnotationRenderer.numberMarkTextFontSize(for: window.test_annotationStyle(at: 0)?.textSize ?? 5, text: text)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
        ]
        let textSize = NSString(string: text).size(withAttributes: attributes)
        let caretProbe = NSRect(
            x: markRect.midX + textSize.width / 2 + 1,
            y: markRect.midY - textSize.height / 2,
            width: 4,
            height: textSize.height
        )
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let caretPixel = try firstPixel(in: image, rect: caretProbe) { pixel in
            pixel.red < 60 && pixel.green < 60 && pixel.blue < 60 && pixel.alpha > 180
        }
        XCTAssertNotNil(caretPixel)
    }

    func testNumberToolbarButtonActivatesNumberModeAndOptionsToolbar() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))

        let numberPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .number))
        window.test_mouseDown(at: numberPoint)
        window.test_mouseUp(at: numberPoint)

        XCTAssertTrue(window.test_isNumberToolActive)
        XCTAssertEqual(window.test_optionsToolbarMode, .numberSequence)
        XCTAssertNotNil(window.test_optionsToolbarRect)
        XCTAssertEqual(window.test_currentStyle?.textSize, 3)
    }

    func testMagnifierToolbarButtonActivatesMagnifierModeAndOptionsToolbar() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 220, height: 160))

        let point = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .magnifier))
        window.test_mouseDown(at: point)

        XCTAssertTrue(window.test_isMagnifierToolActive)
        XCTAssertEqual(window.test_optionsToolbarMode, .magnifier)
        XCTAssertNotNil(window.test_optionsToolbarRect)
        XCTAssertEqual(window.test_currentMagnifierShape, .rectangle)
        XCTAssertEqual(window.test_currentMagnifierZoom, 2)
        XCTAssertEqual(window.test_currentStyle?.strokeWidth, 2)
    }

    func testMagnifierOptionsSwitchShapeZoomStrokeAndColor() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 220, height: 160))
        window.test_activateMagnifierTool()

        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: SelectionOverlayWindow.defaultPaletteColors.count,
            mode: .magnifier
        )
        let rectangleButton = try XCTUnwrap(layout.rectangleMode)
        let rectanglePoint = NSPoint(x: rectangleButton.midX, y: rectangleButton.midY)
        window.test_mouseDown(at: rectanglePoint)
        XCTAssertEqual(window.test_currentMagnifierShape, .rectangle)

        let circleButton = try XCTUnwrap(layout.ellipseMode)
        let circlePoint = NSPoint(x: circleButton.midX, y: circleButton.midY)
        window.test_mouseDown(at: circlePoint)
        XCTAssertEqual(window.test_currentMagnifierShape, .circle)

        let zoomFieldPoint = NSPoint(x: layout.magnifierZoom.midX, y: layout.magnifierZoom.midY)
        window.test_mouseDown(at: zoomFieldPoint)
        XCTAssertTrue(window.test_isMagnifierZoomDropdownVisible)
        let zoomPoint = try XCTUnwrap(window.test_magnifierZoomMenuPoint(3))
        window.test_mouseDown(at: zoomPoint)
        XCTAssertFalse(window.test_isMagnifierZoomDropdownVisible)
        let strokePoint = NSPoint(x: layout.strokeWidths[2].midX, y: layout.strokeWidths[2].midY)
        window.test_mouseDown(at: strokePoint)
        let colorPoint = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 2))
        window.test_mouseDown(at: colorPoint)

        XCTAssertEqual(window.test_currentMagnifierZoom, 3)
        XCTAssertEqual(window.test_currentStyle?.strokeWidth, 7)
        XCTAssertEqual(window.test_currentStyle?.strokeColor, SelectionOverlayWindow.defaultPaletteColors[2])
    }

    func testSelectingExistingMagnifierRestoresMagnifierToolbarState() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 80, y: 80, width: 220, height: 160)
        window.test_setLockedSelectionRect(selection)
        var style = CaptureAnnotationStyle()
        style.strokeColor = SelectionOverlayWindow.defaultPaletteColors[8]
        style.fillColor = SelectionOverlayWindow.defaultPaletteColors[8]
        style.strokeWidth = 7
        style.strokePattern = .solid
        style.fillEnabled = false
        let annotation = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 30, y: 30, width: 70, height: 70),
            style: style,
            magnifierShape: .rectangle,
            magnifierZoom: 4
        )
        window.test_setAnnotations([annotation])

        window.test_mouseDown(at: NSPoint(x: selection.minX + 65, y: selection.minY + 65))

        XCTAssertTrue(window.test_isMagnifierToolActive)
        XCTAssertEqual(window.test_optionsToolbarMode, .magnifier)
        XCTAssertEqual(window.test_currentMagnifierShape, .rectangle)
        XCTAssertEqual(window.test_currentMagnifierZoom, 4)
        XCTAssertEqual(window.test_currentStyle?.strokeWidth, 7)
        XCTAssertEqual(window.test_currentStyle?.strokeColor, SelectionOverlayWindow.defaultPaletteColors[8])

        window.test_activateShapeTool(.rectangle)
        XCTAssertEqual(window.test_currentShapeKind, .rectangle)
        XCTAssertNotEqual(window.test_currentStyle?.strokeWidth, 7)
        XCTAssertNotEqual(window.test_currentStyle?.strokeColor, SelectionOverlayWindow.defaultPaletteColors[8])
    }

    func testSelectedMagnifierStyleOptionsPreserveMagnifierKindShapeAndZoom() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 80, y: 80, width: 220, height: 160)
        window.test_setLockedSelectionRect(selection)
        var style = CaptureAnnotationStyle()
        style.strokeColor = SelectionOverlayWindow.defaultPaletteColors[8]
        style.fillColor = SelectionOverlayWindow.defaultPaletteColors[8]
        style.strokeWidth = 4
        style.strokePattern = .solid
        style.fillEnabled = false
        let annotation = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 30, y: 30, width: 70, height: 70),
            style: style,
            magnifierShape: .rectangle,
            magnifierZoom: 4
        )
        window.test_setAnnotations([annotation])
        let selectionPoint = NSPoint(x: selection.minX + 65, y: selection.minY + 65)
        window.test_mouseDown(at: selectionPoint)
        window.test_mouseUp(at: selectionPoint)

        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: SelectionOverlayWindow.defaultPaletteColors.count,
            mode: .magnifier
        )
        let strokePoint = NSPoint(x: layout.strokeWidths[2].midX, y: layout.strokeWidths[2].midY)
        window.test_mouseDown(at: strokePoint)
        let colorPoint = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 2))
        window.test_mouseDown(at: colorPoint)

        let updated = try XCTUnwrap(window.test_annotation(at: 0))
        XCTAssertEqual(updated.kind, .magnifier)
        XCTAssertEqual(updated.style.strokeWidth, 7)
        XCTAssertEqual(updated.style.strokeColor, SelectionOverlayWindow.defaultPaletteColors[2])
        XCTAssertEqual(updated.effectiveMagnifierShape, .rectangle)
        XCTAssertEqual(updated.effectiveMagnifierZoom, 4)
    }

    func testMagnifierDragCreatesRectangleAndShiftConstrainsToSquare() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 60, y: 60, width: 260, height: 180))
        window.test_activateMagnifierTool()

        window.test_drag(from: NSPoint(x: 100, y: 110), to: NSPoint(x: 190, y: 160), modifiers: [.shift])

        let annotation = try XCTUnwrap(window.test_annotation(at: 0))
        XCTAssertEqual(annotation.kind, .magnifier)
        XCTAssertEqual(annotation.effectiveMagnifierShape, .rectangle)
        XCTAssertEqual(annotation.effectiveMagnifierZoom, 2)
        XCTAssertEqual(annotation.rect.width, annotation.rect.height, accuracy: 0.001)
        XCTAssertNil(window.test_currentShapeKind)
    }

    func testMagnifierTinyDragDoesNotCreateAnnotation() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 60, y: 60, width: 260, height: 180))
        window.test_activateMagnifierTool()

        window.test_drag(from: NSPoint(x: 100, y: 110), to: NSPoint(x: 103, y: 112))

        XCTAssertEqual(window.test_annotationCount, 0)
    }

    func testSelectedMagnifierUsesMoveAndDirectionalResizeCursors() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 80, y: 80, width: 260, height: 180)
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .magnifier,
                rect: NSRect(x: 40, y: 35, width: 100, height: 80),
                style: CaptureAnnotationStyle(),
                magnifierShape: .rectangle,
                magnifierZoom: 2
            ),
        ])
        window.test_activateMagnifierTool()
        window.test_selectAnnotation(at: 0)

        let expected: [(SelectionToolbarState.OverlayResizeHandle, SelectionToolbarState.OverlayCursorStyle)] = [
            (.topLeft, .resizeTopLeft),
            (.top, .resizeUpDown),
            (.topRight, .resizeTopRight),
            (.left, .resizeLeftRight),
            (.right, .resizeLeftRight),
            (.bottomLeft, .resizeBottomLeft),
            (.bottom, .resizeUpDown),
            (.bottomRight, .resizeBottomRight),
        ]
        for (handle, cursor) in expected {
            let point = try XCTUnwrap(window.test_shapeResizeHandlePoint(handle))
            XCTAssertEqual(window.test_cursorStyle(at: point), cursor, String(describing: handle))
        }

        let magnifierRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        XCTAssertEqual(
            window.test_cursorStyle(at: NSPoint(x: magnifierRect.midX, y: magnifierRect.midY)),
            .move
        )
        XCTAssertEqual(
            window.test_cursorStyle(at: NSPoint(x: selection.minX + 12, y: selection.minY + 12)),
            .crosshair
        )
    }

    func testSelectedMagnifierCanResizeMoveDeleteAndRestyle() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 60, y: 60, width: 260, height: 180))
        window.test_activateMagnifierTool()
        window.test_setMagnifierShape(.rectangle)
        window.test_setMagnifierZoom(3)
        window.test_drag(from: NSPoint(x: 100, y: 110), to: NSPoint(x: 190, y: 160))

        let before = try XCTUnwrap(window.test_annotation(at: 0))
        XCTAssertEqual(before.effectiveMagnifierShape, .rectangle)
        XCTAssertEqual(before.effectiveMagnifierZoom, 3)

        let resizeHandle = try XCTUnwrap(window.test_shapeResizeHandlePoint(.topRight))
        window.test_mouseDown(at: resizeHandle)
        window.test_mouseDragged(to: NSPoint(x: resizeHandle.x + 24, y: resizeHandle.y + 16))
        window.test_mouseUp(at: NSPoint(x: resizeHandle.x + 24, y: resizeHandle.y + 16))

        let afterResize = try XCTUnwrap(window.test_annotation(at: 0))
        XCTAssertGreaterThan(afterResize.rect.width, before.rect.width)
        XCTAssertGreaterThan(afterResize.rect.height, before.rect.height)

        let moveRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        let moveStart = NSPoint(x: moveRect.midX, y: moveRect.midY)
        window.test_mouseDown(at: moveStart)
        window.test_mouseDragged(to: NSPoint(x: moveStart.x + 30, y: moveStart.y + 20))
        window.test_mouseUp(at: NSPoint(x: moveStart.x + 30, y: moveStart.y + 20))

        let afterMove = try XCTUnwrap(window.test_annotation(at: 0))
        XCTAssertEqual(afterMove.rect.origin.x, afterResize.rect.origin.x + 30, accuracy: 0.1)
        XCTAssertEqual(afterMove.rect.origin.y, afterResize.rect.origin.y + 20, accuracy: 0.1)

        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: SelectionOverlayWindow.defaultPaletteColors.count,
            mode: .magnifier
        )
        let circleButton = try XCTUnwrap(layout.ellipseMode)
        window.test_mouseDown(at: NSPoint(x: circleButton.midX, y: circleButton.midY))
        window.test_mouseUp(at: NSPoint(x: circleButton.midX, y: circleButton.midY))
        let zoomField = layout.magnifierZoom
        window.test_mouseDown(at: NSPoint(x: zoomField.midX, y: zoomField.midY))
        window.test_mouseUp(at: NSPoint(x: zoomField.midX, y: zoomField.midY))
        let zoom4Point = try XCTUnwrap(window.test_magnifierZoomMenuPoint(4))
        window.test_mouseDown(at: zoom4Point)
        window.test_mouseUp(at: zoom4Point)
        let thickStroke = layout.strokeWidths[2]
        window.test_mouseDown(at: NSPoint(x: thickStroke.midX, y: thickStroke.midY))
        window.test_mouseUp(at: NSPoint(x: thickStroke.midX, y: thickStroke.midY))
        let redPoint = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 0))
        window.test_mouseDown(at: redPoint)
        window.test_mouseUp(at: redPoint)

        let afterStyle = try XCTUnwrap(window.test_annotation(at: 0))
        XCTAssertEqual(afterStyle.kind, .magnifier)
        XCTAssertEqual(afterStyle.effectiveMagnifierShape, .circle)
        XCTAssertEqual(afterStyle.effectiveMagnifierZoom, 4)
        XCTAssertEqual(afterStyle.style.strokeWidth, 7)
        XCTAssertEqual(afterStyle.style.strokeColor, SelectionOverlayWindow.defaultPaletteColors[0])

        window.test_keyDown(keyCode: 51)
        XCTAssertEqual(window.test_annotationCount, 0)
    }

    func testMagnifierToolbarShapeZoomOptionsApplyToDraggedAnnotation() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 60, y: 60, width: 260, height: 180))

        let magnifierPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .magnifier))
        window.test_mouseDown(at: magnifierPoint)
        window.test_mouseUp(at: magnifierPoint)

        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: SelectionOverlayWindow.defaultPaletteColors.count,
            mode: .magnifier
        )
        let rectangleButton = try XCTUnwrap(layout.rectangleMode)
        let rectanglePoint = NSPoint(x: rectangleButton.midX, y: rectangleButton.midY)
        window.test_mouseDown(at: rectanglePoint)
        window.test_mouseUp(at: rectanglePoint)
        let zoomField = layout.magnifierZoom
        window.test_mouseDown(at: NSPoint(x: zoomField.midX, y: zoomField.midY))
        window.test_mouseUp(at: NSPoint(x: zoomField.midX, y: zoomField.midY))
        let zoom4Point = try XCTUnwrap(window.test_magnifierZoomMenuPoint(4))
        window.test_mouseDown(at: zoom4Point)
        window.test_mouseUp(at: zoom4Point)

        window.test_drag(from: NSPoint(x: 100, y: 110), to: NSPoint(x: 190, y: 160))

        let annotation = try XCTUnwrap(window.test_annotation(at: 0))
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(annotation.kind, .magnifier)
        XCTAssertEqual(annotation.effectiveMagnifierShape, .rectangle)
        XCTAssertEqual(annotation.effectiveMagnifierZoom, 4)
        XCTAssertEqual(annotation.style.strokeWidth, window.test_currentStyle?.strokeWidth)
        XCTAssertEqual(annotation.style.strokeColor, window.test_currentStyle?.strokeColor)
    }

    func testNumberToolbarIconStaysBlackWhenColorChanges() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))
        let numberPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .number))

        window.test_mouseDown(at: numberPoint)
        window.test_mouseUp(at: numberPoint)

        let redPoint = try XCTUnwrap(window.test_optionsPaletteColorPoint(at: 0))
        window.test_mouseDown(at: redPoint)
        window.test_mouseUp(at: redPoint)

        XCTAssertEqual(window.test_numberToolbarIconUsesTemplateBlack, true)
    }

    func testNumberOptionsSwitchTypeAndDefaultColors() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        XCTAssertEqual(window.test_numberMarkType, .number)

        let typePoint = try XCTUnwrap(window.test_numberMarkTypePoint())
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        let checkPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.check))
        window.test_mouseDown(at: checkPoint)
        window.test_mouseUp(at: checkPoint)

        XCTAssertEqual(window.test_numberMarkType, .check)
        XCTAssertEqual(window.test_currentStyle?.strokeColor.usingColorSpace(.deviceRGB)?.greenComponent ?? 0, 1, accuracy: 0.35)

        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        let crossPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.cross))
        window.test_mouseDown(at: crossPoint)
        window.test_mouseUp(at: crossPoint)

        XCTAssertEqual(window.test_numberMarkType, .cross)
        XCTAssertGreaterThan(window.test_currentStyle?.strokeColor.usingColorSpace(.deviceRGB)?.redComponent ?? 0, 0.8)
    }

    func testNumberMarkTypeMenuKeepsCheckAndCrossGlyphColorsWhenSelected() throws {
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 760, height: 360), color: .white)) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        let typePoint = try XCTUnwrap(window.test_numberMarkTypePoint())
        window.test_setNumberMarkType(.check)
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        let checkPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.check))
        let checkImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let checkIconRect = NSRect(x: checkPoint.x - 9, y: checkPoint.y - 9, width: 18, height: 18)
        XCTAssertNotNil(try firstPixel(in: checkImage, rect: checkIconRect) { pixel in
            pixel.green > 130 && Int(pixel.green) > Int(pixel.red) + 35 && Int(pixel.green) > Int(pixel.blue) + 20
        })

        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_setNumberMarkType(.cross)
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        let crossPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.cross))
        let crossImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let crossIconRect = NSRect(x: crossPoint.x - 9, y: crossPoint.y - 9, width: 18, height: 18)
        XCTAssertNotNil(try firstPixel(in: crossImage, rect: crossIconRect) { pixel in
            pixel.red > 180 && Int(pixel.red) > Int(pixel.green) + 60 && Int(pixel.red) > Int(pixel.blue) + 60
        })
    }

    func testSelectedNumberAnnotationFollowsTypeDropdownSelection() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()
        window.test_setNumberMarkType(.check)
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))

        XCTAssertEqual(window.test_annotation(at: 0)?.numberMarkType, .check)
        let markRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseDown(at: NSPoint(x: markRect.midX, y: markRect.midY))
        window.test_mouseUp(at: NSPoint(x: markRect.midX, y: markRect.midY))

        let typePoint = try XCTUnwrap(window.test_numberMarkTypePoint())
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        let crossPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.cross))
        window.test_mouseDown(at: crossPoint)
        window.test_mouseUp(at: crossPoint)

        XCTAssertEqual(window.test_annotation(at: 0)?.numberMarkType, .cross)
        XCTAssertNil(window.test_annotation(at: 0)?.numberSequenceIndex)

        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        let numberPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.number))
        window.test_mouseDown(at: numberPoint)
        window.test_mouseUp(at: numberPoint)

        XCTAssertEqual(window.test_annotation(at: 0)?.numberMarkType, .number)
        XCTAssertEqual(window.test_annotation(at: 0)?.numberSequenceIndex, 1)
    }

    func testSelectedCheckOrCrossReturnsToDefaultRedWhenChangedBackToNumber() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()
        window.test_setNumberMarkType(.check)
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))

        let typePoint = try XCTUnwrap(window.test_numberMarkTypePoint())
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        let numberPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.number))
        window.test_mouseDown(at: numberPoint)
        window.test_mouseUp(at: numberPoint)

        let expectedHex = SelectionToolbarState.colorSamplerHexString(
            for: try XCTUnwrap(SelectionOverlayWindow.defaultPaletteColors.first)
        )
        let currentHex = SelectionToolbarState.colorSamplerHexString(
            for: try XCTUnwrap(window.test_currentStyle?.strokeColor)
        )
        let annotationHex = SelectionToolbarState.colorSamplerHexString(
            for: try XCTUnwrap(window.test_annotationStyle(at: 0)?.strokeColor)
        )

        XCTAssertEqual(window.test_annotation(at: 0)?.numberMarkType, .number)
        XCTAssertEqual(currentHex, expectedHex)
        XCTAssertEqual(annotationHex, expectedHex)

        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        let crossPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.cross))
        window.test_mouseDown(at: crossPoint)
        window.test_mouseUp(at: crossPoint)
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: numberPoint)
        window.test_mouseUp(at: numberPoint)

        let crossBackHex = SelectionToolbarState.colorSamplerHexString(
            for: try XCTUnwrap(window.test_annotationStyle(at: 0)?.strokeColor)
        )
        XCTAssertEqual(crossBackHex, expectedHex)
    }

    func testNewlyCreatedSelectedNumberAnnotationFollowsTypeDropdownSelection() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()
        window.test_setNumberMarkType(.check)
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))

        let typePoint = try XCTUnwrap(window.test_numberMarkTypePoint())
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        let crossPoint = try XCTUnwrap(window.test_numberMarkTypeMenuPoint(.cross))
        window.test_mouseDown(at: crossPoint)
        window.test_mouseUp(at: crossPoint)

        XCTAssertEqual(window.test_annotation(at: 0)?.numberMarkType, .cross)
        XCTAssertNil(window.test_annotation(at: 0)?.numberSequenceIndex)
    }

    func testNumberSizeDropdownUpdatesCurrentSize() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        let sizePoint = try XCTUnwrap(window.test_numberSizePoint())
        window.test_mouseDown(at: sizePoint)
        window.test_mouseUp(at: sizePoint)
        window.test_selectNumberSize(36)

        XCTAssertEqual(window.test_currentStyle?.textSize, 36)
    }

    func testNumberSizeDropdownSelectsLargeScrolledSizeFromPopup() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        let sizePoint = try XCTUnwrap(window.test_numberSizePoint())
        window.test_mouseDown(at: sizePoint)
        window.test_mouseUp(at: sizePoint)

        let dropdown = try XCTUnwrap(window.test_textDropdownRect)
        XCTAssertTrue(window.test_isTextSizeDropdownVisible)
        window.test_scrollWheel(at: NSPoint(x: dropdown.midX, y: dropdown.midY), deltaY: -400)
        XCTAssertGreaterThanOrEqual(window.test_textDropdownScrollOffset, 12)

        let lastVisibleSizePoint = NSPoint(x: dropdown.midX, y: dropdown.minY + 15)
        window.test_mouseDown(at: lastVisibleSizePoint)
        window.test_mouseUp(at: lastVisibleSizePoint)

        XCTAssertEqual(window.test_currentStyle?.textSize, 72)
    }

    func testNumberSizeDropdownStaysAtLastPageAfterSmallScrollBounce() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        let sizePoint = try XCTUnwrap(window.test_numberSizePoint())
        window.test_mouseDown(at: sizePoint)
        window.test_mouseUp(at: sizePoint)

        let dropdown = try XCTUnwrap(window.test_textDropdownRect)
        window.test_scrollWheel(at: NSPoint(x: dropdown.midX, y: dropdown.midY), deltaY: -400)
        XCTAssertEqual(window.test_textDropdownScrollOffset, 12)

        window.test_scrollWheel(at: NSPoint(x: dropdown.midX, y: dropdown.midY), deltaY: 2)
        XCTAssertEqual(window.test_textDropdownScrollOffset, 12)

        let lastVisibleSizePoint = NSPoint(x: dropdown.midX, y: dropdown.minY + 15)
        window.test_mouseDown(at: lastVisibleSizePoint)
        window.test_mouseUp(at: lastVisibleSizePoint)

        XCTAssertEqual(window.test_currentStyle?.textSize, 72)
    }

    func testNumberSizeDropdownResizesExistingMarkBackground() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))
        window.test_selectAnnotation(at: 0)

        let before = try XCTUnwrap(window.test_annotationRect(at: 0))
        window.test_selectNumberSize(36)
        let after = try XCTUnwrap(window.test_annotationRect(at: 0))

        XCTAssertGreaterThan(after.width, before.width)
        XCTAssertGreaterThan(after.height, before.height)
        XCTAssertEqual(after.midX, before.midX, accuracy: 0.5)
        XCTAssertEqual(after.midY, before.midY, accuracy: 0.5)
    }

    func testNumberDropdownAndCursorUseFilledNumberIcon() throws {
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 760, height: 360), color: .white)) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let iconInterior = try XCTUnwrap(window.test_numberMarkTypeIconInteriorPoint())
        let toolbarPixel = try XCTUnwrap(rgbaPixel(in: image, at: NSPoint(x: iconInterior.x, y: image.size.height - iconInterior.y)))
        XCTAssertLessThan(toolbarPixel.red, 80)
        XCTAssertLessThan(toolbarPixel.green, 80)
        XCTAssertLessThan(toolbarPixel.blue, 80)

        let cursorImage = try XCTUnwrap(window.test_numberCursorImage(for: .number))
        let cursorPixel = try XCTUnwrap(rgbaPixel(in: cursorImage, at: NSPoint(x: 9, y: 15)))
        XCTAssertGreaterThan(cursorPixel.alpha, 200)
        XCTAssertLessThan(Int(cursorPixel.red) + Int(cursorPixel.green) + Int(cursorPixel.blue), 520)
    }

    func testNumberCursorDisplaysNextSequenceNumber() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        XCTAssertEqual(window.test_numberCursorText(for: .number), "1")

        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))
        XCTAssertEqual(window.test_numberCursorText(for: .number), "2")

        window.test_mouseDown(at: NSPoint(x: 280, y: 150))
        window.test_mouseUp(at: NSPoint(x: 280, y: 150))
        XCTAssertEqual(window.test_numberCursorText(for: .number), "3")
    }

    func testThreeDigitNumberCursorKeepsHorizontalPadding() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        var style = CaptureAnnotationStyle()
        style.textSize = 3
        style.strokeColor = .systemRed
        let mark = CaptureAnnotation(
            kind: .numberSequence,
            rect: NSRect(x: 40, y: 40, width: 21, height: 21),
            style: style,
            numberMarkType: .number,
            numberSequenceIndex: 99
        )
        window.test_setAnnotations([mark])

        let image = try XCTUnwrap(window.test_numberCursorImage(for: .number))
        let circleRect = NSRect(x: 4.5, y: 4.5, width: 21, height: 21)
        let digitBounds = try XCTUnwrap(whiteDigitBounds(in: image, insideCircleRect: circleRect))

        XCTAssertEqual(window.test_numberCursorText(for: .number), "100")
        XCTAssertGreaterThanOrEqual(digitBounds.minX - circleRect.minX, 2.8)
        XCTAssertGreaterThanOrEqual(circleRect.maxX - digitBounds.maxX, 2.8)
    }

    func testNumberSymbolCursorHotSpotIsCenteredOnMark() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        XCTAssertEqual(window.test_numberCursorHotSpot(for: .check), NSPoint(x: 15, y: 15))
        XCTAssertEqual(window.test_numberCursorHotSpot(for: .cross), NSPoint(x: 15, y: 15))
    }

    func testNumberCreationCursorChangesByTypeAndAvoidsToolbar() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()

        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 160, y: 160)), .numberMark)

        window.test_setNumberMarkType(.check)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 160, y: 160)), .numberCheck)

        window.test_setNumberMarkType(.cross)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 160, y: 160)), .numberCross)

        let toolbarPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .number))
        XCTAssertEqual(window.test_cursorStyle(at: toolbarPoint), .arrow)
    }

    func testNumberToolCreatesSequentialMarksInsideAndOutsideSelection() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 120, y: 120, width: 220, height: 140)
        window.test_setLockedSelectionRect(selection)
        window.test_activateNumberTool()

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))
        window.test_mouseDown(at: NSPoint(x: selection.maxX + 30, y: selection.maxY + 24))
        window.test_mouseUp(at: NSPoint(x: selection.maxX + 30, y: selection.maxY + 24))

        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
        XCTAssertEqual(window.test_annotation(at: 1)?.kind, .numberSequence)
    }

    func testNumberCreationDragDoesNotMoveSelectionOrNewMark() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 120, y: 120, width: 220, height: 140)
        let creationPoint = NSPoint(x: 170, y: 165)
        window.test_setLockedSelectionRect(selection)
        window.test_activateNumberTool()

        window.test_mouseDown(at: creationPoint)
        let createdRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        window.test_mouseDragged(to: NSPoint(x: creationPoint.x + 48, y: creationPoint.y + 32))
        window.test_mouseDragged(to: NSPoint(x: creationPoint.x + 70, y: creationPoint.y + 46))
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertEqual(window.test_annotationRect(at: 0), createdRect)
        window.test_mouseUp(at: NSPoint(x: creationPoint.x + 70, y: creationPoint.y + 46))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertEqual(window.test_annotationRect(at: 0), createdRect)
    }

    func testNumberSelectionOutlineSitsOutsideCircleAndControlsStayVisible() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))

        let markRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        let outlineRect = try XCTUnwrap(window.test_numberOutlineRect())

        XCTAssertLessThan(outlineRect.minX, markRect.minX)
        XCTAssertLessThan(outlineRect.minY, markRect.minY)
        XCTAssertGreaterThan(outlineRect.maxX, markRect.maxX)
        XCTAssertGreaterThan(outlineRect.maxY, markRect.maxY)
        XCTAssertTrue(window.test_numberControlsVisible)

        window.test_mouseMoved(to: NSPoint(x: 440, y: 280))
        XCTAssertTrue(window.test_numberControlsVisible)
    }

    func testSelectedTypeChangesKeepFollowingNumberOrder() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 120, y: 120, width: 220, height: 140))
        window.test_activateNumberTool()

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))
        window.test_setNumberMarkType(.check)
        window.test_mouseDown(at: NSPoint(x: 260, y: 150))
        window.test_mouseUp(at: NSPoint(x: 260, y: 150))
        window.test_setNumberMarkType(.number)
        window.test_mouseDown(at: NSPoint(x: 330, y: 150))
        window.test_mouseUp(at: NSPoint(x: 330, y: 150))

        XCTAssertNil(window.test_numberSequenceIndex(at: 0))
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 2)
    }

    func testOverlayRendersStandaloneCheckWithoutBackgroundCircle() throws {
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 300, height: 220), color: .white)) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 180, height: 120))
        window.test_activateNumberTool()
        window.test_setNumberMarkType(.check)
        window.test_mouseDown(at: NSPoint(x: 160, y: 140))
        window.test_mouseUp(at: NSPoint(x: 160, y: 140))

        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let markRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        let corner = try XCTUnwrap(rgbaPixel(in: image, at: NSPoint(x: markRect.minX + 3, y: image.size.height - markRect.minY - 3)))
        XCTAssertGreaterThan(corner.red, 245)
        XCTAssertGreaterThan(corner.green, 245)
        XCTAssertGreaterThan(corner.blue, 245)
    }

    func testNumberDeleteRenumbersRemainingMarks() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()
        [150, 260, 370].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        window.test_selectAnnotation(at: 1)
        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 1))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        let deletePoint = try XCTUnwrap(window.test_numberDeleteHandlePoint())
        window.test_mouseDown(at: deletePoint)
        window.test_mouseUp(at: deletePoint)

        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
    }

    func testDeleteKeyRemovesSelectedNumberCheckAndCrossMarks() throws {
        for type in [CaptureNumberMarkType.number, .check, .cross] {
            let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
            window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
            window.test_activateNumberTool()
            window.test_setNumberMarkType(type)
            window.test_mouseDown(at: NSPoint(x: 180, y: 150))
            window.test_mouseUp(at: NSPoint(x: 180, y: 150))

            let markRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
            window.test_mouseDown(at: NSPoint(x: markRect.midX, y: markRect.midY))
            window.test_mouseUp(at: NSPoint(x: markRect.midX, y: markRect.midY))

            window.test_keyDown(keyCode: 51)

            XCTAssertEqual(window.test_annotationCount, 0, "\(type) should delete with Delete key")
            XCTAssertNil(window.test_selectedAnnotationKind)
        }
    }

    func testDeleteKeyRemovesNewlyCreatedNumberCheckAndCrossMarks() {
        for type in [CaptureNumberMarkType.number, .check, .cross] {
            let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
            window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
            window.test_activateNumberTool()
            window.test_setNumberMarkType(type)
            window.test_mouseDown(at: NSPoint(x: 180, y: 150))
            window.test_mouseUp(at: NSPoint(x: 180, y: 150))

            window.test_keyDown(keyCode: 51)

            XCTAssertEqual(window.test_annotationCount, 0, "\(type) should delete immediately after creation")
            XCTAssertNil(window.test_selectedAnnotationKind)
        }
    }

    func testForwardDeleteKeyRemovesSelectedNumberCheckAndCrossMarks() throws {
        for type in [CaptureNumberMarkType.number, .check, .cross] {
            let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
            window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
            window.test_activateNumberTool()
            window.test_setNumberMarkType(type)
            window.test_mouseDown(at: NSPoint(x: 180, y: 150))
            window.test_mouseUp(at: NSPoint(x: 180, y: 150))

            let markRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
            window.test_mouseDown(at: NSPoint(x: markRect.midX, y: markRect.midY))
            window.test_mouseUp(at: NSPoint(x: markRect.midX, y: markRect.midY))

            window.test_keyDown(keyCode: 117)

            XCTAssertEqual(window.test_annotationCount, 0, "\(type) should delete with forward Delete key")
            XCTAssertNil(window.test_selectedAnnotationKind)
        }
    }

    func testDeleteKeyRemovesHoveredNumberMarkWhenControlsAreRevealed() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))
        window.test_mouseDown(at: NSPoint(x: 260, y: 150))
        window.test_mouseUp(at: NSPoint(x: 260, y: 150))
        window.test_selectAnnotation(at: 99)

        let secondRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 1))
        window.test_mouseMoved(to: NSPoint(x: secondRect.midX, y: secondRect.midY))
        window.test_keyDown(keyCode: 51)

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertNil(window.test_selectedAnnotationKind)
    }

    func testManualNumberModeKeepsRemainingValuesWhenDeletingMarks() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        [150, 260, 370].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        let secondRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 1))
        window.test_doubleClick(at: NSPoint(x: secondRect.midX, y: secondRect.midY))
        window.test_keyDown(keyCode: 51)
        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "7")
        window.test_keyDown(keyCode: 36)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 7)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 3)

        window.test_selectAnnotation(at: 1)
        window.test_mouseMoved(to: NSPoint(x: secondRect.midX, y: secondRect.midY))
        let deleteManualPoint = try XCTUnwrap(window.test_numberDeleteHandlePoint())
        window.test_mouseDown(at: deleteManualPoint)
        window.test_mouseUp(at: deleteManualPoint)

        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 3)

        let firstRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_selectAnnotation(at: 0)
        window.test_mouseMoved(to: NSPoint(x: firstRect.midX, y: firstRect.midY))
        let deleteFirstPoint = try XCTUnwrap(window.test_numberDeleteHandlePoint())
        window.test_mouseDown(at: deleteFirstPoint)
        window.test_mouseUp(at: deleteFirstPoint)

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 3)
    }

    func testNumberPlusMinusSwapAndResetWhenGreaterThanOne() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        [150, 260].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        window.test_selectAnnotation(at: 0)
        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        XCTAssertNil(window.test_numberResetHandlePoint())
        let plusPoint = try XCTUnwrap(window.test_numberIncrementHandlePoint())
        window.test_mouseDown(at: plusPoint)
        window.test_mouseUp(at: plusPoint)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 1)
        let resetPoint = try XCTUnwrap(window.test_numberResetHandlePoint())
        window.test_mouseDown(at: resetPoint)
        window.test_mouseUp(at: resetPoint)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertNil(window.test_numberResetHandlePoint())

        let minusPoint = try XCTUnwrap(window.test_numberDecrementHandlePoint())
        window.test_mouseDown(at: minusPoint)
        window.test_mouseUp(at: minusPoint)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 1)
    }

    func testNumberResetRestartsNextCreatedNumberSequence() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 420, height: 180))
        window.test_activateNumberTool()
        [150, 260, 370].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        window.test_selectAnnotation(at: 2)
        let thirdRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 2))
        window.test_mouseMoved(to: NSPoint(x: thirdRect.midX, y: thirdRect.midY))
        let resetPoint = try XCTUnwrap(window.test_numberResetHandlePoint())
        window.test_mouseDown(at: resetPoint)
        window.test_mouseUp(at: resetPoint)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 1)
        XCTAssertEqual(window.test_numberCursorText(for: .number), "2")

        window.test_mouseDown(at: NSPoint(x: 470, y: 150))
        window.test_mouseUp(at: NSPoint(x: 470, y: 150))

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 3), 2)
        XCTAssertEqual(window.test_numberCursorText(for: .number), "3")
    }

    private func makeSplitNumberSequenceWindow() throws -> SelectionOverlayWindow {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 760, height: 180))
        window.test_activateNumberTool()
        [150, 260, 370].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        window.test_selectAnnotation(at: 2)
        let thirdRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 2))
        window.test_mouseMoved(to: NSPoint(x: thirdRect.midX, y: thirdRect.midY))
        let resetPoint = try XCTUnwrap(window.test_numberResetHandlePoint())
        window.test_mouseDown(at: resetPoint)
        window.test_mouseUp(at: resetPoint)

        [480, 590].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 3), 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 4), 3)
        XCTAssertEqual(window.test_numberCursorText(for: .number), "4")
        return window
    }

    func testSelectingEarlierSequenceMakesNextNumberFollowThatSequence() throws {
        let window = try makeSplitNumberSequenceWindow()

        let oldSecondRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 1))
        let oldSecondPoint = NSPoint(x: oldSecondRect.midX, y: oldSecondRect.midY)
        window.test_mouseDown(at: oldSecondPoint)
        window.test_mouseUp(at: oldSecondPoint)

        XCTAssertEqual(window.test_numberCursorText(for: .number), "3")
        window.test_mouseDown(at: NSPoint(x: 700, y: 150))
        window.test_mouseUp(at: NSPoint(x: 700, y: 150))

        XCTAssertEqual(window.test_numberSequenceIndex(at: 5), 3)
    }

    func testNumberHandleInteractionsMakeNextNumberFollowThatSequence() throws {
        do {
            let window = try makeSplitNumberSequenceWindow()
            window.test_selectAnnotation(at: 1)
            let oldSecondRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 1))
            window.test_mouseMoved(to: NSPoint(x: oldSecondRect.midX, y: oldSecondRect.midY))
            let minusPoint = try XCTUnwrap(window.test_numberDecrementHandlePoint())
            window.test_mouseDown(at: minusPoint)
            window.test_mouseUp(at: minusPoint)
            XCTAssertEqual(window.test_numberCursorText(for: .number), "3")
        }

        do {
            let window = try makeSplitNumberSequenceWindow()
            window.test_selectAnnotation(at: 1)
            let oldSecondRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 1))
            window.test_mouseMoved(to: NSPoint(x: oldSecondRect.midX, y: oldSecondRect.midY))
            let deletePoint = try XCTUnwrap(window.test_numberDeleteHandlePoint())
            window.test_mouseDown(at: deletePoint)
            window.test_mouseUp(at: deletePoint)
            XCTAssertEqual(window.test_numberCursorText(for: .number), "2")
        }

        do {
            let window = try makeSplitNumberSequenceWindow()
            window.test_selectAnnotation(at: 1)
            let oldSecondRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 1))
            window.test_mouseMoved(to: NSPoint(x: oldSecondRect.midX, y: oldSecondRect.midY))
            let resizePoint = try XCTUnwrap(window.test_numberResizeHandlePoint())
            window.test_mouseDown(at: resizePoint)
            window.test_mouseDragged(to: NSPoint(x: resizePoint.x + 16, y: resizePoint.y - 16))
            window.test_mouseUp(at: NSPoint(x: resizePoint.x + 16, y: resizePoint.y - 16))
            XCTAssertEqual(window.test_numberCursorText(for: .number), "3")
        }

        do {
            let window = try makeSplitNumberSequenceWindow()
            window.test_selectAnnotation(at: 1)
            let oldSecondRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 1))
            window.test_mouseMoved(to: NSPoint(x: oldSecondRect.midX, y: oldSecondRect.midY))
            let resetPoint = try XCTUnwrap(window.test_numberResetHandlePoint())
            window.test_mouseDown(at: resetPoint)
            window.test_mouseUp(at: resetPoint)
            XCTAssertEqual(window.test_numberCursorText(for: .number), "2")
        }
    }

    func testDeletingNumberAfterResetRenumbersOnlyCurrentSequence() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 620, height: 180))
        window.test_activateNumberTool()
        [150, 260, 370].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        window.test_selectAnnotation(at: 2)
        let thirdRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 2))
        window.test_mouseMoved(to: NSPoint(x: thirdRect.midX, y: thirdRect.midY))
        let resetPoint = try XCTUnwrap(window.test_numberResetHandlePoint())
        window.test_mouseDown(at: resetPoint)
        window.test_mouseUp(at: resetPoint)

        [480, 590].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 3), 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 4), 3)

        window.test_selectAnnotation(at: 3)
        let newSecondRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 3))
        window.test_mouseMoved(to: NSPoint(x: newSecondRect.midX, y: newSecondRect.midY))
        let deletePoint = try XCTUnwrap(window.test_numberDeleteHandlePoint())
        window.test_mouseDown(at: deletePoint)
        window.test_mouseUp(at: deletePoint)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 3), 2)
    }

    func testManualSequenceDoesNotPreventAutoSequenceDeleteRenumbering() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 620, height: 180))
        window.test_activateNumberTool()
        [150, 260, 370].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        let firstRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_doubleClick(at: NSPoint(x: firstRect.midX, y: firstRect.midY))
        window.test_keyDown(keyCode: 51)
        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "9")
        window.test_keyDown(keyCode: 36)

        window.test_selectAnnotation(at: 2)
        let thirdRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 2))
        window.test_mouseMoved(to: NSPoint(x: thirdRect.midX, y: thirdRect.midY))
        let resetPoint = try XCTUnwrap(window.test_numberResetHandlePoint())
        window.test_mouseDown(at: resetPoint)
        window.test_mouseUp(at: resetPoint)

        [480, 590].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        window.test_selectAnnotation(at: 3)
        let newSecondRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 3))
        window.test_mouseMoved(to: NSPoint(x: newSecondRect.midX, y: newSecondRect.midY))
        let deletePoint = try XCTUnwrap(window.test_numberDeleteHandlePoint())
        window.test_mouseDown(at: deletePoint)
        window.test_mouseUp(at: deletePoint)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 9)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 3), 2)
    }

    func testAutoNumberPlusMinusSwapsAdjacentValues() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        [150, 260, 370].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        window.test_selectAnnotation(at: 2)
        let thirdRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 2))
        window.test_mouseMoved(to: NSPoint(x: thirdRect.midX, y: thirdRect.midY))
        XCTAssertFalse(window.test_numberIncrementHandleIsHitTarget())
        let minusPoint = try XCTUnwrap(window.test_numberDecrementHandlePoint())
        window.test_mouseDown(at: minusPoint)
        window.test_mouseUp(at: minusPoint)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 3)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 2)

        let plusPoint = try XCTUnwrap(window.test_numberIncrementHandlePoint())
        window.test_mouseDown(at: plusPoint)
        window.test_mouseUp(at: plusPoint)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 3)
    }

    func testManualNumberPlusMinusSwapsAdjacentValues() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        [150, 260, 370].forEach { x in
            window.test_mouseDown(at: NSPoint(x: x, y: 150))
            window.test_mouseUp(at: NSPoint(x: x, y: 150))
        }

        let thirdRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 2))
        window.test_doubleClick(at: NSPoint(x: thirdRect.midX, y: thirdRect.midY))
        window.test_keyDown(keyCode: 51)
        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "3")
        window.test_keyDown(keyCode: 36)
        window.test_selectAnnotation(at: 2)
        window.test_mouseMoved(to: NSPoint(x: thirdRect.midX, y: thirdRect.midY))
        let minusPoint = try XCTUnwrap(window.test_numberDecrementHandlePoint())
        window.test_mouseDown(at: minusPoint)
        window.test_mouseUp(at: minusPoint)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 3)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 2), 2)
    }

    func testNumberPlusHandleDisablesAt999AndMinusStaysActive() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))

        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_doubleClick(at: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        window.test_keyDown(keyCode: 51)
        for digit in ["9", "9", "9"] {
            window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: digit)
        }
        window.test_keyDown(keyCode: 36)
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 999)
        XCTAssertFalse(window.test_numberIncrementHandleIsHitTarget())
        XCTAssertTrue(window.test_numberDecrementHandleIsHitTarget())

        let plusPoint = try XCTUnwrap(window.test_numberIncrementHandlePoint())
        window.test_mouseDown(at: plusPoint)
        window.test_mouseUp(at: plusPoint)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 999)
    }

    func testNumberPlusMinusHandlesStackOnLeftSide() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))
        window.test_selectAnnotation(at: 0)
        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))

        let plusRect = try XCTUnwrap(window.test_numberIncrementHandleRect())
        let minusRect = try XCTUnwrap(window.test_numberDecrementHandleRect())
        let outlineRect = try XCTUnwrap(window.test_numberOutlineRect())

        XCTAssertLessThanOrEqual(plusRect.maxX, outlineRect.minX - 1)
        XCTAssertLessThanOrEqual(minusRect.maxX, outlineRect.minX - 1)
        XCTAssertEqual(plusRect.midY, outlineRect.maxY, accuracy: 0.5)
        XCTAssertGreaterThan(plusRect.midY, minusRect.midY)
        XCTAssertEqual(plusRect.minY, minusRect.maxY, accuracy: 0.5)
    }

    func testNumberResetHandleSitsOutsideOutline() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))
        window.test_selectAnnotation(at: 0)
        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        let plusPoint = try XCTUnwrap(window.test_numberIncrementHandlePoint())
        window.test_mouseDown(at: plusPoint)
        window.test_mouseUp(at: plusPoint)

        let resetRect = try XCTUnwrap(window.test_numberResetHandleRect())
        let plusRect = try XCTUnwrap(window.test_numberIncrementHandleRect())
        let minusRect = try XCTUnwrap(window.test_numberDecrementHandleRect())
        let deleteRect = try XCTUnwrap(window.test_numberDeleteHandleRect())
        let resizeRect = try XCTUnwrap(window.test_numberResizeHandleRect())
        let outlineRect = try XCTUnwrap(window.test_numberOutlineRect())

        XCTAssertLessThanOrEqual(resetRect.maxX, outlineRect.minX - 1)
        XCTAssertEqual(plusRect.midY, deleteRect.midY, accuracy: 0.5)
        XCTAssertEqual(resetRect.midY, resizeRect.midY, accuracy: 0.5)
        XCTAssertEqual(resetRect.size.width, plusRect.size.width, accuracy: 0.1)
        XCTAssertEqual(resetRect.size.height, plusRect.size.height, accuracy: 0.1)
        XCTAssertEqual(resetRect.size.width, minusRect.size.width, accuracy: 0.1)
        XCTAssertEqual(resetRect.size.height, minusRect.size.height, accuracy: 0.1)
        XCTAssertEqual(plusRect.width, 12, accuracy: 0.1)
        XCTAssertEqual(plusRect.height, 12, accuracy: 0.1)
        XCTAssertEqual(minusRect.width, 12, accuracy: 0.1)
        XCTAssertEqual(minusRect.height, 12, accuracy: 0.1)
        XCTAssertNotNil(Bundle.main.url(forResource: "reset2", withExtension: "svg"))
        XCTAssertNotNil(Bundle.main.url(forResource: "close", withExtension: "svg"))

        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let resetPixel = try XCTUnwrap(firstPixel(in: image, rect: resetRect.insetBy(dx: 1, dy: 1)) { pixel in
            pixel.blue > 140 && pixel.green > 70 && pixel.red < 120 && pixel.alpha > 120
        })
        XCTAssertGreaterThan(resetPixel.blue, resetPixel.red)
    }

    func testNumberDeleteHandleDrawsAboveDashedOutline() throws {
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 360, height: 260), color: .white)) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 220, height: 120))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))
        window.test_selectAnnotation(at: 0)
        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))

        let deleteRect = try XCTUnwrap(window.test_numberDeleteHandleRect())
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let centerBand = NSRect(x: deleteRect.minX + 3, y: deleteRect.midY - 1, width: deleteRect.width - 6, height: 2)
        let blueOrWhitePixels = try matchingPixelCount(in: image, rect: centerBand) { pixel in
            let isBlue = pixel.blue > 120 && pixel.red < 80 && pixel.green > 70 && pixel.alpha > 180
            let isWhite = pixel.red > 220 && pixel.green > 220 && pixel.blue > 220 && pixel.alpha > 180
            return isBlue || isWhite
        }
        XCTAssertGreaterThan(blueOrWhitePixels, 12)
    }

    func testNumberResizeHandleDrawsWhiteRingOnDarkBackground() throws {
        let window = SelectionOverlayWindow(
            backgroundImage: solidImage(
                size: NSSize(width: 360, height: 240),
                color: NSColor(srgbRed: 0.18, green: 0.18, blue: 0.18, alpha: 1)
            )
        ) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 220, height: 120))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 170, y: 150))
        window.test_mouseUp(at: NSPoint(x: 170, y: 150))
        window.test_selectAnnotation(at: 0)
        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))

        let resizeRect = try XCTUnwrap(window.test_numberResizeHandleRect())
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let ringBand = NSRect(
            x: resizeRect.midX - 1,
            y: resizeRect.maxY - 2,
            width: 2,
            height: 2
        )
        XCTAssertNotNil(try firstLightPixel(in: image, rect: ringBand))
        XCTAssertNotNil(try firstBlueDominantPixel(in: image, rect: resizeRect.insetBy(dx: 2, dy: 2)))
    }

    func testNumberResetHandleDrawsIconWithoutBoxBackground() throws {
        let window = SelectionOverlayWindow(
            backgroundImage: solidImage(
                size: NSSize(width: 360, height: 240),
                color: NSColor(srgbRed: 0.18, green: 0.18, blue: 0.18, alpha: 1)
            )
        ) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 220, height: 120))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 170, y: 150))
        window.test_mouseUp(at: NSPoint(x: 170, y: 150))
        window.test_selectAnnotation(at: 0)
        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        let plusPoint = try XCTUnwrap(window.test_numberIncrementHandlePoint())
        window.test_mouseDown(at: plusPoint)
        window.test_mouseUp(at: plusPoint)

        let resetRect = try XCTUnwrap(window.test_numberResetHandleRect())
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let topLeftCorner = try XCTUnwrap(rgbaPixel(
            in: image,
            at: NSPoint(x: resetRect.minX + 1, y: image.size.height - resetRect.maxY + 2)
        ))
        XCTAssertLessThan(topLeftCorner.red, 170)
        XCTAssertLessThan(topLeftCorner.green, 170)
        XCTAssertLessThan(topLeftCorner.blue, 170)
        let ringBand = NSRect(
            x: resetRect.midX - 1,
            y: resetRect.maxY - 2,
            width: 2,
            height: 2
        )
        XCTAssertNotNil(try firstLightPixel(in: image, rect: ringBand))
        let glyphArea = resetRect.insetBy(dx: 3, dy: 3)
        XCTAssertGreaterThan(try matchingPixelCount(in: image, rect: glyphArea) { pixel in
            pixel.red > 220 && pixel.green > 220 && pixel.blue > 220 && pixel.alpha > 180
        }, 5)
        XCTAssertNotNil(
            try firstBlueDominantPixel(
                in: image,
                rect: resetRect.insetBy(dx: 1, dy: 1)
            )
        )
    }

    func testNumberResetIconUsesVisibleGlyphArea() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 220, height: 120))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 170, y: 150))
        window.test_mouseUp(at: NSPoint(x: 170, y: 150))
        window.test_selectAnnotation(at: 0)
        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        let plusPoint = try XCTUnwrap(window.test_numberIncrementHandlePoint())
        window.test_mouseDown(at: plusPoint)
        window.test_mouseUp(at: plusPoint)

        let resetRect = try XCTUnwrap(window.test_numberResetHandleRect())
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let leftGlyphBand = NSRect(
            x: resetRect.minX + 2,
            y: resetRect.minY + 4,
            width: 1,
            height: resetRect.height - 8
        )
        XCTAssertNotNil(try firstBlueDominantPixel(in: image, rect: leftGlyphBand))
    }

    func testSelectedNumberControlsRenderAboveOverlappingNumberMarks() throws {
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 420, height: 260), color: .white)) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 240, height: 120)
        var style = CaptureAnnotationStyle()
        style.textSize = 5
        style.strokeColor = NSColor(calibratedRed: 245 / 255, green: 34 / 255, blue: 45 / 255, alpha: 1)

        func numberMark(center: NSPoint, index: Int) -> CaptureAnnotation {
            let overlayRect = CaptureAnnotationRenderer.numberMarkRect(centeredAt: center, fontSize: style.textSize)
            return CaptureAnnotation(
                kind: .numberSequence,
                rect: NSRect(
                    x: overlayRect.minX - selection.minX,
                    y: overlayRect.minY - selection.minY,
                    width: overlayRect.width,
                    height: overlayRect.height
                ),
                style: style,
                numberMarkType: .number,
                numberSequenceIndex: index
            )
        }

        let selectedCenter = NSPoint(x: 220, y: 150)
        let selected = numberMark(center: selectedCenter, index: 2)
        window.test_setLockedSelectionRect(selection)
        window.test_activateNumberTool()
        window.test_setAnnotations([selected])
        window.test_selectAnnotation(at: 0)
        window.test_mouseMoved(to: selectedCenter)
        let plusRect = try XCTUnwrap(window.test_numberIncrementHandleRect())
        let coveringMark = numberMark(center: NSPoint(x: plusRect.midX, y: plusRect.midY), index: 3)

        window.test_setAnnotations([selected, coveringMark])
        window.test_selectAnnotation(at: 0)
        window.test_mouseMoved(to: selectedCenter)

        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        XCTAssertNotNil(try firstBlueDominantPixel(in: image, rect: plusRect.insetBy(dx: 1, dy: 1)))
    }

    func testSelectedNumberControlsStayVisibleAndClickableAfterPointerLeaves() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))

        window.test_selectAnnotation(at: 0)
        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        XCTAssertTrue(window.test_numberControlsVisible)

        let plusPoint = try XCTUnwrap(window.test_numberIncrementHandlePoint())
        window.test_mouseMoved(to: NSPoint(x: 440, y: 280))

        XCTAssertTrue(window.test_numberControlsVisible)
        window.test_mouseDown(at: plusPoint)
        window.test_mouseUp(at: plusPoint)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 2)
    }

    func testNumberDoubleClickEditsValueTo999AndIgnoresAdditionalDigit() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))

        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_doubleClick(at: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        window.test_keyDown(keyCode: 51)
        for digit in ["9", "9", "9", "1"] {
            window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: digit)
        }
        window.test_keyDown(keyCode: 36)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 999)
    }

    func testNumberKeyboardInputIgnoresFourthDigitInsteadOfClampingTo999() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))

        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_doubleClick(at: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        window.test_keyDown(keyCode: 51)
        for digit in ["1", "2", "3", "4"] {
            window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: digit)
        }
        window.test_keyDown(keyCode: 36)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 123)
    }

    func testNumberKeyboardInputInsertsAtCaretWithoutClearingExistingDigits() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))

        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_doubleClick(at: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "2")
        window.test_keyDown(keyCode: 123, charactersIgnoringModifiers: "")
        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "9")
        window.test_keyDown(keyCode: 36)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 192)
    }

    func testNumberEmptyKeyboardDraftCompletesToOneAndNextMarkContinuesFromIt() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))

        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_doubleClick(at: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "7")
        window.test_keyDown(keyCode: 51)
        window.test_keyDown(keyCode: 51)
        window.test_mouseMoved(to: NSPoint(x: 420, y: 260))

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 1)

        window.test_mouseDown(at: NSPoint(x: 260, y: 150))
        window.test_mouseUp(at: NSPoint(x: 260, y: 150))

        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 2)
    }

    func testKeyboardEditedNumberStaysWhenCreatingNextNumberMark() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))

        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_doubleClick(at: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: "7")
        window.test_keyDown(keyCode: 36)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 17)

        window.test_mouseDown(at: NSPoint(x: 260, y: 150))
        window.test_mouseUp(at: NSPoint(x: 260, y: 150))

        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 17)
        XCTAssertEqual(window.test_numberSequenceIndex(at: 1), 18)
    }

    func testNumberLargeKeyboardInputFitsInSmallestCircleWithoutWrapping() throws {
        let window = SelectionOverlayWindow(backgroundImage: solidImage(size: NSSize(width: 360, height: 260), color: .white)) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 220, height: 120))
        window.test_activateNumberTool()
        window.test_selectNumberSize(1)
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))

        let markRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_doubleClick(at: NSPoint(x: markRect.midX, y: markRect.midY))
        window.test_keyDown(keyCode: 51)
        for digit in ["9", "9", "9", "8", "7", "6"] {
            window.test_keyDown(keyCode: 0, charactersIgnoringModifiers: digit)
        }
        window.test_keyDown(keyCode: 36)

        XCTAssertEqual(window.test_numberSequenceIndex(at: 0), 999)
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let digitBounds = try XCTUnwrap(whiteDigitBounds(in: image, insideCircleRect: markRect))
        XCTAssertLessThanOrEqual(digitBounds.width, markRect.width * 0.86)
        XCTAssertLessThanOrEqual(digitBounds.height, markRect.height * 0.86)
    }

    func testNumberResizeClampsSize() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_selectNumberSize(70)
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))
        window.test_selectAnnotation(at: 0)

        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))
        let handle = try XCTUnwrap(window.test_numberResizeHandlePoint())
        window.test_mouseDown(at: handle)
        window.test_mouseDragged(to: NSPoint(x: handle.x + 120, y: handle.y - 120))
        window.test_mouseUp(at: NSPoint(x: handle.x + 120, y: handle.y - 120))

        XCTAssertEqual(window.test_annotationStyle(at: 0)?.textSize, 72)
    }

    func testNumberResizeHandleIsHalfTheDeleteHandleSize() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 360, height: 180))
        window.test_activateNumberTool()
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseUp(at: NSPoint(x: 180, y: 150))
        window.test_selectAnnotation(at: 0)
        let selectedRect = try XCTUnwrap(window.test_annotationOverlayRect(at: 0))
        window.test_mouseMoved(to: NSPoint(x: selectedRect.midX, y: selectedRect.midY))

        let deleteRect = try XCTUnwrap(window.test_numberDeleteHandleRect())
        let resizeRect = try XCTUnwrap(window.test_numberResizeHandleRect())

        XCTAssertEqual(resizeRect.width, deleteRect.width / 2, accuracy: 0.5)
        XCTAssertEqual(resizeRect.height, deleteRect.height / 2, accuracy: 0.5)
    }

    func testMosaicDotSizesAndCursorPreviewAreScaledDown() {
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .mosaic), [15, 25, 35])
        XCTAssertEqual(SelectionToolbarState.mosaicCursorDotDiameter(for: 15), 7.8, accuracy: 0.01)
        XCTAssertEqual(SelectionToolbarState.mosaicCursorDotDiameter(for: 25), 13, accuracy: 0.01)
        XCTAssertEqual(SelectionToolbarState.mosaicCursorDotDiameter(for: 35), 18.2, accuracy: 0.01)
        XCTAssertLessThan(SelectionToolbarState.mosaicCursorDotDiameter(for: 35), 20)
    }

    func testOverlayWindowUsesMosaicRectangleDrawingCursorOutsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let outsidePoint = NSPoint(x: 80, y: selection.midY)
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        XCTAssertEqual(window.test_cursorStyle(at: outsidePoint), .crosshair)

        guard let toolbarPoint = window.test_mainToolbarDragPoint() else {
            return XCTFail("Expected toolbar drag point")
        }

        XCTAssertEqual(window.test_cursorStyle(at: outsidePoint), .crosshair)
        XCTAssertEqual(window.test_cursorStyle(at: toolbarPoint), .arrow)
    }

    func testOverlayWindowUsesSelectionResizeCursorOnMosaicBorder() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let rightBorderPoint = NSPoint(x: selection.maxX + 10, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        window.test_toggleShapeTool(.mosaicRectangle)
        XCTAssertEqual(window.test_cursorStyle(at: rightBorderPoint), .resizeLeftRight)

        window.test_activateShapeTool(.mosaicStroke)
        XCTAssertEqual(window.test_cursorStyle(at: rightBorderPoint), .resizeLeftRight)
    }

    func testOverlayWindowMosaicToolReopensWithPixelMosaicRedaction() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        guard let redactionTypePoint = window.test_mosaicRedactionTypePoint(.pixelMosaic) else {
            return XCTFail("Expected mosaic redaction type point")
        }

        window.test_mouseDown(at: redactionTypePoint)
        window.test_mouseUp(at: redactionTypePoint)
        XCTAssertEqual(window.test_mosaicRedactionType, .gaussianBlur)

        window.test_toggleShapeTool(.brush)
        window.test_toggleShapeTool(.mosaicRectangle)

        XCTAssertEqual(window.test_mosaicRedactionType, .pixelMosaic)
        XCTAssertEqual(window.test_currentShapeKind, .mosaicRectangle)
    }

    func testOverlayWindowMosaicRedactionTypeTooltipRefreshesImmediatelyAfterToggle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        guard let redactionTypePoint = window.test_mosaicRedactionTypePoint(.pixelMosaic) else {
            return XCTFail("Expected mosaic redaction type point")
        }

        window.test_mouseMoved(to: redactionTypePoint)
        XCTAssertEqual(window.test_hoveredTooltipText, "马赛克")

        window.test_mouseDown(at: redactionTypePoint)
        XCTAssertEqual(window.test_mosaicRedactionType, .gaussianBlur)
        XCTAssertEqual(window.test_hoveredTooltipText, "高斯")

        window.test_mouseDown(at: redactionTypePoint)
        XCTAssertEqual(window.test_mosaicRedactionType, .pixelMosaic)
        XCTAssertEqual(window.test_hoveredTooltipText, "马赛克")
    }

    func testOverlayWindowSelectedPixelMosaicRedactionGlyphUsesWhiteCenterAndBlueArms() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        let redactionTypePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.pixelMosaic))
        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let centerRect = NSRect(x: redactionTypePoint.x - 3, y: redactionTypePoint.y - 3, width: 6, height: 6)
        let crossRect = NSRect(x: redactionTypePoint.x - 12, y: redactionTypePoint.y - 12, width: 24, height: 24)

        XCTAssertNotNil(try firstLightPixel(in: image, rect: centerRect))
        XCTAssertNotNil(try firstBlueDominantPixel(in: image, rect: crossRect))
    }

    func testOverlayWindowSelectedGaussianRedactionGlyphTurnsBlue() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        let redactionTypePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: redactionTypePoint)
        window.test_mouseUp(at: redactionTypePoint)

        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let sampleRect = NSRect(x: redactionTypePoint.x - 4, y: redactionTypePoint.y - 4, width: 8, height: 8)

        XCTAssertNotNil(try firstBlueDominantPixel(in: image, rect: sampleRect))
    }

    func testOverlayWindowMosaicOptionsKeepPerTypeValuesWithoutShapeModeButtons() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        guard
            let redactionTypePoint = window.test_mosaicRedactionTypePoint(.pixelMosaic),
            let valueMaximumPoint = window.test_mosaicValueIncrementPoint(),
            let valueMinimumPoint = window.test_mosaicValueDecrementPoint()
        else {
            return XCTFail("Expected mosaic option points")
        }

        XCTAssertNotNil(window.test_mosaicRectangleOptionPoint())
        XCTAssertNotNil(window.test_optionsStrokeWidthPoint(at: 0))
        XCTAssertEqual(window.test_currentShapeKind, .mosaicRectangle)

        window.test_mouseDown(at: redactionTypePoint)
        window.test_mouseUp(at: redactionTypePoint)
        XCTAssertEqual(window.test_mosaicRedactionType, .gaussianBlur)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .gaussianBlur), 8)

        window.test_mouseDown(at: valueMaximumPoint)
        window.test_mouseUp(at: valueMaximumPoint)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .gaussianBlur), 20)

        window.test_mouseDown(at: valueMinimumPoint)
        window.test_mouseUp(at: valueMinimumPoint)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .gaussianBlur), 5)

        window.test_mouseDown(at: redactionTypePoint)
        window.test_mouseUp(at: redactionTypePoint)
        XCTAssertEqual(window.test_mosaicRedactionType, .pixelMosaic)
        XCTAssertEqual(window.test_mosaicRedactionValue(for: .pixelMosaic), 8)
    }

    func testOverlayWindowMosaicValueSliderClampsToMaximum() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        guard
            let sliderPoint = window.test_mosaicValueIncrementPoint(),
            let minimumPoint = window.test_mosaicValueDecrementPoint()
        else {
            return XCTFail("Expected mosaic value slider points")
        }

        window.test_mouseDown(at: sliderPoint)
        window.test_mouseDragged(to: NSPoint(x: sliderPoint.x + 40, y: sliderPoint.y))
        window.test_mouseUp(at: NSPoint(x: sliderPoint.x + 40, y: sliderPoint.y))

        XCTAssertEqual(window.test_mosaicRedactionValue(for: .pixelMosaic), 20)

        window.test_mouseDown(at: minimumPoint)
        window.test_mouseDragged(to: NSPoint(x: minimumPoint.x - 40, y: minimumPoint.y))
        window.test_mouseUp(at: NSPoint(x: minimumPoint.x - 40, y: minimumPoint.y))

        XCTAssertEqual(window.test_mosaicRedactionValue(for: .pixelMosaic), 5)
    }

    func testOverlayWindowMosaicValueSliderSkipsSameValuePreviewInvalidation() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))

        let sliderPoint = try XCTUnwrap(window.test_mosaicValueInputPoint())
        window.test_mouseDown(at: sliderPoint)

        let annotation = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 0)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0)),
            mosaicRedaction: try XCTUnwrap(window.test_mosaicRedaction(at: 0))
        )
        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [annotation]))
        XCTAssertTrue(window.test_hasMosaicCompositeCache)

        window.test_mouseDragged(to: sliderPoint)

        XCTAssertTrue(window.test_hasMosaicCompositeCache)
        window.test_mouseUp(at: sliderPoint)
    }

    func testOverlayWindowMosaicRectangleRotationReusesPreviewCompositeCache() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 180))
        window.test_toggleShapeTool(.mosaicRectangle)

        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))
        XCTAssertNotNil(window.test_renderedOverlayImage())
        let fullRenderCountBeforeRotation = window.test_mosaicFullCompositeRenderCount

        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 24, y: rotationPoint.y + 18))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicFullCompositeRenderCount, fullRenderCountBeforeRotation)
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 24, y: rotationPoint.y + 18))
    }

    func testOverlayWindowMosaicRectangleRotationDoesNotRedrawEarlierMosaicsTwice() throws {
        let image = checkerboardImage(size: NSSize(width: 360, height: 260), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 260, height: 180))
        window.test_toggleShapeTool(.mosaicRectangle)

        let gaussianPoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: gaussianPoint)
        window.test_mouseUp(at: gaussianPoint)

        for (start, end) in [
            (NSPoint(x: 70, y: 70), NSPoint(x: 125, y: 115)),
            (NSPoint(x: 145, y: 90), NSPoint(x: 205, y: 140)),
            (NSPoint(x: 225, y: 105), NSPoint(x: 285, y: 165)),
        ] {
            window.test_mouseDown(at: start)
            window.test_mouseDragged(to: end)
            window.test_mouseUp(at: end)
        }

        XCTAssertEqual(window.test_annotationCount, 3)
        XCTAssertNotNil(window.test_renderedOverlayImage())

        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 24, y: rotationPoint.y + 18))

        let drawCountBeforeRotationFrame = window.test_mosaicCompositeDrawCount
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicCompositeDrawCount - drawCountBeforeRotationFrame, 1)
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 24, y: rotationPoint.y + 18))
    }

    func testOverlayWindowMosaicRectangleRotationDrawsConstantCompositePassWithManyEarlierMosaics() throws {
        let image = checkerboardImage(size: NSSize(width: 420, height: 300), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 320, height: 210))
        window.test_toggleShapeTool(.mosaicRectangle)

        let gaussianPoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: gaussianPoint)
        window.test_mouseUp(at: gaussianPoint)

        for (start, end) in [
            (NSPoint(x: 62, y: 62), NSPoint(x: 112, y: 108)),
            (NSPoint(x: 122, y: 78), NSPoint(x: 172, y: 124)),
            (NSPoint(x: 182, y: 94), NSPoint(x: 232, y: 140)),
            (NSPoint(x: 242, y: 110), NSPoint(x: 292, y: 156)),
            (NSPoint(x: 302, y: 126), NSPoint(x: 352, y: 172)),
        ] {
            window.test_mouseDown(at: start)
            window.test_mouseDragged(to: end)
            window.test_mouseUp(at: end)
        }

        XCTAssertEqual(window.test_annotationCount, 5)
        XCTAssertNotNil(window.test_renderedOverlayImage())

        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 28, y: rotationPoint.y + 22))

        let drawCountBeforeRotationFrame = window.test_mosaicCompositeDrawCount
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicCompositeDrawCount - drawCountBeforeRotationFrame, 1)
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 28, y: rotationPoint.y + 22))
    }

    func testOverlayWindowMosaicRectangleRotationPreviewDoesNotRecomposeLaterLayersEachFrame() throws {
        let image = checkerboardImage(size: NSSize(width: 640, height: 420), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 40, width: 540, height: 320)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let annotations = (0..<16).map { index in
            let column = index % 4
            let row = index / 4
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 22 + column * 118, y: 22 + row * 66, width: 74, height: 44),
                style: style,
                mosaicRedaction: redaction
            )
        }
        window.test_setAnnotations(annotations)
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_selectAnnotation(at: 0)

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let fullRenderCountBeforeRotation = window.test_mosaicFullCompositeRenderCount

        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 26, y: rotationPoint.y + 20))
        XCTAssertNotNil(window.test_renderedOverlayImage())
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 38, y: rotationPoint.y + 30))
        XCTAssertNotNil(window.test_renderedOverlayImage())
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 50, y: rotationPoint.y + 40))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertLessThanOrEqual(window.test_mosaicFullCompositeRenderCount - fullRenderCountBeforeRotation, 1)
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 50, y: rotationPoint.y + 40))
    }

    func testOverlayWindowMovingMosaicRectangleDoesNotRecomposeLaterLayersEachFrame() throws {
        let image = checkerboardImage(size: NSSize(width: 760, height: 520), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 40, width: 660, height: 400)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let annotations = (0..<24).map { index in
            let column = index % 6
            let row = index / 6
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 20 + column * 96, y: 24 + row * 74, width: 62, height: 46),
                style: style,
                mosaicRedaction: redaction
            )
        }
        window.test_setAnnotations(annotations)
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_selectAnnotation(at: 0)

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let fullRenderCountBeforeMove = window.test_mosaicFullCompositeRenderCount
        let moveStart = NSPoint(x: selection.minX + 20 + 31, y: selection.minY + 24 + 23)
        window.test_mouseDown(at: moveStart)
        window.test_mouseDragged(to: NSPoint(x: moveStart.x + 24, y: moveStart.y + 12))
        XCTAssertNotNil(window.test_renderedOverlayImage())
        window.test_mouseDragged(to: NSPoint(x: moveStart.x + 40, y: moveStart.y + 20))
        XCTAssertNotNil(window.test_renderedOverlayImage())
        window.test_mouseDragged(to: NSPoint(x: moveStart.x + 56, y: moveStart.y + 28))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertLessThanOrEqual(window.test_mosaicFullCompositeRenderCount - fullRenderCountBeforeMove, 1)
        window.test_mouseUp(at: NSPoint(x: moveStart.x + 56, y: moveStart.y + 28))
    }

    func testOverlayWindowResizingMosaicRectangleDoesNotRecomposeLaterLayersEachFrame() throws {
        let image = checkerboardImage(size: NSSize(width: 760, height: 520), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 40, width: 660, height: 400)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let annotations = (0..<24).map { index in
            let column = index % 6
            let row = index / 6
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 20 + column * 96, y: 24 + row * 74, width: 62, height: 46),
                style: style,
                mosaicRedaction: redaction
            )
        }
        window.test_setAnnotations(annotations)
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_selectAnnotation(at: 0)

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let fullRenderCountBeforeResize = window.test_mosaicFullCompositeRenderCount
        let handlePoint = try XCTUnwrap(window.test_shapeResizeHandlePoint(.bottomRight))
        window.test_mouseDown(at: handlePoint)
        window.test_mouseDragged(to: NSPoint(x: handlePoint.x + 18, y: handlePoint.y + 12))
        XCTAssertNotNil(window.test_renderedOverlayImage())
        window.test_mouseDragged(to: NSPoint(x: handlePoint.x + 30, y: handlePoint.y + 20))
        XCTAssertNotNil(window.test_renderedOverlayImage())
        window.test_mouseDragged(to: NSPoint(x: handlePoint.x + 42, y: handlePoint.y + 28))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertLessThanOrEqual(window.test_mosaicFullCompositeRenderCount - fullRenderCountBeforeResize, 1)
        window.test_mouseUp(at: NSPoint(x: handlePoint.x + 42, y: handlePoint.y + 28))
    }

    func testOverlayWindowResizingMosaicRectangleWithManyLayersDoesNotRecomposeBaseOnFirstFrame() throws {
        let image = checkerboardImage(size: NSSize(width: 980, height: 760), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 40, width: 880, height: 640)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let annotations = (0..<42).map { index in
            let column = index % 7
            let row = index / 7
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 20 + column * 118, y: 24 + row * 88, width: 74, height: 54),
                style: style,
                mosaicRedaction: redaction
            )
        }
        window.test_setAnnotations(annotations)
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_selectAnnotation(at: 0)

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let fullRenderCountBeforeResize = window.test_mosaicFullCompositeRenderCount
        let handlePoint = try XCTUnwrap(window.test_shapeResizeHandlePoint(.bottomRight))
        window.test_mouseDown(at: handlePoint)
        window.test_mouseDragged(to: NSPoint(x: handlePoint.x + 28, y: handlePoint.y - 18))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicFullCompositeRenderCount, fullRenderCountBeforeResize)
        window.test_mouseUp(at: NSPoint(x: handlePoint.x + 28, y: handlePoint.y - 18))
    }

    func testOverlayWindowMovingMosaicRectangleWithManyLayersDoesNotRecomposeBaseOnFrames() throws {
        let image = checkerboardImage(size: NSSize(width: 1040, height: 820), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 40, width: 940, height: 700)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let annotations = (0..<64).map { index in
            let column = index % 8
            let row = index / 8
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 20 + column * 110, y: 24 + row * 82, width: 68, height: 50),
                style: style,
                mosaicRedaction: redaction
            )
        }
        window.test_setAnnotations(annotations)
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_selectAnnotation(at: 0)

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let fullRenderCountBeforeMove = window.test_mosaicFullCompositeRenderCount
        let moveStart = NSPoint(x: selection.minX + 20 + 34, y: selection.minY + 24 + 25)
        window.test_mouseDown(at: moveStart)
        window.test_mouseDragged(to: NSPoint(x: moveStart.x + 32, y: moveStart.y + 18))
        XCTAssertNotNil(window.test_renderedOverlayImage())
        window.test_mouseDragged(to: NSPoint(x: moveStart.x + 56, y: moveStart.y + 30))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicFullCompositeRenderCount, fullRenderCountBeforeMove)
        window.test_mouseUp(at: NSPoint(x: moveStart.x + 56, y: moveStart.y + 30))
    }

    func testOverlayWindowMovingMosaicRectangleWithManyLayersShowsLiveRedaction() throws {
        let image = checkerboardImage(size: NSSize(width: 1040, height: 820), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 40, width: 940, height: 700)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let annotations = (0..<64).map { index in
            let column = index % 8
            let row = index / 8
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 20 + column * 110, y: 24 + row * 82, width: 68, height: 50),
                style: style,
                mosaicRedaction: redaction
            )
        }
        window.test_setAnnotations(annotations)
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_selectAnnotation(at: 0)

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let fullRenderCountBeforeMove = window.test_mosaicFullCompositeRenderCount
        let moveStart = NSPoint(x: selection.minX + 20 + 34, y: selection.minY + 24 + 25)
        let moveEnd = NSPoint(x: moveStart.x + 56, y: moveStart.y + 30)
        window.test_mouseDown(at: moveStart)
        window.test_mouseDragged(to: moveEnd)

        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let originalPixel = try XCTUnwrap(rgbaPixel(in: image, at: moveEnd))
        let livePreviewPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: moveEnd))

        XCTAssertTrue(pixelDiffers(livePreviewPixel, originalPixel))
        XCTAssertEqual(window.test_mosaicFullCompositeRenderCount, fullRenderCountBeforeMove)
        window.test_mouseUp(at: moveEnd)
    }

    func testOverlayWindowRotatingMosaicRectangleWithManyLayersDoesNotRecomposeBaseOnFrames() throws {
        let image = checkerboardImage(size: NSSize(width: 1040, height: 820), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 40, width: 940, height: 700)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let annotations = (0..<64).map { index in
            let column = index % 8
            let row = index / 8
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 20 + column * 110, y: 24 + row * 82, width: 68, height: 50),
                style: style,
                mosaicRedaction: redaction
            )
        }
        window.test_setAnnotations(annotations)
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_selectAnnotation(at: 0)

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let fullRenderCountBeforeRotation = window.test_mosaicFullCompositeRenderCount
        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 34, y: rotationPoint.y + 26))
        XCTAssertNotNil(window.test_renderedOverlayImage())
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 58, y: rotationPoint.y + 42))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicFullCompositeRenderCount, fullRenderCountBeforeRotation)
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 58, y: rotationPoint.y + 42))
    }

    func testOverlayWindowSelectingMosaicRectangleDoesNotRecomposeManyLayers() throws {
        let image = checkerboardImage(size: NSSize(width: 900, height: 640), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 40, width: 780, height: 520)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let annotations = (0..<36).map { index in
            let column = index % 6
            let row = index / 6
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 20 + column * 118, y: 24 + row * 78, width: 74, height: 48),
                style: style,
                mosaicRedaction: redaction
            )
        }
        window.test_setAnnotations(annotations)
        window.test_activateShapeTool(.mosaicRectangle)

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let fullRenderCountBeforeSelection = window.test_mosaicFullCompositeRenderCount

        let selectionPoint = NSPoint(x: selection.minX + 20 + 37, y: selection.minY + 24 + 24)
        window.test_mouseDown(at: selectionPoint)
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicFullCompositeRenderCount, fullRenderCountBeforeSelection)
    }

    func testOverlayWindowMosaicRectangleEmptyClickReusesCompletedCompositeCache() throws {
        let image = gradientImage(size: NSSize(width: 260, height: 180))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        window.test_mouseDown(at: NSPoint(x: 52, y: 48))
        window.test_mouseDragged(to: NSPoint(x: 134, y: 104))
        window.test_mouseUp(at: NSPoint(x: 134, y: 104))

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let renderCountBeforeEmptyClick = window.test_mosaicCompositeRenderCount

        window.test_mouseDown(at: NSPoint(x: 190, y: 80))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountBeforeEmptyClick)
        window.test_mouseUp(at: NSPoint(x: 190, y: 80))
    }

    func testOverlayWindowSecondGaussianMosaicRectangleDraftReusesPreviewWorkWhileResizing() throws {
        let image = gradientImage(size: NSSize(width: 360, height: 240))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 300, height: 180))
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        window.test_mouseDown(at: NSPoint(x: 52, y: 48))
        window.test_mouseDragged(to: NSPoint(x: 134, y: 104))
        window.test_mouseUp(at: NSPoint(x: 134, y: 104))

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let fullRenderCountBeforeSecondDraft = window.test_mosaicFullCompositeRenderCount

        window.test_mouseDown(at: NSPoint(x: 176, y: 80))
        window.test_mouseDragged(to: NSPoint(x: 248, y: 136))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        let fullRenderCountAfterFirstPreview = window.test_mosaicFullCompositeRenderCount
        let redactedBaseRenderCountAfterFirstPreview = window.test_mosaicDraftRedactedBaseRenderCount

        window.test_mouseDragged(to: NSPoint(x: 252, y: 140))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicFullCompositeRenderCount, fullRenderCountAfterFirstPreview)
        XCTAssertLessThanOrEqual(
            window.test_mosaicDraftRedactedBaseRenderCount - redactedBaseRenderCountAfterFirstPreview,
            1
        )
        XCTAssertGreaterThanOrEqual(fullRenderCountAfterFirstPreview, fullRenderCountBeforeSecondDraft)
        window.test_mouseUp(at: NSPoint(x: 252, y: 140))
    }

    func testOverlayWindowDraggingMosaicValueUsesLocalPreviewWithoutFullCompositeRender() throws {
        let image = gradientImage(size: NSSize(width: 260, height: 180))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.pixelMosaic))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: NSPoint(x: 52, y: 48))
        window.test_mouseDragged(to: NSPoint(x: 134, y: 104))
        window.test_mouseUp(at: NSPoint(x: 134, y: 104))

        XCTAssertNotNil(window.test_renderedOverlayImage())
        let renderCountBeforeDrag = window.test_mosaicCompositeRenderCount
        let sliderPoint = try XCTUnwrap(window.test_mosaicValueIncrementPoint())

        window.test_mouseDown(at: sliderPoint)
        window.test_mouseDragged(to: NSPoint(x: sliderPoint.x + 20, y: sliderPoint.y))
        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())

        let overlayPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: NSPoint(x: 92, y: 76)))
        let originalPixel = try XCTUnwrap(rgbaPixel(in: image, at: NSPoint(x: 92, y: 76)))
        XCTAssertTrue(pixelDiffers(overlayPixel, originalPixel))
        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountBeforeDrag)
        window.test_mouseUp(at: NSPoint(x: sliderPoint.x + 20, y: sliderPoint.y))
    }

    func testOverlayWindowMosaicRectangleRotationHandleWinsOutsideSelection() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))

        let rotationPoint = try XCTUnwrap(window.test_mosaicRectangleRotationHandlePoint())
        XCTAssertGreaterThan(rotationPoint.y, selection.maxY)
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 24, y: rotationPoint.y + 18))
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 24, y: rotationPoint.y + 18))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertGreaterThan(abs(window.test_annotationRotationAngle(at: 0) ?? 0), 0.05)
    }

    func testOverlayWindowMosaicToolbarShowsDotAndRectangleModeControls() {
        var refreshCallCount = 0
        let window = SelectionOverlayWindow(
            backgroundImage: nil,
            refreshHandler: {
                refreshCallCount += 1
                return nil
            }
        ) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        XCTAssertEqual(refreshCallCount, 0)
        XCTAssertNotNil(window.test_mosaicRectangleOptionPoint())
        XCTAssertNotNil(window.test_optionsStrokeWidthPoint(at: 0))
        XCTAssertEqual(window.test_currentShapeKind, .mosaicRectangle)
    }

    func testOverlayWindowMosaicLargeDotDoesNotTriggerRefreshAndCanDraw() {
        var refreshCallCount = 0
        let window = SelectionOverlayWindow(
            backgroundImage: nil,
            refreshHandler: {
                refreshCallCount += 1
                return nil
            }
        ) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)
        window.test_setCurrentStrokeWidth(35)

        XCTAssertEqual(refreshCallCount, 0)
        XCTAssertEqual(window.test_currentShapeKind, .mosaicStroke)
        XCTAssertEqual(window.test_currentStyle?.strokeWidth, 35)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 180))
        window.test_mouseUp(at: NSPoint(x: 210, y: 180))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_annotationStyle(at: 0)?.strokeWidth, 35)
    }

    func testOverlayWindowMosaicDotClickCreatesDotRedaction() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseUp(at: NSPoint(x: 150, y: 150))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_annotationStyle(at: 0)?.strokeWidth, 15)
        XCTAssertEqual(window.test_mosaicStroke(at: 0)?.points.count, 1)
    }

    func testOverlayWindowMosaicRectangleOptionSwitchesFromDotToRectangleMode() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        guard let rectanglePoint = window.test_mosaicRectangleOptionPoint() else {
            return XCTFail("Expected mosaic rectangle option")
        }
        window.test_mouseDown(at: rectanglePoint)
        window.test_mouseUp(at: rectanglePoint)

        XCTAssertEqual(window.test_currentShapeKind, .mosaicRectangle)
        XCTAssertEqual(window.test_optionsToolbarMode, .mosaic)
    }

    func testOverlayWindowMosaicRectangleOptionGlyphTurnsBlueWhenSelected() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        let rectanglePoint = try XCTUnwrap(window.test_mosaicRectangleOptionPoint())
        window.test_mouseDown(at: rectanglePoint)
        window.test_mouseUp(at: rectanglePoint)

        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let sampleRect = NSRect(x: rectanglePoint.x - 10, y: rectanglePoint.y - 10, width: 20, height: 20)
        XCTAssertNotNil(try firstBlueDominantPixel(in: image, rect: sampleRect))
    }

    func testOverlayWindowMosaicLargeDotKeepsShortHorizontalStroke() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)
        window.test_setCurrentStrokeWidth(35)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 150))
        window.test_mouseUp(at: NSPoint(x: 210, y: 150))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_annotationStyle(at: 0)?.strokeWidth, 35)
        XCTAssertEqual(window.test_mosaicStroke(at: 0)?.points.count ?? 0, 2)
    }

    func testOverlayWindowMosaicStrokeCollectsDraggedPoints() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 165))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 180))
        window.test_mouseUp(at: NSPoint(x: 240, y: 200))

        guard let stroke = window.test_mosaicStroke(at: 0) else {
            return XCTFail("Expected mosaic stroke")
        }
        XCTAssertGreaterThan(stroke.points.count, 2)
    }

    func testOverlayWindowMosaicStrokeCanStartOutsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 80, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 160))
        window.test_mouseUp(at: NSPoint(x: 180, y: 170))

        guard let stroke = window.test_mosaicStroke(at: 0) else {
            return XCTFail("Expected mosaic stroke")
        }

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertLessThan(stroke.points.first?.x ?? 0, 0)
        XCTAssertGreaterThan(stroke.points.last?.x ?? 0, 0)
    }

    func testOverlayWindowMosaicStrokeResizesSelectionFromBorder() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: selection.minX, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 150, y: 160))
        window.test_mouseUp(at: NSPoint(x: 150, y: 160))

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertEqual(window.test_lockedSelectionRect?.minX, 150)
        XCTAssertEqual(window.test_lockedSelectionRect?.width, 250)
    }

    func testOverlayWindowMosaicStrokeShiftDrawsAxisLockedLine() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 190, y: 162), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: 190, y: 162), modifierFlags: [.shift])

        guard let stroke = window.test_mosaicStroke(at: 0) else {
            return XCTFail("Expected mosaic stroke")
        }
        XCTAssertEqual(stroke.points.count, 2)
        XCTAssertEqual(stroke.points[0].y, stroke.points[1].y, accuracy: 0.001)
        XCTAssertGreaterThan(stroke.points[1].x, stroke.points[0].x)
    }

    func testOverlayWindowMosaicStrokeDoesNotMoveExistingStroke() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 150))
        window.test_mouseUp(at: NSPoint(x: 210, y: 150))

        let original = window.test_mosaicStroke(at: 0)?.points
        window.test_mouseDown(at: NSPoint(x: 180, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 200, y: 170))
        window.test_mouseUp(at: NSPoint(x: 200, y: 170))

        guard let before = original, let after = window.test_mosaicStroke(at: 0)?.points else {
            return XCTFail("Expected mosaic stroke")
        }
        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(after.first?.x ?? 0, before.first?.x ?? 0, accuracy: 0.001)
        XCTAssertEqual(after.first?.y ?? 0, before.first?.y ?? 0, accuracy: 0.001)
    }

    func testOverlayWindowMosaicRectangleCanMoveResizeAndRotate() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected mosaic rectangle")
        }
        XCTAssertEqual(window.test_selectedAnnotationKind, .mosaicRectangle)
        XCTAssertTrue(window.test_selectedAnnotationShowsOutline)

        window.test_mouseDown(at: NSPoint(x: 160, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 190, y: 170))
        window.test_mouseUp(at: NSPoint(x: 190, y: 170))

        guard let moved = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected moved mosaic rectangle")
        }
        XCTAssertEqual(moved.origin.x, original.origin.x + 30, accuracy: 0.1)
        XCTAssertEqual(moved.origin.y, original.origin.y + 20, accuracy: 0.1)

        guard let resizePoint = window.test_shapeResizeHandlePoint(.bottomRight) else {
            return XCTFail("Expected resize handle")
        }
        window.test_mouseDown(at: resizePoint)
        window.test_mouseDragged(to: NSPoint(x: resizePoint.x + 30, y: resizePoint.y - 20))
        window.test_mouseUp(at: NSPoint(x: resizePoint.x + 30, y: resizePoint.y - 20))

        guard let resized = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected resized mosaic rectangle")
        }
        XCTAssertGreaterThan(resized.width, moved.width)
        XCTAssertGreaterThan(resized.height, moved.height)

        guard let rotationPoint = window.test_mosaicRectangleRotationHandlePoint() else {
            return XCTFail("Expected rotation handle")
        }
        window.test_mouseDown(at: rotationPoint)
        window.test_mouseDragged(to: NSPoint(x: rotationPoint.x + 30, y: rotationPoint.y + 25))
        window.test_mouseUp(at: NSPoint(x: rotationPoint.x + 30, y: rotationPoint.y + 25))

        XCTAssertGreaterThan(abs(window.test_annotationRotationAngle(at: 0) ?? 0), 0.05)
        XCTAssertEqual(window.test_mosaicRectangleRotationHandleGlyph(), .refreshDot)
    }

    func testOverlayWindowResizesMosaicRectangleEdgeAfterHalfTurnRotation() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 360, height: 260)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let annotation = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 50, y: 54, width: 120, height: 80),
            style: style,
            rotationAngle: .pi,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )
        window.test_setAnnotations([annotation])
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_selectAnnotation(at: 0)

        let original = try XCTUnwrap(window.test_annotationRect(at: 0))
        let visualBottomHandleForTopEdge = try XCTUnwrap(window.test_shapeResizeHandlePoint(.top))
        window.test_mouseDown(at: visualBottomHandleForTopEdge)
        window.test_mouseDragged(to: NSPoint(x: visualBottomHandleForTopEdge.x, y: visualBottomHandleForTopEdge.y - 28))
        window.test_mouseUp(at: NSPoint(x: visualBottomHandleForTopEdge.x, y: visualBottomHandleForTopEdge.y - 28))

        let resized = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertGreaterThan(resized.height, original.height)
        XCTAssertEqual(window.test_annotationRotationAngle(at: 0) ?? 0, .pi, accuracy: 0.001)
    }

    func testOverlayWindowHalfTurnMosaicRectangleResizesVisualLeftEdge() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 360, height: 260)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let annotation = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 50, y: 54, width: 120, height: 80),
            style: style,
            rotationAngle: .pi,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )
        window.test_setAnnotations([annotation])
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_selectAnnotation(at: 0)

        let visualLeftHandle = try XCTUnwrap(window.test_shapeResizeHandlePoint(.right))
        let visualRightBefore = try XCTUnwrap(window.test_shapeResizeHandlePoint(.left))
        window.test_mouseDown(at: visualLeftHandle)
        window.test_mouseDragged(to: NSPoint(x: visualLeftHandle.x - 28, y: visualLeftHandle.y))
        window.test_mouseUp(at: NSPoint(x: visualLeftHandle.x - 28, y: visualLeftHandle.y))

        let visualLeftAfter = try XCTUnwrap(window.test_shapeResizeHandlePoint(.right))
        let visualRightAfter = try XCTUnwrap(window.test_shapeResizeHandlePoint(.left))
        XCTAssertLessThan(visualLeftAfter.x, visualLeftHandle.x)
        XCTAssertEqual(visualRightAfter.x, visualRightBefore.x, accuracy: 0.5)
        XCTAssertEqual(window.test_annotationCount, 1)
    }

    func testOverlayWindowHalfTurnMosaicRectangleResizesVisualRightEdge() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 360, height: 260)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let annotation = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 50, y: 54, width: 120, height: 80),
            style: style,
            rotationAngle: .pi,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )
        window.test_setAnnotations([annotation])
        window.test_activateShapeTool(.mosaicRectangle)
        window.test_selectAnnotation(at: 0)

        let visualRightHandle = try XCTUnwrap(window.test_shapeResizeHandlePoint(.left))
        let visualLeftBefore = try XCTUnwrap(window.test_shapeResizeHandlePoint(.right))
        window.test_mouseDown(at: visualRightHandle)
        window.test_mouseDragged(to: NSPoint(x: visualRightHandle.x + 28, y: visualRightHandle.y))
        window.test_mouseUp(at: NSPoint(x: visualRightHandle.x + 28, y: visualRightHandle.y))

        let visualRightAfter = try XCTUnwrap(window.test_shapeResizeHandlePoint(.left))
        let visualLeftAfter = try XCTUnwrap(window.test_shapeResizeHandlePoint(.right))
        XCTAssertGreaterThan(visualRightAfter.x, visualRightHandle.x)
        XCTAssertEqual(visualLeftAfter.x, visualLeftBefore.x, accuracy: 0.5)
        XCTAssertEqual(window.test_annotationCount, 1)
    }

    func testOverlayWindowMosaicRectangleCanStartOutsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 80, y: 130))
        window.test_mouseDragged(to: NSPoint(x: 160, y: 190))
        window.test_mouseUp(at: NSPoint(x: 160, y: 190))

        guard let rect = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected mosaic rectangle")
        }

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertLessThan(rect.minX, 0)
        XCTAssertGreaterThan(rect.maxX, 0)
    }

    func testOverlayWindowMosaicStrokeDraftUsesLiveCompositePreviewPath() {
        let image = NSImage(size: NSSize(width: 500, height: 400))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 500, height: 400).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))

        XCTAssertTrue(window.test_mosaicStrokeDraftUsesLiveCompositePreviewPath)

        window.test_mouseUp(at: NSPoint(x: 220, y: 180))
    }

    func testOverlayWindowMosaicRectangleDraftUsesLiveCompositePreviewPath() {
        let image = NSImage(size: NSSize(width: 500, height: 400))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 500, height: 400).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))

        XCTAssertTrue(window.test_mosaicRectangleDraftUsesLivePreviewPath)

        window.test_mouseUp(at: NSPoint(x: 220, y: 180))
    }

    func testOverlayWindowMosaicStrokeDraftUsesLocalPreviewTile() {
        let image = NSImage(size: NSSize(width: 500, height: 400))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 500, height: 400).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let stroke = CaptureMosaicStroke(points: [
            NSPoint(x: 40, y: 40),
            NSPoint(x: 120, y: 80),
        ])
        let draft = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: stroke.boundingRect,
            style: style,
            mosaicStroke: stroke,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        guard let drawRect = window.test_mosaicDraftPreviewDrawRect(for: draft) else {
            return XCTFail("Expected mosaic stroke preview draw rect")
        }

        XCTAssertLessThan(drawRect.width, image.size.width)
        XCTAssertLessThan(drawRect.height, image.size.height)
        XCTAssertLessThan(drawRect.minX, 140)
        XCTAssertLessThan(drawRect.minY, 140)
        XCTAssertGreaterThan(drawRect.maxX, 220)
        XCTAssertGreaterThan(drawRect.maxY, 180)
    }

    func testOverlayWindowMosaicRectangleDraftUsesLocalPreviewTile() {
        let image = NSImage(size: NSSize(width: 500, height: 400))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 500, height: 400).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 40, y: 40, width: 80, height: 40),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        guard let drawRect = window.test_mosaicDraftPreviewDrawRect(for: draft) else {
            return XCTFail("Expected mosaic rectangle preview draw rect")
        }

        XCTAssertLessThan(drawRect.width, image.size.width)
        XCTAssertLessThan(drawRect.height, image.size.height)
        XCTAssertLessThan(drawRect.minX, 140)
        XCTAssertLessThan(drawRect.minY, 140)
        XCTAssertGreaterThan(drawRect.maxX, 220)
        XCTAssertGreaterThan(drawRect.maxY, 180)
    }

    func testOverlayWindowMosaicRectangleDraftReusesRedactedBaseWhileResizing() throws {
        let image = checkerboardImage(size: NSSize(width: 500, height: 400), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let firstDraft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 40, y: 40, width: 80, height: 40),
            style: style,
            mosaicRedaction: redaction
        )
        let resizedDraft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 40, y: 40, width: 170, height: 120),
            style: style,
            mosaicRedaction: redaction
        )

        let renderCountBeforePreview = window.test_mosaicDraftRedactedBaseRenderCount
        XCTAssertNotNil(window.test_mosaicDraftPreview(for: firstDraft))
        XCTAssertNotNil(window.test_mosaicDraftPreview(for: resizedDraft))

        XCTAssertEqual(window.test_mosaicDraftRedactedBaseRenderCount - renderCountBeforePreview, 1)
    }

    func testOverlayWindowMosaicRectangleDraftWithExistingMosaicAvoidsFullCompositeRender() throws {
        let image = checkerboardImage(size: NSSize(width: 760, height: 520), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 660, height: 400))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let annotations = (0..<24).map { index in
            let column = index % 6
            let row = index / 6
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 20 + column * 96, y: 24 + row * 74, width: 62, height: 46),
                style: style,
                mosaicRedaction: redaction
            )
        }
        window.test_setAnnotations(annotations)

        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 72, y: 66, width: 130, height: 92),
            style: style,
            mosaicRedaction: redaction
        )
        let fullRenderCountBeforePreview = window.test_mosaicFullCompositeRenderCount

        XCTAssertNotNil(window.test_mosaicDraftPreview(for: draft))
        XCTAssertEqual(window.test_mosaicFullCompositeRenderCount, fullRenderCountBeforePreview)
    }

    func testOverlayWindowDrawingMosaicRectangleDraftWithExistingMosaicAvoidsFullCompositeRender() throws {
        let image = checkerboardImage(size: NSSize(width: 760, height: 520), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 660, height: 400))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 25
        let redaction = CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        let annotations = (0..<24).map { index in
            let column = index % 6
            let row = index / 6
            return CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 20 + column * 96, y: 24 + row * 74, width: 62, height: 46),
                style: style,
                mosaicRedaction: redaction
            )
        }
        window.test_setAnnotations(annotations)
        window.test_toggleShapeTool(.mosaicRectangle)

        let fullRenderCountBeforeDraw = window.test_mosaicFullCompositeRenderCount
        window.test_mouseDown(at: NSPoint(x: 132, y: 122))
        window.test_mouseDragged(to: NSPoint(x: 286, y: 204))

        XCTAssertNotNil(window.test_renderedOverlayImage())
        XCTAssertEqual(window.test_mosaicFullCompositeRenderCount, fullRenderCountBeforeDraw)

        window.test_mouseUp(at: NSPoint(x: 286, y: 204))
    }

    func testOverlayWindowDrawsMosaicRectangleDraftWithoutAllocatingPreviewImageWhileResizing() throws {
        let image = checkerboardImage(size: NSSize(width: 500, height: 400), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        let previewImageRenderCountBeforeDrag = window.test_mosaicDraftPreviewImageRenderCount
        let redactedBaseRenderCountBeforeDrag = window.test_mosaicDraftRedactedBaseRenderCount

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 280, y: 230))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        let redactedBaseRenderCountAfterFirstFrame = window.test_mosaicDraftRedactedBaseRenderCount

        window.test_mouseDragged(to: NSPoint(x: 320, y: 260))
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicDraftPreviewImageRenderCount, previewImageRenderCountBeforeDrag)
        XCTAssertEqual(redactedBaseRenderCountAfterFirstFrame - redactedBaseRenderCountBeforeDrag, 1)
        XCTAssertEqual(window.test_mosaicDraftRedactedBaseRenderCount, redactedBaseRenderCountAfterFirstFrame)

        window.test_mouseUp(at: NSPoint(x: 320, y: 260))
    }

    func testOverlayWindowMosaicRectangleDraftPreservesExistingDotMosaic() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 88, y: 82))
        window.test_mouseUp(at: NSPoint(x: 88, y: 82))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 40, y: 35, width: 80, height: 70),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        guard let preview = window.test_mosaicDraftPreview(for: draft) else {
            return XCTFail("Expected mosaic rectangle preview")
        }
        let originalCrop = try XCTUnwrap(croppedImage(image, to: preview.drawRect))
        let originalOnlyPreview = CaptureAnnotationRenderer.redactedPreview(
            image: originalCrop,
            redaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        XCTAssertNotEqual(try rgbaBytes(in: preview.image), try rgbaBytes(in: originalOnlyPreview))
    }

    func testOverlayWindowMosaicRectangleDraftFullyRedactsOverExistingDotMosaic() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 88, y: 82))
        window.test_mouseUp(at: NSPoint(x: 88, y: 82))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 40, y: 35, width: 80, height: 70),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let originalCrop = try XCTUnwrap(croppedImage(image, to: preview.drawRect))

        for point in [
            NSPoint(x: 72, y: 60),
            NSPoint(x: 88, y: 82),
            NSPoint(x: 112, y: 92),
            NSPoint(x: 132, y: 122),
        ] {
            let localPoint = NSPoint(x: point.x - preview.drawRect.minX, y: point.y - preview.drawRect.minY)
            let previewPixel = try XCTUnwrap(rgbaPixel(in: preview.image, at: localPoint))
            let originalPixel = try XCTUnwrap(rgbaPixel(in: originalCrop, at: localPoint))
            XCTAssertTrue(pixelDiffers(previewPixel, originalPixel), "Expected draft mosaic to redact \(point)")
        }
    }

    func testOverlayWindowRenderedMosaicRectangleDoesNotRevealExistingDotMosaic() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let originalClearPixel = try XCTUnwrap(rgbaPixel(in: image, at: NSPoint(x: 112, y: 92)))

        let combinedWindow = SelectionOverlayWindow(backgroundImage: image) { _ in }
        combinedWindow.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        combinedWindow.test_toggleShapeTool(.mosaicStroke)
        combinedWindow.test_mouseDown(at: NSPoint(x: 88, y: 82))
        combinedWindow.test_mouseUp(at: NSPoint(x: 88, y: 82))
        let typePoint = try XCTUnwrap(combinedWindow.test_mosaicRedactionTypePoint(.gaussianBlur))
        combinedWindow.test_mouseDown(at: typePoint)
        combinedWindow.test_mouseUp(at: typePoint)
        combinedWindow.test_toggleShapeTool(.mosaicRectangle)
        combinedWindow.test_mouseDown(at: NSPoint(x: 60, y: 55))
        combinedWindow.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        combinedWindow.test_mouseUp(at: NSPoint(x: 140, y: 125))
        let combinedImage = try XCTUnwrap(combinedWindow.test_renderedOverlayImage())
        let combinedDotPixel = try XCTUnwrap(rgbaPixel(in: combinedImage, at: NSPoint(x: 88, y: 82)))
        let combinedRectanglePixel = try XCTUnwrap(rgbaPixel(in: combinedImage, at: NSPoint(x: 112, y: 92)))

        let originalDotPixel = try XCTUnwrap(rgbaPixel(in: image, at: NSPoint(x: 88, y: 82)))
        XCTAssertTrue(pixelDiffers(combinedDotPixel, originalDotPixel))
        XCTAssertTrue(pixelDiffers(combinedRectanglePixel, originalClearPixel))
    }

    func testOverlayWindowRenderedDotAndRectangleMosaicOverlapKeepsStackedRedaction() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let overlapPoint = NSPoint(x: 88, y: 82)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicStroke)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: overlapPoint)
        window.test_mouseUp(at: overlapPoint)

        window.test_toggleShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))

        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let style = try XCTUnwrap(window.test_annotationStyle(at: 1))
        let rectangleRedaction = try XCTUnwrap(window.test_mosaicRedaction(at: 1))
        let secondAnnotation = overlayMosaicAnnotation(CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 1)),
            style: style,
            mosaicRedaction: rectangleRedaction
        ), selection: selection)
        let rectangleOnly = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [secondAnnotation]
        )

        let overlayPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: overlapPoint))
        let originalPixel = try XCTUnwrap(rgbaPixel(in: image, at: overlapPoint))
        let rectangleOnlyPixel = try XCTUnwrap(rgbaPixel(in: rectangleOnly, at: overlapPoint))

        XCTAssertTrue(pixelDiffers(overlayPixel, originalPixel))
        XCTAssertTrue(pixelDiffers(overlayPixel, rectangleOnlyPixel))
    }

    func testOverlayAppliesLocalEraserMaskToAnnotationPixels() throws {
        let image = solidImage(size: NSSize(width: 320, height: 220), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 30, width: 220, height: 140)
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        style.fillEnabled = true
        style.fillColor = .red
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 30, y: 30, width: 100, height: 70),
            style: style
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(
            rect: NSRect(x: 55, y: 45, width: 25, height: 25),
            affectedAnnotationIDs: [annotation.id]
        ))

        let rendered = try XCTUnwrap(window.test_renderedOverlayImage())
        let maskedPoint = NSPoint(
            x: selection.minX + 60,
            y: rendered.size.height - selection.minY - 50
        )
        let unmaskedPoint = NSPoint(
            x: selection.minX + 35,
            y: rendered.size.height - selection.minY - 35
        )

        XCTAssertEqual(hex(try XCTUnwrap(rgbaPixel(in: rendered, at: maskedPoint))), "#FFFFFF")
        XCTAssertEqual(hex(try XCTUnwrap(rgbaPixel(in: rendered, at: unmaskedPoint))), "#FF0000")
    }

    func testOverlayEraserMaskRevealsOriginalScreenshotThroughMosaic() throws {
        let image = gradientImage(size: NSSize(width: 320, height: 220))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 30, width: 220, height: 140)
        let mosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 30, y: 30, width: 100, height: 70),
            style: CaptureAnnotationStyle(),
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 10)
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([mosaic])
        window.test_addEraserMask(EraserMask(
            rect: NSRect(x: 55, y: 45, width: 25, height: 25),
            affectedAnnotationIDs: [mosaic.id]
        ))

        let rendered = try XCTUnwrap(window.test_renderedOverlayImage())
        let overlayPoint = NSPoint(
            x: selection.minX + 60,
            y: rendered.size.height - selection.minY - 50
        )
        let originalPoint = NSPoint(
            x: selection.minX + 60,
            y: image.size.height - selection.minY - 50
        )
        let original = try XCTUnwrap(rgbaPixel(
            in: image,
            at: originalPoint
        ))
        let overlay = try XCTUnwrap(rgbaPixel(
            in: rendered,
            at: overlayPoint
        ))

        XCTAssertLessThan(abs(Int(overlay.red) - Int(original.red)), 4)
        XCTAssertLessThan(abs(Int(overlay.green) - Int(original.green)), 4)
        XCTAssertLessThan(abs(Int(overlay.blue) - Int(original.blue)), 4)
    }

    func testOverlayKeepsSelectionHandleVisibleWithEraserMasks() throws {
        let image = solidImage(size: NSSize(width: 320, height: 220), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 30, width: 220, height: 140)
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        style.fillEnabled = true
        style.fillColor = .red
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 30, y: 30, width: 100, height: 70),
            style: style
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(
            rect: NSRect(x: 55, y: 45, width: 25, height: 25),
            affectedAnnotationIDs: [annotation.id]
        ))

        let rendered = try XCTUnwrap(window.test_renderedOverlayImage())
        let handle = NSPoint(x: selection.midX, y: selection.maxY)
        let pixel = try XCTUnwrap(rgbaPixel(
            in: rendered,
            at: NSPoint(x: handle.x, y: rendered.size.height - handle.y)
        ))

        XCTAssertGreaterThan(pixel.blue, 200)
        XCTAssertGreaterThan(pixel.green, 90)
        XCTAssertLessThan(pixel.red, 130)
    }

    func testOverlayKeepsMosaicDraftPreviewVisibleWithEraserMasks() throws {
        let image = checkerboardImage(size: NSSize(width: 320, height: 220), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 30, width: 220, height: 140)
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        style.fillEnabled = true
        style.fillColor = .red
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 10, y: 10, width: 40, height: 30),
            style: style
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])
        window.test_addEraserMask(EraserMask(
            rect: NSRect(x: 20, y: 20, width: 10, height: 10),
            affectedAnnotationIDs: [annotation.id]
        ))

        window.test_toggleShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: selection.minX + 80, y: selection.minY + 60))
        window.test_mouseDragged(to: NSPoint(x: selection.minX + 170, y: selection.minY + 115))

        let rendered = try XCTUnwrap(window.test_renderedOverlayImage())
        let probe = NSPoint(x: selection.minX + 112, y: selection.minY + 82)
        let overlay = try XCTUnwrap(rgbaPixel(
            in: rendered,
            at: NSPoint(x: probe.x, y: rendered.size.height - probe.y)
        ))
        let original = try XCTUnwrap(rgbaPixel(
            in: image,
            at: NSPoint(x: probe.x, y: image.size.height - probe.y)
        ))

        XCTAssertTrue(pixelDiffers(overlay, original))
    }

    func testMosaicPreviewCacheInvalidatesWhenEraserMaskChanges() throws {
        let image = gradientImage(size: NSSize(width: 320, height: 220))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 40, y: 30, width: 220, height: 140)
        let annotation = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 30, y: 30, width: 100, height: 70),
            style: CaptureAnnotationStyle(),
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 10)
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [annotation]))
        let renderCountBeforeMask = window.test_mosaicCompositeRenderCount
        window.test_addEraserMask(EraserMask(
            rect: NSRect(x: 55, y: 45, width: 25, height: 25),
            affectedAnnotationIDs: [annotation.id]
        ))

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [annotation]))
        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountBeforeMask + 1)
    }

    func testRendererWithoutEraserMasksMatchesExistingRenderPath() throws {
        let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        style.fillEnabled = true
        style.fillColor = .red
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 40, height: 30), style: style)

        let existing = CaptureAnnotationRenderer.render(image: image, annotations: [annotation])
        let maskedEntry = CaptureAnnotationRenderer.render(image: image, annotations: [annotation], eraserMasks: [])

        XCTAssertEqual(
            hex(try XCTUnwrap(rgbaRenderPixel(in: existing, at: NSPoint(x: 20, y: 20)))),
            hex(try XCTUnwrap(rgbaRenderPixel(in: maskedEntry, at: NSPoint(x: 20, y: 20))))
        )
    }

    func testRendererNoMaskFastPathReturnsOriginalImageWhenNoAnnotations() {
        let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [], eraserMasks: [])

        XCTAssertTrue(rendered === image)
    }

    func testRendererAppliesEraserMaskOnlyToAffectedAnnotationLayer() throws {
        let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
        var redStyle = CaptureAnnotationStyle()
        redStyle.strokeColor = .red
        redStyle.fillEnabled = true
        redStyle.fillColor = .red
        var blueStyle = CaptureAnnotationStyle()
        blueStyle.strokeColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        blueStyle.fillEnabled = true
        blueStyle.fillColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

        let red = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 40, height: 30), style: redStyle)
        let blue = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 50, y: 10, width: 20, height: 30), style: blueStyle)
        let mask = EraserMask(rect: NSRect(x: 18, y: 18, width: 12, height: 12), affectedAnnotationIDs: [red.id])

        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [red, blue], eraserMasks: [mask])

        XCTAssertEqual(hex(try XCTUnwrap(rgbaRenderPixel(in: rendered, at: NSPoint(x: 22, y: 22)))), "#FFFFFF")
        XCTAssertEqual(hex(try XCTUnwrap(rgbaRenderPixel(in: rendered, at: NSPoint(x: 14, y: 14)))), "#FF0000")
        let bluePixel = try XCTUnwrap(rgbaRenderPixel(in: rendered, at: NSPoint(x: 58, y: 22)))
        XCTAssertLessThanOrEqual(bluePixel.red, 8)
        XCTAssertLessThanOrEqual(bluePixel.green, 8)
        XCTAssertGreaterThanOrEqual(bluePixel.blue, 247)
    }

    func testRendererKeepsOverlappingUnaffectedAnnotationVisibleInsideMask() throws {
        let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
        var redStyle = CaptureAnnotationStyle()
        redStyle.strokeColor = .red
        redStyle.fillEnabled = true
        redStyle.fillColor = .red
        var blueStyle = CaptureAnnotationStyle()
        blueStyle.strokeColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        blueStyle.fillEnabled = true
        blueStyle.fillColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

        let red = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 44, height: 34), style: redStyle)
        let blue = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 22, y: 18, width: 34, height: 26), style: blueStyle)
        let mask = EraserMask(rect: NSRect(x: 26, y: 22, width: 18, height: 12), affectedAnnotationIDs: [red.id])

        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [red, blue], eraserMasks: [mask])

        let overlapPixel = try XCTUnwrap(rgbaRenderPixel(in: rendered, at: NSPoint(x: 30, y: 26)))
        XCTAssertLessThanOrEqual(overlapPixel.red, 8)
        XCTAssertLessThanOrEqual(overlapPixel.green, 8)
        XCTAssertGreaterThanOrEqual(overlapPixel.blue, 247)
    }

    func testRendererWithUnrelatedEraserMaskPreservesMosaicAnnotation() throws {
        let image = checkerboardImage(size: NSSize(width: 96, height: 72), squareSize: 2)
        var style = CaptureAnnotationStyle()
        style.strokeWidth = 0
        let mosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 16, y: 14, width: 54, height: 36),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )
        let unrelatedMask = EraserMask(
            rect: NSRect(x: 20, y: 18, width: 12, height: 12),
            affectedAnnotationIDs: [UUID()]
        )

        let existing = CaptureAnnotationRenderer.render(image: image, annotations: [mosaic])
        let maskedEntry = CaptureAnnotationRenderer.render(image: image, annotations: [mosaic], eraserMasks: [unrelatedMask])
        let probePoint = NSPoint(x: 42, y: 32)
        let existingPixel = try XCTUnwrap(rgbaRenderPixel(in: existing, at: probePoint))
        let maskedPixel = try XCTUnwrap(rgbaRenderPixel(in: maskedEntry, at: probePoint))

        XCTAssertLessThanOrEqual(pixelDistance(existingPixel, maskedPixel), 4)
    }

    @MainActor
    func testCaptureCoordinatorExportAppliesEraserMasks() async throws {
        let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        style.fillEnabled = true
        style.fillColor = .red
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 60, height: 40), style: style)
        let mask = EraserMask(rect: NSRect(x: 30, y: 25, width: 20, height: 20), affectedAnnotationIDs: [annotation.id])
        let result = CaptureSelectionResult(
            screenRect: NSRect(origin: .zero, size: image.size),
            snapshotRect: NSRect(origin: .zero, size: image.size),
            annotations: [annotation],
            eraserMasks: [mask],
            action: .copy
        )
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService()
        )
        let expectation = expectation(description: "capture")
        coordinator.captureSessionDidEnd = {
            expectation.fulfill()
        }

        coordinator.test_handleSelection(result, frozenDesktopImage: image)
        await fulfillment(of: [expectation], timeout: 2)

        let exported = try XCTUnwrap(coordinator.test_lastCapture)
        XCTAssertEqual(hex(try XCTUnwrap(rgbaRenderPixel(in: exported, at: NSPoint(x: 36, y: 32)))), "#FFFFFF")
        XCTAssertEqual(hex(try XCTUnwrap(rgbaRenderPixel(in: exported, at: NSPoint(x: 16, y: 16)))), "#FF0000")
    }

    @MainActor
    func testCaptureCoordinatorPinCreatesPinnedWindowWithRenderedImage() async throws {
        let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
        var style = CaptureAnnotationStyle()
        style.strokeColor = .red
        style.fillEnabled = true
        style.fillColor = .red
        let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 40, height: 30), style: style)
        let result = CaptureSelectionResult(
            screenRect: NSRect(x: 40, y: 50, width: image.size.width, height: image.size.height),
            snapshotRect: NSRect(origin: .zero, size: image.size),
            annotations: [annotation],
            action: .pin
        )
        var pinnedWindows: [FakePinnedWindow] = []
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            pinnedWindowFactory: { image, screenRect in
                let window = FakePinnedWindow(image: image, screenRect: screenRect)
                pinnedWindows.append(window)
                return window
            }
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("keep-me", forType: .string)
        let expectation = expectation(description: "pin capture")
        coordinator.captureSessionDidEnd = {
            expectation.fulfill()
        }

        coordinator.test_handleSelection(result, frozenDesktopImage: image)
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(coordinator.test_pinnedWindowCount, 1)
        let pinned = try XCTUnwrap(pinnedWindows.first)
        XCTAssertTrue(pinned.didShow)
        XCTAssertEqual(pinned.screenRect, result.screenRect)
        XCTAssertEqual(hex(try XCTUnwrap(rgbaRenderPixel(in: pinned.image, at: NSPoint(x: 16, y: 16)))), "#FF0000")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "keep-me")
    }

    @MainActor
    func testCaptureCoordinatorRestoresMostRecentlyHiddenPinnedWindow() async throws {
        let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
        var pinnedWindows: [FakePinnedWindow] = []
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            pinnedWindowFactory: { image, screenRect in
                let window = FakePinnedWindow(image: image, screenRect: screenRect)
                pinnedWindows.append(window)
                return window
            }
        )

        for index in 0..<2 {
            let completion = expectation(description: "pin \(index)")
            coordinator.captureSessionDidEnd = { completion.fulfill() }
            coordinator.test_handleSelection(
                CaptureSelectionResult(
                    screenRect: NSRect(x: CGFloat(index * 100), y: 0, width: 80, height: 60),
                    snapshotRect: NSRect(origin: .zero, size: image.size),
                    annotations: [],
                    action: .pin
                ),
                frozenDesktopImage: image
            )
            await fulfillment(of: [completion], timeout: 2)
        }

        pinnedWindows[0].simulateHide()
        pinnedWindows[1].simulateHide()

        XCTAssertTrue(coordinator.restoreMostRecentlyHiddenPinnedWindow())
        XCTAssertEqual(pinnedWindows[0].showCount, 1)
        XCTAssertEqual(pinnedWindows[1].showCount, 2)
        XCTAssertFalse(coordinator.restoreMostRecentlyHiddenPinnedWindow())
    }

    @MainActor
    func testCaptureCoordinatorCloseInvalidatesRecentHiddenPinnedWindow() async throws {
        let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
        var createdPinnedWindow: FakePinnedWindow?
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            pinnedWindowFactory: { image, screenRect in
                let window = FakePinnedWindow(image: image, screenRect: screenRect)
                createdPinnedWindow = window
                return window
            }
        )
        let completion = expectation(description: "pin")
        coordinator.captureSessionDidEnd = { completion.fulfill() }
        coordinator.test_handleSelection(
            CaptureSelectionResult(
                screenRect: NSRect(x: 0, y: 0, width: 80, height: 60),
                snapshotRect: NSRect(origin: .zero, size: image.size),
                annotations: [],
                action: .pin
            ),
            frozenDesktopImage: image
        )
        await fulfillment(of: [completion], timeout: 2)

        let pinnedWindow = try XCTUnwrap(createdPinnedWindow)
        pinnedWindow.simulateHide()
        pinnedWindow.simulateClose()

        XCTAssertFalse(coordinator.restoreMostRecentlyHiddenPinnedWindow())
        XCTAssertEqual(coordinator.test_pinnedWindowCount, 0)
    }

    @MainActor
    func testCaptureCoordinatorDetectsOnlyOnScrollRequestAndStartsResolvedTargetOnce() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        let resolvedLocalRect = NSRect(x: 20, y: 24, width: 48, height: 28)
        let resolvedScreenRect = overlay.convertToScreen(resolvedLocalRect).standardized
        let detector = FakeScrollCaptureTargetDetector(results: [resolvedScreenRect])
        var capturedSeed: ScrollCaptureSeed?
        var session: FakeScrollCaptureSession?
        let presentation = FakeScrollCapturePresentation()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { seed, _ in
                capturedSeed = seed
                let value = FakeScrollCaptureSession(seed: seed)
                session = value
                return value
            },
            scrollCapturePresentationFactory: { _ in presentation },
            frontmostApplicationResolver: { .current },
            applicationActivator: { _ in },
            scrollCaptureTargetDetector: detector
        )

        coordinator.test_installOverlayWindow(overlay)
        overlay.test_setLockedSelectionRect(seed.snapshotRect)
        XCTAssertTrue(detector.calls.isEmpty, "installing and editing an ordinary selection must not probe AX")

        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where session?.startCount != 1 { await Task.yield() }

        XCTAssertEqual(detector.calls, [FakeScrollCaptureTargetDetector.Call(
            selection: seed.screenRect,
            processIdentifier: NSRunningApplication.current.processIdentifier
        )])
        let resolvedSeed = try XCTUnwrap(capturedSeed)
        XCTAssertEqual(resolvedSeed.snapshotRect, resolvedLocalRect)
        XCTAssertEqual(resolvedSeed.screenRect, resolvedScreenRect)
        XCTAssertEqual(resolvedSeed.targetApplicationProcessIdentifier, NSRunningApplication.current.processIdentifier)
        XCTAssertEqual(session?.startCount, 1)
        XCTAssertEqual(presentation.startCount, 1)
        XCTAssertTrue(overlay.test_selectionBorderColor.isEqual(NSColor.systemGreen))
        XCTAssertTrue(overlay.test_selectionHandleColor.isEqual(NSColor.systemGreen))
    }

    @MainActor
    func testCaptureCoordinatorDetectorFallbackStartsOriginalSeedWithBlueChrome() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        let detector = FakeScrollCaptureTargetDetector(results: [nil])
        var capturedSeed: ScrollCaptureSeed?
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { seed, _ in
                capturedSeed = seed
                return FakeScrollCaptureSession(seed: seed)
            },
            scrollCapturePresentationFactory: { _ in FakeScrollCapturePresentation() },
            frontmostApplicationResolver: { .current },
            applicationActivator: { _ in },
            scrollCaptureTargetDetector: detector
        )
        coordinator.test_installOverlayWindow(overlay)

        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where capturedSeed == nil { await Task.yield() }

        XCTAssertEqual(detector.calls.count, 1)
        XCTAssertEqual(capturedSeed?.screenRect, seed.screenRect)
        XCTAssertEqual(capturedSeed?.snapshotRect, seed.snapshotRect)
        XCTAssertEqual(capturedSeed?.frozenImage, seed.frozenImage)
        XCTAssertEqual(overlay.test_lockedSelectionRect, seed.snapshotRect)
        XCTAssertTrue(overlay.test_selectionBorderColor.isEqual(overlay.test_defaultSelectionColor))
        XCTAssertTrue(overlay.test_selectionHandleColor.isEqual(overlay.test_defaultSelectionColor))
    }

    @MainActor
    func testCaptureCoordinatorFallbackPreservesBoundaryCrossingOriginalSeedForNilAndInvalidTargets() async throws {
        for usesInvalidTarget in [false, true] {
            let image = solidImage(size: NSSize(width: 640, height: 420), color: .white)
            let overlay = SelectionOverlayWindow(backgroundImage: image) { _ in }
            let selection = NSRect(x: 80, y: 60, width: 300, height: 220)
            let annotation = CaptureAnnotation(
                kind: .rectangle,
                rect: NSRect(x: 0, y: 24, width: 44, height: 32),
                style: CaptureAnnotationStyle(strokeWidth: 8)
            )
            let mask = EraserMask(
                rect: NSRect(x: -3, y: 28, width: 18, height: 12),
                affectedAnnotationIDs: [annotation.id]
            )
            overlay.test_setLockedSelectionRect(selection)
            overlay.test_setAnnotations([annotation])
            overlay.test_setEraserMasks([mask])
            let detectorTarget = usesInvalidTarget
                ? overlay.convertToScreen(NSRect(x: 0, y: 80, width: 70, height: 80))
                : nil
            let detector = FakeScrollCaptureTargetDetector(results: [detectorTarget])
            var capturedSeed: ScrollCaptureSeed?
            let coordinator = CaptureCoordinator(
                permissionCoordinator: PermissionCoordinator(),
                screenCaptureService: ScreenCaptureService(),
                scrollCaptureSessionFactory: { seed, _ in
                    capturedSeed = seed
                    return FakeScrollCaptureSession(seed: seed)
                },
                scrollCapturePresentationFactory: { _ in FakeScrollCapturePresentation() },
                frontmostApplicationResolver: { .current },
                applicationActivator: { _ in },
                scrollCaptureTargetDetector: detector
            )
            coordinator.test_installOverlayWindow(overlay)

            overlay.test_beginScrollCapture()
            for _ in 0..<40 where capturedSeed == nil { await Task.yield() }

            let fallbackSeed = try XCTUnwrap(
                capturedSeed,
                usesInvalidTarget ? "invalid target fallback" : "nil target fallback"
            )
            XCTAssertEqual(fallbackSeed.snapshotRect, selection)
            XCTAssertEqual(fallbackSeed.annotations, [annotation])
            XCTAssertEqual(fallbackSeed.eraserMasks, [mask])
            XCTAssertEqual(overlay.test_lockedSelectionRect, selection)
            XCTAssertTrue(overlay.test_selectionBorderColor.isEqual(overlay.test_defaultSelectionColor))
            XCTAssertTrue(overlay.test_selectionHandleColor.isEqual(overlay.test_defaultSelectionColor))
            coordinator.test_cancelScrollCapture()
        }
    }

    @MainActor
    func testCaptureCoordinatorDiscardsCancelledDetectionAfterNewGenerationStarts() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let detector = FakeScrollCaptureTargetDetector(results: [], suspendsRequests: true)
        var createdSessions: [FakeScrollCaptureSession] = []
        var createdPresentations: [FakeScrollCapturePresentation] = []
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { seed, _ in
                let session = FakeScrollCaptureSession(seed: seed)
                createdSessions.append(session)
                return session
            },
            scrollCapturePresentationFactory: { _ in
                let presentation = FakeScrollCapturePresentation()
                createdPresentations.append(presentation)
                return presentation
            },
            frontmostApplicationResolver: { .current },
            applicationActivator: { _ in },
            scrollCaptureTargetDetector: detector
        )
        let firstOverlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(firstOverlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where detector.pendingRequestCount < 1 { await Task.yield() }

        coordinator.test_cancelScrollCapture()

        XCTAssertTrue(createdSessions.isEmpty)
        XCTAssertTrue(createdPresentations.isEmpty)
        XCTAssertEqual(firstOverlay.test_lockedSelectionRect, seed.snapshotRect)
        XCTAssertTrue(firstOverlay.test_selectionBorderColor.isEqual(firstOverlay.test_defaultSelectionColor))

        let secondOverlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(secondOverlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where detector.pendingRequestCount < 2 { await Task.yield() }
        detector.resumeRequest(at: 1, returning: nil)
        for _ in 0..<20 where createdSessions.isEmpty { await Task.yield() }
        detector.resumeRequest(
            at: 0,
            returning: firstOverlay.convertToScreen(NSRect(x: 20, y: 24, width: 48, height: 28))
        )
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(detector.calls.count, 2)
        XCTAssertEqual(createdSessions.count, 1)
        XCTAssertEqual(createdSessions.first?.startCount, 1)
        XCTAssertEqual(createdPresentations.count, 1)
        XCTAssertEqual(createdPresentations.first?.startCount, 1)
        XCTAssertTrue(coordinator.test_overlayWindow === secondOverlay)
        XCTAssertEqual(firstOverlay.test_lockedSelectionRect, seed.snapshotRect)
        XCTAssertTrue(firstOverlay.test_selectionBorderColor.isEqual(firstOverlay.test_defaultSelectionColor))
    }

    @MainActor
    func testCaptureCoordinatorStartsOneScrollSessionAndRoutesPresentationUpdates() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in
            XCTFail("scroll capture must not use ordinary completion")
        }
        var update: (@MainActor (ScrollCapturePresentationUpdate) -> Void)?
        var session: FakeScrollCaptureSession?
        let presentation = FakeScrollCapturePresentation()
        var activatedApplication: NSRunningApplication?
        var presentationOrder: [String] = []
        presentation.onStart = { presentationOrder.append("presentation") }
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { capturedSeed, callback in
                XCTAssertEqual(capturedSeed.screenRect, seed.screenRect)
                XCTAssertEqual(
                    capturedSeed.targetApplicationProcessIdentifier,
                    NSRunningApplication.current.processIdentifier
                )
                update = callback
                let value = FakeScrollCaptureSession(seed: capturedSeed)
                session = value
                return value
            },
            scrollCapturePresentationFactory: { context in
                presentation.onStep = context.onStep
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { _, _ in XCTFail("unexpected handoff") },
            frontmostApplicationResolver: { .current },
            applicationActivator: {
                activatedApplication = $0
                presentationOrder.append("activation")
            },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.test_installOverlayWindow(overlay)
        overlay.orderFrontRegardless()
        XCTAssertTrue(overlay.isVisible)

        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where session?.startCount != 1 { await Task.yield() }

        XCTAssertEqual(session?.startCount, 1)
        XCTAssertEqual(presentation.startCount, 1)
        XCTAssertEqual(presentationOrder, ["activation", "presentation"])
        XCTAssertEqual(presentation.placements.count, 1)
        XCTAssertTrue(overlay.isVisible, "selection chrome and toolbar must remain visible while scrolling")
        XCTAssertEqual(activatedApplication?.processIdentifier, NSRunningApplication.current.processIdentifier)
        XCTAssertTrue(coordinator.test_hasScrollCaptureSession)
        presentation.onStep?(.up)
        for _ in 0..<20 where session?.stepDirections != [.up] { await Task.yield() }
        XCTAssertEqual(session?.stepDirections, [.up])
        let preview = NSImage(size: NSSize(width: 30, height: 80))
        update?(.preview(
            preview,
            edge: .top,
            viewport: ScrollCapturePreviewViewport(viewportHeight: 100, outputHeight: 13_174)
        ))
        XCTAssertTrue(presentation.previews.last === preview)
        XCTAssertEqual(presentation.previewEdges, [.top])
        XCTAssertEqual(
            overlay.test_measurementLabelText,
            "80 x 60  px    滚动高度：13,174 px"
        )
        let scrollActivity = ScrollCaptureScrollActivity(direction: .down, distance: 16)
        update?(.viewportScroll(scrollActivity))
        XCTAssertEqual(presentation.scrollActivities, [scrollActivity])
        update?(.warning(.lowConfidence))
        XCTAssertEqual(overlay.scrollCaptureOverlayState, .capturing)
        XCTAssertEqual(presentation.warnings.last, L10n(language: .zhHans).text(.scrollCaptureLowConfidence))
        update?(.warning(nil))
        XCTAssertEqual(overlay.scrollCaptureOverlayState, .capturing)
        XCTAssertEqual(presentation.clearWarningCount, 1)
        update?(.state(.capturing))
        XCTAssertEqual(overlay.scrollCaptureOverlayState, .capturing)
        XCTAssertEqual(presentation.clearWarningCount, 1)
        update?(.state(.paused(.resourceLimit)))
        XCTAssertTrue(coordinator.test_hasScrollCaptureSession)
        XCTAssertEqual(session?.cancelCount, 0)
        XCTAssertEqual(presentation.warnings.last, L10n(language: .zhHans).text(.scrollCaptureResourceLimit))
        update?(.state(.paused(.captureFailure)))
        XCTAssertEqual(overlay.scrollCaptureOverlayState, .paused(message: L10n(language: .zhHans).text(.scrollCaptureFailure)))
        XCTAssertEqual(presentation.warnings.last, L10n(language: .zhHans).text(.scrollCaptureFailure))
    }

    @MainActor
    func testCaptureCoordinatorRoutesExternalTerminalCommandToActiveScrollLifecycle() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        var update: (@MainActor (ScrollCapturePresentationUpdate) -> Void)?
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, callback in
                update = callback
                return session
            },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { _, _ in XCTFail("cancel must not hand off") },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()

        update?(.terminalCommand(.cancel))
        update?(.terminalCommand(.cancel))
        overlay.onScrollCaptureFinishRequested?()

        XCTAssertEqual(session.cancelCount, 1)
        XCTAssertEqual(session.finishCount, 0)
        XCTAssertEqual(presentation.stopCount, 1)
        XCTAssertEqual(overlay.scrollCaptureOverlayState, .inactive)
    }

    @MainActor
    func testCaptureCoordinatorFinishStopsAndHandsRawImageWithFrozenSeedExactlyOnce() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in
            XCTFail("scroll capture must not use ordinary completion")
        }
        let session = FakeScrollCaptureSession(seed: seed)
        session.finishedImage = NSImage(size: NSSize(width: 31, height: 240))
        let presentation = FakeScrollCapturePresentation()
        var handoffs: [(NSImage, ScrollCaptureSeed)] = []
        var endCount = 0
        var coordinator: CaptureCoordinator!
        coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: {
                XCTAssertTrue(coordinator.test_isScrollCapturePhaseIdle)
                XCTAssertTrue(coordinator.test_canStartCapture)
                handoffs.append(($0, $1))
            },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.captureSessionDidEnd = {
            XCTAssertTrue(coordinator.test_isScrollCapturePhaseIdle)
            XCTAssertTrue(coordinator.test_canStartCapture)
            endCount += 1
        }
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where session.startCount != 1 { await Task.yield() }

        presentation.onFinish?()
        presentation.onFinish?()
        for _ in 0..<20 where handoffs.isEmpty { await Task.yield() }

        XCTAssertEqual(session.finishCount, 1)
        XCTAssertEqual(presentation.stopCount, 1)
        XCTAssertEqual(handoffs.count, 1)
        XCTAssertEqual(endCount, 1)
        let handoff = try XCTUnwrap(handoffs.first)
        XCTAssertTrue(handoff.0 === session.finishedImage)
        XCTAssertEqual(handoff.1.annotations.map(\.id), seed.annotations.map(\.id))
        XCTAssertEqual(handoff.1.eraserMasks.count, seed.eraserMasks.count)
        XCTAssertFalse(coordinator.test_hasScrollCaptureSession)
        XCTAssertNil(coordinator.test_overlayWindow)
    }

    @MainActor
    func testCaptureCoordinatorResourceLimitCanFinishAcceptedImageWithoutAutoCancel() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let acceptedImage = solidImage(size: NSSize(width: 80, height: 500), color: .purple)
        let stitcher = ResourceLimitCoordinatorStitcher(acceptedImage: acceptedImage)
        let presentation = FakeScrollCapturePresentation()
        var session: ScrollCaptureSession?
        var handedOff: NSImage?
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { capturedSeed, callback in
                let value = ScrollCaptureSession(
                    seed: capturedSeed,
                    capturer: ResourceLimitCoordinatorCapturer(image: acceptedImage),
                    stitcher: stitcher,
                    clock: ResourceLimitCoordinatorClock(),
                    activityMonitor: ResourceLimitCoordinatorMonitor(),
                    presentation: callback
                )
                session = value
                return value
            },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { image, _ in handedOff = image },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.test_installOverlayWindow(SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in })
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where session?.state != .capturing { await Task.yield() }
        XCTAssertTrue(presentation.previews.last === acceptedImage)

        session?.recordScrollActivity()
        await session?.test_runSamplingTick()
        XCTAssertEqual(session?.state, .paused(.resourceLimit))
        XCTAssertTrue(presentation.previews.last === acceptedImage)

        presentation.onFinish?()
        for _ in 0..<20 where handedOff == nil { await Task.yield() }

        XCTAssertTrue(handedOff === acceptedImage)
        XCTAssertEqual(presentation.stopCount, 1)
    }

    @MainActor
    func testCaptureCoordinatorQueuesFinishRequestedWhileSessionIsStarting() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let session = FakeScrollCaptureSession(seed: seed)
        session.suspendsStart = true
        let presentation = FakeScrollCapturePresentation()
        var handoffCount = 0
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { _, _ in handoffCount += 1 },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<10 where session.startContinuation == nil { await Task.yield() }

        presentation.onFinish?()
        overlay.onScrollCaptureFinishRequested?()
        presentation.onCancel?()
        overlay.onScrollCaptureCancelRequested?()
        XCTAssertEqual(session.finishCount, 0)
        XCTAssertEqual(session.cancelCount, 0)
        session.startContinuation?.resume()
        for _ in 0..<10 where handoffCount == 0 { await Task.yield() }

        XCTAssertEqual(session.finishCount, 1)
        XCTAssertEqual(handoffCount, 1)
        XCTAssertEqual(presentation.stopCount, 1)
    }

    @MainActor
    func testCaptureCoordinatorFinishPendingRejectsEscapeWithoutLeavingPassiveMode() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let detector = FakeScrollCaptureTargetDetector(results: [], suspendsRequests: true)
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        var handoffCount = 0
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { _, _ in handoffCount += 1 },
            frontmostApplicationResolver: { .current },
            applicationActivator: { _ in },
            scrollCaptureTargetDetector: detector
        )
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where detector.pendingRequestCount == 0 { await Task.yield() }

        overlay.onScrollCaptureFinishRequested?()
        overlay.test_keyDown(keyCode: 53)

        XCTAssertEqual(overlay.scrollCaptureOverlayState, .capturing)
        XCTAssertTrue(overlay.ignoresMouseEvents)
        XCTAssertEqual(session.cancelCount, 0)

        detector.resumeRequest(at: 0, returning: nil)
        for _ in 0..<40 where handoffCount == 0 { await Task.yield() }

        XCTAssertEqual(handoffCount, 1)
        XCTAssertEqual(overlay.scrollCaptureOverlayState, .inactive)
        XCTAssertFalse(overlay.ignoresMouseEvents)
    }

    @MainActor
    func testCaptureCoordinatorFinishingRejectsEscapeWithoutLeavingPassiveMode() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let session = FakeScrollCaptureSession(seed: seed)
        session.suspendsFinish = true
        let presentation = FakeScrollCapturePresentation()
        var handoffCount = 0
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { _, _ in handoffCount += 1 },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where session.startCount == 0 { await Task.yield() }

        presentation.onFinish?()
        for _ in 0..<20 where session.finishContinuation == nil { await Task.yield() }
        overlay.test_keyDown(keyCode: 53)

        XCTAssertEqual(overlay.scrollCaptureOverlayState, .capturing)
        XCTAssertTrue(overlay.ignoresMouseEvents)
        XCTAssertEqual(session.cancelCount, 0)

        session.finishContinuation?.resume(returning: session.finishedImage)
        for _ in 0..<20 where handoffCount == 0 { await Task.yield() }

        XCTAssertEqual(handoffCount, 1)
        XCTAssertEqual(overlay.scrollCaptureOverlayState, .inactive)
        XCTAssertFalse(overlay.ignoresMouseEvents)
    }

    @MainActor
    func testCaptureCoordinatorEscapeCancelsStartingDetectionAndRestoresInteractiveBlueOverlay() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let detector = FakeScrollCaptureTargetDetector(results: [], suspendsRequests: true)
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in
                XCTFail("cancelled detection must not create a session")
                return FakeScrollCaptureSession(seed: seed)
            },
            scrollCapturePresentationFactory: { _ in
                XCTFail("cancelled detection must not create presentation")
                return FakeScrollCapturePresentation()
            },
            frontmostApplicationResolver: { .current },
            applicationActivator: { _ in },
            scrollCaptureTargetDetector: detector
        )
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where detector.pendingRequestCount == 0 { await Task.yield() }

        overlay.test_keyDown(keyCode: 53)

        XCTAssertEqual(overlay.scrollCaptureOverlayState, .inactive)
        XCTAssertFalse(overlay.ignoresMouseEvents)
        XCTAssertEqual(overlay.test_lockedSelectionRect, seed.snapshotRect)
        XCTAssertTrue(overlay.test_selectionBorderColor.isEqual(overlay.test_defaultSelectionColor))
        detector.resumeRequest(at: 0, returning: nil)
        await Task.yield()
    }

    @MainActor
    func testCaptureCoordinatorEscapeCancelsActiveResolvedCaptureAndRestoresOriginalSelection() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        let resolvedLocalRect = NSRect(x: 20, y: 24, width: 48, height: 28)
        let detector = FakeScrollCaptureTargetDetector(results: [overlay.convertToScreen(resolvedLocalRect)])
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { _ in presentation },
            frontmostApplicationResolver: { .current },
            applicationActivator: { _ in },
            scrollCaptureTargetDetector: detector
        )
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where session.startCount == 0 { await Task.yield() }
        XCTAssertEqual(overlay.test_lockedSelectionRect, resolvedLocalRect)
        XCTAssertTrue(overlay.test_selectionBorderColor.isEqual(NSColor.systemGreen))

        overlay.test_keyDown(keyCode: 53)

        XCTAssertEqual(session.cancelCount, 1)
        XCTAssertEqual(presentation.stopCount, 1)
        XCTAssertEqual(overlay.scrollCaptureOverlayState, .inactive)
        XCTAssertFalse(overlay.ignoresMouseEvents)
        XCTAssertEqual(overlay.test_lockedSelectionRect, seed.snapshotRect)
        XCTAssertTrue(overlay.test_selectionBorderColor.isEqual(overlay.test_defaultSelectionColor))
    }

    @MainActor
    func testCaptureCoordinatorStartFailureAfterPendingFinishRecoversOverlay() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let session = FakeScrollCaptureSession(seed: seed)
        session.suspendsStart = true
        let presentation = FakeScrollCapturePresentation()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { _, _ in XCTFail("failed start must not hand off") },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<100 where session.startContinuation == nil { await Task.yield() }
        XCTAssertNotNil(session.startContinuation)
        presentation.onFinish?()

        session.startContinuation?.resume(throwing: FakeScrollCaptureSession.Failure.start)
        for _ in 0..<100 where coordinator.test_hasScrollCaptureSession { await Task.yield() }

        XCTAssertFalse(coordinator.test_hasScrollCaptureSession)
        XCTAssertEqual(session.finishCount, 0)
        XCTAssertEqual(session.cancelCount, 1)
        XCTAssertEqual(presentation.stopCount, 1)
        XCTAssertTrue(coordinator.test_overlayWindow === overlay)
        XCTAssertEqual(overlay.scrollCaptureOverlayState, .inactive)
    }

    @MainActor
    func testCaptureCoordinatorFinishingIgnoresFurtherFinishAndCancelAcrossEntrypoints() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let firstSession = FakeScrollCaptureSession(seed: seed)
        firstSession.suspendsFinish = true
        let secondSession = FakeScrollCaptureSession(seed: seed)
        let firstPresentation = FakeScrollCapturePresentation()
        let secondPresentation = FakeScrollCapturePresentation()
        var sessionIndex = 0
        var presentationIndex = 0
        var handoffCount = 0
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in
                defer { sessionIndex += 1 }
                return sessionIndex == 0 ? firstSession : secondSession
            },
            scrollCapturePresentationFactory: { context in
                let value = presentationIndex == 0 ? firstPresentation : secondPresentation
                presentationIndex += 1
                value.onFinish = context.onFinish
                value.onCancel = context.onCancel
                return value
            },
            longImageHandoff: { _, _ in handoffCount += 1 },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        let firstOverlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(firstOverlay)
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()

        firstOverlay.test_keyDown(keyCode: 36)
        for _ in 0..<10 where firstSession.finishContinuation == nil { await Task.yield() }
        firstPresentation.onFinish?()
        firstOverlay.onScrollCaptureFinishRequested?()
        firstOverlay.onScrollCaptureCancelRequested?()

        XCTAssertEqual(firstSession.finishCount, 1)
        XCTAssertEqual(firstSession.cancelCount, 0)
        firstSession.finishContinuation?.resume(returning: firstSession.finishedImage)
        for _ in 0..<10 where handoffCount == 0 { await Task.yield() }
        XCTAssertEqual(handoffCount, 1)

        let secondOverlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(secondOverlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where secondSession.startCount != 1 { await Task.yield() }
        XCTAssertEqual(secondSession.startCount, 1)
        XCTAssertEqual(secondSession.finishCount, 0)
    }

    @MainActor
    func testCaptureCoordinatorCancelFirstMakesLaterFinishInert() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { _, _ in XCTFail("cancelled lifecycle must not hand off") },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()

        presentation.onCancel?()
        presentation.onFinish?()
        overlay.onScrollCaptureFinishRequested?()

        XCTAssertEqual(session.cancelCount, 1)
        XCTAssertEqual(session.finishCount, 0)
        XCTAssertEqual(presentation.stopCount, 1)
    }

    @MainActor
    func testCaptureCoordinatorFinishedOverlayIsDismissedAndReleasedWithoutRetirement() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { _, _ in },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        var overlay: SelectionOverlayWindow? = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        weak var weakOverlay = overlay
        coordinator.test_installOverlayWindow(try XCTUnwrap(overlay))
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<20 where presentation.startCount != 1 { await Task.yield() }

        presentation.onFinish?()
        for _ in 0..<20 where coordinator.test_overlayWindow != nil { await Task.yield() }
        overlay = nil
        await Task.yield()

        XCTAssertNil(weakOverlay)
        XCTAssertEqual(coordinator.test_retiredOverlayCount, 0)
    }

    @MainActor
    func testCaptureCoordinatorFinishShowsRetainedEditorAndEndsOnlyWhenEditorCloses() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        let editor = FakeLongImageEditor()
        var capturedImage: NSImage?
        var capturedSeed: ScrollCaptureSeed?
        var capturedActions: LongImageEditorActions?
        var copiedImages: [NSImage] = []
        var savedImages: [NSImage] = []
        var pinnedWindow: FakePinnedWindow?
        var endCount = 0
        var coordinator: CaptureCoordinator!
        editor.onShow = {
            XCTAssertTrue(coordinator.test_isScrollCapturePhaseIdle)
            XCTAssertFalse(coordinator.test_canStartCapture)
        }
        coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            pinnedWindowFactory: { image, screenRect in
                let window = FakePinnedWindow(image: image, screenRect: screenRect)
                pinnedWindow = window
                return window
            },
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageEditorFactory: { image, seed, actions in
                XCTAssertTrue(coordinator.test_isScrollCapturePhaseIdle)
                XCTAssertFalse(coordinator.test_canStartCapture)
                capturedImage = image
                capturedSeed = seed
                capturedActions = actions
                return editor
            },
            longImageCopyHandler: { copiedImages.append($0); return true },
            longImageSaveHandler: { savedImages.append($0); return true },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.captureSessionDidEnd = {
            endCount += 1
            XCTAssertTrue(coordinator.test_isScrollCapturePhaseIdle)
            XCTAssertTrue(coordinator.test_canStartCapture)
        }
        coordinator.test_installOverlayWindow(SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in })
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()
        presentation.onFinish?()
        for _ in 0..<100 where coordinator.test_hasScrollCaptureSession { await Task.yield() }

        XCTAssertTrue(capturedImage === session.finishedImage)
        XCTAssertEqual(capturedSeed?.annotations.map(\.id), seed.annotations.map(\.id))
        XCTAssertEqual(editor.showCount, 1)
        XCTAssertTrue(coordinator.test_lastCapture === session.finishedImage)
        XCTAssertEqual(endCount, 0)
        XCTAssertTrue(coordinator.test_hasLongImageEditor)
        XCTAssertFalse(coordinator.test_canStartCapture)

        let rendered = CaptureAnnotationRenderer.renderLongImage(
            image: solidImage(size: NSSize(width: 80, height: 500), color: .white),
            annotations: seed.annotations,
            eraserMasks: seed.eraserMasks
        )
        XCTAssertEqual(capturedActions?.copy(rendered), true)
        XCTAssertEqual(capturedActions?.save(rendered), true)
        XCTAssertEqual(capturedActions?.pin(rendered), true)
        XCTAssertTrue(copiedImages.first === rendered)
        XCTAssertTrue(savedImages.first === rendered)
        XCTAssertTrue(pinnedWindow?.image === rendered)
        XCTAssertEqual(pinnedWindow?.showCount, 1)

        editor.simulateClose()
        XCTAssertEqual(endCount, 1)
        XCTAssertFalse(coordinator.test_hasLongImageEditor)
        XCTAssertTrue(coordinator.test_canStartCapture)
    }

    @MainActor
    func testDefaultLongEditorStaysOnCaptureDisplay() async throws {
        var seed = scrollCaptureSeedForCoordinatorTests()
        seed = ScrollCaptureSeed(
            screenRect: NSRect(x: 1_200, y: 120, width: 80, height: 60),
            snapshotRect: seed.snapshotRect,
            frozenImage: seed.frozenImage,
            annotations: seed.annotations,
            eraserMasks: seed.eraserMasks
        )
        let secondary = NSRect(x: 1_000, y: 0, width: 900, height: 700)
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            screenVisibleFrameResolver: { rect in
                XCTAssertTrue(rect.contains(NSPoint(x: seed.screenRect.midX, y: seed.screenRect.midY)))
                return secondary
            },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.test_installOverlayWindow(SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in })
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()
        presentation.onFinish?()
        for _ in 0..<100 where coordinator.test_hasScrollCaptureSession { await Task.yield() }

        let frame = try XCTUnwrap(coordinator.test_longImageEditorWindowFrame)
        XCTAssertTrue(secondary.contains(NSPoint(x: frame.midX, y: frame.midY)))
        XCTAssertEqual(frame.midX, secondary.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, secondary.midY, accuracy: 0.001)
    }

    @MainActor
    func testPinnedLongImageResolvesAndCentersOnRequestedDisplayWithoutMutatingSource() throws {
        let main = NSRect(x: 0, y: 0, width: 900, height: 700)
        let secondary = NSRect(x: 1_000, y: 0, width: 800, height: 600)
        let image = solidImage(size: NSSize(width: 500, height: 2_000), color: .white)
        let requested = NSRect(x: 1_100, y: 100, width: 500, height: 2_000)
        let controller = PinnedImageWindowController(
            image: image,
            screenRect: requested,
            screenResolver: { rect in rect.origin.x >= 1_000 ? secondary : main }
        )

        XCTAssertTrue(controller.image === image)
        XCTAssertEqual(controller.screenRect, requested)
        let frame = try XCTUnwrap(controller.window?.frame)
        XCTAssertTrue(secondary.contains(frame))
        XCTAssertEqual(frame.midX, secondary.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, secondary.midY, accuracy: 0.001)

        let mainController = PinnedImageWindowController(
            image: image,
            screenRect: NSRect(x: 100, y: 100, width: 500, height: 2_000),
            screenResolver: { rect in rect.origin.x >= 1_000 ? secondary : main }
        )
        XCTAssertTrue(main.contains(try XCTUnwrap(mainController.window?.frame)))
    }

    @MainActor
    func testCaptureCoordinatorEditorFactoryFailureOffersExactImageFallbackSaveAndEnds() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        var fallbackImage: NSImage?
        var savedImages: [NSImage] = []
        var fallbackChoices: [LongImageFallbackChoice] = [.save, .save]
        var endCount = 0
        var coordinator: CaptureCoordinator!
        coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageEditorFactory: { _, _, _ in throw FakeScrollCaptureSession.Failure.finish },
            longImageFallbackPresenter: { image in
                XCTAssertTrue(coordinator.test_isScrollCapturePhaseIdle)
                XCTAssertFalse(coordinator.test_canStartCapture)
                fallbackImage = image
                return fallbackChoices.removeFirst()
            },
            longImageSaveHandler: {
                savedImages.append($0)
                return savedImages.count == 2
            },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.captureSessionDidEnd = {
            XCTAssertTrue(coordinator.test_canStartCapture)
            endCount += 1
        }
        coordinator.test_installOverlayWindow(SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in })
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()
        presentation.onFinish?()
        for _ in 0..<100 where coordinator.test_hasScrollCaptureSession { await Task.yield() }

        XCTAssertTrue(fallbackImage === session.finishedImage)
        XCTAssertEqual(savedImages.count, 2)
        XCTAssertTrue(savedImages[0] === session.finishedImage)
        XCTAssertTrue(savedImages[1] === session.finishedImage)
        XCTAssertTrue(fallbackChoices.isEmpty)
        XCTAssertTrue(coordinator.test_lastCapture === session.finishedImage)
        XCTAssertEqual(endCount, 1)
        XCTAssertFalse(coordinator.test_hasLongImageEditor)
    }

    @MainActor
    func testCaptureCoordinatorEditorFactoryFailureFallbackCancelDoesNotSave() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        var saveCount = 0
        var fallbackChoices: [LongImageFallbackChoice] = [.save, .cancel]
        var endCount = 0
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageEditorFactory: { _, _, _ in nil },
            longImageFallbackPresenter: { _ in fallbackChoices.removeFirst() },
            longImageSaveHandler: { _ in saveCount += 1; return false },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.captureSessionDidEnd = { endCount += 1 }
        coordinator.test_installOverlayWindow(SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in })
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()
        presentation.onFinish?()
        for _ in 0..<20 where coordinator.test_hasScrollCaptureSession { await Task.yield() }

        XCTAssertEqual(saveCount, 1)
        XCTAssertTrue(fallbackChoices.isEmpty)
        XCTAssertEqual(endCount, 1)
        XCTAssertTrue(coordinator.test_lastCapture === session.finishedImage)
    }

    @MainActor
    func testCaptureCoordinatorCancelRestoresToolThenUsesOrdinaryTwoStageEscape() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        var ordinaryCompletionCount = 0
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in ordinaryCompletionCount += 1 }
        overlay.test_setLockedSelectionRect(seed.snapshotRect)
        overlay.test_activateShapeTool(.rectangle)
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { _, _ in },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()

        presentation.onCancel?()

        XCTAssertEqual(session.cancelCount, 1)
        XCTAssertEqual(presentation.stopCount, 1)
        XCTAssertTrue(coordinator.test_overlayWindow === overlay)
        XCTAssertEqual(overlay.scrollCaptureOverlayState, .inactive)
        XCTAssertFalse(overlay.ignoresMouseEvents)
        XCTAssertTrue(overlay.test_toolbarButtonIsSelected(.rectangle))
        XCTAssertEqual(ordinaryCompletionCount, 0)
        overlay.test_keyDown(keyCode: 53)
        XCTAssertEqual(ordinaryCompletionCount, 0)
        XCTAssertFalse(overlay.test_toolbarButtonIsSelected(.rectangle))
        overlay.test_keyDown(keyCode: 53)
        await Task.yield()
        XCTAssertEqual(ordinaryCompletionCount, 1)
    }

    @MainActor
    func testCaptureCoordinatorCancelWithoutToolLetsNextEscapeCloseOrdinaryOverlay() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        var ordinaryCompletionCount = 0
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in ordinaryCompletionCount += 1 }
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { _, _ in },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()

        presentation.onCancel?()
        XCTAssertEqual(ordinaryCompletionCount, 0)
        overlay.test_keyDown(keyCode: 53)
        await Task.yield()

        XCTAssertEqual(ordinaryCompletionCount, 1)
    }

    @MainActor
    func testCaptureCoordinatorStartErrorStopsPresentationAndRecoversOverlay() async throws {
        for failure in [FakeScrollCaptureSession.Failure.start] {
            let seed = scrollCaptureSeedForCoordinatorTests()
            let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
            let session = FakeScrollCaptureSession(seed: seed)
            if failure == .start { session.startError = failure } else { session.finishError = failure }
            let presentation = FakeScrollCapturePresentation()
            let detector = FakeScrollCaptureTargetDetector(results: [
                overlay.convertToScreen(NSRect(x: 20, y: 24, width: 48, height: 28))
            ])
            let coordinator = CaptureCoordinator(
                permissionCoordinator: PermissionCoordinator(),
                screenCaptureService: ScreenCaptureService(),
                scrollCaptureSessionFactory: { _, _ in session },
                scrollCapturePresentationFactory: { context in
                    presentation.onFinish = context.onFinish
                    presentation.onCancel = context.onCancel
                    return presentation
                },
                longImageHandoff: { _, _ in XCTFail("error must not hand off") },
                scrollCaptureTargetDetector: detector
            )
            coordinator.test_installOverlayWindow(overlay)
            coordinator.test_requestScrollCapture(seed: seed)
            for _ in 0..<20 where presentation.stopCount != 1 { await Task.yield() }
            if failure == .finish {
                presentation.onFinish?()
                await Task.yield()
                await Task.yield()
            }

            XCTAssertEqual(presentation.stopCount, 1)
            XCTAssertFalse(coordinator.test_hasScrollCaptureSession)
            XCTAssertTrue(coordinator.test_overlayWindow === overlay)
            XCTAssertEqual(overlay.scrollCaptureOverlayState, .inactive)
            XCTAssertFalse(overlay.ignoresMouseEvents)
            XCTAssertEqual(overlay.test_lockedSelectionRect, seed.snapshotRect)
            XCTAssertTrue(overlay.test_selectionBorderColor.isEqual(overlay.test_defaultSelectionColor))
        }
    }

    @MainActor
    func testCaptureCoordinatorCompositionFailureKeepsPreviewAndRetriesSameSession() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        let session = FakeScrollCaptureSession(seed: seed)
        session.finishErrors = [FakeScrollCaptureSession.Failure.finish]
        let presentation = FakeScrollCapturePresentation()
        var handoffCount = 0
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in session },
            scrollCapturePresentationFactory: { context in
                presentation.onFinish = context.onFinish
                presentation.onCancel = context.onCancel
                return presentation
            },
            longImageHandoff: { image, _ in
                XCTAssertTrue(image === session.finishedImage)
                handoffCount += 1
            },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        coordinator.test_installOverlayWindow(overlay)
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()

        overlay.test_keyDown(keyCode: 36)
        for _ in 0..<20 where session.finishCount < 1 { await Task.yield() }
        XCTAssertTrue(coordinator.test_hasScrollCaptureSession)
        XCTAssertTrue(coordinator.test_overlayWindow === overlay)
        XCTAssertEqual(presentation.stopCount, 0)
        XCTAssertEqual(presentation.resetTerminalCount, 1)

        overlay.test_keyDown(keyCode: 36)
        for _ in 0..<20 where handoffCount == 0 { await Task.yield() }
        XCTAssertEqual(session.finishCount, 2)
        XCTAssertEqual(handoffCount, 1)
        XCTAssertEqual(presentation.stopCount, 1)
    }

    @MainActor
    func testCaptureCoordinatorStaleStartCannotClearNewScrollLifecycle() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let oldSession = FakeScrollCaptureSession(seed: seed)
        oldSession.suspendsStart = true
        let newSession = FakeScrollCaptureSession(seed: seed)
        let oldPresentation = FakeScrollCapturePresentation()
        let newPresentation = FakeScrollCapturePresentation()
        var sessionIndex = 0
        var presentationIndex = 0
        let coordinator = CaptureCoordinator(
            permissionCoordinator: PermissionCoordinator(),
            screenCaptureService: ScreenCaptureService(),
            scrollCaptureSessionFactory: { _, _ in
                defer { sessionIndex += 1 }
                return sessionIndex == 0 ? oldSession : newSession
            },
            scrollCapturePresentationFactory: { context in
                let value = presentationIndex == 0 ? oldPresentation : newPresentation
                presentationIndex += 1
                value.onFinish = context.onFinish
                value.onCancel = context.onCancel
                return value
            },
            longImageHandoff: { _, _ in XCTFail("stale start must not hand off") },
            scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
        )
        let firstOverlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(firstOverlay)
        coordinator.test_requestScrollCapture(seed: seed)
        for _ in 0..<10 where oldSession.startContinuation == nil { await Task.yield() }
        coordinator.test_cancelScrollCapture()

        let secondOverlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
        coordinator.test_installOverlayWindow(secondOverlay)
        coordinator.test_requestScrollCapture(seed: seed)
        await Task.yield()
        oldSession.startContinuation?.resume()
        await Task.yield()

        XCTAssertTrue(coordinator.test_hasScrollCaptureSession)
        XCTAssertEqual(newSession.startCount, 1)
        XCTAssertEqual(newPresentation.stopCount, 0)
    }

    @MainActor
    func testCaptureCoordinatorDeinitStopsAndCancelsOwnedScrollLifecycle() async throws {
        let seed = scrollCaptureSeedForCoordinatorTests()
        let session = FakeScrollCaptureSession(seed: seed)
        let presentation = FakeScrollCapturePresentation()
        weak var weakCoordinator: CaptureCoordinator?
        do {
            var coordinator: CaptureCoordinator? = CaptureCoordinator(
                permissionCoordinator: PermissionCoordinator(),
                screenCaptureService: ScreenCaptureService(),
                scrollCaptureSessionFactory: { _, _ in session },
                scrollCapturePresentationFactory: { context in
                    presentation.onFinish = context.onFinish
                    presentation.onCancel = context.onCancel
                    return presentation
                },
                longImageHandoff: { _, _ in },
                scrollCaptureTargetDetector: FakeScrollCaptureTargetDetector()
            )
            weakCoordinator = coordinator
            coordinator?.test_installOverlayWindow(SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in })
            coordinator?.test_requestScrollCapture(seed: seed)
            await Task.yield()
            coordinator = nil
        }
        await Task.yield()

        XCTAssertNil(weakCoordinator)
        XCTAssertEqual(session.cancelCount, 1)
        XCTAssertEqual(presentation.stopCount, 1)
    }

    func testMagnifierRendererSamplesOriginalImageInsteadOfAnnotations() throws {
        let base = solidImage(size: NSSize(width: 80, height: 80), color: .white)
        var coveringAnnotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 20, width: 40, height: 40),
            style: {
                var style = CaptureAnnotationStyle()
                style.fillEnabled = true
                style.fillColor = .green
                style.strokeColor = .green
                style.strokeWidth = 2
                return style
            }()
        )
        coveringAnnotation.style.fillEnabled = true
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 20, y: 20, width: 40, height: 40),
            style: {
                var style = CaptureAnnotationStyle()
                style.strokeColor = .black
                style.strokeWidth = 2
                return style
            }(),
            magnifierShape: .rectangle,
            magnifierZoom: 2
        )

        let rendered = CaptureAnnotationRenderer.render(image: base, annotations: [coveringAnnotation, magnifier])
        let center = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 50, y: 50)))

        XCTAssertEqual(hex(center), "#FFFFFF")
    }

    func testMagnifierRendererConvertsRenderYToCGImageCropY() throws {
        let base = rowBandImage(
            width: 80,
            height: 80,
            colorAtRow: { row in
                if row < 30 {
                    return .blue
                }
                if row >= 50 {
                    return .red
                }
                return .white
            }
        )
        let coveringAnnotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 0, width: 40, height: 40),
            style: {
                var style = CaptureAnnotationStyle()
                style.fillEnabled = true
                style.fillColor = .green
                style.strokeColor = .green
                style.strokeWidth = 2
                return style
            }()
        )
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 20, y: 0, width: 40, height: 40),
            style: {
                var style = CaptureAnnotationStyle()
                style.strokeColor = .black
                style.strokeWidth = 2
                return style
            }(),
            magnifierShape: .rectangle,
            magnifierZoom: 2
        )

        let rendered = CaptureAnnotationRenderer.render(image: base, annotations: [coveringAnnotation, magnifier])
        let center = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 40, y: 20)))

        XCTAssertEqual(hex(center), "#0000FF")
    }

    func testMagnifierRendererClipsSourceAtImageBounds() throws {
        let sourceRed = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let annotationGreen = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        let base = makeTestImage(size: NSSize(width: 80, height: 80)) { point in
            point.x < 6 ? sourceRed : NSColor.white
        }
        let coveringAnnotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 0, y: 0, width: 80, height: 80),
            style: {
                var style = CaptureAnnotationStyle()
                style.fillEnabled = true
                style.fillColor = annotationGreen
                style.strokeColor = annotationGreen
                style.strokeWidth = 2
                return style
            }()
        )
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: -25, y: 20, width: 40, height: 40),
            style: {
                var style = CaptureAnnotationStyle()
                style.strokeColor = .black
                style.strokeWidth = 2
                return style
            }(),
            magnifierShape: .rectangle,
            magnifierZoom: 2
        )

        let rendered = CaptureAnnotationRenderer.render(image: base, annotations: [coveringAnnotation, magnifier])
        let visibleLeftEdgeSource = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 2, y: 40)))
        let visibleInnerSource = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: 8, y: 40)))

        XCTAssertEqual(hex(visibleLeftEdgeSource), "#FF0000")
        XCTAssertEqual(hex(visibleInnerSource), "#FF0000")
    }

    func testMagnifierRendererMovesLeftFramedContentAwayFromLensEdge() throws {
        let sourceRed = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let annotationGreen = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        let base = makeTestImage(size: NSSize(width: 160, height: 80)) { point in
            point.x >= 60 && point.x < 62 ? sourceRed : NSColor.white
        }
        let coveringAnnotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 0, y: 0, width: 160, height: 80),
            style: {
                var style = CaptureAnnotationStyle()
                style.fillEnabled = true
                style.fillColor = annotationGreen
                style.strokeColor = annotationGreen
                style.strokeWidth = 0
                return style
            }()
        )
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 40, y: 20, width: 80, height: 40),
            style: {
                var style = CaptureAnnotationStyle()
                style.strokeWidth = 0
                return style
            }(),
            magnifierShape: .rectangle,
            magnifierZoom: 2
        )

        let rendered = CaptureAnnotationRenderer.render(image: base, annotations: [coveringAnnotation, magnifier])
        let redColumns = try (40..<80).filter { x in
            let pixel = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: x, y: 40)))
            return hex(pixel) == "#FF0000"
        }

        XCTAssertEqual(redColumns.first, 52)
        XCTAssertFalse(redColumns.contains(46))
    }

    func testMagnifierOverlayPreviewSamplesOriginalImageInsteadOfAnnotations() throws {
        let sourceGreen = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        let annotationRed = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let base = solidImage(size: NSSize(width: 120, height: 80), color: sourceGreen)
        let window = SelectionOverlayWindow(backgroundImage: base) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 0, y: 0, width: 120, height: 80))
        var coverStyle = CaptureAnnotationStyle()
        coverStyle.strokeWidth = 0
        coverStyle.fillEnabled = true
        coverStyle.fillColor = annotationRed
        var magnifierStyle = CaptureAnnotationStyle()
        magnifierStyle.strokeWidth = 0
        window.test_setAnnotations([
            CaptureAnnotation(
                kind: .rectangle,
                rect: NSRect(x: 0, y: 0, width: 120, height: 80),
                style: coverStyle
            ),
            CaptureAnnotation(
                kind: .magnifier,
                rect: NSRect(x: 40, y: 20, width: 40, height: 40),
                style: magnifierStyle,
                magnifierShape: .rectangle,
                magnifierZoom: 2
            ),
        ])

        let rendered = try XCTUnwrap(window.test_renderedOverlayImage())
        let probePoint = NSPoint(
            x: 60,
            y: rendered.size.height - 40 - CaptureAnnotationRenderer.magnifierContentYOffset
        )
        let pixel = try XCTUnwrap(rgbaPixel(in: rendered, at: probePoint))

        XCTAssertGreaterThan(pixel.green, 180)
        XCTAssertLessThan(pixel.red, 80)
    }

    func testMagnifierOverlayPreviewMatchesExportRendererAtCenter() throws {
        let imageSize = NSSize(width: 240, height: 160)
        let base = coordinateRedBlueImage(width: Int(imageSize.width), height: Int(imageSize.height))
        let selection = NSRect(x: 24, y: 18, width: 168, height: 108)
        var style = CaptureAnnotationStyle()
        style.strokeWidth = 0
        let localCenter = NSPoint(x: 126, y: 62)
        let lensSize: CGFloat = 48
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(
                x: localCenter.x - lensSize / 2,
                y: localCenter.y - lensSize / 2,
                width: lensSize,
                height: lensSize
            ),
            style: style,
            magnifierShape: .circle,
            magnifierZoom: 2
        )
        let window = fixedCanvasOverlayWindow(backgroundImage: base, canvasSize: imageSize)
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([magnifier])

        let overlayCenter = NSPoint(
            x: selection.minX + localCenter.x,
            y: selection.minY + localCenter.y
        )
        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let exported = CaptureAnnotationRenderer.render(
            image: base,
            annotations: [overlayAnnotation(magnifier, selection: selection)]
        )
        let overlayPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: overlayCenter))
        let exportPixel = try XCTUnwrap(rgbaPixel(in: exported, at: overlayCenter))

        XCTAssertLessThanOrEqual(pixelDistance(overlayPixel, exportPixel), 4)
    }

    func testMagnifierDoesNotMagnifyMosaicOrTextAnnotations() throws {
        let imageSize = NSSize(width: 180, height: 120)
        let base = coordinateRedBlueImage(width: Int(imageSize.width), height: Int(imageSize.height))
        let selection = NSRect(x: 20, y: 16, width: 130, height: 88)
        var coverStyle = CaptureAnnotationStyle()
        coverStyle.fillEnabled = true
        coverStyle.fillColor = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        coverStyle.strokeColor = coverStyle.fillColor
        coverStyle.strokeWidth = 0
        var textStyle = CaptureAnnotationStyle()
        textStyle.strokeColor = .white
        textStyle.fillColor = .white
        textStyle.textSize = 36
        var mosaicStyle = CaptureAnnotationStyle()
        mosaicStyle.strokeWidth = 24
        var magnifierStyle = CaptureAnnotationStyle()
        magnifierStyle.strokeWidth = 0
        let localCenter = NSPoint(x: 72, y: 48)
        let coveringAnnotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 54, y: 30, width: 36, height: 36),
            style: coverStyle
        )
        let text = CaptureAnnotation(
            kind: .text,
            rect: NSRect(x: 50, y: 26, width: 56, height: 44),
            style: textStyle,
            text: "X"
        )
        let mosaicLike = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 46, y: 22, width: 56, height: 52),
            style: mosaicStyle,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )
        let magnifier = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: localCenter.x - 28, y: localCenter.y - 28, width: 56, height: 56),
            style: magnifierStyle,
            magnifierShape: .circle,
            magnifierZoom: 2
        )
        let precedingAnnotations = [coveringAnnotation, text, mosaicLike]
        let window = fixedCanvasOverlayWindow(backgroundImage: base, canvasSize: imageSize)
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations(precedingAnnotations + [magnifier])

        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let annotationComposite = CaptureAnnotationRenderer.render(
            image: base,
            annotations: precedingAnnotations.map { overlayAnnotation($0, selection: selection) }
        )
        let overlayMagnifier = overlayAnnotation(magnifier, selection: selection)
        let expectedOriginalMagnified = CaptureAnnotationRenderer.render(
            image: base,
            annotations: [overlayMagnifier]
        )
        let compositedMagnified = CaptureAnnotationRenderer.render(
            image: annotationComposite,
            annotations: [overlayMagnifier]
        )
        let exported = CaptureAnnotationRenderer.render(
            image: base,
            annotations: precedingAnnotations.map { overlayAnnotation($0, selection: selection) } + [overlayMagnifier]
        )
        let overlayCenter = NSPoint(
            x: selection.minX + localCenter.x,
            y: selection.minY + localCenter.y
        )
        let destinationOffsets = [
            NSPoint(x: 0, y: 0),
            NSPoint(x: 8, y: 0),
            NSPoint(x: 0, y: 8),
            NSPoint(x: -8, y: -8),
        ]

        for offset in destinationOffsets {
            let outputPoint = NSPoint(x: overlayCenter.x + offset.x, y: overlayCenter.y + offset.y)
            let expectedPixel = try XCTUnwrap(rgbaPixel(in: expectedOriginalMagnified, at: outputPoint))
            let compositedPixel = try XCTUnwrap(rgbaPixel(in: compositedMagnified, at: outputPoint))
            let overlayPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: outputPoint))
            let exportPixel = try XCTUnwrap(rgbaPixel(in: exported, at: outputPoint))

            XCTAssertGreaterThan(pixelDistance(compositedPixel, expectedPixel), 40)
            XCTAssertLessThanOrEqual(pixelDistance(overlayPixel, expectedPixel), 4)
            XCTAssertLessThanOrEqual(pixelDistance(exportPixel, expectedPixel), 4)
        }
    }

    func testOverlayWindowDrawsOverlappingMosaicLayersSequentially() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicStroke)
        window.test_mouseDown(at: NSPoint(x: 88, y: 82))
        window.test_mouseUp(at: NSPoint(x: 88, y: 82))
        window.test_toggleShapeTool(.mosaicRectangle)
        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))

        let renderCountBeforeImage = window.test_mosaicCompositeRenderCount
        _ = try XCTUnwrap(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicCompositeRenderCount - renderCountBeforeImage, 1)
    }

    func testOverlayWindowSwitchingFromSelectedMosaicRectangleToDotDoesNotMutateRectangleRedaction() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: NSPoint(x: 60, y: 55))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 125))
        window.test_mouseUp(at: NSPoint(x: 140, y: 125))

        XCTAssertEqual(window.test_selectedAnnotationKind, .mosaicRectangle)
        let originalRectangleRedaction = try XCTUnwrap(window.test_mosaicRedaction(at: 0))

        window.test_toggleShapeTool(.mosaicStroke)
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        XCTAssertEqual(window.test_mosaicRedaction(at: 0), originalRectangleRedaction)
        XCTAssertEqual(window.test_currentShapeKind, .mosaicStroke)
    }

    func testOverlayWindowRenderedOverlappingMosaicRectanglesDoNotRevealOriginalPixels() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: NSPoint(x: 52, y: 48))
        window.test_mouseDragged(to: NSPoint(x: 134, y: 104))
        window.test_mouseUp(at: NSPoint(x: 134, y: 104))

        window.test_mouseDown(at: NSPoint(x: 164, y: 124))
        window.test_mouseDragged(to: NSPoint(x: 84, y: 68))
        window.test_mouseUp(at: NSPoint(x: 84, y: 68))

        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let firstRedaction = try XCTUnwrap(window.test_mosaicRedaction(at: 0))
        let secondStyle = try XCTUnwrap(window.test_annotationStyle(at: 1))
        let secondRedaction = try XCTUnwrap(window.test_mosaicRedaction(at: 1))
        XCTAssertEqual(firstRedaction.type, .gaussianBlur)
        XCTAssertEqual(secondRedaction.type, .gaussianBlur)
        let secondAnnotation = overlayMosaicAnnotation(CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 1)),
            style: secondStyle,
            mosaicRedaction: secondRedaction
        ), selection: selection)
        let secondOnly = CaptureAnnotationRenderer.render(image: image, annotations: [secondAnnotation])

        let overlapPoint = NSPoint(x: 100, y: 84)
        let overlayPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: overlapPoint))
        let originalPixel = try XCTUnwrap(rgbaPixel(in: image, at: overlapPoint))
        let secondOnlyPixel = try XCTUnwrap(rgbaPixel(in: secondOnly, at: overlapPoint))

        XCTAssertTrue(pixelDiffers(overlayPixel, originalPixel))
        XCTAssertTrue(pixelDiffers(overlayPixel, secondOnlyPixel))
    }

    func testOverlayWindowMosaicDraftOverMultipleExistingRectanglesKeepsPreviousRedaction() throws {
        let image = gradientImage(size: NSSize(width: 240, height: 160))
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicRectangle)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: NSPoint(x: 52, y: 48))
        window.test_mouseDragged(to: NSPoint(x: 134, y: 104))
        window.test_mouseUp(at: NSPoint(x: 134, y: 104))

        window.test_mouseDown(at: NSPoint(x: 92, y: 112))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 136))
        window.test_mouseUp(at: NSPoint(x: 170, y: 136))

        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 64, y: 48, width: 80, height: 56),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0)),
            mosaicRedaction: try XCTUnwrap(window.test_mosaicRedaction(at: 0))
        )
        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let draftOnly = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [overlayMosaicAnnotation(draft, selection: selection)]
        )

        let overlapPoint = NSPoint(x: 100, y: 84)
        let previewPoint = NSPoint(
            x: overlapPoint.x - preview.drawRect.minX,
            y: overlapPoint.y - preview.drawRect.minY
        )
        let previewPixel = try XCTUnwrap(rgbaPixel(in: preview.image, at: previewPoint))
        let originalPixel = try XCTUnwrap(rgbaPixel(in: image, at: overlapPoint))
        let draftOnlyPixel = try XCTUnwrap(rgbaPixel(in: draftOnly, at: overlapPoint))

        XCTAssertTrue(pixelDiffers(previewPixel, originalPixel))
        XCTAssertTrue(pixelDiffers(previewPixel, draftOnlyPixel))
    }

    func testOverlayWindowGaussianDotDraftStacksAboveExistingPixelDotMosaic() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let dotPoint = NSPoint(x: 88, y: 82)
        let localDotPoint = NSPoint(x: dotPoint.x - selection.minX, y: dotPoint.y - selection.minY)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: dotPoint)
        window.test_mouseUp(at: dotPoint)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        let style = try XCTUnwrap(window.test_currentStyle)
        let draft = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(origin: localDotPoint, size: .zero),
            style: style,
            mosaicStroke: CaptureMosaicStroke(points: [localDotPoint]),
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let first = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(origin: dotPoint, size: .zero),
            style: style,
            mosaicStroke: CaptureMosaicStroke(points: [dotPoint]),
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )
        let firstComposite = CaptureAnnotationRenderer.render(image: image, annotations: [first])
        let originalCrop = try XCTUnwrap(croppedImage(image, to: preview.drawRect))
        let firstCrop = try XCTUnwrap(croppedImage(firstComposite, to: preview.drawRect))

        XCTAssertTrue(try imageBytesDiffer(preview.image, originalCrop))
        XCTAssertTrue(try imageBytesDiffer(preview.image, firstCrop))
    }

    func testOverlayWindowRectangleDraftStacksAboveExistingDotMosaic() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let selection = NSRect(x: 20, y: 20, width: 180, height: 120)
        let dotPoint = NSPoint(x: 88, y: 82)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_toggleShapeTool(.mosaicStroke)

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: dotPoint)
        window.test_mouseUp(at: dotPoint)

        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        let existingDotStyle = try XCTUnwrap(window.test_annotationStyle(at: 0))
        var style = try XCTUnwrap(window.test_currentStyle)
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 40, y: 35, width: 80, height: 70),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let first = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(origin: dotPoint, size: .zero),
            style: existingDotStyle,
            mosaicStroke: CaptureMosaicStroke(points: [dotPoint]),
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )
        let second = overlayMosaicAnnotation(draft, selection: selection)
        let firstComposite = CaptureAnnotationRenderer.render(image: image, annotations: [first])
        let expected = CaptureAnnotationRenderer.render(image: firstComposite, annotations: [second])
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: preview.drawRect))
        let firstCompositeCrop = try XCTUnwrap(croppedImage(firstComposite, to: preview.drawRect))

        XCTAssertLessThan(try averagePixelDistance(preview.image, expectedCrop), 8)
        XCTAssertGreaterThan(try averagePixelDistance(preview.image, firstCompositeCrop), 12)
    }

    func testOverlayWindowMosaicDraftOverlapDoesNotIncreaseSharpness() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)
        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.pixelMosaic))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        window.test_mouseDown(at: NSPoint(x: 50, y: 44))
        window.test_mouseDragged(to: NSPoint(x: 140, y: 104))
        window.test_mouseUp(at: NSPoint(x: 140, y: 104))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 64, y: 34, width: 90, height: 60),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )
        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let firstCompositeImage = CaptureAnnotationRenderer.render(image: image, annotations: [
            CaptureAnnotation(
                kind: .mosaicRectangle,
                rect: NSRect(x: 50, y: 44, width: 90, height: 60),
                style: style,
                mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
            )
        ])

        let overlap = NSRect(x: 76, y: 58, width: 44, height: 28)
        let firstCrop = try XCTUnwrap(croppedImage(firstCompositeImage, to: overlap))
        let previewCrop = try XCTUnwrap(croppedImage(preview.image, to: NSRect(
            x: overlap.minX - preview.drawRect.minX,
            y: overlap.minY - preview.drawRect.minY,
            width: overlap.width,
            height: overlap.height
        )))

        let firstSharpness = try averageLumaDelta(in: firstCrop, rect: NSRect(origin: .zero, size: firstCrop.size))
        let previewSharpness = try averageLumaDelta(in: previewCrop, rect: NSRect(origin: .zero, size: previewCrop.size))
        XCTAssertLessThanOrEqual(previewSharpness, firstSharpness * 1.08)
    }

    func testOverlayWindowMosaicDraftRedactsExistingMarkerAnnotation() throws {
        let image = checkerboardImage(size: desktopImageSize(), squareSize: 8)
        let selection = NSRect(x: 100, y: 100, width: 220, height: 160)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)
        window.test_setCurrentStrokeWidth(30)
        window.test_mouseDown(at: NSPoint(x: 150, y: 170))
        window.test_mouseDragged(to: NSPoint(x: 260, y: 220))
        window.test_mouseUp(at: NSPoint(x: 260, y: 220))

        let marker = CaptureAnnotation(
            kind: .marker,
            rect: try XCTUnwrap(window.test_annotationRect(at: 0)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0)),
            markerLine: try XCTUnwrap(window.test_markerLine(at: 0))
        )
        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 30, y: 50, width: 160, height: 90),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let expected = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [
                overlayAnnotation(marker, selection: selection),
                overlayAnnotation(draft, selection: selection),
            ]
        )
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: preview.drawRect))

        XCTAssertLessThan(try averagePixelDistance(preview.image, expectedCrop), 8)
    }

    func testOverlayWindowPixelMosaicDraftUsesCompositePixelsForExistingRectangleStroke() throws {
        let image = checkerboardImage(size: desktopImageSize(), squareSize: 8)
        let selection = NSRect(x: 100, y: 100, width: 260, height: 180)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.rectangle)
        window.test_setCurrentStrokeWidth(24)
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 250, y: 230))
        window.test_mouseUp(at: NSPoint(x: 250, y: 230))

        let rectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 0)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0))
        )
        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draft = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 44, y: 44, width: 116, height: 104),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )

        let preview = try XCTUnwrap(window.test_mosaicDraftPreview(for: draft))
        let expected = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [
                overlayAnnotation(rectangle, selection: selection),
                overlayAnnotation(draft, selection: selection),
            ]
        )
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: preview.drawRect))
        let backgroundOnly = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [overlayAnnotation(draft, selection: selection)]
        )
        let backgroundOnlyCrop = try XCTUnwrap(croppedImage(backgroundOnly, to: preview.drawRect))

        XCTAssertLessThan(try averagePixelDistance(preview.image, expectedCrop), 8)
        XCTAssertGreaterThan(try averagePixelDistance(preview.image, backgroundOnlyCrop), 12)
    }

    func testOverlayWindowCommittedMosaicRedactsEarlierMarkerAnnotation() throws {
        let image = checkerboardImage(size: desktopImageSize(), squareSize: 8)
        let selection = NSRect(x: 100, y: 100, width: 220, height: 160)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)
        window.test_setCurrentStrokeWidth(30)
        window.test_mouseDown(at: NSPoint(x: 150, y: 170))
        window.test_mouseDragged(to: NSPoint(x: 260, y: 220))
        window.test_mouseUp(at: NSPoint(x: 260, y: 220))

        let marker = CaptureAnnotation(
            kind: .marker,
            rect: try XCTUnwrap(window.test_annotationRect(at: 0)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0)),
            markerLine: try XCTUnwrap(window.test_markerLine(at: 0))
        )
        window.test_toggleShapeTool(.mosaicRectangle)
        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.pixelMosaic))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)
        window.test_mouseDown(at: NSPoint(x: 130, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 290, y: 240))
        window.test_mouseUp(at: NSPoint(x: 290, y: 240))

        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let mosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 1)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 1)),
            mosaicRedaction: try XCTUnwrap(window.test_mosaicRedaction(at: 1))
        )
        let expected = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [
                overlayAnnotation(marker, selection: selection),
                overlayAnnotation(mosaic, selection: selection),
            ]
        )
        let checkRect = NSRect(x: 140, y: 160, width: 140, height: 70)
        let overlayCrop = try XCTUnwrap(croppedImage(overlayImage, to: checkRect))
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: checkRect))

        XCTAssertLessThan(try averagePixelDistance(overlayCrop, expectedCrop), 8)
    }

    func testOverlayWindowMosaicRectangleCanStartOnExistingRectangleVerticalBorder() throws {
        let image = checkerboardImage(size: desktopImageSize(), squareSize: 8)
        let selection = NSRect(x: 100, y: 100, width: 260, height: 180)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.rectangle)
        window.test_setCurrentStrokeWidth(24)
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 250, y: 230))
        window.test_mouseUp(at: NSPoint(x: 250, y: 230))

        let rectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 0)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 0))
        )
        window.test_toggleShapeTool(.mosaicRectangle)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 150, y: 182)), .crosshair)
        window.test_mouseDown(at: NSPoint(x: 150, y: 182))
        window.test_mouseDragged(to: NSPoint(x: 178, y: 218))
        window.test_mouseUp(at: NSPoint(x: 178, y: 218))

        XCTAssertEqual(window.test_annotationCount, 2)
        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let mosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: try XCTUnwrap(window.test_annotationRect(at: 1)),
            style: try XCTUnwrap(window.test_annotationStyle(at: 1)),
            mosaicRedaction: try XCTUnwrap(window.test_mosaicRedaction(at: 1))
        )
        let expected = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [
                overlayAnnotation(rectangle, selection: selection),
                overlayAnnotation(mosaic, selection: selection),
            ]
        )
        let checkRect = NSRect(x: 156, y: 190, width: 20, height: 20)
        let overlayCrop = try XCTUnwrap(croppedImage(overlayImage, to: checkRect))
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: checkRect))

        XCTAssertLessThan(try averagePixelDistance(overlayCrop, expectedCrop), 18)
    }

    func testOverlayWindowSequentialMosaicCompositesReuseCacheAcrossPrefixes() throws {
        let image = checkerboardImage(size: NSSize(width: 260, height: 180), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))

        var markerStyle = CaptureAnnotationStyle()
        markerStyle.strokeColor = SelectionToolbarState.defaultMarkerColor
        markerStyle.strokeWidth = 24
        let marker = CaptureAnnotation(
            kind: .marker,
            rect: NSRect(x: 42, y: 44, width: 86, height: 40),
            style: markerStyle,
            markerLine: CaptureMarkerLine(start: NSPoint(x: 42, y: 44), end: NSPoint(x: 128, y: 84))
        )
        var mosaicStyle = CaptureAnnotationStyle()
        mosaicStyle.strokeWidth = 30
        let redaction = CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        let firstMosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 32, y: 26, width: 76, height: 50),
            style: mosaicStyle,
            mosaicRedaction: redaction
        )
        let secondMosaic = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 66, y: 54, width: 82, height: 50),
            style: mosaicStyle,
            mosaicRedaction: redaction
        )

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [marker, firstMosaic]))
        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [marker, firstMosaic, secondMosaic]))
        let renderCountAfterTwoPrefixes = window.test_mosaicCompositeRenderCount
        XCTAssertGreaterThan(renderCountAfterTwoPrefixes, 0)

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [marker, firstMosaic]))

        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountAfterTwoPrefixes)
    }

    func testOverlayWindowMosaicCompositeCacheKeyIncludesMagnifierShapeAndZoom() throws {
        let image = coordinateRedBlueImage(width: 240, height: 160)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 160, height: 100))

        var magnifierStyle = CaptureAnnotationStyle()
        magnifierStyle.strokeWidth = 0
        let circleTwoX = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 48, y: 28, width: 56, height: 56),
            style: magnifierStyle,
            magnifierShape: .circle,
            magnifierZoom: 2
        )
        let circleFourX = CaptureAnnotation(
            kind: .magnifier,
            rect: circleTwoX.rect,
            style: magnifierStyle,
            magnifierShape: .circle,
            magnifierZoom: 4
        )
        let rectangleFourX = CaptureAnnotation(
            kind: .magnifier,
            rect: circleTwoX.rect,
            style: magnifierStyle,
            magnifierShape: .rectangle,
            magnifierZoom: 4
        )

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [circleTwoX]))
        let renderCountAfterFirstComposite = window.test_mosaicCompositeRenderCount
        XCTAssertGreaterThan(renderCountAfterFirstComposite, 0)

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [circleTwoX]))
        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountAfterFirstComposite)

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [circleFourX]))
        let renderCountAfterZoomChange = window.test_mosaicCompositeRenderCount
        XCTAssertEqual(renderCountAfterZoomChange, renderCountAfterFirstComposite + 1)

        XCTAssertNotNil(window.test_mosaicPreviewComposite(for: [rectangleFourX]))
        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountAfterZoomChange + 1)
    }

    func testOverlayWindowMosaicOnlyAnnotationsUseSequentialCompositeDraw() {
        let image = checkerboardImage(size: NSSize(width: 260, height: 180), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 200, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        window.test_mouseDown(at: NSPoint(x: 42, y: 46))
        window.test_mouseDragged(to: NSPoint(x: 92, y: 96))
        window.test_mouseUp(at: NSPoint(x: 92, y: 96))
        window.test_mouseDown(at: NSPoint(x: 142, y: 50))
        window.test_mouseDragged(to: NSPoint(x: 192, y: 100))
        window.test_mouseUp(at: NSPoint(x: 192, y: 100))

        XCTAssertEqual(window.test_annotationCount, 2)
        let renderCountBeforeImage = window.test_mosaicCompositeRenderCount
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicCompositeRenderCount - renderCountBeforeImage, 1)
    }

    func testOverlayWindowRepeatedMosaicLayersRenderWithSingleCompositePass() throws {
        let image = checkerboardImage(size: NSSize(width: 320, height: 220), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 260, height: 160))
        window.test_toggleShapeTool(.mosaicStroke)

        let gaussianPoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: gaussianPoint)
        window.test_mouseUp(at: gaussianPoint)

        for point in [
            NSPoint(x: 68, y: 70),
            NSPoint(x: 92, y: 86),
            NSPoint(x: 116, y: 102),
            NSPoint(x: 140, y: 118),
        ] {
            window.test_mouseDown(at: point)
            window.test_mouseUp(at: point)
        }

        window.test_toggleShapeTool(.mosaicRectangle)
        for rect in [
            (start: NSPoint(x: 52, y: 48), end: NSPoint(x: 142, y: 112)),
            (start: NSPoint(x: 154, y: 76), end: NSPoint(x: 240, y: 142)),
        ] {
            window.test_mouseDown(at: rect.start)
            window.test_mouseDragged(to: rect.end)
            window.test_mouseUp(at: rect.end)
        }

        XCTAssertEqual(window.test_annotationCount, 6)
        let renderCountBeforeImage = window.test_mosaicCompositeRenderCount
        let drawCountBeforeImage = window.test_mosaicCompositeDrawCount
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicCompositeRenderCount - renderCountBeforeImage, 1)
        XCTAssertEqual(window.test_mosaicCompositeDrawCount - drawCountBeforeImage, 1)
    }

    func testOverlayWindowWheelZoomReusesCompletedMosaicCompositeForMultipleLayers() throws {
        let image = checkerboardImage(size: NSSize(width: 420, height: 300), squareSize: 4)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 40, y: 40, width: 300, height: 200))
        window.test_toggleShapeTool(.mosaicRectangle)

        let gaussianPoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: gaussianPoint)
        window.test_mouseUp(at: gaussianPoint)

        for (start, end) in [
            (NSPoint(x: 70, y: 70), NSPoint(x: 130, y: 120)),
            (NSPoint(x: 150, y: 90), NSPoint(x: 220, y: 150)),
            (NSPoint(x: 240, y: 110), NSPoint(x: 310, y: 180)),
        ] {
            window.test_mouseDown(at: start)
            window.test_mouseDragged(to: end)
            window.test_mouseUp(at: end)
        }

        XCTAssertEqual(window.test_annotationCount, 3)
        XCTAssertNotNil(window.test_renderedOverlayImage())
        let renderCountAfterPrimingCache = window.test_mosaicCompositeRenderCount

        window.test_scrollWheel(at: NSPoint(x: 190, y: 140), deltaY: 8)
        XCTAssertNotNil(window.test_renderedOverlayImage())

        XCTAssertEqual(window.test_mosaicCompositeRenderCount, renderCountAfterPrimingCache)
    }

    func testOverlayWindowMosaicStrokeIsNotMutatedWhenPreparingNextRectangleMosaic() throws {
        let image = checkerboardImage(size: NSSize(width: 240, height: 160))
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 20, y: 20, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 88, y: 82))
        window.test_mouseUp(at: NSPoint(x: 88, y: 82))

        XCTAssertNil(window.test_selectedAnnotationKind)
        let originalRedaction = try XCTUnwrap(window.test_mosaicRedaction(at: 0))

        let typePoint = try XCTUnwrap(window.test_mosaicRedactionTypePoint(.gaussianBlur))
        window.test_mouseDown(at: typePoint)
        window.test_mouseUp(at: typePoint)

        window.test_toggleShapeTool(.mosaicRectangle)

        XCTAssertEqual(window.test_mosaicRedaction(at: 0), originalRedaction)
        XCTAssertEqual(window.test_currentShapeKind, .mosaicRectangle)
    }

    func testOverlayWindowMosaicDraftPreviewKeepsExistingMosaicAnnotations() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_toggleShapeTool(.mosaicStroke)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 200, y: 160))
        window.test_mouseUp(at: NSPoint(x: 200, y: 160))

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let draftStroke = CaptureMosaicStroke(points: [
            NSPoint(x: 130, y: 90),
            NSPoint(x: 190, y: 92),
        ])
        let draft = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: draftStroke.boundingRect,
            style: style,
            mosaicStroke: draftStroke,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        XCTAssertEqual(window.test_mosaicDraftPreviewAnnotationCount(for: draft), 2)
    }

    func testMosaicStrokePreviewDotsStayVisuallySmall() {
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewDotDiameter(for: 15), 5)
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewDotDiameter(for: 30), 8)
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewDotDiameter(for: 40), 11)
    }

    func testOverlayWindowGaussianMosaicPreviewUsesLocalCompositeTile() {
        let image = NSImage(size: NSSize(width: 240, height: 160))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 240, height: 160).fill()
        NSColor.black.setFill()
        NSRect(x: 120, y: 50, width: 50, height: 24).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 100, y: 40, width: 80, height: 60)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 16
        let annotation = CaptureAnnotation(
            kind: .mosaicRectangle,
            rect: NSRect(x: 20, y: 10, width: 50, height: 24),
            style: style,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        guard let preview = window.test_mosaicPreviewComposite(for: [annotation]) else {
            return XCTFail("Expected mosaic preview composite")
        }

        XCTAssertLessThan(preview.size.width, image.size.width)
        XCTAssertLessThan(preview.size.height, image.size.height)
        XCTAssertLessThan(preview.drawRect.width, image.size.width)
        XCTAssertLessThan(preview.drawRect.height, image.size.height)
        XCTAssertLessThanOrEqual(preview.drawRect.minX, 120)
        XCTAssertLessThanOrEqual(preview.drawRect.minY, 50)
        XCTAssertGreaterThanOrEqual(preview.drawRect.maxX, 170)
        XCTAssertGreaterThanOrEqual(preview.drawRect.maxY, 74)
    }

    func testOverlayWindowMosaicPreviewKeepsOutOfSelectionGeometryVisible() {
        let image = NSImage(size: NSSize(width: 240, height: 160))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 240, height: 160).fill()
        image.unlockFocus()

        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        let selection = NSRect(x: 100, y: 40, width: 80, height: 60)
        window.test_setLockedSelectionRect(selection)

        var style = CaptureAnnotationStyle()
        style.strokeWidth = 30
        let outsideStroke = CaptureMosaicStroke(points: [
            NSPoint(x: -40, y: 30),
            NSPoint(x: -25, y: 30),
        ])
        let annotation = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: outsideStroke.boundingRect,
            style: style,
            mosaicStroke: outsideStroke,
            mosaicRedaction: CaptureMosaicRedaction(type: .gaussianBlur, value: 8)
        )

        guard let preview = window.test_mosaicPreviewComposite(for: [annotation]) else {
            return XCTFail("Expected mosaic preview composite")
        }

        guard let clipBounds = window.test_mosaicPreviewClipBounds(for: [annotation]) else {
            return XCTFail("Expected mosaic preview clip bounds")
        }
        XCTAssertLessThan(preview.size.width, image.size.width)
        XCTAssertLessThan(preview.size.height, image.size.height)
        XCTAssertLessThanOrEqual(preview.drawRect.minX, clipBounds.minX)
        XCTAssertLessThanOrEqual(preview.drawRect.minY, clipBounds.minY)
        XCTAssertGreaterThanOrEqual(preview.drawRect.maxX, clipBounds.maxX)
        XCTAssertGreaterThanOrEqual(preview.drawRect.maxY, clipBounds.maxY)
        XCTAssertLessThan(clipBounds.maxX, selection.minX)
        XCTAssertLessThan(clipBounds.width, preview.drawRect.width)
        XCTAssertLessThan(clipBounds.height, preview.drawRect.height)
        XCTAssertTrue(window.test_mosaicPreviewClipContains(NSPoint(x: 67.5, y: 70), for: [annotation]))
    }

    func testToolSwitchingResetsStrokePatternToFirstOption() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 260, height: 160))

        window.test_setCurrentStrokePattern(.dashLong)
        window.test_toggleShapeTool(.rectangle)
        XCTAssertEqual(window.test_currentStrokePattern, .solid)

        window.test_setCurrentStrokePattern(.dashNarrow)
        window.test_toggleShapeTool(.arrowLine)
        XCTAssertEqual(window.test_currentStrokePattern, .solid)

        window.test_setCurrentStrokePattern(.dashLongShort)
        window.test_toggleShapeTool(.brush)
        XCTAssertEqual(window.test_currentStrokePattern, .solid)

        window.test_setCurrentStrokePattern(.dashLong)
        window.test_toggleShapeTool(.rectangle)
        XCTAssertEqual(window.test_currentStrokePattern, .solid)
    }

    func testOverlayWindowDoesNotMoveBrushGeometryAfterDrawing() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 180, y: 180))
        window.test_mouseUp(at: NSPoint(x: 180, y: 180))

        guard let original = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected brush annotation")
        }
        let originalPath = window.test_brushPath(at: 0)

        window.test_mouseDown(at: NSPoint(x: 160, y: 160))
        window.test_mouseDragged(to: NSPoint(x: 190, y: 190))
        window.test_mouseUp(at: NSPoint(x: 190, y: 190))

        guard let unchanged = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected brush annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(unchanged.origin.x, original.origin.x, accuracy: 0.1)
        XCTAssertEqual(unchanged.origin.y, original.origin.y, accuracy: 0.1)
        XCTAssertEqual(unchanged.width, original.width, accuracy: 0.1)
        XCTAssertEqual(unchanged.height, original.height, accuracy: 0.1)
        XCTAssertEqual(window.test_brushPath(at: 0)?.points, originalPath?.points)
    }

    func testOverlayWindowKeepsMoveCursorWhileDraggingRectangleAndArrow() {
        let rectangleWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        rectangleWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        rectangleWindow.test_activateShapeTool(.rectangle)
        rectangleWindow.test_mouseDown(at: NSPoint(x: 140, y: 140))
        rectangleWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        rectangleWindow.test_mouseUp(at: NSPoint(x: 220, y: 180))
        rectangleWindow.test_mouseDown(at: NSPoint(x: 160, y: 140))
        rectangleWindow.test_mouseDragged(to: NSPoint(x: 170, y: 150))
        XCTAssertEqual(rectangleWindow.test_cursorStyle(at: NSPoint(x: 170, y: 150)), .move)
        rectangleWindow.test_mouseUp(at: NSPoint(x: 170, y: 150))

        let arrowWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        arrowWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        arrowWindow.test_activateShapeTool(.arrowLine)
        arrowWindow.test_mouseDown(at: NSPoint(x: 160, y: 160))
        arrowWindow.test_mouseDragged(to: NSPoint(x: 240, y: 200))
        arrowWindow.test_mouseUp(at: NSPoint(x: 240, y: 200))
        arrowWindow.test_mouseDown(at: NSPoint(x: 190, y: 175))
        arrowWindow.test_mouseDragged(to: NSPoint(x: 200, y: 185))
        XCTAssertEqual(arrowWindow.test_cursorStyle(at: NSPoint(x: 200, y: 185)), .move)
        arrowWindow.test_mouseUp(at: NSPoint(x: 200, y: 185))

    }

    func testOverlayWindowShiftDraggingRectangleCreatesSquareUntilShiftIsReleased() throws {
        let squareWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        squareWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        squareWindow.test_activateShapeTool(.rectangle)
        squareWindow.test_mouseDown(at: NSPoint(x: 140, y: 150))
        squareWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180), modifierFlags: [.shift])
        squareWindow.test_mouseUp(at: NSPoint(x: 220, y: 180), modifierFlags: [.shift])

        let squareRect = try XCTUnwrap(squareWindow.test_annotationRect(at: 0))
        XCTAssertEqual(squareRect.width, 80, accuracy: 0.1)
        XCTAssertEqual(squareRect.height, 80, accuracy: 0.1)

        let freeWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        freeWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        freeWindow.test_activateShapeTool(.rectangle)
        freeWindow.test_mouseDown(at: NSPoint(x: 140, y: 150))
        freeWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180), modifierFlags: [.shift])
        freeWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        freeWindow.test_mouseUp(at: NSPoint(x: 220, y: 180))

        let freeRect = try XCTUnwrap(freeWindow.test_annotationRect(at: 0))
        XCTAssertEqual(freeRect.width, 80, accuracy: 0.1)
        XCTAssertEqual(freeRect.height, 30, accuracy: 0.1)
    }

    func testOverlayWindowShiftDraggingEllipseCreatesCircle() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.ellipse)
        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: 220, y: 180), modifierFlags: [.shift])

        let circleRect = try XCTUnwrap(window.test_annotationRect(at: 0))
        XCTAssertEqual(circleRect.width, 80, accuracy: 0.1)
        XCTAssertEqual(circleRect.height, 80, accuracy: 0.1)
    }

    func testOverlayWindowDoesNotMoveBrushAnnotationAfterDrawing() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 190, y: 190))
        window.test_mouseUp(at: NSPoint(x: 190, y: 190))

        guard let original = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected brush annotation")
        }
        let originalPath = window.test_brushPath(at: 0)

        window.test_activateShapeTool(.rectangle)
        window.test_mouseDown(at: NSPoint(x: 170, y: 170))
        window.test_mouseDragged(to: NSPoint(x: 200, y: 200))
        window.test_mouseUp(at: NSPoint(x: 200, y: 200))

        guard let unchanged = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected brush annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 2)
        XCTAssertEqual(unchanged.origin.x, original.origin.x, accuracy: 0.1)
        XCTAssertEqual(unchanged.origin.y, original.origin.y, accuracy: 0.1)
        XCTAssertEqual(window.test_brushPath(at: 0)?.points, originalPath?.points)
    }

    func testOverlayWindowDragsSelectedArrowControlPoint() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let control = NSPoint(x: 100 + original.control.x, y: 100 + original.control.y)

        window.test_mouseDown(at: control)
        window.test_mouseDragged(to: NSPoint(x: control.x, y: control.y + 50))
        window.test_mouseUp(at: NSPoint(x: control.x, y: control.y + 50))

        guard let updated = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected updated arrow annotation")
        }
        XCTAssertEqual(updated.control.x, original.control.x, accuracy: 0.1)
        XCTAssertEqual(updated.control.y, original.control.y + 50, accuracy: 0.1)
    }

    func testOverlayWindowSelectedArrowShowsControlHandles() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        XCTAssertEqual(window.test_selectedAnnotationKind, .arrowLine)
        XCTAssertTrue(window.test_selectedAnnotationShowsOutline)
    }

    func testOverlayWindowDeleteKeyRemovesSelectedAnnotations() {
        let rectangleWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        rectangleWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        rectangleWindow.test_activateShapeTool(.rectangle)
        rectangleWindow.test_mouseDown(at: NSPoint(x: 140, y: 140))
        rectangleWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        rectangleWindow.test_mouseUp(at: NSPoint(x: 220, y: 180))
        rectangleWindow.test_mouseDown(at: NSPoint(x: 160, y: 140))
        rectangleWindow.test_mouseUp(at: NSPoint(x: 160, y: 140))
        XCTAssertEqual(rectangleWindow.test_selectedAnnotationKind, .rectangle)
        rectangleWindow.test_keyDown(keyCode: 51)
        XCTAssertEqual(rectangleWindow.test_annotationCount, 0)
        XCTAssertNil(rectangleWindow.test_selectedAnnotationKind)

        let ellipseWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        ellipseWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        ellipseWindow.test_activateShapeTool(.ellipse)
        ellipseWindow.test_mouseDown(at: NSPoint(x: 140, y: 140))
        ellipseWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        ellipseWindow.test_mouseUp(at: NSPoint(x: 220, y: 180))
        ellipseWindow.test_mouseDown(at: NSPoint(x: 160, y: 140))
        ellipseWindow.test_mouseUp(at: NSPoint(x: 160, y: 140))
        XCTAssertEqual(ellipseWindow.test_selectedAnnotationKind, .ellipse)
        ellipseWindow.test_keyDown(keyCode: 51)
        XCTAssertEqual(ellipseWindow.test_annotationCount, 0)
        XCTAssertNil(ellipseWindow.test_selectedAnnotationKind)

        let arrowWindow = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        arrowWindow.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        arrowWindow.test_activateShapeTool(.arrowLine)
        arrowWindow.test_mouseDown(at: NSPoint(x: 140, y: 140))
        arrowWindow.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        arrowWindow.test_mouseUp(at: NSPoint(x: 220, y: 180))
        arrowWindow.test_mouseDown(at: NSPoint(x: 180, y: 160))
        arrowWindow.test_mouseUp(at: NSPoint(x: 180, y: 160))
        XCTAssertEqual(arrowWindow.test_selectedAnnotationKind, .arrowLine)
        arrowWindow.test_keyDown(keyCode: 51)
        XCTAssertEqual(arrowWindow.test_annotationCount, 0)
        XCTAssertNil(arrowWindow.test_selectedAnnotationKind)

    }

    func testOverlayWindowDoesNotSelectOrDeleteBrushAnnotationAfterDrawing() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)
        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 190, y: 190))
        window.test_mouseUp(at: NSPoint(x: 190, y: 190))

        window.test_mouseDown(at: NSPoint(x: 170, y: 170))
        window.test_mouseUp(at: NSPoint(x: 170, y: 170))

        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertNil(window.test_selectedAnnotationKind)
        window.test_keyDown(keyCode: 51)
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertNil(window.test_selectedAnnotationKind)
    }

    func testOverlayWindowBrushDoesNotShowEndpointMarkersImmediatelyAfterDrawing() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 180))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 190))
        window.test_mouseUp(at: NSPoint(x: 240, y: 170))

        XCTAssertNil(window.test_selectedAnnotationKind)
        XCTAssertTrue(window.test_selectedBrushEndpointMarkers.isEmpty)
    }

    func testOverlayWindowBrushDoesNotShowEndpointMarkersAfterClickingPath() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 150, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 180))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 190))
        window.test_mouseUp(at: NSPoint(x: 240, y: 170))
        window.test_mouseDown(at: NSPoint(x: 170, y: 180))
        window.test_mouseUp(at: NSPoint(x: 170, y: 180))

        let markers = window.test_selectedBrushEndpointMarkers
        XCTAssertTrue(markers.isEmpty)
        XCTAssertNil(window.test_selectedAnnotationKind)
    }

    func testOverlayWindowShiftDoesNotChangeStraightArrowEndpointDrag() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let end = NSPoint(x: 100 + original.end.x, y: 100 + original.end.y)
        window.test_mouseDown(at: end)
        window.test_mouseDragged(to: NSPoint(x: end.x + 30, y: end.y + 40), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: end.x + 30, y: end.y + 40), modifierFlags: [.shift])

        guard let updated = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected updated arrow annotation")
        }
        XCTAssertEqual(updated.end.x, original.end.x + 30, accuracy: 0.1)
        XCTAssertEqual(updated.end.y, original.end.y + 40, accuracy: 0.1)
        XCTAssertEqual(updated.control.x, (updated.start.x + updated.end.x) / 2, accuracy: 0.1)
        XCTAssertEqual(updated.control.y, (updated.start.y + updated.end.y) / 2, accuracy: 0.1)
    }

    func testOverlayWindowShiftDoesNotChangeCurvedArrowEndpointDrag() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let control = NSPoint(x: 100 + original.control.x, y: 100 + original.control.y)
        window.test_mouseDown(at: control)
        window.test_mouseDragged(to: NSPoint(x: control.x, y: control.y + 50))
        window.test_mouseUp(at: NSPoint(x: control.x, y: control.y + 50))

        guard let curved = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected curved arrow annotation")
        }
        let end = NSPoint(x: 100 + curved.end.x, y: 100 + curved.end.y)
        window.test_mouseDown(at: end)
        window.test_mouseDragged(to: NSPoint(x: end.x + 30, y: end.y + 40), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: end.x + 30, y: end.y + 40), modifierFlags: [.shift])

        guard let updated = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected updated arrow annotation")
        }
        XCTAssertEqual(updated.end.x, curved.end.x + 30, accuracy: 0.1)
        XCTAssertEqual(updated.end.y, curved.end.y + 40, accuracy: 0.1)
        let curvedMidpoint = NSPoint(x: (curved.start.x + curved.end.x) / 2, y: (curved.start.y + curved.end.y) / 2)
        let updatedMidpoint = NSPoint(x: (updated.start.x + updated.end.x) / 2, y: (updated.start.y + updated.end.y) / 2)
        XCTAssertEqual(updated.control.x - updatedMidpoint.x, curved.control.x - curvedMidpoint.x, accuracy: 0.1)
        XCTAssertEqual(updated.control.y - updatedMidpoint.y, curved.control.y - curvedMidpoint.y, accuracy: 0.1)
    }

    func testOverlayWindowArrowEndpointUsesVerticalResizeCursor() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let arrowLine = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }

        let start = NSPoint(x: 100 + arrowLine.start.x, y: 100 + arrowLine.start.y)
        let end = NSPoint(x: 100 + arrowLine.end.x, y: 100 + arrowLine.end.y)
        XCTAssertEqual(window.test_cursorStyle(at: start), .resizeUpDown)
        XCTAssertEqual(window.test_cursorStyle(at: end), .resizeUpDown)
    }

    func testOverlayWindowBrushEndpointDoesNotExposeEditCursorAfterDrawing() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 180, y: 180))
        window.test_mouseUp(at: NSPoint(x: 180, y: 180))

        let path = CaptureBrushPath(points: [NSPoint(x: 140, y: 140), NSPoint(x: 180, y: 180)])
        let startHandle = SelectionToolbarState.brushRotationHandlePoint(for: .start, path: path)!
        let endHandle = SelectionToolbarState.brushRotationHandlePoint(for: .end, path: path)!

        XCTAssertNotEqual(window.test_cursorStyle(at: startHandle), .rotationHandle)
        XCTAssertNotEqual(window.test_cursorStyle(at: endHandle), .rotationHandle)

        window.test_mouseDown(at: NSPoint(x: 160, y: 160))
        window.test_mouseUp(at: NSPoint(x: 160, y: 160))

        XCTAssertEqual(window.test_cursorStyle(at: startHandle), .brush)
        XCTAssertEqual(window.test_cursorStyle(at: endHandle), .brush)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 140, y: 140)), .brush)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 180, y: 180)), .brush)
    }

    func testOverlayWindowDraggingBrushEndpointDoesNotModifyExistingPath() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 180, y: 180))
        window.test_mouseUp(at: NSPoint(x: 180, y: 180))

        guard let original = window.test_brushPath(at: 0) else {
            return XCTFail("Expected brush annotation")
        }
        XCTAssertGreaterThanOrEqual(original.points.count, 2)

        let overlayPath = CaptureBrushPath(points: original.points.map { NSPoint(x: $0.x + 100, y: $0.y + 100) })
        let endHandle = SelectionToolbarState.brushRotationHandlePoint(for: .end, path: overlayPath)!

        window.test_mouseDown(at: NSPoint(x: 160, y: 160))
        window.test_mouseUp(at: NSPoint(x: 160, y: 160))

        window.test_mouseDown(at: endHandle)
        window.test_mouseDragged(to: NSPoint(x: 210, y: 220))
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 210, y: 220)), .brush)
        window.test_mouseUp(at: NSPoint(x: 210, y: 220))

        guard let updated = window.test_brushPath(at: 0) else {
            return XCTFail("Expected brush annotation")
        }
        XCTAssertEqual(updated.points.count, original.points.count)
        XCTAssertEqual(updated.points.first!.x, original.points.first!.x, accuracy: 0.1)
        XCTAssertEqual(updated.points.first!.y, original.points.first!.y, accuracy: 0.1)
        XCTAssertEqual(updated.points.last!.x, original.points.last!.x, accuracy: 0.1)
        XCTAssertEqual(updated.points.last!.y, original.points.last!.y, accuracy: 0.1)
        XCTAssertNil(window.test_selectedAnnotationKind)
        XCTAssertTrue(window.test_selectedBrushEndpointMarkers.isEmpty)
    }

    func testOverlayWindowBrushShiftDragDrawsStraightLineAtAnyAngle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 170, y: 146), modifierFlags: [.shift])
        window.test_mouseDragged(to: NSPoint(x: 210, y: 132), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: 240, y: 151), modifierFlags: [.shift])

        guard let path = window.test_brushPath(at: 0) else {
            return XCTFail("Expected brush annotation")
        }

        XCTAssertEqual(path.points.count, 2)
        XCTAssertEqual(path.points[0].x, 40, accuracy: 0.1)
        XCTAssertEqual(path.points[0].y, 40, accuracy: 0.1)
        XCTAssertEqual(path.points[1].x, 140, accuracy: 0.1)
        XCTAssertEqual(path.points[1].y, 51, accuracy: 0.1)
    }

    func testOverlayWindowBrushToolMovesWholeArrowFromControlPointWithoutReshaping() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let control = NSPoint(x: 100 + original.control.x, y: 100 + original.control.y)

        window.test_activateShapeTool(.brush)
        XCTAssertNil(window.test_selectedAnnotationKind)
        XCTAssertEqual(window.test_cursorStyle(at: control), .move)

        window.test_mouseDown(at: control)
        window.test_mouseDragged(to: NSPoint(x: control.x, y: control.y + 50))
        window.test_mouseUp(at: NSPoint(x: control.x, y: control.y + 50))

        guard let updated = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .arrowLine)
        XCTAssertEqual(updated.start.x, original.start.x, accuracy: 0.1)
        XCTAssertEqual(updated.start.y, original.start.y + 50, accuracy: 0.1)
        XCTAssertEqual(updated.end.x, original.end.x, accuracy: 0.1)
        XCTAssertEqual(updated.end.y, original.end.y + 50, accuracy: 0.1)
        XCTAssertEqual(updated.control.x, original.control.x, accuracy: 0.1)
        XCTAssertEqual(updated.control.y, original.control.y + 50, accuracy: 0.1)
    }

    func testOverlayWindowMovesArrowLineBodyWhileBrushToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let body = NSPoint(x: 100 + original.boundingRect.midX, y: 100 + original.boundingRect.midY)

        window.test_activateShapeTool(.brush)
        window.test_mouseDown(at: body)
        window.test_mouseDragged(to: NSPoint(x: body.x + 24, y: body.y + 18))
        window.test_mouseUp(at: NSPoint(x: body.x + 24, y: body.y + 18))

        guard let moved = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected moved arrow annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .arrowLine)
        XCTAssertEqual(moved.start.x, original.start.x + 24, accuracy: 0.1)
        XCTAssertEqual(moved.start.y, original.start.y + 18, accuracy: 0.1)
        XCTAssertEqual(moved.end.x, original.end.x + 24, accuracy: 0.1)
        XCTAssertEqual(moved.end.y, original.end.y + 18, accuracy: 0.1)
        XCTAssertEqual(moved.control.x, original.control.x + 24, accuracy: 0.1)
        XCTAssertEqual(moved.control.y, original.control.y + 18, accuracy: 0.1)
    }

    func testOverlayWindowArrowControlPointWinsOverSelectionResizeHandle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.arrowLine)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected arrow annotation")
        }
        let initialControl = NSPoint(x: selection.minX + original.control.x, y: selection.minY + original.control.y)
        let edgeControl = NSPoint(x: selection.maxX - 4, y: initialControl.y)
        window.test_mouseDown(at: initialControl)
        window.test_mouseDragged(to: edgeControl)
        window.test_mouseUp(at: edgeControl)

        window.test_mouseDown(at: edgeControl)
        window.test_mouseDragged(to: NSPoint(x: edgeControl.x - 40, y: edgeControl.y + 40))
        window.test_mouseUp(at: NSPoint(x: edgeControl.x - 40, y: edgeControl.y + 40))

        guard let updated = window.test_arrowLine(at: 0) else {
            return XCTFail("Expected updated arrow annotation")
        }
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
        XCTAssertEqual(updated.control.x, edgeControl.x - selection.minX - 40, accuracy: 0.1)
        XCTAssertEqual(updated.control.y, edgeControl.y - selection.minY + 40, accuracy: 0.1)
    }

    func testOverlayWindowUsesBrushCursorAtSelectedBrushBoundsInsteadOfResizeHandle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.brush)

        window.test_mouseDown(at: NSPoint(x: 140, y: 140))
        window.test_mouseDragged(to: NSPoint(x: 180, y: 180))
        window.test_mouseUp(at: NSPoint(x: 180, y: 180))

        guard let original = window.test_annotationRect(at: 0) else {
            return XCTFail("Expected brush annotation")
        }

        let formerBottomRightHandle = NSPoint(x: 100 + original.maxX - 1, y: 100 + original.minY)
        XCTAssertEqual(window.test_cursorStyle(at: formerBottomRightHandle), .brush)
    }

    func testDefaultCaptureFilenameIncludesTimestampToSecond() {
        let date = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(
            CaptureCoordinator.defaultCaptureFilename(date: date, timeZone: TimeZone(secondsFromGMT: 0)!),
            "xxsnap 截图 19700101-000000.png"
        )
    }

    func testOptionsToolbarOnlyShownForRectangleTool() {
        XCTAssertTrue(SelectionToolbarState.shouldShowOptionsToolbar(isPrimaryShapeToolActive: true))
        XCTAssertFalse(SelectionToolbarState.shouldShowOptionsToolbar(isPrimaryShapeToolActive: false))
    }

    func testPrimaryShapeAndArrowToolbarButtonsUseFunctionNamedIcons() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }

        XCTAssertEqual(window.test_symbolName(for: .rectangle), "toolbar-screenshot")
        XCTAssertEqual(window.test_symbolName(for: .arrow), "toolbar-arrow")
    }

    func testMainToolbarIconInsetsMatchRequestedPreviewSizes() {
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "screenshot"), -1)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "arrow"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "masaike2"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "text-tool"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "number-sequence"), 3)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "undo-enabled"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "undo-disabled"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "redo-enabled"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "redo-disabled"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "pencil-tool"), 2)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "straw-ranging"), 0)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "trash"), 3)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "eyedropper"), 2)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "copy-to-clipboard"), 2)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "settings-more"), 2)
        XCTAssertEqual(SelectionToolbarState.toolbarIconInset(for: "scroll-screen2"), 0)
    }

    func testTextToolbarIconsAreBundledAndSizedConsistently() {
        XCTAssertEqual(SelectionToolbarState.textOptionIconSize, 15)
        XCTAssertEqual(SelectionToolbarState.textEmphasisIconSize, 20)
        XCTAssertNotNil(Bundle.main.url(forResource: "bold", withExtension: "svg"))
        XCTAssertNotNil(Bundle.main.url(forResource: "italic", withExtension: "svg"))
        XCTAssertNotNil(Bundle.main.url(forResource: "stroke", withExtension: "svg"))
    }

    func testMosaicRectangleToolbarIconIsBundledWithBlackBackgroundArtwork() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "square_masaike", withExtension: "svg"))
        let svg = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(svg.contains("fill=\"#000000\""))
        XCTAssertFalse(svg.contains("#334CE6"))
    }

    func testEraserClearAllToolbarIconIsBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "trash", withExtension: "svg"))
    }

    func testCurrentColorToolbarIconsUseTemplateTint() {
        XCTAssertFalse(SelectionToolbarState.usesFixedColorToolbarIconResource("pencil-tool"))
        XCTAssertFalse(SelectionToolbarState.usesFixedColorToolbarIconResource("arrow"))
        XCTAssertFalse(SelectionToolbarState.usesFixedColorToolbarIconResource("mosaic-tool"))
        XCTAssertFalse(SelectionToolbarState.usesFixedColorToolbarIconResource("straw-ranging"))
        XCTAssertTrue(SelectionToolbarState.usesFixedColorToolbarIconResource("undo-enabled"))
    }

    func testMosaicToolbarButtonUsesMasaike2Resource() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }

        XCTAssertEqual(window.test_symbolName(for: .mosaic), "toolbar-masaike2")
    }

    func testEraserCursorUsesSameResourceAsToolbarButton() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let toolbarSymbol = try XCTUnwrap(window.test_symbolName(for: .eraser))
        let toolbarResource = toolbarSymbol.replacingOccurrences(of: "toolbar-", with: "")

        XCTAssertEqual(toolbarResource, "eraser-tool")
        XCTAssertEqual(SelectionToolbarState.eraserCursorIconResourceName, toolbarResource)
        XCTAssertNotNil(Bundle.main.url(forResource: toolbarResource, withExtension: "svg"))
    }

    func testMosaicPreviewProgressMapsRangeEndpoints() {
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewProgress(for: 5), 0, accuracy: 0.001)
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewProgress(for: 12), 7.0 / 15.0, accuracy: 0.001)
        XCTAssertEqual(SelectionToolbarState.mosaicPreviewProgress(for: 20), 1, accuracy: 0.001)
    }

    func testMosaicPreviewBackgroundColorDarkensAsValueIncreases() {
        let low = SelectionToolbarState.mosaicPreviewBackgroundColor(for: 5).usingColorSpace(.sRGB)!
        let high = SelectionToolbarState.mosaicPreviewBackgroundColor(for: 20).usingColorSpace(.sRGB)!

        XCTAssertGreaterThan(low.redComponent, high.redComponent)
        XCTAssertGreaterThan(low.greenComponent, high.greenComponent)
        XCTAssertGreaterThan(low.blueComponent, high.blueComponent)
    }

    func testPolylineTooltipUsesArrowLineLabel() {
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "polyline"), "箭头线")
    }

    func testArrowTypeTooltipTitlesOmitTypeSuffix() {
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "startArrowType"), "开始箭头")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "endArrowType"), "结束箭头")
    }

    func testOptionsToolbarLayoutSwitchesShapeAndArrowControls() {
        let optionsRect = NSRect(x: 100, y: 100, width: 640, height: 40)
        let shapeLayout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .shape
        )
        let arrowLayout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .arrowLine
        )

        XCTAssertNotNil(shapeLayout.fillToggle)
        XCTAssertNotNil(shapeLayout.rectangleMode)
        XCTAssertNotNil(shapeLayout.ellipseMode)
        XCTAssertNil(shapeLayout.startArrowType)
        XCTAssertNil(shapeLayout.endArrowType)

        XCTAssertNil(arrowLayout.fillToggle)
        XCTAssertNil(arrowLayout.rectangleMode)
        XCTAssertNil(arrowLayout.ellipseMode)
        XCTAssertNotNil(arrowLayout.startArrowType)
        XCTAssertNotNil(arrowLayout.endArrowType)
        XCTAssertGreaterThan(arrowLayout.colorSwatches.first!.minX, arrowLayout.endArrowType!.maxX)
    }

    func testArrowOptionsToolbarWidthShrinksWhenShapeOnlyControlsAreHidden() {
        XCTAssertLessThan(
            SelectionToolbarState.optionsToolbarWidth(paletteCount: 8, mode: .arrowLine),
            SelectionToolbarState.optionsToolbarWidth(paletteCount: 8, mode: .shape)
        )
    }

    func testArrowOptionsToolbarCompactsFieldsAfterStrokeWidths() {
        let optionsRect = NSRect(x: 100, y: 100, width: 480, height: 40)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .arrowLine
        )

        XCTAssertLessThanOrEqual(layout.strokeStyle.minX - layout.strokeWidths.last!.maxX, 22)
        XCTAssertEqual(layout.startArrowType?.width, 42)
        XCTAssertEqual(layout.endArrowType?.width, 42)
        XCTAssertLessThan(layout.endArrowType!.maxX, layout.colorSwatches.first!.minX)
    }

    func testArrowOptionsToolbarLeavesSeparatorSpacingAroundArrowTypeFields() {
        let optionsRect = NSRect(x: 100, y: 100, width: 480, height: 40)
        let arrowLayout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .arrowLine
        )
        let shapeLayout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .shape
        )

        let strokeWidthToStyleGap = arrowLayout.strokeStyle.minX - arrowLayout.strokeWidths.last!.maxX
        XCTAssertGreaterThanOrEqual(arrowLayout.startArrowType!.minX - arrowLayout.strokeStyle.maxX, strokeWidthToStyleGap)

        let shapeSeparatorX = shapeLayout.strokeStyle.maxX + (shapeLayout.colorSwatches.first!.minX - shapeLayout.strokeStyle.maxX) / 2
        let arrowSeparatorX = arrowLayout.endArrowType!.maxX + (arrowLayout.colorSwatches.first!.minX - arrowLayout.endArrowType!.maxX) / 2
        let separatorWidth: CGFloat = 1.5
        let selectedSwatchExpansion: CGFloat = 3
        let shapeSeparatorToSelectedSwatchGap = shapeLayout.colorSwatches.first!.minX - selectedSwatchExpansion - (floor(shapeSeparatorX) + 0.25 + separatorWidth)
        let arrowSeparatorToSelectedSwatchGap = arrowLayout.colorSwatches.first!.minX - selectedSwatchExpansion - (floor(arrowSeparatorX) + 0.25 + separatorWidth)

        XCTAssertEqual(arrowSeparatorToSelectedSwatchGap, shapeSeparatorToSelectedSwatchGap, accuracy: 0.5)
    }

    func testArrowTypeFieldsAndMenuUseConsistentSampleWidth() {
        let optionsRect = NSRect(x: 100, y: 100, width: 480, height: 40)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .arrowLine
        )
        let menu = NSRect(x: 120, y: 80, width: 58, height: CGFloat(CaptureArrowType.allCases.count) * 24 + 8)
        let item = SelectionToolbarState.arrowTypeMenuItemRects(in: menu, itemCount: CaptureArrowType.allCases.count)[4]

        let fieldSample = SelectionToolbarState.arrowTypeSampleRect(in: layout.endArrowType!, pointsRight: true)
        let fieldDisclosure = SelectionToolbarState.arrowTypeDisclosureRect(in: layout.endArrowType!)
        let menuSample = SelectionToolbarState.arrowTypeSampleRect(in: item.insetBy(dx: 8, dy: 4), pointsRight: true)

        XCTAssertEqual(fieldSample.width, 22)
        XCTAssertEqual(menuSample.width, fieldSample.width)
        XCTAssertGreaterThanOrEqual(fieldDisclosure.minX - fieldSample.maxX, 3)
        XCTAssertLessThanOrEqual(fieldDisclosure.maxX, layout.endArrowType!.maxX - 3)
    }

    func testArrowTypeMenuHitTargetSelectsEveryMenuItem() {
        let itemCount = CaptureArrowType.allCases.count
        let menu = NSRect(x: 120, y: 80, width: 180, height: CGFloat(itemCount) * 24 + 8)

        for (index, rect) in SelectionToolbarState.arrowTypeMenuItemRects(in: menu, itemCount: itemCount).enumerated() {
            XCTAssertEqual(
                SelectionToolbarState.arrowTypeMenuHitTarget(
                    at: NSPoint(x: rect.midX, y: rect.midY),
                    in: menu,
                    itemCount: itemCount
                ),
                .item(index)
            )
        }
    }

    func testArrowTypeOptionsMatchCompactIconMenu() {
        XCTAssertEqual(
            CaptureArrowType.allCases.map(\.title),
            [
                "没有箭头的实线",
                "普通箭头线",
                "实心箭头线",
                "空心箭头线",
                "菱形箭头线",
                "端帽箭头线",
                "圆点箭头线",
            ]
        )
        XCTAssertFalse(CaptureArrowType.allCases.map(\.title).contains("手绘箭头线"))
    }

    func testDefaultArrowLineActivationUsesFirstPaletteColorAndExpectedArrowTypes() {
        let state = SelectionToolbarState.arrowLineActivationState(
            currentStyle: CaptureAnnotationStyle(),
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: state.style.strokeColor), "#FF001A")
        XCTAssertEqual(state.style.strokeWidth, 4)
        XCTAssertEqual(state.startArrowType, .none)
        XCTAssertEqual(state.endArrowType, .normal)
    }

    func testShapeAndArrowToolbarsUseSeparateStrokeWidthOptions() {
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .shape), [2, 4, 7])
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .arrowLine), [3, 4, 6])
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .brush), [3, 5, 7])
    }

    func testShapeArrowBrushAndMarkerToolbarsUseDistinctStrokeWidthOptions() {
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .shape), [2, 4, 7])
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .arrowLine), [3, 4, 6])
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .brush), [3, 5, 7])
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .marker), [14, 18, 22])
    }

    func testMarkerToolSelectionDoesNotChangeBrushDefaults() {
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .brush), [3, 5, 7])
        XCTAssertEqual(
            SelectionToolbarState.strokePatternOptions(canUsePremiumStrokePatterns: true, mode: .brush).map(\.pattern),
            [.solid, .dashLong, .dashNarrow, .dashLongShort]
        )
    }

    func testBrushActivationUsesFirstPaletteColorAndMediumWidth() {
        let style = SelectionToolbarState.brushActivationStyle(
            currentStyle: CaptureAnnotationStyle(),
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#FF001A")
        XCTAssertEqual(style.strokeWidth, 3)
        XCTAssertFalse(style.fillEnabled)
    }

    func testBrushActivationFallsBackToSolidWhenCurrentStrokePatternIsSketchOnly() {
        var current = CaptureAnnotationStyle()
        current.strokePattern = .sketchDashed

        let style = SelectionToolbarState.brushActivationStyle(
            currentStyle: current,
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(style.strokePattern, .solid)
    }

    func testBrushOptionsToolbarShowsStrokeStyleAndColorsOnly() {
        let optionsRect = NSRect(x: 100, y: 100, width: 420, height: 40)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .brush
        )

        XCTAssertEqual(layout.strokeWidths.count, 3)
        XCTAssertNil(layout.fillToggle)
        XCTAssertNil(layout.rectangleMode)
        XCTAssertNil(layout.ellipseMode)
        XCTAssertNil(layout.startArrowType)
        XCTAssertNil(layout.endArrowType)
        XCTAssertGreaterThan(layout.strokeStyle.minX, layout.strokeWidths.last!.maxX)
        XCTAssertGreaterThan(layout.colorSwatches.first!.minX, layout.strokeStyle.maxX)
    }

    func testMarkerStrokeWidthValuesUseHighlighterSizes() {
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .marker), [14, 18, 22])
    }

    func testMosaicOptionsToolbarShowsDotRectangleRedactionAndValueControls() {
        let optionsRect = NSRect(x: 100, y: 100, width: 420, height: 40)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .mosaic
        )

        XCTAssertEqual(layout.strokeWidths.count, 3)
        XCTAssertNil(layout.ellipseMode)
        XCTAssertNotNil(layout.rectangleMode)
        XCTAssertEqual(layout.strokeWidths.first?.minX, optionsRect.minX + 10)
        XCTAssertGreaterThan(
            layout.rectangleMode?.minX ?? 0,
            layout.strokeWidths.last?.maxX ?? 0
        )
        XCTAssertGreaterThan(
            SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect).minX,
            layout.rectangleMode?.maxX ?? 0
        )
        XCTAssertGreaterThan(
            SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect).minX,
            SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect).maxX
        )
    }

    func testMosaicOptionsToolbarBalancesLeadingAndTrailingGapAroundControls() {
        let width = SelectionToolbarState.optionsToolbarWidth(paletteCount: 8, mode: .mosaic)
        let optionsRect = NSRect(x: 100, y: 100, width: width, height: 40)
        let layout = SelectionToolbarState.optionsToolbarLayout(in: optionsRect, paletteCount: 8, mode: .mosaic)
        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect)

        guard let firstControl = layout.strokeWidths.first else {
            return XCTFail("Expected mosaic dot controls")
        }
        let leadingGap = firstControl.minX - optionsRect.minX
        let trailingGap = optionsRect.maxX - valueRect.maxX

        XCTAssertLessThan(width, 300)
        XCTAssertEqual(leadingGap, 10, accuracy: 0.1)
        XCTAssertEqual(leadingGap, trailingGap, accuracy: 0.1)
    }

    func testOptionsToolbarLeadingAndTrailingGapsAreTenPixels() throws {
        let optionsRect = NSRect(x: 100, y: 100, width: 600, height: 40)
        let modes: [SelectionToolbarState.OptionsToolbarMode] = [.shape, .arrowLine, .brush, .marker, .mosaic]

        for mode in modes {
            let width = SelectionToolbarState.optionsToolbarWidth(paletteCount: 8, mode: mode)
            let modeRect = NSRect(x: optionsRect.minX, y: optionsRect.minY, width: width, height: optionsRect.height)
            let layout = SelectionToolbarState.optionsToolbarLayout(in: modeRect, paletteCount: 8, mode: mode)
            var controls = layout.strokeWidths
            controls.append(contentsOf: layout.colorSwatches)
            [
                layout.fillToggle,
                layout.rectangleMode,
                layout.ellipseMode,
                layout.strokeStyle.isEmpty ? nil : layout.strokeStyle,
                layout.startArrowType,
                layout.endArrowType,
            ].compactMap { $0 }.forEach { controls.append($0) }
            if mode == .mosaic {
                controls.append(SelectionToolbarState.mosaicRedactionTypeButtonRect(in: modeRect))
                controls.append(SelectionToolbarState.mosaicRedactionValueRect(in: modeRect))
            }

            let minX = try XCTUnwrap(controls.map(\.minX).min(), "Expected controls for \(mode)")
            let maxX = try XCTUnwrap(controls.map(\.maxX).max(), "Expected controls for \(mode)")
            XCTAssertEqual(minX - modeRect.minX, 10, accuracy: 0.1, "\(mode) leading gap")
            XCTAssertEqual(modeRect.maxX - maxX, 10, accuracy: 0.1, "\(mode) trailing gap")
        }
    }

    func testMosaicOptionsToolbarMatchesMainToolbarHeightAndOmitsSeparator() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 60, y: 60, width: 180, height: 120))
        window.test_toggleShapeTool(.mosaicRectangle)

        let optionsRect = try XCTUnwrap(window.test_optionsToolbarRect)
        XCTAssertEqual(optionsRect.height, 28, accuracy: 0.1)

        let image = try XCTUnwrap(window.test_renderedOverlayImage())
        let typeRect = SelectionToolbarState.mosaicRedactionTypeButtonRect(in: optionsRect)
        let typeBackground = typeRect.insetBy(dx: -3, dy: -5)
        let valueRect = SelectionToolbarState.mosaicRedactionValueRect(in: optionsRect)
        let oldSeparatorX = floor(typeBackground.maxX + (valueRect.minX - typeBackground.maxX) / 2) + 1
        let separatorPoint = NSPoint(x: oldSeparatorX, y: optionsRect.midY)
        let gapPoint = NSPoint(x: oldSeparatorX - 3, y: optionsRect.midY)
        let separatorPixel = try XCTUnwrap(rgbaPixel(in: image, at: separatorPoint))
        let gapPixel = try XCTUnwrap(rgbaPixel(in: image, at: gapPoint))

        XCTAssertLessThanOrEqual(pixelDistance(separatorPixel, gapPixel), 3)
    }

    func testSelectedToolbarBackgroundsAreHiddenExceptMeasurementControls() {
        XCTAssertEqual(SelectionToolbarState.toolbarSelectedBackgroundAlpha, 0, accuracy: 0.001)
        XCTAssertEqual(SelectionToolbarState.measurementControlSelectedBackgroundAlpha, 0.34, accuracy: 0.001)
        XCTAssertGreaterThan(SelectionToolbarState.measurementControlSelectedBackgroundAlpha, 0.22)
    }

    func testMarkerActivationUsesDefaultHighlighterStyle() {
        var current = CaptureAnnotationStyle()
        current.strokeColor = .systemRed
        current.fillColor = .systemRed
        current.strokeWidth = 4
        current.strokePattern = .dashLong
        current.fillEnabled = true

        let style = SelectionToolbarState.markerActivationStyle(currentStyle: current)

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#B3EB00")
        XCTAssertEqual(style.strokeWidth, 18)
        XCTAssertEqual(style.strokePattern, .solid)
        XCTAssertFalse(style.fillEnabled)
    }

    func testMarkerToolbarStrokeWidthPreviewUsesScaledBrushLikeWidths() {
        XCTAssertEqual(SelectionToolbarState.strokeWidthPreviewLineWidth(for: 14, mode: .marker), 3)
        XCTAssertEqual(SelectionToolbarState.strokeWidthPreviewLineWidth(for: 18, mode: .marker), 5)
        XCTAssertEqual(SelectionToolbarState.strokeWidthPreviewLineWidth(for: 22, mode: .marker), 7)
        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .marker), [14, 18, 22])
    }

    func testMarkerCursorDotDiameterTracksStrokeWidthWithoutUsingFullHighlighterSize() {
        XCTAssertEqual(SelectionToolbarState.markerCursorDotDiameter(for: 14), 10)
        XCTAssertEqual(SelectionToolbarState.markerCursorDotDiameter(for: 18), 13)
        XCTAssertEqual(SelectionToolbarState.markerCursorDotDiameter(for: 22), 16)
    }

    func testMarkerOptionsToolbarShowsWidthAndColorsOnly() {
        let optionsRect = NSRect(x: 100, y: 100, width: 360, height: 40)
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 8,
            mode: .marker
        )

        XCTAssertEqual(layout.strokeWidths.count, 3)
        XCTAssertNil(layout.fillToggle)
        XCTAssertNil(layout.rectangleMode)
        XCTAssertNil(layout.ellipseMode)
        XCTAssertNil(layout.startArrowType)
        XCTAssertNil(layout.endArrowType)
        XCTAssertEqual(layout.strokeStyle, .zero)
        XCTAssertGreaterThan(layout.colorSwatches.first!.minX, layout.strokeWidths.last!.maxX)
        for strokeWidth in layout.strokeWidths {
            XCTAssertFalse(layout.colorSwatches.contains { $0.intersects(strokeWidth) })
        }
    }

    func testMarkerOptionsToolbarDoesNotExposeStrokeStyleField() {
        XCTAssertFalse(SelectionToolbarState.showsStrokeStyleField(for: .marker))
        XCTAssertTrue(SelectionToolbarState.showsStrokeStyleField(for: .shape))
        XCTAssertTrue(SelectionToolbarState.showsStrokeStyleField(for: .arrowLine))
        XCTAssertTrue(SelectionToolbarState.showsStrokeStyleField(for: .brush))
    }

    func testMagnifierToolbarModeHasShapeZoomStrokeAndColorSections() throws {
        let optionsRect = NSRect(
            x: 20,
            y: 30,
            width: SelectionToolbarState.optionsToolbarWidth(paletteCount: 20, mode: .magnifier),
            height: 40
        )
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 20,
            mode: .magnifier
        )

        XCTAssertEqual(SelectionToolbarState.strokeWidthValues(for: .magnifier), [2, 4, 7])
        XCTAssertEqual(SelectionToolbarState.magnifierZoomValues, [1.5, 2, 3, 4])
        XCTAssertNotNil(layout.rectangleMode)
        XCTAssertNotNil(layout.ellipseMode)
        XCTAssertTrue(layout.magnifierZooms.isEmpty)
        XCTAssertFalse(layout.magnifierZoom.isEmpty)
        XCTAssertEqual(layout.colorSwatches.count, 21)
        let sectionRects = layout.strokeWidths
            + [try XCTUnwrap(layout.rectangleMode), try XCTUnwrap(layout.ellipseMode)]
            + [layout.magnifierZoom]
            + layout.colorSwatches
        for rect in sectionRects {
            XCTAssertTrue(optionsRect.contains(rect), "Expected \(rect) inside \(optionsRect)")
        }
        let maxControlX = try XCTUnwrap(sectionRects.map(\.maxX).max())
        XCTAssertGreaterThanOrEqual(optionsRect.maxX - maxControlX, SelectionToolbarState.optionsToolbarHorizontalPadding)
        for firstIndex in sectionRects.indices {
            for secondIndex in sectionRects.indices where firstIndex < secondIndex {
                XCTAssertFalse(
                    sectionRects[firstIndex].intersects(sectionRects[secondIndex]),
                    "Expected magnifier toolbar sections \(firstIndex) and \(secondIndex) not to overlap"
                )
            }
        }
        XCTAssertFalse(SelectionToolbarState.showsStrokeStyleField(for: .magnifier))
    }

    func testMagnifierToolbarOrdersStrokeShapeZoomAndColorSections() throws {
        let optionsRect = NSRect(
            x: 20,
            y: 30,
            width: SelectionToolbarState.optionsToolbarWidth(paletteCount: 20, mode: .magnifier),
            height: 40
        )
        let layout = SelectionToolbarState.optionsToolbarLayout(
            in: optionsRect,
            paletteCount: 20,
            mode: .magnifier
        )
        let rectangle = try XCTUnwrap(layout.rectangleMode)
        let ellipse = try XCTUnwrap(layout.ellipseMode)
        let firstSwatch = try XCTUnwrap(layout.colorSwatches.first)

        XCTAssertLessThan(layout.strokeWidths.last!.maxX, rectangle.minX)
        XCTAssertLessThan(rectangle.maxX, ellipse.minX)
        XCTAssertLessThan(ellipse.maxX, layout.magnifierZoom.minX)
        XCTAssertLessThan(layout.magnifierZoom.maxX, firstSwatch.minX)
        XCTAssertEqual(rectangle.minX - layout.strokeWidths.last!.maxX, 14, accuracy: 0.001)
        XCTAssertEqual(layout.magnifierZoom.minX - ellipse.maxX, 14, accuracy: 0.001)
        XCTAssertEqual(firstSwatch.minX - layout.magnifierZoom.maxX, 18, accuracy: 0.001)
    }

    func testMagnifierDrawGeometryRaisesMagnifiedContentSlightly() throws {
        let destination = CGRect(x: 40, y: 30, width: 80, height: 60)
        let sourceBounds = CGRect(x: 0, y: 0, width: 200, height: 160)

        let geometry = try XCTUnwrap(CaptureAnnotationRenderer.magnifierDrawGeometry(
            destination: destination,
            sourceBounds: sourceBounds,
            zoom: 2
        ))

        XCTAssertEqual(geometry.drawRect.minX, destination.minX, accuracy: 0.001)
        XCTAssertEqual(geometry.integralSource.minX, 54, accuracy: 0.001)
        XCTAssertGreaterThan(geometry.drawRect.minY, destination.minY)
        XCTAssertEqual(geometry.drawRect.minY - destination.minY, 3, accuracy: 0.001)
    }

    func testMagnifierDrawGeometryKeepsClippedContentVisibleInsideLens() throws {
        let sourceBounds = CGRect(x: 0, y: 0, width: 200, height: 160)
        let leftEdgeDestination = CGRect(x: 0, y: 40, width: 80, height: 60)
        let rightEdgeDestination = CGRect(x: 160, y: 40, width: 80, height: 60)

        let leftGeometry = try XCTUnwrap(CaptureAnnotationRenderer.magnifierDrawGeometry(
            destination: leftEdgeDestination,
            sourceBounds: sourceBounds,
            zoom: 2
        ))
        let rightGeometry = try XCTUnwrap(CaptureAnnotationRenderer.magnifierDrawGeometry(
            destination: rightEdgeDestination,
            sourceBounds: sourceBounds,
            zoom: 2
        ))

        XCTAssertEqual(leftGeometry.drawRect.minX, leftEdgeDestination.minX, accuracy: 0.001)
        XCTAssertGreaterThan(leftGeometry.drawRect.width, 0)
        XCTAssertLessThanOrEqual(leftGeometry.drawRect.maxX, leftEdgeDestination.maxX + 0.001)
        XCTAssertEqual(rightGeometry.drawRect.maxX, sourceBounds.maxX, accuracy: 0.001)
        XCTAssertGreaterThan(rightGeometry.drawRect.width, 0)
        XCTAssertGreaterThanOrEqual(rightGeometry.drawRect.minX, rightEdgeDestination.minX - 0.001)
    }

    func testMagnifierKindSupportsSelectionAndGeometryEditing() {
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.magnifier))
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsGeometryEditing(.magnifier))
    }

    func testDefaultMagnifierAnnotationStateIsRectangleTwoX() {
        var annotation = CaptureAnnotation(
            kind: .magnifier,
            rect: NSRect(x: 10, y: 20, width: 120, height: 120),
            style: CaptureAnnotationStyle()
        )

        XCTAssertNil(annotation.magnifierShape)
        XCTAssertNil(annotation.magnifierZoom)
        XCTAssertEqual(annotation.effectiveMagnifierShape, .rectangle)
        XCTAssertEqual(annotation.effectiveMagnifierZoom, 2)

        annotation.magnifierShape = .rectangle
        annotation.magnifierZoom = 4

        XCTAssertEqual(annotation.magnifierShape, .rectangle)
        XCTAssertEqual(annotation.magnifierZoom, 4)
        XCTAssertEqual(annotation.effectiveMagnifierShape, .rectangle)
        XCTAssertEqual(annotation.effectiveMagnifierZoom, 4)

        let rectangle = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 20, y: 30, width: 80, height: 60),
            style: CaptureAnnotationStyle()
        )

        XCTAssertNil(rectangle.magnifierShape)
        XCTAssertNil(rectangle.magnifierZoom)
    }

    func testOverlayWindowUsesMarkerOptionsToolbarModeForMarkerShape() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_activateShapeTool(.marker)

        XCTAssertEqual(window.test_optionsToolbarMode, .marker)
    }

    func testOverlayWindowMarkerActivationUsesDefaultHighlighterStyle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_activateShapeTool(.rectangle)
        window.test_setCurrentStrokePattern(.dashLong)

        window.test_activateShapeTool(.marker)

        guard let style = window.test_currentStyle else {
            return XCTFail("Expected current marker style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#B3EB00")
        XCTAssertEqual(style.strokeWidth, 18)
        XCTAssertEqual(style.strokePattern, .solid)
        XCTAssertFalse(style.fillEnabled)
    }

    func testOverlayWindowMarkerColorDoesNotLeakIntoOtherShapeTools() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        guard let markerBluePoint = window.test_optionsPaletteColorPoint(at: 8) else {
            return XCTFail("Expected marker palette control")
        }
        window.test_mouseDown(at: markerBluePoint)
        window.test_mouseUp(at: markerBluePoint)

        guard let markerStyle = window.test_currentStyle else {
            return XCTFail("Expected marker style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: markerStyle.strokeColor), "#3C53D7")

        window.test_activateShapeTool(.rectangle)
        guard let rectangleStyle = window.test_currentStyle else {
            return XCTFail("Expected rectangle style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: rectangleStyle.strokeColor), "#FF001A")

        window.test_activateShapeTool(.arrowLine)
        guard let arrowStyle = window.test_currentStyle else {
            return XCTFail("Expected arrow line style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: arrowStyle.strokeColor), "#FF001A")

        window.test_activateShapeTool(.brush)
        guard let brushStyle = window.test_currentStyle else {
            return XCTFail("Expected brush style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: brushStyle.strokeColor), "#FF001A")

        window.test_activateShapeTool(.marker)
        guard let restoredMarkerStyle = window.test_currentStyle else {
            return XCTFail("Expected restored marker style")
        }
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: restoredMarkerStyle.strokeColor), "#3C53D7")
    }

    func testOverlayWindowNonMarkerToolsResetToRedAfterCustomNonMarkerColor() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.rectangle)

        guard let rectangleBluePoint = window.test_optionsPaletteColorPoint(at: 8) else {
            return XCTFail("Expected rectangle palette control")
        }
        window.test_mouseDown(at: rectangleBluePoint)
        window.test_mouseUp(at: rectangleBluePoint)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#3C53D7"
        )

        window.test_activateShapeTool(.arrowLine)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#FF001A"
        )

        guard let arrowBluePoint = window.test_optionsPaletteColorPoint(at: 8) else {
            return XCTFail("Expected arrow palette control")
        }
        window.test_mouseDown(at: arrowBluePoint)
        window.test_mouseUp(at: arrowBluePoint)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#3C53D7"
        )

        window.test_activateShapeTool(.brush)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#FF001A"
        )

        guard let brushBluePoint = window.test_optionsPaletteColorPoint(at: 8) else {
            return XCTFail("Expected brush palette control")
        }
        window.test_mouseDown(at: brushBluePoint)
        window.test_mouseUp(at: brushBluePoint)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#3C53D7"
        )

        window.test_activateShapeTool(.mosaicRectangle)
        XCTAssertEqual(
            SelectionToolbarState.colorSamplerHexString(for: window.test_currentStyle?.strokeColor ?? .clear),
            "#FF001A"
        )
    }

    func testMarkerActivationClearsStaleStrokeStyleMenu() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_activateShapeTool(.rectangle)
        window.test_setStrokeStyleMenuVisible(true)

        window.test_activateShapeTool(.marker)

        XCTAssertFalse(window.test_showsStrokeStyleMenu)
    }

    func testMarkerActivationClearsStaleArrowTypeMenus() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_activateShapeTool(.arrowLine)
        window.test_setArrowTypeMenusVisible(start: true, end: true)

        window.test_activateShapeTool(.marker)

        XCTAssertFalse(window.test_showsStartArrowTypeMenu)
        XCTAssertFalse(window.test_showsEndArrowTypeMenu)
    }

    func testOverlayWindowDraggingMarkerCreatesLocalMarkerAnnotation() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let markerLine = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .marker)
        XCTAssertEqual(markerLine.start.x, 40, accuracy: 0.1)
        XCTAssertEqual(markerLine.start.y, 50, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.x, 120, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.y, 80, accuracy: 0.1)
    }

    func testOverlayWindowClickingMarkerCreatesDotAnnotation() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseUp(at: NSPoint(x: 140, y: 150))

        guard let markerLine = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker dot annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .marker)
        XCTAssertEqual(markerLine.start.x, 40, accuracy: 0.1)
        XCTAssertEqual(markerLine.start.y, 50, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.x, 40, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.y, 50, accuracy: 0.1)
    }

    func testOverlayWindowIgnoresShortMarkerDragsUnderEightPoints() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 146, y: 150))
        window.test_mouseUp(at: NSPoint(x: 146, y: 150))

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertNil(window.test_markerLine(at: 0))
    }

    func testOverlayWindowShiftDraggingMarkerSnapsToNearestAxisOrDiagonal() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 204, y: 170), modifierFlags: [.shift])
        window.test_mouseUp(at: NSPoint(x: 204, y: 170), modifierFlags: [.shift])

        guard let markerLine = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker annotation")
        }
        XCTAssertEqual(markerLine.start.x, 40, accuracy: 0.1)
        XCTAssertEqual(markerLine.start.y, 50, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.x, 104, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.y, 50, accuracy: 0.1)
    }

    func testOverlayWindowMovesSelectedMarkerLineWithoutAddingAnnotation() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        guard let original = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker annotation")
        }

        window.test_mouseDown(at: NSPoint(x: 180, y: 165))
        window.test_mouseDragged(to: NSPoint(x: 210, y: 185))
        window.test_mouseUp(at: NSPoint(x: 210, y: 185))

        guard let moved = window.test_markerLine(at: 0) else {
            return XCTFail("Expected moved marker annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(window.test_selectedAnnotationKind, .marker)
        XCTAssertEqual(moved.start.x, original.start.x + 30, accuracy: 0.1)
        XCTAssertEqual(moved.start.y, original.start.y + 20, accuracy: 0.1)
        XCTAssertEqual(moved.end.x, original.end.x + 30, accuracy: 0.1)
        XCTAssertEqual(moved.end.y, original.end.y + 20, accuracy: 0.1)
    }

    func testOverlayWindowMarkerEndpointHandlesResizeLineWithoutCoveringExactEndpoints() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        let overlayLine = CaptureMarkerLine(start: NSPoint(x: 140, y: 150), end: NSPoint(x: 220, y: 180))
        let startHandle = SelectionToolbarState.markerRotationHandlePoint(for: .start, line: overlayLine)!

        XCTAssertEqual(window.test_cursorStyle(at: startHandle), .resizeUpDown)
        XCTAssertEqual(window.test_cursorStyle(at: overlayLine.start), .marker)

        window.test_mouseDown(at: startHandle)
        window.test_mouseDragged(to: NSPoint(x: 155, y: 130))
        window.test_mouseUp(at: NSPoint(x: 155, y: 130))

        guard let markerLine = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(markerLine.start.x, 55, accuracy: 0.1)
        XCTAssertEqual(markerLine.start.y, 30, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.x, 120, accuracy: 0.1)
        XCTAssertEqual(markerLine.end.y, 80, accuracy: 0.1)
    }

    func testOverlayWindowMovesSinglePointMarkerWithoutResizingIt() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        let point = NSPoint(x: 140, y: 150)
        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)

        guard let original = window.test_markerLine(at: 0) else {
            return XCTFail("Expected marker annotation")
        }
        XCTAssertEqual(original.start.x, original.end.x, accuracy: 0.1)
        XCTAssertEqual(original.start.y, original.end.y, accuracy: 0.1)
        XCTAssertEqual(window.test_cursorStyle(at: point), .move)

        window.test_mouseDown(at: point)
        window.test_mouseDragged(to: NSPoint(x: 170, y: 180))
        window.test_mouseUp(at: NSPoint(x: 170, y: 180))

        guard let moved = window.test_markerLine(at: 0) else {
            return XCTFail("Expected moved marker annotation")
        }
        XCTAssertEqual(window.test_annotationCount, 1)
        XCTAssertEqual(moved.start.x, original.start.x + 30, accuracy: 0.1)
        XCTAssertEqual(moved.start.y, original.start.y + 30, accuracy: 0.1)
        XCTAssertEqual(moved.end.x, moved.start.x, accuracy: 0.1)
        XCTAssertEqual(moved.end.y, moved.start.y, accuracy: 0.1)
    }

    func testOverlayWindowCanContinueDrawingMarkerFromExistingEndpoint() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))

        window.test_mouseDown(at: NSPoint(x: 220, y: 180))
        window.test_mouseDragged(to: NSPoint(x: 250, y: 180))
        window.test_mouseUp(at: NSPoint(x: 250, y: 180))

        XCTAssertEqual(window.test_annotationCount, 2)
        guard let continued = window.test_markerLine(at: 1) else {
            return XCTFail("Expected continued marker annotation")
        }
        XCTAssertEqual(continued.start.x, 120, accuracy: 0.1)
        XCTAssertEqual(continued.start.y, 80, accuracy: 0.1)
        XCTAssertEqual(continued.end.x, 150, accuracy: 0.1)
        XCTAssertEqual(continued.end.y, 80, accuracy: 0.1)
    }

    func testMarkerAnnotationStyleCanEditButGeometryCannotResizeAfterDrawing() {
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.marker))
        XCTAssertFalse(SelectionToolbarState.annotationKindSupportsGeometryEditing(.marker))
    }

    func testOverlayWindowDeleteKeyRemovesSelectedMarker() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))
        window.test_mouseDown(at: NSPoint(x: 180, y: 165))
        window.test_mouseUp(at: NSPoint(x: 180, y: 165))

        XCTAssertEqual(window.test_selectedAnnotationKind, .marker)
        window.test_keyDown(keyCode: 51)

        XCTAssertEqual(window.test_annotationCount, 0)
        XCTAssertNil(window.test_selectedAnnotationKind)
    }

    func testOverlayWindowMarkerOptionsToolbarEditsSelectedMarkerStyle() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        window.test_mouseDown(at: NSPoint(x: 140, y: 150))
        window.test_mouseDragged(to: NSPoint(x: 220, y: 180))
        window.test_mouseUp(at: NSPoint(x: 220, y: 180))
        window.test_mouseDown(at: NSPoint(x: 180, y: 165))
        window.test_mouseUp(at: NSPoint(x: 180, y: 165))

        guard let strokeWidthPoint = window.test_optionsStrokeWidthPoint(at: 2),
              let colorPoint = window.test_optionsPaletteColorPoint(at: 0) else {
            return XCTFail("Expected marker options toolbar controls")
        }

        window.test_mouseDown(at: strokeWidthPoint)
        window.test_mouseUp(at: strokeWidthPoint)
        window.test_mouseDown(at: colorPoint)
        window.test_mouseUp(at: colorPoint)

        guard let style = window.test_annotationStyle(at: 0) else {
            return XCTFail("Expected marker annotation style")
        }
        XCTAssertEqual(window.test_optionsToolbarMode, .marker)
        XCTAssertEqual(style.strokeWidth, 22)
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#FF001A")
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.fillColor), "#FF001A")
    }

    func testSnappedMarkerEndPointKeepsRawPointWithoutShift() {
        let rawEnd = NSPoint(x: 64, y: 34)

        let snapped = SelectionToolbarState.snappedMarkerEndPoint(
            start: .zero,
            rawEnd: rawEnd,
            isShiftPressed: false
        )

        XCTAssertEqual(snapped.x, rawEnd.x, accuracy: 0.1)
        XCTAssertEqual(snapped.y, rawEnd.y, accuracy: 0.1)
    }

    func testSnappedMarkerEndPointUsesNearestHorizontalVerticalOrDiagonalWithShift() {
        let horizontal = SelectionToolbarState.snappedMarkerEndPoint(
            start: .zero,
            rawEnd: NSPoint(x: 64, y: 20),
            isShiftPressed: true
        )
        XCTAssertEqual(horizontal.x, 64, accuracy: 0.1)
        XCTAssertEqual(horizontal.y, 0, accuracy: 0.1)

        let vertical = SelectionToolbarState.snappedMarkerEndPoint(
            start: .zero,
            rawEnd: NSPoint(x: 12, y: 64),
            isShiftPressed: true
        )
        XCTAssertEqual(vertical.x, 0, accuracy: 0.1)
        XCTAssertEqual(vertical.y, 64, accuracy: 0.1)

        let diagonal = SelectionToolbarState.snappedMarkerEndPoint(
            start: .zero,
            rawEnd: NSPoint(x: 42, y: 38),
            isShiftPressed: true
        )
        XCTAssertEqual(diagonal.x, diagonal.y, accuracy: 0.1)
    }

    func testMarkerToolbarButtonClickActivatesMarkerMode() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.rectangle)
        window.test_setStrokeStyleMenuVisible(true)
        window.test_setArrowTypeMenusVisible(start: true, end: true)

        guard let point = window.test_markerToolbarButtonPoint() else {
            return XCTFail("Expected visible marker toolbar button")
        }
        window.test_mouseDown(at: point)
        window.test_mouseUp(at: point)

        XCTAssertEqual(window.test_optionsToolbarMode, .marker)
        XCTAssertEqual(window.test_cursorStyle(at: NSPoint(x: 150, y: 150)), .marker)
        XCTAssertFalse(window.test_showsStrokeStyleMenu)
        XCTAssertFalse(window.test_showsStartArrowTypeMenu)
        XCTAssertFalse(window.test_showsEndArrowTypeMenu)
    }

    func testMarkerToolbarButtonUsesArrowCursorWhenMarkerIsActive() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.marker)

        let markerButtonPoint = try XCTUnwrap(window.test_markerToolbarButtonPoint())

        XCTAssertEqual(window.test_cursorStyle(at: markerButtonPoint), .arrow)
    }

    func testMarkerToolbarButtonSelectedStateWorksWhenMarkerIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        XCTAssertFalse(window.test_markerToolbarButtonIsSelected)

        window.test_activateShapeTool(.marker)

        XCTAssertTrue(window.test_markerToolbarButtonIsSelected)
    }

    func testMainToolbarHasLeadingAndTrailingDragHandles() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 360, height: 220))

        let leadingPoint = try XCTUnwrap(window.test_mainToolbarLeadingDragPoint())
        let trailingPoint = try XCTUnwrap(window.test_mainToolbarTrailingDragPoint())
        let firstButton = try XCTUnwrap(window.test_mainToolbarButtonRects().first)
        let lastButton = try XCTUnwrap(window.test_mainToolbarButtonRects().last)

        XCTAssertLessThan(leadingPoint.x, firstButton.minX)
        XCTAssertGreaterThan(trailingPoint.x, lastButton.maxX)
        XCTAssertEqual(window.test_cursorStyle(at: leadingPoint), .move)
        XCTAssertEqual(window.test_cursorStyle(at: trailingPoint), .move)
    }

    func testMainToolbarLeadingDragHandleMovesToolbar() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 360, height: 220))
        let firstButtonBefore = try XCTUnwrap(window.test_mainToolbarButtonRects().first)
        let leadingPoint = try XCTUnwrap(window.test_mainToolbarLeadingDragPoint())

        window.test_mouseDown(at: leadingPoint)
        window.test_mouseDragged(to: NSPoint(x: leadingPoint.x + 36, y: leadingPoint.y + 10))
        window.test_mouseUp(at: NSPoint(x: leadingPoint.x + 36, y: leadingPoint.y + 10))

        let firstButtonAfter = try XCTUnwrap(window.test_mainToolbarButtonRects().first)
        XCTAssertGreaterThan(firstButtonAfter.minX, firstButtonBefore.minX + 20)
    }

    func testSelectedMainToolbarIconIsBlueWithoutSelectedBackground() throws {
        let image = solidImage(size: NSSize(width: 900, height: 520), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))
        window.test_activateShapeTool(.rectangle)

        let button = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .rectangle))
        let unselectedButton = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .mosaic))
        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let iconPixel = try XCTUnwrap(firstBlueDominantPixel(in: overlayImage, rect: button))
        let selectedBackgroundPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: NSPoint(x: button.minX + 1, y: button.minY + 1)))
        let unselectedBackgroundPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: NSPoint(x: unselectedButton.minX + 1, y: unselectedButton.minY + 1)))

        XCTAssertGreaterThan(iconPixel.blue, iconPixel.red)
        XCTAssertGreaterThan(iconPixel.blue, iconPixel.green)
        XCTAssertLessThan(pixelDistance(selectedBackgroundPixel, unselectedBackgroundPixel), 8)
    }

    func testSelectedEyedropperToolbarIconIsBlueWithoutSelectedBackground() throws {
        let image = solidImage(size: NSSize(width: 900, height: 520), color: .white)
        let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 300, height: 220))

        let eyedropperPoint = try XCTUnwrap(window.test_mainToolbarButtonPoint(for: .eyedropper))
        window.test_mouseDown(at: eyedropperPoint)
        window.test_mouseUp(at: eyedropperPoint)

        let button = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .eyedropper))
        let unselectedButton = try XCTUnwrap(window.test_mainToolbarButtonRect(for: .mosaic))
        let overlayImage = try XCTUnwrap(window.test_renderedOverlayImage())
        let iconPixel = try XCTUnwrap(firstBlueDominantPixel(in: overlayImage, rect: button))
        let selectedBackgroundPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: NSPoint(x: button.minX + 1, y: button.minY + 1)))
        let unselectedBackgroundPixel = try XCTUnwrap(rgbaPixel(in: overlayImage, at: NSPoint(x: unselectedButton.minX + 1, y: unselectedButton.minY + 1)))

        XCTAssertTrue(window.test_eyedropperToolbarButtonIsSelected)
        XCTAssertGreaterThan(iconPixel.blue, iconPixel.red)
        XCTAssertGreaterThan(iconPixel.blue, iconPixel.green)
        XCTAssertLessThan(pixelDistance(selectedBackgroundPixel, unselectedBackgroundPixel), 8)
    }

    func testMainToolbarButtonsUseRoomierDefaultSpacing() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 80, y: 80, width: 360, height: 220))

        let rects = window.test_mainToolbarButtonRects()
        XCTAssertGreaterThan(rects.count, 8)

        let gaps = zip(rects, rects.dropFirst()).map { left, right in
            right.minX - left.maxX
        }
        XCTAssertGreaterThanOrEqual(gaps.min() ?? 0, 8)
    }

    func testBrushAnnotationStyleIsNotEditableAfterDrawing() {
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.rectangle))
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.ellipse))
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.arrowLine))
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.marker))
        XCTAssertFalse(SelectionToolbarState.annotationKindSupportsPostDrawEditing(.brush))
    }

    func testBrushAnnotationGeometryCannotMoveOrResizeAfterDrawing() {
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsGeometryEditing(.rectangle))
        XCTAssertTrue(SelectionToolbarState.annotationKindSupportsGeometryEditing(.ellipse))
        XCTAssertFalse(SelectionToolbarState.annotationKindSupportsGeometryEditing(.arrowLine))
        XCTAssertFalse(SelectionToolbarState.annotationKindSupportsGeometryEditing(.brush))
    }

    func testBrushAnnotationStyleIsFrozenAfterDrawing() {
        var original = CaptureAnnotationStyle()
        original.strokeWidth = 5
        original.strokePattern = .solid
        original.strokeColor = .systemRed

        var current = CaptureAnnotationStyle()
        current.strokeWidth = 7
        current.strokePattern = .dashLong
        current.strokeColor = .systemBlue

        let applied = SelectionToolbarState.updatedSelectedAnnotationStyle(
            kind: .brush,
            existingStyle: original,
            currentStyle: current
        )

        XCTAssertEqual(applied.strokeWidth, 5)
        XCTAssertEqual(applied.strokePattern, .solid)
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: applied.strokeColor), "#FF3B30")
    }

    func testEditableAnnotationStyleUsesCurrentToolbarStyle() {
        var original = CaptureAnnotationStyle()
        original.strokeWidth = 4
        original.strokePattern = .solid

        var current = CaptureAnnotationStyle()
        current.strokeWidth = 7
        current.strokePattern = .dashLong

        let applied = SelectionToolbarState.updatedSelectedAnnotationStyle(
            kind: .rectangle,
            existingStyle: original,
            currentStyle: current
        )

        XCTAssertEqual(applied.strokeWidth, 7)
        XCTAssertEqual(applied.strokePattern, .dashLong)
    }

    func testSelectionResizeCursorWinsOverBrushOnSelectionBorder() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: .topLeft,
                isAnnotationBorder: false,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .brush
            ),
            .resizeTopLeft
        )
    }

    func testBrushCursorStillShowsInsideSelectionAwayFromBorder() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .brush
            ),
            .brush
        )
    }

    func testBrushCursorUsesBrushOutsideSelectionAndArrowOnToolbar() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: false,
                isShapeToolActive: true,
                currentShapeKind: .brush
            ),
            .brush
        )

        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: true,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .brush
            ),
            .arrow
        )
    }

    func testShapeToolCursorStaysActiveOutsideSelectionAwayFromBorder() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: false,
                isShapeToolActive: true,
                currentShapeKind: .rectangle
            ),
            .crosshair
        )
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: false,
                isShapeToolActive: true,
                currentShapeKind: .arrowLine
            ),
            .crosshair
        )
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: false,
                isShapeToolActive: true,
                currentShapeKind: .marker
            ),
            .marker
        )
    }

    func testBrushCursorUsesArrowOnToolbarDragArea() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: true,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: false,
                isShapeToolActive: true,
                currentShapeKind: .brush
            ),
            .arrow
        )
    }

    func testShapeToolCursorUsesMoveOnAnnotationBorderWhileToolIsActive() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .rectangle
            ),
            .move
        )
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .arrowLine
            ),
            .move
        )
    }

    func testShapeToolCursorUsesResizeOnAnnotationHandleWhileToolIsActive() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: .topLeft,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .rectangle
            ),
            .resizeTopLeft
        )
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: .right,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .arrowLine
            ),
            .resizeLeftRight
        )
    }

    func testAnnotationResizeCursorWinsOverSelectionResizeWhileDrawingToolIsActive() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: .topLeft,
                selectionResizeHandle: .right,
                isAnnotationBorder: true,
                isInsideSelection: true,
                isShapeToolActive: true,
                currentShapeKind: .rectangle
            ),
            .resizeTopLeft
        )
    }

    func testAnnotatingCursorUsesArrowOutsideSelection() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: false,
                isInsideSelection: false,
                currentShapeKind: .rectangle
            ),
            .arrow
        )
    }

    func testSpecialArrowTypesCanOnlyBeSelectedOnOneEnd() {
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .normal,
                currentEnd: .normal,
                selectedType: .solidArrow,
                endpoint: .start
            ),
            SelectionToolbarState.ArrowTypePair(start: .solidArrow, end: .none)
        )
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .normal,
                currentEnd: .normal,
                selectedType: .hollowArrow,
                endpoint: .end
            ),
            SelectionToolbarState.ArrowTypePair(start: .none, end: .hollowArrow)
        )
    }

    func testChangingOtherEndClearsExistingSpecialArrowType() {
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .solidArrow,
                currentEnd: .none,
                selectedType: .bar,
                endpoint: .end
            ),
            SelectionToolbarState.ArrowTypePair(start: .none, end: .bar)
        )
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .none,
                currentEnd: .hollowArrow,
                selectedType: .dot,
                endpoint: .start
            ),
            SelectionToolbarState.ArrowTypePair(start: .dot, end: .none)
        )
    }

    func testRegularArrowTypesStillSupportBothEnds() {
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .diamond,
                currentEnd: .bar,
                selectedType: .normal,
                endpoint: .start
            ),
            SelectionToolbarState.ArrowTypePair(start: .normal, end: .bar)
        )
        XCTAssertEqual(
            SelectionToolbarState.arrowTypesAfterSelection(
                currentStart: .normal,
                currentEnd: .dot,
                selectedType: .diamond,
                endpoint: .end
            ),
            SelectionToolbarState.ArrowTypePair(start: .normal, end: .diamond)
        )
    }

    func testArrowLineHitTargetDistinguishesHandlesAndBody() {
        let line = CaptureArrowLine(
            start: NSPoint(x: 10, y: 10),
            end: NSPoint(x: 110, y: 10),
            control: NSPoint(x: 60, y: 60),
            startArrowType: .none,
            endArrowType: .normal
        )

        XCTAssertEqual(SelectionToolbarState.arrowLineHitTarget(at: NSPoint(x: 10, y: 10), line: line), .start)
        XCTAssertEqual(SelectionToolbarState.arrowLineHitTarget(at: NSPoint(x: 110, y: 10), line: line), .end)
        XCTAssertEqual(SelectionToolbarState.arrowLineHitTarget(at: NSPoint(x: 60, y: 60), line: line), .control)
        XCTAssertEqual(SelectionToolbarState.arrowLineHitTarget(at: NSPoint(x: 60, y: 34), line: line), .body)
        XCTAssertEqual(SelectionToolbarState.arrowLineHitTarget(at: NSPoint(x: 60, y: 90), line: line), .none)
    }

    func testBrushRotationHitTargetUsesInsetHandlesInsteadOfPathEndpoints() {
        let path = CaptureBrushPath(points: [
            NSPoint(x: 10, y: 10),
            NSPoint(x: 35, y: 45),
            NSPoint(x: 60, y: 70),
            NSPoint(x: 110, y: 10),
        ])

        let startHandle = SelectionToolbarState.brushRotationHandlePoint(for: .start, path: path)!
        let endHandle = SelectionToolbarState.brushRotationHandlePoint(for: .end, path: path)!

        XCTAssertNotEqual(startHandle, path.points.first)
        XCTAssertNotEqual(endHandle, path.points.last)
        XCTAssertEqual(SelectionToolbarState.brushRotationHitTarget(at: NSPoint(x: 10, y: 10), path: path), .none)
        XCTAssertEqual(SelectionToolbarState.brushRotationHitTarget(at: NSPoint(x: 110, y: 10), path: path), .none)
        XCTAssertEqual(SelectionToolbarState.brushRotationHitTarget(at: startHandle, path: path), .start)
        XCTAssertEqual(SelectionToolbarState.brushRotationHitTarget(at: endHandle, path: path), .end)
        XCTAssertEqual(SelectionToolbarState.brushRotationHitTarget(at: NSPoint(x: 60, y: 70), path: path), .none)
    }

    func testMarkerRotationHitTargetUsesInsetHandlesInsteadOfLineEndpoints() {
        let line = CaptureMarkerLine(start: NSPoint(x: 10, y: 10), end: NSPoint(x: 110, y: 10))

        XCTAssertEqual(SelectionToolbarState.markerRotationHandlePoint(for: .start, line: line), NSPoint(x: 24, y: 10))
        XCTAssertEqual(SelectionToolbarState.markerRotationHandlePoint(for: .end, line: line), NSPoint(x: 96, y: 10))
        XCTAssertEqual(SelectionToolbarState.markerRotationHitTarget(at: line.start, line: line), .none)
        XCTAssertEqual(SelectionToolbarState.markerRotationHitTarget(at: line.end, line: line), .none)
        XCTAssertEqual(SelectionToolbarState.markerRotationHitTarget(at: NSPoint(x: 24, y: 10), line: line), .start)
        XCTAssertEqual(SelectionToolbarState.markerRotationHitTarget(at: NSPoint(x: 96, y: 10), line: line), .end)
    }

    func testDraggingMarkerEndpointChangesOnlyThatEndpoint() {
        let line = CaptureMarkerLine(start: NSPoint(x: 10, y: 10), end: NSPoint(x: 110, y: 10))

        let movedStart = SelectionToolbarState.resizedMarkerLine(line, dragging: .start, to: NSPoint(x: 20, y: 35))
        XCTAssertEqual(movedStart.start.x, 20, accuracy: 0.1)
        XCTAssertEqual(movedStart.start.y, 35, accuracy: 0.1)
        XCTAssertEqual(movedStart.end.x, 110, accuracy: 0.1)
        XCTAssertEqual(movedStart.end.y, 10, accuracy: 0.1)

        let movedEnd = SelectionToolbarState.resizedMarkerLine(line, dragging: .end, to: NSPoint(x: 80, y: 45))
        XCTAssertEqual(movedEnd.start.x, 10, accuracy: 0.1)
        XCTAssertEqual(movedEnd.start.y, 10, accuracy: 0.1)
        XCTAssertEqual(movedEnd.end.x, 80, accuracy: 0.1)
        XCTAssertEqual(movedEnd.end.y, 45, accuracy: 0.1)
    }

    func testBrushRotationHandleAngleFollowsEndpointTangent() {
        let horizontal = CaptureBrushPath(points: [
            NSPoint(x: 10, y: 10),
            NSPoint(x: 40, y: 10),
            NSPoint(x: 70, y: 10),
        ])
        XCTAssertEqual(
            SelectionToolbarState.brushRotationHandleAngle(for: .start, path: horizontal)!,
            .pi,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SelectionToolbarState.brushRotationHandleAngle(for: .end, path: horizontal)!,
            0,
            accuracy: 0.001
        )

        let vertical = CaptureBrushPath(points: [
            NSPoint(x: 10, y: 10),
            NSPoint(x: 10, y: 40),
            NSPoint(x: 10, y: 70),
        ])
        XCTAssertEqual(
            SelectionToolbarState.brushRotationHandleAngle(for: .end, path: vertical)!,
            .pi / 2,
            accuracy: 0.001
        )
    }

    func testDraggingBrushEndpointTransformsWholePathAroundOppositeEndpoint() {
        let path = CaptureBrushPath(points: [
            NSPoint(x: 10, y: 10),
            NSPoint(x: 40, y: 30),
            NSPoint(x: 70, y: 10),
        ])

        let moved = SelectionToolbarState.rotatedBrushPath(
            path,
            dragging: .end,
            to: NSPoint(x: 40, y: 40)
        )

        XCTAssertEqual(moved.points.count, path.points.count)
        XCTAssertEqual(moved.points[0].x, 10, accuracy: 0.1)
        XCTAssertEqual(moved.points[0].y, 10, accuracy: 0.1)
        XCTAssertEqual(moved.points[1].x, 15, accuracy: 0.1)
        XCTAssertEqual(moved.points[1].y, 35, accuracy: 0.1)
        XCTAssertEqual(moved.points[2].x, 40, accuracy: 0.1)
        XCTAssertEqual(moved.points[2].y, 40, accuracy: 0.1)
    }

    func testPrimaryShapeToolSelectionTogglesOffWhenAnyShapeToolIsActive() {
        XCTAssertEqual(
            SelectionToolbarState.toggledPrimaryShapeTool(current: nil, defaultShape: .rectangle),
            .rectangle
        )
        XCTAssertNil(
            SelectionToolbarState.toggledPrimaryShapeTool(current: .rectangle, defaultShape: .rectangle)
        )
        XCTAssertNil(
            SelectionToolbarState.toggledPrimaryShapeTool(current: .ellipse, defaultShape: .rectangle)
        )
    }

    func testPrimaryShapeToolActivationUsesFirstPaletteColorWhenStyleIsStillDefault() {
        let style = SelectionToolbarState.styleForPrimaryShapeToolActivation(
            currentStyle: CaptureAnnotationStyle(),
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#FF001A")
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.fillColor), "#FF001A")
        XCTAssertEqual(style.strokeWidth, 4)
        XCTAssertEqual(style.cornerRadius, 5)
    }

    func testPrimaryShapeToolActivationUsesFirstPaletteColorAfterUserChosenColor() {
        var currentStyle = CaptureAnnotationStyle()
        currentStyle.strokeColor = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        currentStyle.fillColor = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)

        let style = SelectionToolbarState.styleForPrimaryShapeToolActivation(
            currentStyle: currentStyle,
            paletteColors: SelectionOverlayWindow.defaultPaletteColors
        )

        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.strokeColor), "#FF001A")
        XCTAssertEqual(SelectionToolbarState.colorSamplerHexString(for: style.fillColor), "#FF001A")
        XCTAssertEqual(style.strokeWidth, 4)
        XCTAssertEqual(style.cornerRadius, 5)
    }

    func testFillPreviewUsesNeutralGrayWithoutFill() {
        let style = CaptureAnnotationStyle()

        let preview = SelectionToolbarState.fillPreviewStyle(
            currentShapeKind: .rectangle,
            currentStyle: style
        )

        XCTAssertEqual(preview.shape, .rectangle)
        XCTAssertFalse(preview.showsStrokeOutline)
        XCTAssertTrue(preview.color.isEqual(NSColor.systemGray))
    }

    func testFillPreviewUsesSelectedColorAndShapeWhenFillEnabled() {
        var style = CaptureAnnotationStyle()
        style.fillEnabled = true
        style.fillColor = .systemGreen

        let preview = SelectionToolbarState.fillPreviewStyle(
            currentShapeKind: .ellipse,
            currentStyle: style
        )

        XCTAssertEqual(preview.shape, .ellipse)
        XCTAssertFalse(preview.showsStrokeOutline)
        XCTAssertTrue(preview.color.isEqual(NSColor.systemGreen))
    }

    func testColorSwatchesUseTwoRowsAndSquarePaletteButton() {
        let optionsRect = NSRect(x: 100, y: 100, width: 510, height: 40)
        let swatches = SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: 20)
        let firstRow = swatches[0]
        let secondRow = swatches[10]
        let customSlot = SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: 20).last!

        XCTAssertEqual(firstRow.minY, optionsRect.minY + 23)
        XCTAssertEqual(secondRow.minY, optionsRect.minY + 7)
        XCTAssertEqual(customSlot.width, 32)
        XCTAssertEqual(customSlot.height, 32)
        XCTAssertEqual(customSlot.minY, optionsRect.minY + 4)
    }

    func testCompactColorSwatchesUseSingleRowAndShortToolbar() {
        let optionsRect = NSRect(x: 100, y: 100, width: 422, height: 30)
        let swatches = SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: 4)
        let customSlot = swatches.last!

        XCTAssertEqual(SelectionToolbarState.optionsToolbarHeight(paletteCount: 4), 30)
        XCTAssertEqual(SelectionToolbarState.optionsToolbarWidth(paletteCount: 4), 425)
        XCTAssertEqual(swatches.count, 5)
        XCTAssertTrue(swatches[0..<4].allSatisfy { $0.minY == optionsRect.minY + 9 })
        XCTAssertEqual(customSlot.width, 20)
        XCTAssertEqual(customSlot.height, 20)
        XCTAssertEqual(customSlot.minY, optionsRect.minY + 5)
    }

    func testDefaultPalettePutsFrequentRedFirstInRequestedTwoRowColors() {
        let hexColors = SelectionOverlayWindow.defaultPaletteColors.map {
            SelectionToolbarState.colorSamplerHexString(for: $0)
        }

        XCTAssertEqual(
            hexColors,
            [
                "#FF001A",
                "#8A8A8A",
                "#000000",
                "#A3000D",
                "#FF7E06",
                "#FFF300",
                "#00BE4E",
                "#00B0EF",
                "#3C53D7",
                "#BB4AB0",
                "#FFFFFF",
                "#CACACA",
                "#CE815D",
                "#FFB2D0",
                "#FFCC00",
                "#F5E7B5",
                "#B3EB00",
                "#8EE1EE",
                "#6F9EC8",
                "#D0C6EC",
            ]
        )
    }

    func testPaletteLastGraySwatchDoesNotTriggerCustomPalette() {
        let optionsRect = NSRect(x: 100, y: 100, width: 510, height: 40)
        let swatches = SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: 20)
        let lastGraySwatch = swatches[19]

        XCTAssertEqual(
            SelectionToolbarState.swatchHitTarget(at: NSPoint(x: lastGraySwatch.midX, y: lastGraySwatch.midY), in: optionsRect, paletteCount: 20),
            .palette(19)
        )
    }

    func testCustomPaletteButtonUsesItsOwnHitTargetOnly() {
        let optionsRect = NSRect(x: 100, y: 100, width: 510, height: 40)
        let customSlot = SelectionToolbarState.colorSwatchRects(in: optionsRect, paletteCount: 20).last!

        XCTAssertEqual(
            SelectionToolbarState.swatchHitTarget(at: NSPoint(x: customSlot.midX, y: customSlot.midY), in: optionsRect, paletteCount: 20),
            .custom
        )
        XCTAssertNil(
            SelectionToolbarState.swatchHitTarget(at: NSPoint(x: customSlot.maxX + 4, y: customSlot.midY), in: optionsRect, paletteCount: 20)
        )
    }

    func testOptionsToolbarWidthShrinksWhenPaletteCountIsReduced() {
        let fullPaletteWidth = SelectionToolbarState.optionsToolbarWidth(paletteCount: 20)
        let compactPaletteWidth = SelectionToolbarState.optionsToolbarWidth(paletteCount: 8)

        XCTAssertEqual(fullPaletteWidth, 533)
        XCTAssertLessThan(compactPaletteWidth, fullPaletteWidth)
    }

    func testStrokePatternOptionsReserveSketchLinesForPremiumAccess() {
        let freeOptions = SelectionToolbarState.strokePatternOptions(canUsePremiumStrokePatterns: false)

        XCTAssertEqual(
            freeOptions.map(\.pattern),
            [.solid, .dashLong, .dashNarrow, .dashLongShort, .sketchSolid, .sketchDashed]
        )
        XCTAssertTrue(freeOptions.allSatisfy(\.isEnabled))

        let premiumOptions = SelectionToolbarState.strokePatternOptions(canUsePremiumStrokePatterns: true)
        XCTAssertTrue(premiumOptions.allSatisfy(\.isEnabled))
    }

    func testBrushStrokePatternOptionsHideSketchLines() {
        let options = SelectionToolbarState.strokePatternOptions(
            canUsePremiumStrokePatterns: true,
            mode: .brush
        )

        XCTAssertEqual(options.map(\.pattern), [.solid, .dashLong, .dashNarrow, .dashLongShort])
    }

    func testMarkerStrokePatternOptionsOnlyUseSolidLine() {
        let options = SelectionToolbarState.strokePatternOptions(
            canUsePremiumStrokePatterns: true,
            mode: .marker
        )

        XCTAssertEqual(options.map(\.pattern), [.solid])
    }

    func testShapeAndArrowStrokePatternOptionsKeepSketchLines() {
        let shapeOptions = SelectionToolbarState.strokePatternOptions(
            canUsePremiumStrokePatterns: true,
            mode: .shape
        )
        let arrowOptions = SelectionToolbarState.strokePatternOptions(
            canUsePremiumStrokePatterns: true,
            mode: .arrowLine
        )

        XCTAssertEqual(shapeOptions.map(\.pattern), CaptureStrokePattern.allCases)
        XCTAssertEqual(arrowOptions.map(\.pattern), CaptureStrokePattern.allCases)
    }

    func testStrokeMenuHitTargetSelectsEveryMenuItem() {
        let itemCount = SelectionToolbarState.strokePatternOptions(canUsePremiumStrokePatterns: true).count
        let menu = NSRect(x: 120, y: 80, width: 102, height: CGFloat(itemCount) * 24 + 8)

        for (index, rect) in SelectionToolbarState.strokeStyleMenuItemRects(in: menu, itemCount: itemCount).enumerated() {
            XCTAssertEqual(
                SelectionToolbarState.strokeMenuHitTarget(at: NSPoint(x: rect.midX, y: rect.midY), in: menu, itemCount: itemCount),
                .item(index)
            )
        }
    }

    func testToolbarRectRightAlignsToAnchor() {
        let anchor = NSRect(x: 200, y: 300, width: 120, height: 80)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 260, height: 30),
            anchoredTo: anchor,
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(toolbar.maxX, anchor.maxX)
    }

    func testToolbarRectStaysInsideBoundsForFullScreenSelection() {
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 520, height: 30),
            anchoredTo: bounds,
            inside: bounds
        )

        XCTAssertTrue(bounds.insetBy(dx: 8, dy: 8).contains(toolbar))
    }

    func testToolbarRectAvoidsMenuBarVisibleBoundsForFullScreenSelection() {
        let selection = NSRect(x: 0, y: 0, width: 800, height: 600)
        let visibleBounds = NSRect(x: 0, y: 0, width: 800, height: 560)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 520, height: 30),
            anchoredTo: selection,
            inside: visibleBounds
        )

        XCTAssertLessThanOrEqual(toolbar.maxY, visibleBounds.maxY - 8)
    }

    func testToolbarRectUsesBottomRightInsideForFullScreenSelection() {
        let selection = NSRect(x: 0, y: 0, width: 800, height: 600)
        let visibleBounds = NSRect(x: 0, y: 0, width: 800, height: 560)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 520, height: 30),
            anchoredTo: selection,
            inside: visibleBounds
        )

        XCTAssertEqual(toolbar.maxX, visibleBounds.maxX - 8)
        XCTAssertEqual(toolbar.minY, visibleBounds.minY + 8)
    }

    func testToolbarRectStaysOutsideMaximizedButNotFullScreenSelection() {
        let screenBounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let maximizedSelection = NSRect(x: 0, y: 40, width: 800, height: 520)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 520, height: 30),
            anchoredTo: maximizedSelection,
            inside: screenBounds,
            allowsInsidePlacement: false
        )

        XCTAssertFalse(toolbar.intersects(maximizedSelection))
        XCTAssertTrue(screenBounds.insetBy(dx: 8, dy: 8).contains(toolbar))
    }

    func testToolbarRectUsesSideSpaceForTallNonFullScreenSelection() {
        let screenBounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let tallSelection = NSRect(x: 0, y: 0, width: 560, height: 600)
        let toolbar = SelectionToolbarState.toolbarRect(
            size: NSSize(width: 180, height: 30),
            anchoredTo: tallSelection,
            inside: screenBounds,
            allowsInsidePlacement: false
        )

        XCTAssertGreaterThanOrEqual(toolbar.minX, tallSelection.maxX)
        XCTAssertFalse(toolbar.intersects(tallSelection))
        XCTAssertTrue(screenBounds.insetBy(dx: 8, dy: 8).contains(toolbar))
    }

    func testFullScreenSelectionUsesScreenFrameNotVisibleFrame() {
        let screenBounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let maximizedSelection = NSRect(x: 0, y: 40, width: 800, height: 520)

        XCTAssertFalse(SelectionToolbarState.isFullScreenSelection(maximizedSelection, in: screenBounds))
        XCTAssertTrue(SelectionToolbarState.isFullScreenSelection(screenBounds, in: screenBounds))
    }

    func testDraggedToolbarRectAppliesOffsetAndClampsInsideBounds() {
        let dragged = SelectionToolbarState.draggedToolbarRect(
            baseRect: NSRect(x: 100, y: 120, width: 220, height: 28),
            offset: NSSize(width: 500, height: -200),
            inside: NSRect(x: 0, y: 0, width: 480, height: 320)
        )

        XCTAssertEqual(dragged.maxX, 472, accuracy: 0.1)
        XCTAssertEqual(dragged.minY, 8, accuracy: 0.1)
    }

    func testMainToolbarDragHandleIconColorIsSofterThanToolIcons() throws {
        let color: NSColor = try XCTUnwrap(
            SelectionToolbarState.mainToolbarDragHandleIconColor(enabled: true)
                .usingColorSpace(NSColorSpace.deviceRGB)
        )
        let disabled = SelectionToolbarState.mainToolbarDragHandleIconColor(enabled: false)

        XCTAssertEqual(color.redComponent, 0.48, accuracy: 0.02)
        XCTAssertEqual(color.alphaComponent, 0.75, accuracy: 0.02)
        XCTAssertLessThan(color.alphaComponent, 1)
        XCTAssertEqual(disabled, NSColor.disabledControlTextColor)
    }

    func testSelectionMeasurementControlLayoutAddsThreeButtonsAfterSizeText() {
        let selection = NSRect(x: 120, y: 140, width: 300, height: 180)
        let layout = SelectionToolbarState.measurementControlLayout(
            anchoredTo: selection,
            textSize: NSSize(width: 82, height: 15),
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertGreaterThan(layout.panel.width, 82 + 18)
        XCTAssertEqual(layout.cornerStyle.width, 20)
        XCTAssertEqual(layout.aspectRatio.width, 20)
        XCTAssertEqual(layout.refresh.width, 20)
        XCTAssertEqual(layout.labelSeparator.width, 1)
        XCTAssertEqual(layout.refreshSeparator.width, 1)
        XCTAssertEqual(layout.cornerStyle.minX - layout.labelSeparator.maxX, 8)
        XCTAssertEqual(layout.aspectRatio.minX - layout.cornerStyle.maxX, 8)
        XCTAssertEqual(layout.refreshSeparator.minX - layout.aspectRatio.maxX, 8)
        XCTAssertEqual(layout.refresh.minX - layout.refreshSeparator.maxX, 8)
    }

    func testSelectionMeasurementControlHitTestingFindsEachButton() {
        let selection = NSRect(x: 120, y: 140, width: 300, height: 180)
        let layout = SelectionToolbarState.measurementControlLayout(
            anchoredTo: selection,
            textSize: NSSize(width: 82, height: 15),
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(
            SelectionToolbarState.measurementControl(
                at: NSPoint(x: layout.cornerStyle.midX, y: layout.cornerStyle.midY),
                in: layout
            ),
            .cornerStyle
        )
        XCTAssertEqual(
            SelectionToolbarState.measurementControl(
                at: NSPoint(x: layout.aspectRatio.midX, y: layout.aspectRatio.midY),
                in: layout
            ),
            .aspectRatioLock
        )
        XCTAssertEqual(
            SelectionToolbarState.measurementControl(
                at: NSPoint(x: layout.refresh.midX, y: layout.refresh.midY),
                in: layout
            ),
            .refresh
        )
    }

    func testLockedAspectRatioSelectionResizeKeepsStartRatioFromCorner() {
        let start = NSRect(x: 100, y: 100, width: 200, height: 100)
        let resized = SelectionToolbarState.resizedSelectionRect(
            from: start,
            handle: .bottomRight,
            point: NSPoint(x: 360, y: 40),
            lockAspectRatio: true
        )

        XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.01)
        XCTAssertEqual(resized.minX, 100, accuracy: 0.1)
        XCTAssertEqual(resized.maxY, 200, accuracy: 0.1)
    }

    func testLockedAspectRatioSelectionResizeCanFlipPastAnchor() {
        let start = NSRect(x: 100, y: 100, width: 200, height: 100)
        let resized = SelectionToolbarState.resizedSelectionRect(
            from: start,
            handle: .bottomRight,
            point: NSPoint(x: 60, y: 240),
            lockAspectRatio: true
        )

        XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.01)
        XCTAssertEqual(resized.maxX, 100, accuracy: 0.1)
        XCTAssertEqual(resized.minY, 200, accuracy: 0.1)
        XCTAssertGreaterThan(resized.width, 8)
        XCTAssertGreaterThan(resized.height, 8)
    }

    func testPopoverRectPrefersBelowAnchorWithoutCoveringIt() {
        let anchor = NSRect(x: 600, y: 420, width: 12, height: 12)
        let popover = SelectionToolbarState.popoverRect(
            size: NSSize(width: 240, height: 180),
            anchoredTo: anchor,
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertLessThanOrEqual(popover.maxY, anchor.minY - 8)
        XCTAssertFalse(popover.intersects(anchor))
    }

    func testPopoverRectFlipsAboveAnchorNearBottomAndStaysInsideBounds() {
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let anchor = NSRect(x: 600, y: 12, width: 12, height: 12)
        let popover = SelectionToolbarState.popoverRect(
            size: NSSize(width: 240, height: 180),
            anchoredTo: anchor,
            inside: bounds
        )

        XCTAssertGreaterThanOrEqual(popover.minY, anchor.maxY + 8)
        XCTAssertTrue(bounds.insetBy(dx: 8, dy: 8).contains(popover))
    }

    func testLocalAnnotationRectAllowsDrawingOutsideSelection() {
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        let overlayRect = NSRect(x: 50, y: 80, width: 300, height: 180)

        XCTAssertEqual(
            SelectionToolbarState.localAnnotationRect(fromOverlayRect: overlayRect, selectionRect: selection),
            NSRect(x: -50, y: -20, width: 300, height: 180)
        )
    }

    func testLocalAnnotationRectKeepsOverlayPositionWhenSelectionMoves() {
        let movedSelection = NSRect(x: 160, y: 130, width: 200, height: 120)
        let existingOverlayRect = NSRect(x: 130, y: 140, width: 80, height: 50)

        XCTAssertEqual(
            SelectionToolbarState.localAnnotationRect(fromOverlayRect: existingOverlayRect, selectionRect: movedSelection),
            NSRect(x: -30, y: 10, width: 80, height: 50)
        )
    }

    func testLocalAnnotationRectsPreserveOverlayPositionsWhenSelectionMoves() {
        let movedSelection = NSRect(x: 160, y: 130, width: 200, height: 120)
        let existingOverlayRects = [
            NSRect(x: 130, y: 140, width: 80, height: 50),
            NSRect(x: 220, y: 180, width: 40, height: 30),
        ]

        XCTAssertEqual(
            SelectionToolbarState.localAnnotationRectsPreservingOverlayPositions(
                existingOverlayRects,
                selectionRect: movedSelection
            ),
            [
                NSRect(x: -30, y: 10, width: 80, height: 50),
                NSRect(x: 60, y: 50, width: 40, height: 30),
            ]
        )
    }

    func testShapeBorderHitIgnoresInteriorSoNestedDrawingCanStart() {
        let rect = NSRect(x: 100, y: 100, width: 120, height: 80)

        XCTAssertFalse(
            SelectionToolbarState.shapeBorderContains(
                point: NSPoint(x: rect.midX, y: rect.midY),
                rect: rect,
                kind: .rectangle,
                cornerRadius: 0
            )
        )
    }

    func testShapeBorderHitAcceptsPointNearBorderForMoving() {
        let rect = NSRect(x: 100, y: 100, width: 120, height: 80)

        XCTAssertTrue(
            SelectionToolbarState.shapeBorderContains(
                point: NSPoint(x: rect.minX + 2, y: rect.midY),
                rect: rect,
                kind: .rectangle,
                cornerRadius: 0
            )
        )
    }

    func testAnnotationBorderCursorUsesMoveCursorOverSelectionCrosshair() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true
            ),
            .move
        )
    }

    func testResizeHandleCursorWinsOverAnnotationBorder() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: .left,
                selectionResizeHandle: nil,
                isAnnotationBorder: true,
                isInsideSelection: true
            ),
            .resizeLeftRight
        )
    }

    func testResizeHandleCursorDirections() {
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .left), .resizeLeftRight)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .right), .resizeLeftRight)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .top), .resizeUpDown)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .bottom), .resizeUpDown)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .topLeft), .resizeTopLeft)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .topRight), .resizeTopRight)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .bottomLeft), .resizeBottomLeft)
        XCTAssertEqual(SelectionToolbarState.overlayCursorStyle(for: .bottomRight), .resizeBottomRight)
    }

    func testSelectionResizeHandleCursorWinsOverSelectionCrosshair() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: nil,
                selectionResizeHandle: .right,
                isAnnotationBorder: false,
                isInsideSelection: true
            ),
            .resizeLeftRight
        )
    }

    func testShapeResizeHandleCursorWinsOverSelectionResizeHandle() {
        XCTAssertEqual(
            SelectionToolbarState.overlayCursorStyle(
                isSelecting: false,
                isToolbarOrPanelPoint: false,
                resizeHandle: .topLeft,
                selectionResizeHandle: .right,
                isAnnotationBorder: true,
                isInsideSelection: true
            ),
            .resizeTopLeft
        )
    }

    func testSelectionResizeHandleHitsEntireEdges() {
        let rect = NSRect(x: 100, y: 100, width: 220, height: 140)

        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.minX + 2, y: rect.midY), in: rect),
            .left
        )
        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.maxX - 2, y: rect.midY), in: rect),
            .right
        )
        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.midX, y: rect.maxY - 2), in: rect),
            .top
        )
        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.midX, y: rect.minY + 2), in: rect),
            .bottom
        )
    }

    func testSelectionResizeHandleAcceptsVisibleHandleOutset() {
        let rect = NSRect(x: 100, y: 100, width: 220, height: 140)

        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.maxX + 10, y: rect.midY), in: rect),
            .right
        )
        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.midX, y: rect.maxY + 10), in: rect),
            .top
        )
    }

    func testSelectionResizeHandleHitsCornersAndIgnoresInterior() {
        let rect = NSRect(x: 100, y: 100, width: 220, height: 140)

        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.minX + 2, y: rect.maxY - 2), in: rect),
            .topLeft
        )
        XCTAssertEqual(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.maxX - 2, y: rect.minY + 2), in: rect),
            .bottomRight
        )
        XCTAssertNil(
            SelectionToolbarState.selectionResizeHandle(at: NSPoint(x: rect.midX, y: rect.midY), in: rect)
        )
    }

    func testSelectionCornerRadiusDefaultsToRounded() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }

        XCTAssertEqual(window.test_selectionCornerRadius, 10)
    }

    func testClickingCornerStyleMeasurementControlTogglesSelectionCornerRadius() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 220, height: 140))

        guard let point = window.test_measurementControlPoint(.cornerStyle) else {
            return XCTFail("Expected corner style control")
        }
        window.test_mouseDown(at: point)

        XCTAssertEqual(window.test_selectionCornerRadius, 0)

        window.test_mouseDown(at: point)

        XCTAssertEqual(window.test_selectionCornerRadius, 10)
    }

    func testRoundedSelectionHidesCornerHandlesAndSquareSelectionShowsThem() {
        let rect = NSRect(x: 100, y: 120, width: 220, height: 140)

        XCTAssertEqual(
            SelectionToolbarState.selectionHandlePoints(in: rect, cornerRadius: 0),
            [
                NSPoint(x: rect.minX, y: rect.maxY),
                NSPoint(x: rect.midX, y: rect.maxY),
                NSPoint(x: rect.maxX, y: rect.maxY),
                NSPoint(x: rect.minX, y: rect.midY),
                NSPoint(x: rect.maxX, y: rect.midY),
                NSPoint(x: rect.minX, y: rect.minY),
                NSPoint(x: rect.midX, y: rect.minY),
                NSPoint(x: rect.maxX, y: rect.minY),
            ]
        )

        XCTAssertEqual(
            SelectionToolbarState.selectionHandlePoints(in: rect, cornerRadius: 8),
            [
                NSPoint(x: rect.midX, y: rect.maxY),
                NSPoint(x: rect.minX, y: rect.midY),
                NSPoint(x: rect.maxX, y: rect.midY),
                NSPoint(x: rect.midX, y: rect.minY),
            ]
        )
    }

    func testSelectionMeasurementControlSvgResourcesAreBundled() {
        let resourceNames: [String] = [
            "border-corner-rounded",
            "border-corner-square",
            "aspect-ratio",
            "aspect-ratio-fill",
            "refresh",
            "reset2",
        ]
        resourceNames.forEach { name in
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "svg"), "\(name).svg should be bundled")
        }
    }

    func testClickingAspectRatioMeasurementControlLocksSelectionResizeRatio() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 100))

        guard let aspectPoint = window.test_measurementControlPoint(.aspectRatioLock) else {
            return XCTFail("Expected aspect ratio control")
        }
        window.test_mouseDown(at: aspectPoint)

        XCTAssertTrue(window.test_isSelectionAspectRatioLocked)

        window.test_mouseDown(at: NSPoint(x: 300, y: 100))
        window.test_mouseDragged(to: NSPoint(x: 360, y: 40))
        window.test_mouseUp(at: NSPoint(x: 360, y: 40))

        guard let resized = window.test_lockedSelectionRect else {
            return XCTFail("Expected locked selection")
        }
        XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.01)
    }

    func testLockedAspectRatioSelectionDragCanContinueAfterCrossingMinimumSize() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setLockedSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 100))

        guard let aspectPoint = window.test_measurementControlPoint(.aspectRatioLock) else {
            return XCTFail("Expected aspect ratio control")
        }
        window.test_mouseDown(at: aspectPoint)

        window.test_mouseDown(at: NSPoint(x: 300, y: 100))
        window.test_mouseDragged(to: NSPoint(x: 60, y: 240))
        window.test_mouseUp(at: NSPoint(x: 60, y: 240))

        guard let resized = window.test_lockedSelectionRect else {
            return XCTFail("Expected locked selection")
        }
        XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.01)
        XCTAssertEqual(resized.maxX, 100, accuracy: 0.1)
        XCTAssertEqual(resized.minY, 200, accuracy: 0.1)
    }

    func testClickingRefreshMeasurementControlKeepsSelectionAndRequestsRefresh() {
        let expectation = expectation(description: "refresh requested")
        let window = SelectionOverlayWindow(
            backgroundImage: nil,
            refreshHandler: {
                expectation.fulfill()
                return nil
            },
            selectionHandler: { _ in }
        )
        let selection = NSRect(x: 100, y: 100, width: 220, height: 140)
        window.test_setLockedSelectionRect(selection)

        guard let point = window.test_measurementControlPoint(.refresh) else {
            return XCTFail("Expected refresh control")
        }
        window.test_mouseDown(at: point)

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
    }

    func testCaptureRefreshIgnoresSniporyAsRefreshTarget() {
        XCTAssertFalse(
            CaptureCoordinator.shouldRefreshTargetApplication(
                targetBundleIdentifier: "com.snipory.v2.mac",
                mainBundleIdentifier: "com.snipory.v2.mac"
            )
        )
        XCTAssertFalse(
            CaptureCoordinator.shouldRefreshTargetApplication(
                targetBundleIdentifier: nil,
                mainBundleIdentifier: "com.snipory.v2.mac"
            )
        )
        XCTAssertTrue(
            CaptureCoordinator.shouldRefreshTargetApplication(
                targetBundleIdentifier: "com.apple.Safari",
                mainBundleIdentifier: "com.snipory.v2.mac"
            )
        )
    }

    func testCaptureRefreshIgnoresXxsnapAsRefreshTarget() {
        XCTAssertFalse(
            CaptureCoordinator.shouldRefreshTargetApplication(
                targetBundleIdentifier: "com.xxsnap.mac",
                mainBundleIdentifier: "com.xxsnap.mac"
            )
        )
        XCTAssertTrue(
            CaptureCoordinator.shouldRefreshTargetApplication(
                targetBundleIdentifier: "com.apple.finder",
                mainBundleIdentifier: "com.xxsnap.mac"
            )
        )
    }

    func testAnnotationMoveMouseDownWinsOverSelectionResize() {
        XCTAssertEqual(
            SelectionToolbarState.annotatingMouseDownTarget(
                shapeResizeHandle: nil,
                isAnnotationBorder: true,
                selectionResizeHandle: .left,
                selectionMoveEligible: true
            ),
            .annotationMove
        )
    }

    func testShapeResizeMouseDownWinsOverAnnotationMove() {
        XCTAssertEqual(
            SelectionToolbarState.annotatingMouseDownTarget(
                shapeResizeHandle: .topLeft,
                isAnnotationBorder: true,
                selectionResizeHandle: .left,
                selectionMoveEligible: true
            ),
            .shapeResize(.topLeft)
        )
    }

    func testSelectionResizeMouseDownWinsOverSelectionMove() {
        XCTAssertEqual(
            SelectionToolbarState.annotatingMouseDownTarget(
                shapeResizeHandle: nil,
                isAnnotationBorder: false,
                selectionResizeHandle: .left,
                selectionMoveEligible: true
            ),
            .selectionResize(.left)
        )
    }

    func testSelectionMoveMouseDownStartsFromColorSamplerInterior() {
        XCTAssertEqual(
            SelectionToolbarState.annotatingMouseDownTarget(
                shapeResizeHandle: nil,
                isAnnotationBorder: false,
                selectionResizeHandle: nil,
                selectionMoveEligible: true
            ),
            .selectionMove
        )
    }

    func testSelectionMoveEligibilityRequiresPlainInteriorNonFullscreenSelection() {
        let selection = NSRect(x: 80, y: 90, width: 240, height: 160)
        let screenBounds = NSRect(x: 0, y: 0, width: 640, height: 480)

        XCTAssertTrue(
            SelectionToolbarState.shouldStartSelectionMove(
                isShapeToolActive: false,
                pointer: NSPoint(x: 160, y: 140),
                selectionRect: selection,
                screenBounds: screenBounds,
                selectionResizeHandle: nil
            )
        )
        XCTAssertFalse(
            SelectionToolbarState.shouldStartSelectionMove(
                isShapeToolActive: true,
                pointer: NSPoint(x: 160, y: 140),
                selectionRect: selection,
                screenBounds: screenBounds,
                selectionResizeHandle: nil
            )
        )
        XCTAssertFalse(
            SelectionToolbarState.shouldStartSelectionMove(
                isShapeToolActive: false,
                pointer: NSPoint(x: 82, y: 140),
                selectionRect: selection,
                screenBounds: screenBounds,
                selectionResizeHandle: .left
            )
        )
        XCTAssertFalse(
            SelectionToolbarState.shouldStartSelectionMove(
                isShapeToolActive: false,
                pointer: NSPoint(x: 320, y: 240),
                selectionRect: screenBounds,
                screenBounds: screenBounds,
                selectionResizeHandle: nil
            )
        )
    }

    func testMovedSelectionRectIsClampedInsideScreenBounds() {
        let moved = SelectionToolbarState.movedSelectionRect(
            startRect: NSRect(x: 80, y: 90, width: 200, height: 120),
            pointer: NSPoint(x: 720, y: 520),
            pointerOffset: NSPoint(x: 10, y: 10),
            inside: NSRect(x: 0, y: 0, width: 640, height: 480)
        )

        XCTAssertEqual(moved.origin.x, 440, accuracy: 0.1)
        XCTAssertEqual(moved.origin.y, 360, accuracy: 0.1)
        XCTAssertEqual(moved.width, 200, accuracy: 0.1)
        XCTAssertEqual(moved.height, 120, accuracy: 0.1)
    }

    func testToolbarTooltipTitlesAreAvailableForPrimaryButtons() {
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "rectangle"), "形状")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "marker"), "荧光笔")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "mosaicRectangle"), "矩形模糊")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "mosaicBlur"), "高斯")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "mosaicPixel"), "马赛克")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "save"), "保存")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "copy"), "复制到剪切板")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "pin"), "贴图")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "scroll"), "滚动截图")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "eyedropper"), "取色 ｜ 测距")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "eraserPoint"), "橡皮擦")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "eraserRectangle"), "矩形擦除")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "eraserClearAll"), "清除所有")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "cornerStyle"), "直角/圆角切换")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "aspectRatioLockedOn"), "锁定长宽比(开)")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "aspectRatioLockedOff"), "锁定长宽比(关)")
        XCTAssertEqual(SelectionToolbarState.tooltipTitle(for: "refreshCapture"), "刷新截图")
        XCTAssertNil(SelectionToolbarState.tooltipTitle(for: "ocr"))
        XCTAssertNil(SelectionToolbarState.tooltipTitle(for: "settings"))
    }

    func testPrimaryToolbarShortcutDescriptorsMatchApprovedMap() {
        let expected: [String: (key: String, modifiers: NSEvent.ModifierFlags)] = [
            "rectangle": ("s", []),
            "polyline": ("a", []),
            "pen": ("b", []),
            "marker": ("h", []),
            "eyedropper": ("p", []),
            "mosaic": ("m", []),
            "text": ("t", []),
            "number": ("n", []),
            "magnifier": ("g", []),
            "eraser": ("e", []),
            "undo": ("z", [.command]),
            "redo": ("z", [.command, .shift]),
            "cancel": ("\u{1b}", []),
            "pin": ("1", [.command]),
            "save": ("s", [.command]),
            "copy": ("c", [.command]),
            "finishEditing": ("\u{1b}", []),
        ]

        for (identifier, expectedShortcut) in expected {
            let shortcut = SelectionToolbarState.toolbarShortcut(for: identifier)
            XCTAssertEqual(shortcut?.key, expectedShortcut.key, identifier)
            XCTAssertEqual(shortcut?.modifiers, expectedShortcut.modifiers, identifier)
        }
        XCTAssertNil(SelectionToolbarState.toolbarShortcut(for: "scroll"))
    }

    func testToolbarShortcutMatchingIsCaseInsensitiveAndRequiresExactRelevantModifiers() throws {
        let shape = try XCTUnwrap(SelectionToolbarState.toolbarShortcut(for: "rectangle"))
        XCTAssertTrue(shape.matches(charactersIgnoringModifiers: "s", modifierFlags: []))
        XCTAssertTrue(shape.matches(charactersIgnoringModifiers: "S", modifierFlags: [.capsLock]))
        XCTAssertTrue(shape.matches(charactersIgnoringModifiers: "S", modifierFlags: [.shift]))
        XCTAssertTrue(shape.matches(charactersIgnoringModifiers: "S", modifierFlags: [.shift, .capsLock]))
        XCTAssertFalse(shape.matches(charactersIgnoringModifiers: "s", modifierFlags: [.command]))
        XCTAssertFalse(shape.matches(charactersIgnoringModifiers: "s", modifierFlags: [.control]))
        XCTAssertFalse(shape.matches(charactersIgnoringModifiers: "s", modifierFlags: [.option]))

        let save = try XCTUnwrap(SelectionToolbarState.toolbarShortcut(for: "save"))
        XCTAssertTrue(save.matches(charactersIgnoringModifiers: "S", modifierFlags: [.command]))
        XCTAssertFalse(save.matches(charactersIgnoringModifiers: "S", modifierFlags: [.command, .shift]))

        let redo = try XCTUnwrap(SelectionToolbarState.toolbarShortcut(for: "redo"))
        XCTAssertTrue(redo.matches(charactersIgnoringModifiers: "Z", modifierFlags: [.command, .shift, .capsLock]))
        XCTAssertFalse(redo.matches(charactersIgnoringModifiers: "z", modifierFlags: [.command]))
        XCTAssertFalse(redo.matches(charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift, .option]))
    }

    func testToolbarShortcutDisplayMetadataSupportsPlainCommandRedoAndEscape() throws {
        let shape = try XCTUnwrap(SelectionToolbarState.toolbarShortcut(for: "rectangle"))
        XCTAssertNil(shape.iconName)
        XCTAssertEqual(shape.displayText, "S")

        let pin = try XCTUnwrap(SelectionToolbarState.toolbarShortcut(for: "pin"))
        XCTAssertEqual(pin.iconName, "command")
        XCTAssertEqual(pin.displayText, "1")

        let redo = try XCTUnwrap(SelectionToolbarState.toolbarShortcut(for: "redo"))
        XCTAssertEqual(redo.iconName, "command")
        XCTAssertEqual(redo.displayText, "⇧Z")

        let cancel = try XCTUnwrap(SelectionToolbarState.toolbarShortcut(for: "cancel"))
        XCTAssertNil(cancel.iconName)
        XCTAssertEqual(cancel.displayText, "ESC")
    }

    func testCommandTooltipIconRendersVisibleWhitePixels() throws {
        let image = try XCTUnwrap(SelectionToolbarState.tooltipShortcutIconImage(named: "command", tint: .white, size: 12))
        let whitePixels = try matchingPixelCount(in: image, rect: NSRect(origin: .zero, size: image.size)) { pixel in
            pixel.red == 255 && pixel.green == 255 && pixel.blue == 255 && pixel.alpha > 180
        }
        XCTAssertGreaterThan(whitePixels, 12)
    }

    func testTooltipRectStaysInsideVisibleBounds() {
        let anchor = NSRect(x: 760, y: 560, width: 22, height: 22)
        let tooltip = SelectionToolbarState.tooltipRect(
            textSize: NSSize(width: 100, height: 18),
            anchoredTo: anchor,
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertTrue(NSRect(x: 0, y: 0, width: 800, height: 600).insetBy(dx: 8, dy: 8).contains(tooltip))
        XCTAssertFalse(tooltip.intersects(anchor))
    }

    func testColorSamplerOnlyShowsInsideSelectionWhenNoToolIsActive() {
        let selection = NSRect(x: 100, y: 100, width: 300, height: 200)

        XCTAssertTrue(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: false,
                hasAnnotations: false,
                pointer: NSPoint(x: 180, y: 180),
                selectionRect: selection
            )
        )

        XCTAssertFalse(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: true,
                hasAnnotations: false,
                pointer: NSPoint(x: 180, y: 180),
                selectionRect: selection
            )
        )

        XCTAssertFalse(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: false,
                hasAnnotations: false,
                pointer: NSPoint(x: 90, y: 180),
                selectionRect: selection
            )
        )
    }

    func testColorSamplerAcceptsPointerOnSelectionBorder() {
        let selection = NSRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertTrue(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: false,
                hasAnnotations: false,
                pointer: NSPoint(x: selection.maxX, y: selection.midY),
                selectionRect: selection
            )
        )
    }

    func testWheelZoomExpandsShrinksAndClampsLockedSelection() {
        let start = NSRect(x: 110, y: 90, width: 140, height: 90)
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        let anchor = NSPoint(x: start.midX, y: start.midY)

        let expanded = SelectionToolbarState.wheelZoomedSelectionRect(
            from: start,
            anchor: anchor,
            deltaY: 4,
            inside: bounds,
            minimumSize: 64
        )
        XCTAssertGreaterThan(expanded.width, start.width)
        XCTAssertGreaterThan(expanded.height, start.height)
        XCTAssertLessThan(expanded.width - start.width, 14)

        let shrunk = SelectionToolbarState.wheelZoomedSelectionRect(
            from: start,
            anchor: anchor,
            deltaY: -8,
            inside: bounds,
            minimumSize: 64
        )
        XCTAssertGreaterThanOrEqual(shrunk.width, 64)
        XCTAssertGreaterThanOrEqual(shrunk.height, 64)

        let hugeBounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        let nearlyFull = SelectionToolbarState.wheelZoomedSelectionRect(
            from: NSRect(x: 80, y: 70, width: 90, height: 80),
            anchor: NSPoint(x: 120, y: 110),
            deltaY: 80,
            inside: hugeBounds,
            minimumSize: 64
        )
        XCTAssertTrue(hugeBounds.contains(nearlyFull))
    }

    func testWheelZoomCanReachFullBoundsAfterRepeatedExpansion() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        var rect = NSRect(x: 100, y: 110, width: 200, height: 80)

        for _ in 0..<80 {
            rect = SelectionToolbarState.wheelZoomedSelectionRect(
                from: rect,
                anchor: NSPoint(x: rect.midX, y: rect.midY),
                deltaY: 8,
                inside: bounds,
                minimumSize: 64
            )
        }

        XCTAssertEqual(rect.minX, bounds.minX, accuracy: 0.5)
        XCTAssertEqual(rect.minY, bounds.minY, accuracy: 0.5)
        XCTAssertEqual(rect.maxX, bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(rect.maxY, bounds.maxY, accuracy: 0.5)
    }

    func testWheelZoomAppliesWhileShapeToolIsActive() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 80, width: 160, height: 120)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)

        XCTAssertTrue(window.test_handleScrollWheel(
            at: NSPoint(x: selection.midX, y: selection.midY),
            deltaY: 8
        ))
        XCTAssertNotEqual(window.test_lockedSelectionRect, selection)
    }

    func testWheelZoomAnimatesTowardTargetSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 80, width: 160, height: 120)
        let pointer = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)
        window.test_activateShapeTool(.marker)

        let target = SelectionToolbarState.wheelZoomedSelectionRect(
            from: selection,
            anchor: pointer,
            deltaY: 8,
            inside: window.test_overlayBounds,
            minimumSize: 64
        )

        XCTAssertTrue(window.test_handleScrollWheel(at: pointer, deltaY: 8))

        guard let immediate = window.test_lockedSelectionRect else {
            return XCTFail("Expected animated selection")
        }
        XCTAssertNotEqual(immediate, target)
        XCTAssertGreaterThan(immediate.width, selection.width)
        XCTAssertLessThan(immediate.width, target.width)

        window.test_completeSelectionWheelAnimation()
        XCTAssertEqual(window.test_lockedSelectionRect?.minX ?? 0, target.minX, accuracy: 0.5)
        XCTAssertEqual(window.test_lockedSelectionRect?.minY ?? 0, target.minY, accuracy: 0.5)
        XCTAssertEqual(window.test_lockedSelectionRect?.width ?? 0, target.width, accuracy: 0.5)
        XCTAssertEqual(window.test_lockedSelectionRect?.height ?? 0, target.height, accuracy: 0.5)
    }

    func testWheelZoomPreservesMosaicStrokeOverlayPosition() throws {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 80, width: 160, height: 120)
        let overlayPoint = NSPoint(x: 150, y: 130)
        let localPoint = NSPoint(x: overlayPoint.x - selection.minX, y: overlayPoint.y - selection.minY)
        let annotation = CaptureAnnotation(
            kind: .mosaicStroke,
            rect: NSRect(x: localPoint.x, y: localPoint.y, width: 1, height: 1),
            style: CaptureAnnotationStyle(),
            mosaicStroke: CaptureMosaicStroke(points: [localPoint]),
            mosaicRedaction: CaptureMosaicRedaction(type: .pixelMosaic, value: 8)
        )
        window.test_setLockedSelectionRect(selection)
        window.test_setAnnotations([annotation])

        XCTAssertTrue(window.test_handleScrollWheel(at: NSPoint(x: selection.midX, y: selection.midY), deltaY: 8))
        window.test_completeSelectionWheelAnimation()

        let resizedSelection = try XCTUnwrap(window.test_lockedSelectionRect)
        let resizedStroke = try XCTUnwrap(window.test_mosaicStroke(at: 0))
        let resizedPoint = try XCTUnwrap(resizedStroke.points.first)
        XCTAssertEqual(resizedSelection.minX + resizedPoint.x, overlayPoint.x, accuracy: 0.5)
        XCTAssertEqual(resizedSelection.minY + resizedPoint.y, overlayPoint.y, accuracy: 0.5)
    }

    func testWheelZoomUsesSelectionCenterWhenPointerIsOutsideSelection() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 120, y: 120, width: 160, height: 120)
        window.test_setLockedSelectionRect(selection)

        XCTAssertTrue(window.test_handleScrollWheel(
            at: NSPoint(x: selection.maxX + 24, y: selection.midY),
            deltaY: 6
        ))

        guard let resized = window.test_lockedSelectionRect else {
            return XCTFail("Expected resized selection")
        }

        XCTAssertEqual(resized.midX, selection.midX, accuracy: 0.5)
        XCTAssertEqual(resized.midY, selection.midY, accuracy: 0.5)
    }

    func testWheelZoomDoesNotApplyOverToolbarButtons() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)

        guard let point = window.test_mainToolbarButtonPoint(for: .mosaic) else {
            return XCTFail("Expected toolbar button")
        }

        XCTAssertFalse(window.test_handleScrollWheel(at: point, deltaY: 8))
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
    }

    func testTrackpadMagnifyUsesSameSelectionZoomBehaviorAsWheel() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 80, width: 160, height: 120)
        let anchor = NSPoint(x: selection.midX, y: selection.midY)
        window.test_setLockedSelectionRect(selection)

        XCTAssertTrue(window.test_handleMagnify(at: anchor, magnification: 0.08))

        guard let immediate = window.test_lockedSelectionRect else {
            return XCTFail("Expected animated selection")
        }
        XCTAssertGreaterThan(immediate.width, selection.width)
        XCTAssertGreaterThan(immediate.height, selection.height)

        window.test_completeSelectionWheelAnimation()

        guard let magnified = window.test_lockedSelectionRect else {
            return XCTFail("Expected final magnified selection")
        }
        XCTAssertGreaterThan(magnified.width, immediate.width)
        XCTAssertGreaterThan(magnified.height, immediate.height)
    }

    func testTrackpadMagnifyDoesNotApplyOverToolbarButtons() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let selection = NSRect(x: 100, y: 100, width: 200, height: 120)
        window.test_setLockedSelectionRect(selection)

        guard let point = window.test_mainToolbarButtonPoint(for: .mosaic) else {
            return XCTFail("Expected toolbar button")
        }

        XCTAssertFalse(window.test_handleMagnify(at: point, magnification: 0.08))
        XCTAssertEqual(window.test_lockedSelectionRect, selection)
    }

    func testInitialHoverImmediatelyTracksWindowRegion() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let candidate = WindowSelectionCandidate(
            id: 1,
            ownerPID: 10,
            layer: 0,
            alpha: 1,
            bounds: NSRect(x: 36, y: 28, width: 240, height: 140),
            name: "app"
        )
        window.test_setWindowSelectionCandidates([
            candidate
        ])

        window.test_mouseMoved(to: NSPoint(x: 90, y: 78))

        XCTAssertEqual(window.test_currentSelectionRect, candidate.bounds)
    }

    func testInitialHoverLocksCurrentWindowRegionOnClickAndStopsTracking() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let first = WindowSelectionCandidate(
            id: 1,
            ownerPID: 10,
            layer: 0,
            alpha: 1,
            bounds: NSRect(x: 20, y: 20, width: 140, height: 120),
            name: "first"
        )
        let second = WindowSelectionCandidate(
            id: 2,
            ownerPID: 11,
            layer: 0,
            alpha: 1,
            bounds: NSRect(x: 190, y: 20, width: 140, height: 120),
            name: "second"
        )
        window.test_setWindowSelectionCandidates([
            first,
            second,
        ])

        window.test_mouseMoved(to: NSPoint(x: 88, y: 110))
        guard let lockedTarget = window.test_currentSelectionRect else {
            return XCTFail("Expected live window region before click")
        }
        XCTAssertEqual(lockedTarget, first.bounds)

        window.test_mouseDown(at: NSPoint(x: 88, y: 110))
        XCTAssertNil(window.test_lockedSelectionRect)
        XCTAssertEqual(window.test_currentSelectionRect, lockedTarget)

        window.test_mouseUp(at: NSPoint(x: 88, y: 110))
        XCTAssertEqual(window.test_lockedSelectionRect, lockedTarget)

        window.test_mouseMoved(to: NSPoint(x: 240, y: 66))
        XCTAssertEqual(window.test_lockedSelectionRect, lockedTarget)
        XCTAssertEqual(window.test_currentSelectionRect, lockedTarget)
    }

    func testDraggingFromInitialHoverCreatesManualSelectionInsteadOfLockingWindow() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let candidate = WindowSelectionCandidate(
            id: 1,
            ownerPID: 10,
            layer: 0,
            alpha: 1,
            bounds: NSRect(x: 20, y: 20, width: 180, height: 140),
            name: "app"
        )
        window.test_setWindowSelectionCandidates([
            candidate
        ])

        let start = NSPoint(x: 80, y: 90)
        let end = NSPoint(x: 260, y: 210)
        let expectedManualSelection = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        window.test_mouseMoved(to: start)
        XCTAssertEqual(window.test_currentSelectionRect, candidate.bounds)

        window.test_mouseDown(at: start)
        window.test_mouseDragged(to: end)
        XCTAssertEqual(window.test_currentSelectionRect, expectedManualSelection)

        window.test_mouseUp(at: end)
        XCTAssertEqual(window.test_lockedSelectionRect, expectedManualSelection)
    }

    func testInitialHoverWindowTrackingStaysResponsiveAcrossMouseMoves() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        window.test_setWindowSelectionCandidates([
            WindowSelectionCandidate(
                id: 1,
                ownerPID: 10,
                layer: 0,
                alpha: 1,
                bounds: NSRect(x: 80, y: 90, width: 1100, height: 670),
                name: "large app"
            )
        ])

        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<60 {
            window.test_mouseMoved(to: NSPoint(
                x: 180 + CGFloat(index % 20) * 18,
                y: 160 + CGFloat(index % 12) * 22
            ))
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 0.20)
    }

    func testInitialHoverTracksSystemBarRegions() {
        let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
        let menubar = WindowSelectionCandidate(
            id: 1,
            ownerPID: 0,
            layer: 24,
            alpha: 1,
            bounds: NSRect(x: 0, y: 563, width: 900, height: 37),
            name: "Menubar"
        )
        let dock = WindowSelectionCandidate(
            id: 2,
            ownerPID: 0,
            layer: 20,
            alpha: 1,
            bounds: NSRect(x: 0, y: 0, width: 900, height: 48),
            name: "Dock"
        )
        window.test_setWindowSelectionCandidates([
            menubar,
            dock,
        ])

        window.test_mouseMoved(to: NSPoint(x: 420, y: 580))
        XCTAssertEqual(window.test_currentSelectionRect, menubar.bounds)

        window.test_mouseMoved(to: NSPoint(x: 420, y: 24))
        XCTAssertEqual(window.test_currentSelectionRect, dock.bounds)
    }

    func testColorSamplerHidesAfterUserHasAnnotations() {
        let selection = NSRect(x: 0, y: 0, width: 400, height: 300)

        XCTAssertFalse(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: false,
                hasAnnotations: true,
                pointer: NSPoint(x: 120, y: 140),
                selectionRect: selection
            )
        )
    }

    func testColorSamplerRectFollowsPointerAndStaysInVisibleBounds() {
        let visibleBounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let sampler = SelectionToolbarState.colorSamplerRect(
            size: NSSize(width: 168, height: 122),
            pointer: NSPoint(x: 790, y: 30),
            inside: visibleBounds
        )

        XCTAssertTrue(visibleBounds.insetBy(dx: 8, dy: 8).contains(sampler))
        XCTAssertLessThan(sampler.minX, 790)
        XCTAssertGreaterThan(sampler.minY, 30)
    }

    func testColorSamplerRectPrefersPointerLowerRightWhenSpaceAllows() {
        let sampler = SelectionToolbarState.colorSamplerRect(
            size: NSSize(width: 168, height: 122),
            pointer: NSPoint(x: 120, y: 360),
            inside: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(sampler.origin.x, 134)
        XCTAssertEqual(sampler.origin.y, 224)
    }

    func testColorSamplerCanUseInProgressSelectionRect() {
        let currentSelection = NSRect(x: 100, y: 100, width: 120, height: 80)

        XCTAssertTrue(
            SelectionToolbarState.shouldShowColorSampler(
                isShapeToolActive: false,
                hasAnnotations: false,
                pointer: NSPoint(x: currentSelection.maxX, y: currentSelection.maxY),
                selectionRect: currentSelection
            )
        )
    }

    func testColorSamplerToggleModeSwitchesBetweenHexAndRgb() {
        XCTAssertEqual(
            SelectionToolbarState.toggledColorSamplerCopyMode(from: .hex),
            .rgb
        )

        XCTAssertEqual(
            SelectionToolbarState.toggledColorSamplerCopyMode(from: .rgb),
            .hex
        )
    }

    func testColorSamplerCopyHintUsesUppercaseCWithSpacingAndHexText() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintText, "按 C 复制HEX颜色值")
    }

    func testColorSamplerCopyHintFollowsCopyMode() {
        let l10n = L10n(language: .zhHans)

        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintText(for: .hex, l10n: l10n), "按 C 复制HEX颜色值")
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintText(for: .rgb, l10n: l10n), "按 C 复制RGB颜色值")
    }

    func testColorSamplerCopySuccessFeedbackText() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopySuccessText, "复制成功")
    }

    func testColorSamplerCopySuccessFeedbackTextColorIsGreen() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopySuccessTextColor, NSColor.systemGreen)
    }

    func testColorSamplerCopySuccessFeedbackDurationIsBrief() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopySuccessDuration, 1.2, accuracy: 0.01)
    }

    func testColorSamplerCopyShortcutUsesPlainCOnly() {
        XCTAssertTrue(
            SelectionToolbarState.isColorSamplerCopyShortcut(
                charactersIgnoringModifiers: "c",
                modifierFlags: []
            )
        )
        XCTAssertTrue(
            SelectionToolbarState.isColorSamplerCopyShortcut(
                charactersIgnoringModifiers: "C",
                modifierFlags: [.shift]
            )
        )
        XCTAssertFalse(
            SelectionToolbarState.isColorSamplerCopyShortcut(
                charactersIgnoringModifiers: "c",
                modifierFlags: [.command]
            )
        )
    }

    func testColorSamplerInfoTextColorsAreWhite() {
        XCTAssertEqual(SelectionToolbarState.colorSamplerCoordinateTextColor, NSColor.white)
        XCTAssertEqual(SelectionToolbarState.colorSamplerValueTextColor, NSColor.white)
        XCTAssertEqual(SelectionToolbarState.colorSamplerCopyHintTextColor, NSColor.white)
        XCTAssertEqual(SelectionToolbarState.colorSamplerSwitchHintTextColor, NSColor.white)
    }

    func testColorSamplerCopyHintIsPlacedBelowColorSwatch() {
        let infoRect = NSRect(x: 0, y: 0, width: 170, height: 76)
        let swatchRect = NSRect(x: 44, y: 36, width: 18, height: 18)
        let hintRect = SelectionToolbarState.colorSamplerCopyHintRect(
            textSize: NSSize(width: 92, height: 12),
            infoRect: infoRect,
            swatchRect: swatchRect
        )

        XCTAssertLessThanOrEqual(hintRect.maxY, swatchRect.minY - 4)
        XCTAssertEqual(hintRect.midX, infoRect.midX, accuracy: 0.5)
    }

    func testColorSamplerSwitchHintIsBelowCopyHintWithSpacing() {
        let infoRect = NSRect(x: 0, y: 0, width: 170, height: 76)
        let copyRect = NSRect(x: 38, y: 22, width: 94, height: 12)
        let switchRect = SelectionToolbarState.colorSamplerSwitchHintRect(
            textSize: NSSize(width: 106, height: 12),
            infoRect: infoRect,
            copyHintRect: copyRect
        )

        XCTAssertLessThanOrEqual(switchRect.maxY, copyRect.minY - 5)
        XCTAssertEqual(switchRect.midX, infoRect.midX, accuracy: 0.5)
    }

    func testColorSamplerReadsWhitePixelNextToGreenPixel() {
        let pixels: [UInt8] = [
            40, 180, 70, 255,
            255, 255, 255, 255,
        ]
        let cgImage = makeTestImage(
            width: 2,
            height: 1,
            pixels: pixels,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )

        let green = SelectionToolbarState.sampleColor(atPixelX: 0, y: 0, in: cgImage)
        let color = SelectionToolbarState.sampleColor(atPixelX: 1, y: 0, in: cgImage)

        XCTAssertEqual(green?.redComponent ?? -1, CGFloat(40) / 255, accuracy: 0.01)
        XCTAssertEqual(green?.greenComponent ?? -1, CGFloat(180) / 255, accuracy: 0.01)
        XCTAssertEqual(green?.blueComponent ?? -1, CGFloat(70) / 255, accuracy: 0.01)
        XCTAssertEqual(color?.redComponent ?? -1, 1, accuracy: 0.01)
        XCTAssertEqual(color?.greenComponent ?? -1, 1, accuracy: 0.01)
        XCTAssertEqual(color?.blueComponent ?? -1, 1, accuracy: 0.01)
    }

    func testColorSamplerReadsRawRgbWithoutColorSpaceShifting() {
        let pixels: [UInt8] = [
            255, 0, 26, 255,
        ]
        let cgImage = makeTestImage(
            width: 1,
            height: 1,
            pixels: pixels,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        let color = SelectionToolbarState.sampleColor(atPixelX: 0, y: 0, in: cgImage)

        XCTAssertEqual(color?.redComponent ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(color?.greenComponent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(color?.blueComponent ?? -1, CGFloat(26) / 255, accuracy: 0.001)
    }

    func testColorSamplerReadsAlphaFirstBitmapWithoutTurningRedYellow() {
        let pixels: [UInt8] = [
            26, 0, 255, 255,
        ]
        let cgImage = makeTestImage(
            width: 1,
            height: 1,
            pixels: pixels,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        let color = SelectionToolbarState.sampleColor(atPixelX: 0, y: 0, in: cgImage)

        XCTAssertEqual(color?.redComponent ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(color?.greenComponent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(color?.blueComponent ?? -1, CGFloat(26) / 255, accuracy: 0.001)
    }

    func testColorSamplerDoesNotColorMatchGenericRgbByteSamples() {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 4,
            bitsPerPixel: 32
        )!
        var pixel = [255, 0, 26, 255]
        bitmap.setPixel(&pixel, atX: 0, y: 0)

        let color = SelectionToolbarState.sampleColor(atPixelX: 0, y: 0, in: bitmap)

        XCTAssertEqual(color.map(SelectionToolbarState.colorSamplerHexString(for:)), "#FF001A")
    }

    func testColorSamplerConvertsDisplayP3PixelsToSrgb() {
        let pixels: [UInt8] = [
            45, 51, 234, 255,
        ]
        let cgImage = makeTestImage(
            width: 1,
            height: 1,
            pixels: pixels,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue,
            colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!
        )

        let color = SelectionToolbarState.sampleColor(atPixelX: 0, y: 0, in: cgImage)

        XCTAssertEqual(color?.redComponent ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(color?.greenComponent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(color?.blueComponent ?? -1, CGFloat(26) / 255, accuracy: 0.002)
        XCTAssertEqual(color.map(SelectionToolbarState.colorSamplerHexString(for:)), "#FF001A")
    }

    private func makeTestImage(
        width: Int,
        height: Int,
        pixels: [UInt8],
        bitmapInfo: UInt32,
        colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    ) -> CGImage {
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func fixedCanvasOverlayWindow(backgroundImage: NSImage, canvasSize: NSSize) -> SelectionOverlayWindow {
        let window = SelectionOverlayWindow(backgroundImage: backgroundImage) { _ in }
        let frame = NSRect(origin: .zero, size: canvasSize)
        window.setFrame(frame, display: false)
        window.contentView?.frame = frame
        return window
    }

    private func coordinateRedBlueImage(width: Int, height: Int) -> NSImage {
        let pixels = (0..<height).map { y in
            (0..<width).map { x in
                let leftHalf = x < width / 2
                let secondary = CGFloat((x * 13 + y * 29) % 180) / 255
                let tertiary = CGFloat((x * 31 + y * 17) % 120) / 255
                return leftHalf
                    ? NSColor(srgbRed: 1, green: secondary, blue: tertiary, alpha: 1)
                    : NSColor(srgbRed: tertiary, green: secondary, blue: 1, alpha: 1)
            }
        }
        return pixelImage(width: width, height: height, pixels: pixels)
    }

    private func makeTestImage(size: NSSize, colorAt: (NSPoint) -> NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                colorAt(NSPoint(x: x, y: y)).setFill()
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
        image.unlockFocus()
        return image
    }

    private func rowBandImage(width: Int, height: Int, colorAtRow: (Int) -> NSColor) -> NSImage {
        var bytes: [UInt8] = []
        for row in 0..<height {
            let color = colorAtRow(row).usingColorSpace(.sRGB) ?? colorAtRow(row)
            for _ in 0..<width {
                bytes.append(UInt8(round(color.redComponent * 255)))
                bytes.append(UInt8(round(color.greenComponent * 255)))
                bytes.append(UInt8(round(color.blueComponent * 255)))
                bytes.append(UInt8(round(color.alphaComponent * 255)))
            }
        }
        let cgImage = makeTestImage(
            width: width,
            height: height,
            pixels: bytes,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func checkerboardImage(size: NSSize) -> NSImage {
        checkerboardImage(size: size, squareSize: 8)
    }

    private func checkerboardImage(size: NSSize, squareSize: Int) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        for x in stride(from: 0, to: Int(size.width), by: squareSize) {
            for y in stride(from: 0, to: Int(size.height), by: squareSize) {
                let isDark = ((x / squareSize) + (y / squareSize)).isMultiple(of: 2)
                (isDark ? NSColor.black : NSColor.white).setFill()
                NSRect(x: x, y: y, width: squareSize, height: squareSize).fill()
            }
        }
        image.unlockFocus()
        return image
    }

    private func scrollCaptureSeedForCoordinatorTests() -> ScrollCaptureSeed {
        let annotation = CaptureAnnotation(
            kind: .rectangle,
            rect: NSRect(x: 4, y: 5, width: 12, height: 14),
            style: CaptureAnnotationStyle()
        )
        return ScrollCaptureSeed(
            screenRect: NSRect(x: 100, y: 120, width: 80, height: 60),
            snapshotRect: NSRect(x: 10, y: 20, width: 80, height: 60),
            frozenImage: solidImage(size: NSSize(width: 80, height: 60), color: .white),
            annotations: [annotation],
            eraserMasks: [EraserMask(rect: NSRect(x: 6, y: 7, width: 4, height: 5), affectedAnnotationIDs: [annotation.id])]
        )
    }

    private func solidImage(size: NSSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    private func retinaSolidImage(size: NSSize, color: NSColor) -> NSImage {
        let width = Int(size.width * 2)
        let height = Int(size.height * 2)
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let pixel = [
            UInt8(round(rgb.redComponent * 255)),
            UInt8(round(rgb.greenComponent * 255)),
            UInt8(round(rgb.blueComponent * 255)),
            UInt8(round(rgb.alphaComponent * 255)),
        ]
        let cgImage = makeTestImage(
            width: width,
            height: height,
            pixels: Array(repeating: pixel, count: width * height).flatMap { $0 },
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return NSImage(cgImage: cgImage, size: size)
    }

    private func retinaColorStripeImage(size: NSSize) -> NSImage {
        let width = Int(size.width * 2)
        let height = Int(size.height * 2)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                bytes[index] = UInt8((x * 37 + y * 11) % 256)
                bytes[index + 1] = UInt8((x * 17 + y * 29) % 256)
                bytes[index + 2] = UInt8((x * 7 + y * 43) % 256)
                bytes[index + 3] = 255
            }
        }
        let cgImage = makeTestImage(
            width: width,
            height: height,
            pixels: bytes,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return NSImage(cgImage: cgImage, size: size)
    }

    private func blackImageWithWhitePatch(size: NSSize, centeredAt point: NSPoint, patchSize: NSSize) -> NSImage {
        let image = solidImage(size: size, color: .black)
        image.lockFocus()
        NSColor.white.setFill()
        for y in [point.y, size.height - point.y] {
            NSRect(
                x: point.x - patchSize.width / 2,
                y: y - patchSize.height / 2,
                width: patchSize.width,
                height: patchSize.height
            ).fill()
        }
        image.unlockFocus()
        return image
    }

    private func pixelImage(width: Int, height: Int, pixels: [[NSColor]]) -> NSImage {
        var bytes: [UInt8] = []
        for row in 0..<height {
            for column in 0..<width {
                let color = pixels[row][column].usingColorSpace(.sRGB) ?? pixels[row][column]
                bytes.append(UInt8(round(color.redComponent * 255)))
                bytes.append(UInt8(round(color.greenComponent * 255)))
                bytes.append(UInt8(round(color.blueComponent * 255)))
                bytes.append(UInt8(round(color.alphaComponent * 255)))
            }
        }
        let cgImage = makeTestImage(
            width: width,
            height: height,
            pixels: bytes,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func gradientImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        for x in 0..<Int(size.width) {
            let red = CGFloat(x) / max(size.width - 1, 1)
            for y in 0..<Int(size.height) {
                let green = CGFloat(y) / max(size.height - 1, 1)
                NSColor(srgbRed: red, green: green, blue: 1 - red * 0.4, alpha: 1).setFill()
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
        image.unlockFocus()
        return image
    }

    private func desktopImageSize() -> NSSize {
        let frame = NSScreen.screens.reduce(NSRect.null) { partial, screen in
            partial.union(screen.frame)
        }
        return frame.isNull ? NSSize(width: 640, height: 420) : frame.size
    }

    private func croppedImage(_ image: NSImage, to rect: NSRect) -> NSImage? {
        let normalizedRect = rect.standardized
        let clippedRect = normalizedRect.intersection(NSRect(origin: .zero, size: image.size))
        guard !clippedRect.isEmpty else {
            return nil
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let pixelRect = CGRect(
            x: clippedRect.minX * scaleX,
            y: (image.size.height - clippedRect.maxY) * scaleY,
            width: clippedRect.width * scaleX,
            height: clippedRect.height * scaleY
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard !pixelRect.isEmpty, let croppedImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }
        return NSImage(cgImage: croppedImage, size: clippedRect.size)
    }

    private func rgbaBytes(in image: NSImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return bytes
    }

    private func rgbaPixel(in image: NSImage, at point: NSPoint) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let pixelX = Int((point.x * scaleX).rounded(.down))
        let pixelY = Int((point.y * scaleY).rounded(.down))
        guard pixelX >= 0, pixelX < cgImage.width, pixelY >= 0, pixelY < cgImage.height else {
            return nil
        }

        let bytes = try rgbaBytes(in: image)
        let index = (pixelY * cgImage.width + pixelX) * 4
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }

    private func rgbaRenderPixel(in image: NSImage, at point: NSPoint) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let pixelX = Int((point.x * scaleX).rounded(.down))
        let renderY = Int((point.y * scaleY).rounded(.down))
        guard pixelX >= 0, pixelX < cgImage.width, renderY >= 0, renderY < cgImage.height else {
            return nil
        }

        let bytes = try rgbaBytes(in: image)
        let pixelY = cgImage.height - 1 - renderY
        let index = (pixelY * cgImage.width + pixelX) * 4
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }

    private func rgbaRenderValues(in image: NSImage, rect: NSRect) throws -> [UInt32] {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: image)
        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        var values: [UInt32] = []
        for y in Int(ceil(rect.minY))..<Int(floor(rect.maxY)) {
            for x in Int(ceil(rect.minX))..<Int(floor(rect.maxX)) {
                let pixelX = Int(((CGFloat(x) + 0.5) * scaleX).rounded(.down))
                let renderY = Int(((CGFloat(y) + 0.5) * scaleY).rounded(.down))
                guard pixelX >= 0, pixelX < cgImage.width, renderY >= 0, renderY < cgImage.height else {
                    continue
                }
                let pixelY = cgImage.height - 1 - renderY
                let index = (pixelY * cgImage.width + pixelX) * 4
                values.append(
                    UInt32(bytes[index]) << 24
                        | UInt32(bytes[index + 1]) << 16
                        | UInt32(bytes[index + 2]) << 8
                        | UInt32(bytes[index + 3])
                )
            }
        }
        return values
    }

    private func hex(_ pixel: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> String {
        String(format: "#%02X%02X%02X", pixel.red, pixel.green, pixel.blue)
    }

    private func pixelDiffers(
        _ lhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
        _ rhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
    ) -> Bool {
        lhs.red != rhs.red || lhs.green != rhs.green || lhs.blue != rhs.blue || lhs.alpha != rhs.alpha
    }

    private func pixelDistance(
        _ lhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
        _ rhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
    ) -> Int {
        abs(Int(lhs.red) - Int(rhs.red))
            + abs(Int(lhs.green) - Int(rhs.green))
            + abs(Int(lhs.blue) - Int(rhs.blue))
            + abs(Int(lhs.alpha) - Int(rhs.alpha))
    }

    private func firstBlueDominantPixel(
        in image: NSImage,
        rect: NSRect
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        try firstPixel(in: image, rect: rect) { pixel in
            Int(pixel.blue) > Int(pixel.red) + 20
                && Int(pixel.blue) > Int(pixel.green) + 20
                && pixel.alpha > 200
        }
    }

    private func firstLightPixel(
        in image: NSImage,
        rect: NSRect
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        try firstPixel(in: image, rect: rect) { pixel in
            pixel.red > 230
                && pixel.green > 230
                && pixel.blue > 230
                && pixel.alpha > 200
        }
    }

    private func firstPixel(
        in image: NSImage,
        rect: NSRect,
        matching predicate: ((red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> Bool
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        try pixels(in: image, rect: rect).first(where: predicate)
    }

    private func whiteDigitBounds(in image: NSImage, insideCircleRect rect: NSRect) throws -> NSRect? {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: image)
        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let minX = max(0, Int((rect.minX * scaleX).rounded(.down)))
        let maxX = min(cgImage.width - 1, Int((rect.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int(((image.size.height - rect.maxY) * scaleY).rounded(.down)))
        let maxY = min(cgImage.height - 1, Int(((image.size.height - rect.minY) * scaleY).rounded(.up)))

        var bounds: NSRect?
        for y in minY...maxY {
            for x in minX...maxX {
                let overlayPoint = NSPoint(x: CGFloat(x) / scaleX, y: image.size.height - CGFloat(y) / scaleY)
                guard hypot(overlayPoint.x - center.x, overlayPoint.y - center.y) <= radius - 2 else {
                    continue
                }
                let index = (y * cgImage.width + x) * 4
                let pixel = (
                    red: bytes[index],
                    green: bytes[index + 1],
                    blue: bytes[index + 2],
                    alpha: bytes[index + 3]
                )
                guard pixel.red > 230, pixel.green > 230, pixel.blue > 230, pixel.alpha > 100 else {
                    continue
                }
                let pointRect = NSRect(x: overlayPoint.x, y: overlayPoint.y, width: 1 / scaleX, height: 1 / scaleY)
                bounds = bounds.map { $0.union(pointRect) } ?? pointRect
            }
        }
        return bounds
    }

    private func matchingPixelCount(
        in image: NSImage,
        rect: NSRect,
        matching predicate: ((red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> Bool
    ) throws -> Int {
        try pixels(in: image, rect: rect).filter(predicate).count
    }

    private func overlayPixelCount(
        in image: NSImage,
        rect: NSRect,
        matching predicate: ((red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> Bool
    ) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: image)
        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let minX = max(0, Int((rect.minX * scaleX).rounded(.down)))
        let maxX = min(cgImage.width - 1, Int((rect.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int(((image.size.height - rect.maxY) * scaleY).rounded(.down)))
        let maxY = min(cgImage.height - 1, Int(((image.size.height - rect.minY) * scaleY).rounded(.up)))
        guard minX < maxX, minY < maxY else {
            return 0
        }

        var count = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let index = (y * cgImage.width + x) * 4
                let pixel = (
                    red: bytes[index],
                    green: bytes[index + 1],
                    blue: bytes[index + 2],
                    alpha: bytes[index + 3]
                )
                if predicate(pixel) {
                    count += 1
                }
            }
        }
        return count
    }

    private func overlayPixelBounds(
        in image: NSImage,
        rect: NSRect,
        matching predicate: ((red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> Bool
    ) throws -> NSRect? {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: image)
        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let minX = max(0, Int((rect.minX * scaleX).rounded(.down)))
        let maxX = min(cgImage.width - 1, Int((rect.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int(((image.size.height - rect.maxY) * scaleY).rounded(.down)))
        let maxY = min(cgImage.height - 1, Int(((image.size.height - rect.minY) * scaleY).rounded(.up)))
        guard minX <= maxX, minY <= maxY else {
            return nil
        }

        var bounds: NSRect?
        for y in minY...maxY {
            for x in minX...maxX {
                let index = (y * cgImage.width + x) * 4
                let pixel = (
                    red: bytes[index],
                    green: bytes[index + 1],
                    blue: bytes[index + 2],
                    alpha: bytes[index + 3]
                )
                guard predicate(pixel) else {
                    continue
                }
                let pointRect = NSRect(
                    x: CGFloat(x) / scaleX,
                    y: image.size.height - CGFloat(y + 1) / scaleY,
                    width: 1 / scaleX,
                    height: 1 / scaleY
                )
                bounds = bounds.map { $0.union(pointRect) } ?? pointRect
            }
        }
        return bounds
    }

    private func pixels(
        in image: NSImage,
        rect: NSRect
    ) throws -> [(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)] {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: image)
        let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let minX = max(0, Int((rect.minX * scaleX).rounded(.down)))
        let maxX = min(cgImage.width - 1, Int((rect.maxX * scaleX).rounded(.up)))
        let directY = (
            min: max(0, Int((rect.minY * scaleY).rounded(.down))),
            max: min(cgImage.height - 1, Int((rect.maxY * scaleY).rounded(.up)))
        )
        let flippedY = (
            min: max(0, Int(((image.size.height - rect.maxY) * scaleY).rounded(.down))),
            max: min(cgImage.height - 1, Int(((image.size.height - rect.minY) * scaleY).rounded(.up)))
        )
        guard minX < maxX else {
            return []
        }

        var result: [(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)] = []
        for yRange in [directY, flippedY] where yRange.min < yRange.max {
            for y in yRange.min...yRange.max {
                for x in minX...maxX {
                    let index = (y * cgImage.width + x) * 4
                    let pixel = (
                        red: bytes[index],
                        green: bytes[index + 1],
                        blue: bytes[index + 2],
                        alpha: bytes[index + 3]
                    )
                    result.append(pixel)
                }
            }
        }
        return result
    }

    private func averageLumaDelta(in image: NSImage, rect: NSRect) throws -> Double {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: image)
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(cgImage.width - 1, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(cgImage.height - 1, Int(rect.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else {
            return 0
        }

        var total = 0.0
        var count = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let luma = lumaAt(x: x, y: y, width: cgImage.width, height: cgImage.height, bytes: bytes)
                let right = lumaAt(x: x + 1, y: y, width: cgImage.width, height: cgImage.height, bytes: bytes)
                let down = lumaAt(x: x, y: y + 1, width: cgImage.width, height: cgImage.height, bytes: bytes)
                total += abs(luma - right) + abs(luma - down)
                count += 2
            }
        }
        return total / Double(max(1, count))
    }

    private func lumaAt(x: Int, y: Int, width: Int, height: Int, bytes: [UInt8]) -> Double {
        let index = (y * width + x) * 4
        return 0.2126 * Double(bytes[index])
            + 0.7152 * Double(bytes[index + 1])
            + 0.0722 * Double(bytes[index + 2])
    }

    private func overlayMosaicAnnotation(_ annotation: CaptureAnnotation, selection: NSRect) -> CaptureAnnotation {
        overlayAnnotation(annotation, selection: selection)
    }

    private func overlayAnnotation(_ annotation: CaptureAnnotation, selection: NSRect) -> CaptureAnnotation {
        var overlay = annotation
        overlay.rect.origin.x += selection.minX
        overlay.rect.origin.y += selection.minY
        if let arrowLine = annotation.arrowLine {
            overlay.arrowLine = CaptureArrowLine(
                start: overlayPoint(arrowLine.start, selection: selection),
                end: overlayPoint(arrowLine.end, selection: selection),
                control: overlayPoint(arrowLine.control, selection: selection),
                startArrowType: arrowLine.startArrowType,
                endArrowType: arrowLine.endArrowType
            )
        }
        if let markerLine = annotation.markerLine {
            overlay.markerLine = CaptureMarkerLine(
                start: overlayPoint(markerLine.start, selection: selection),
                end: overlayPoint(markerLine.end, selection: selection)
            )
        }
        if let brushPath = annotation.brushPath {
            overlay.brushPath = CaptureBrushPath(
                points: brushPath.points.map { overlayPoint($0, selection: selection) }
            )
        }
        if let stroke = annotation.mosaicStroke {
            overlay.mosaicStroke = CaptureMosaicStroke(
                points: stroke.points.map { overlayPoint($0, selection: selection) }
            )
        }
        return overlay
    }

    private func overlayPoint(_ point: NSPoint, selection: NSRect) -> NSPoint {
        NSPoint(x: point.x + selection.minX, y: point.y + selection.minY)
    }

    private func expectedTextAnnotationSize(text: String, style: CaptureAnnotationStyle) -> NSSize {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineHeight = CaptureAnnotationRenderer.textLineHeight(style: style)
        let horizontalPadding = CaptureAnnotationRenderer.textHorizontalPadding * 2
        guard !trimmedText.isEmpty else {
            return NSSize(width: horizontalPadding + 1, height: lineHeight)
        }

        let attributedText = NSAttributedString(
            string: text,
            attributes: CaptureAnnotationRenderer.textAttributes(style: style)
        )
        let measured = attributedText.boundingRect(
            with: NSSize(width: 10_000, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return NSSize(
            width: horizontalPadding + max(1, ceil(measured.width)),
            height: max(lineHeight, ceil(measured.height))
        )
    }

    private func measuredTextWidth(_ text: String, style: CaptureAnnotationStyle) -> CGFloat {
        let measured = NSAttributedString(
            string: text,
            attributes: CaptureAnnotationRenderer.textAttributes(style: style)
        ).boundingRect(
            with: NSSize(width: 10_000, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(measured.width)
    }

    private func rotatedPoint(_ point: NSPoint, around center: NSPoint, angle: CGFloat) -> NSPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosine = cos(angle)
        let sine = sin(angle)
        return NSPoint(
            x: center.x + dx * cosine - dy * sine,
            y: center.y + dx * sine + dy * cosine
        )
    }

    private func boundingRect(of points: [NSPoint]) -> NSRect {
        guard let first = points.first else {
            return .zero
        }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func clickTextInsertionPoint(
        in window: SelectionOverlayWindow,
        annotationIndex: Int,
        characterIndex: Int
    ) throws {
        _ = try XCTUnwrap(window.firstResponder as? NSTextView)
        _ = try XCTUnwrap(window.test_textAnnotation(at: annotationIndex))
        let clickPoint = try XCTUnwrap(window.test_textEditorOverlayPointForInsertion(at: characterIndex))
        window.test_mouseDown(at: clickPoint)
        window.test_mouseUp(at: clickPoint)
    }

    private func assertPreview(
        _ preview: (image: NSImage, drawRect: NSRect),
        matchesCropFrom expected: NSImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expectedCrop = try XCTUnwrap(croppedImage(expected, to: preview.drawRect))
        XCTAssertEqual(try rgbaBytes(in: preview.image), try rgbaBytes(in: expectedCrop), file: file, line: line)
    }

    private func imageBytesDiffer(_ lhs: NSImage, _ rhs: NSImage) throws -> Bool {
        try rgbaBytes(in: lhs) != rgbaBytes(in: rhs)
    }

    private func averagePixelDistance(_ lhs: NSImage, _ rhs: NSImage) throws -> Double {
        let lhsBytes = try rgbaBytes(in: lhs)
        let rhsBytes = try rgbaBytes(in: rhs)
        XCTAssertEqual(lhsBytes.count, rhsBytes.count)
        guard lhsBytes.count == rhsBytes.count, !lhsBytes.isEmpty else {
            return .infinity
        }

        var total = 0
        for index in stride(from: 0, to: lhsBytes.count, by: 4) {
            total += abs(Int(lhsBytes[index]) - Int(rhsBytes[index]))
            total += abs(Int(lhsBytes[index + 1]) - Int(rhsBytes[index + 1]))
            total += abs(Int(lhsBytes[index + 2]) - Int(rhsBytes[index + 2]))
            total += abs(Int(lhsBytes[index + 3]) - Int(rhsBytes[index + 3]))
        }
        return Double(total) / Double(lhsBytes.count / 4)
    }
}
