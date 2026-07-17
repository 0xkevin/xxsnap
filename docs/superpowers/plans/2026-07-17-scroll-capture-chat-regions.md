# Scroll Capture Chat Regions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make scroll capture identify and snap to the real vertical scroll container, show a green eligible-region outline, choose a 30% or 50% automatic step from region height, and render a 0.1pt-equivalent white seam in preview and exported long images.

**Architecture:** The macOS shell owns Accessibility target discovery and selection-state feedback; the shared C++ stitcher owns accepted segment boundaries and pixel composition. `CaptureCoordinator` resolves the target only after the scroll tool is activated, `SelectionOverlayWindow` applies or restores the snapped selection, and `ScrollCaptureSession` derives step distance from the final region. The bridge converts the requested 0.1pt seam to a one-pixel white coverage value using the source backing scale.

**Tech Stack:** Swift/AppKit, macOS Accessibility API, Objective-C++, C++20, XCTest, Qt Test, CMake, Xcode.

---

## Scope and baseline

- Product contract: `docs/superpowers/specs/2026-07-16-scroll-capture-target-detection-and-seams-design.md`
- Working branch: `fix/scroll-capture-chat-regions`
- Baseline commits: `0830536` (scroll capture implementation) and `37be681` (approved design)
- Existing left-side preview geometry and its blue viewport indicator are immutable for this work.
- Existing full macOS baseline has environment-sensitive failures in live screen/color sampling and unrelated magnifier, number-control, and status-item assertions. Every focused suite named below must pass; the final full run must not add failures beyond the captured baseline.

## File map

### New files

- `platforms/mac/Sources/ScrollCapture/ScrollCaptureTargetDetector.swift` — Accessibility candidate discovery, coordinate conversion, candidate ranking, and detector protocol.
- `platforms/mac/Tests/ScrollCaptureTargetDetectorTests.swift` — deterministic tests for probes, filtering, ranking, and coordinate conversion without querying the live desktop.

### Modified files

- `platforms/mac/Sources/App/CaptureCoordinator.swift` — inject and call the detector only when scroll capture starts; pass the resolved seed to the existing session.
- `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift` — preserve the original selection, snap/remap to the resolved region, expose green/blue state, and restore on cancel/start failure.
- `platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift` — replace fixed 30% distance with the 600pt policy.
- `platforms/mac/Tests/SelectionToolbarStateTests.swift` — selection-color, snap, fallback, annotation/mask remap, and restore tests.
- `platforms/mac/Tests/ScrollCaptureSessionTests.swift` — 30%/50% boundary and actual step-distance tests.
- `platforms/mac/xxsnap.xcodeproj/project.pbxproj` — compile the new detector and test files.
- `core/include/snipory/core/scroll/ScrollStitchSession.h` — add seam white-coverage configuration.
- `core/src/scroll/ScrollStitchSession.cpp` — derive segment boundaries and blend seam rows in preview/final composition.
- `core/tests/TestScrollStitchSession.cpp` — final, preview, duplicate, and upward seam tests.
- `platforms/mac/Sources/Bridge/ScrollCaptureBridge.mm` — convert 0.1pt to backing-scale coverage when constructing the core session.
- `platforms/mac/Tests/ScrollCaptureBridgeTests.swift` — Retina/non-Retina seam coverage and preview/export consistency tests.
- `platforms/mac/Tests/manual-capture-checklist.md` — chat target, green/blue feedback, dynamic step, and 0.1pt seam smoke checks.

---

### Task 1: Add deterministic Accessibility scroll-target detection

**Files:**
- Create: `platforms/mac/Sources/ScrollCapture/ScrollCaptureTargetDetector.swift`
- Create: `platforms/mac/Tests/ScrollCaptureTargetDetectorTests.swift`
- Modify: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the failing detector tests and Xcode project entries**

Add these test cases to `ScrollCaptureTargetDetectorTests.swift`:

```swift
import AppKit
import XCTest
@testable import xxsnap

final class ScrollCaptureTargetDetectorTests: XCTestCase {
    func testProbePointsCoverCenterAndThreeByThreeInteriorGrid() {
        let rect = NSRect(x: 100, y: 200, width: 900, height: 600)
        let points = ScrollCaptureTargetDetector.probePoints(in: rect)

        XCTAssertEqual(points.count, 9)
        XCTAssertTrue(points.contains(NSPoint(x: 550, y: 500)))
        XCTAssertTrue(points.allSatisfy { rect.contains($0) })
    }

    func testLargestScrollableIntersectionWinsOverNarrowChatSidebar() {
        let selection = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let candidates = [
            ScrollCaptureTargetCandidate(identity: 1, screenRect: NSRect(x: 0, y: 0, width: 250, height: 800), minimum: 0, maximum: 1, firstProbeIndex: 0),
            ScrollCaptureTargetCandidate(identity: 2, screenRect: NSRect(x: 250, y: 80, width: 750, height: 640), minimum: 0, maximum: 1, firstProbeIndex: 4),
        ]

        XCTAssertEqual(
            ScrollCaptureTargetDetector.bestRegion(in: selection, candidates: candidates),
            NSRect(x: 250, y: 80, width: 750, height: 640)
        )
    }

    func testCandidateIsClippedToOriginalSelectionAndNeverExpandsIt() {
        let selection = NSRect(x: 100, y: 100, width: 500, height: 400)
        let candidate = ScrollCaptureTargetCandidate(
            identity: 7,
            screenRect: NSRect(x: 40, y: 20, width: 800, height: 700),
            minimum: 0,
            maximum: 100,
            firstProbeIndex: 0
        )

        XCTAssertEqual(
            ScrollCaptureTargetDetector.bestRegion(in: selection, candidates: [candidate]),
            selection
        )
    }

    func testInvalidRangeAndSubminimumRegionFallBack() {
        let selection = NSRect(x: 0, y: 0, width: 800, height: 600)
        let noRange = ScrollCaptureTargetCandidate(identity: 1, screenRect: selection, minimum: 1, maximum: 1, firstProbeIndex: 0)
        let tooSmall = ScrollCaptureTargetCandidate(identity: 2, screenRect: NSRect(x: 0, y: 0, width: 119, height: 119), minimum: 0, maximum: 1, firstProbeIndex: 1)

        XCTAssertNil(ScrollCaptureTargetDetector.bestRegion(in: selection, candidates: [noRange, tooSmall]))
    }

    func testQuartzRectConvertsToAppKitBottomOrigin() {
        XCTAssertEqual(
            ScrollCaptureScreenCoordinates.appKitRect(
                quartzPosition: CGPoint(x: 300, y: 120),
                size: CGSize(width: 800, height: 600),
                quartzOriginY: 1_080
            ),
            NSRect(x: 300, y: 360, width: 800, height: 600)
        )
        XCTAssertEqual(
            ScrollCaptureScreenCoordinates.appKitRect(
                quartzPosition: CGPoint(x: -1_280, y: 1_080),
                size: CGSize(width: 1_280, height: 720),
                quartzOriginY: 1_080
            ),
            NSRect(x: -1_280, y: -720, width: 1_280, height: 720)
        )
    }
}
```

Add PBX file references/build files with these exact unused identifiers:

```text
AA5300000000000000000001 /* ScrollCaptureTargetDetector.swift in Sources */
AA5300000000000000000002 /* ScrollCaptureTargetDetectorTests.swift in Sources */
AA5300000000000000000011 /* ScrollCaptureTargetDetector.swift */
AA5300000000000000000012 /* ScrollCaptureTargetDetectorTests.swift */
```

- [ ] **Step 2: Run the test and verify it fails because the detector types do not exist**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/ScrollCaptureTargetDetectorTests
```

Expected: build fails with unresolved `ScrollCaptureTargetDetector`, `ScrollCaptureTargetCandidate`, and `ScrollCaptureScreenCoordinates` symbols.

- [ ] **Step 3: Implement the pure detector contract, probes, filtering, and ranking**

Create the public/internal portion of `ScrollCaptureTargetDetector.swift` exactly around these types:

```swift
import AppKit
import ApplicationServices

protocol ScrollCaptureTargetDetecting: AnyObject {
    func scrollableRegion(in selection: NSRect, processIdentifier: pid_t) -> NSRect?
}

struct ScrollCaptureTargetCandidate: Equatable {
    let identity: CFHashCode
    let screenRect: NSRect
    let minimum: Double
    let maximum: Double
    let firstProbeIndex: Int
}

protocol ScrollCaptureTargetCandidateQuerying {
    func candidates(
        processIdentifier: pid_t,
        probePoints: [NSPoint]
    ) -> [ScrollCaptureTargetCandidate]
}

enum ScrollCaptureScreenCoordinates {
    static func appKitRect(
        quartzPosition: CGPoint,
        size: CGSize,
        quartzOriginY: CGFloat
    ) -> NSRect {
        NSRect(
            x: quartzPosition.x,
            y: quartzOriginY - quartzPosition.y - size.height,
            width: size.width,
            height: size.height
        ).standardized
    }
}

final class ScrollCaptureTargetDetector: ScrollCaptureTargetDetecting {
    static let minimumRegionSize = NSSize(width: 120, height: 120)
    private let query: any ScrollCaptureTargetCandidateQuerying

    init(query: any ScrollCaptureTargetCandidateQuerying = AccessibilityScrollCaptureCandidateQuery()) {
        self.query = query
    }

    func scrollableRegion(in selection: NSRect, processIdentifier: pid_t) -> NSRect? {
        let rect = selection.standardized
        return Self.bestRegion(
            in: rect,
            candidates: query.candidates(
                processIdentifier: processIdentifier,
                probePoints: Self.probePoints(in: rect)
            )
        )
    }

    static func probePoints(in selection: NSRect) -> [NSPoint] {
        let fractions: [CGFloat] = [0.2, 0.5, 0.8]
        return fractions.flatMap { y in
            fractions.map { x in
                NSPoint(
                    x: selection.minX + selection.width * x,
                    y: selection.minY + selection.height * y
                )
            }
        }
    }

    static func bestRegion(
        in selection: NSRect,
        candidates: [ScrollCaptureTargetCandidate]
    ) -> NSRect? {
        var unique: [CFHashCode: ScrollCaptureTargetCandidate] = [:]
        for candidate in candidates where candidate.maximum > candidate.minimum {
            if let current = unique[candidate.identity], current.firstProbeIndex <= candidate.firstProbeIndex {
                continue
            }
            unique[candidate.identity] = candidate
        }

        let scored = unique.values.compactMap { candidate -> (NSRect, CGFloat, CGFloat, CGFloat, Int)? in
            let intersection = selection.intersection(candidate.screenRect).standardized
            guard !intersection.isNull,
                  intersection.width >= minimumRegionSize.width,
                  intersection.height >= minimumRegionSize.height else { return nil }
            let area = intersection.width * intersection.height
            let dx = intersection.midX - selection.midX
            let dy = intersection.midY - selection.midY
            return (intersection, area, intersection.height, hypot(dx, dy), candidate.firstProbeIndex)
        }

        return scored.max { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            if lhs.3 != rhs.3 { return lhs.3 > rhs.3 }
            return lhs.4 > rhs.4
        }?.0
    }
}
```

- [ ] **Step 4: Implement the production Accessibility candidate query**

In the same file, add `AccessibilityScrollCaptureCandidateQuery`. It must:

1. Convert each AppKit probe to Quartz coordinates using the union of `NSScreen.screens`.
2. Hit-test the target application.
3. Walk at most 16 parents.
4. Accept only an element with a vertical scrollbar whose numeric maximum exceeds minimum.
5. Read the owner element's `AXPosition` and `AXSize` and convert to AppKit coordinates.

Use these exact helper signatures so the behavior remains local and testable:

```swift
struct AccessibilityScrollCaptureCandidateQuery: ScrollCaptureTargetCandidateQuerying {
    private let quartzOriginYProvider: () -> CGFloat?

    init(quartzOriginYProvider: @escaping () -> CGFloat? = {
        NSScreen.screens.first?.frame.maxY
    }) {
        self.quartzOriginYProvider = quartzOriginYProvider
    }

    func candidates(processIdentifier: pid_t, probePoints: [NSPoint]) -> [ScrollCaptureTargetCandidate] {
        guard let quartzOriginY = quartzOriginYProvider(), quartzOriginY.isFinite else { return [] }
        let application = AXUIElementCreateApplication(processIdentifier)
        var output: [ScrollCaptureTargetCandidate] = []

        for (probeIndex, point) in probePoints.enumerated() {
            let quartz = CGPoint(x: point.x, y: quartzOriginY - point.y)
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(application, Float(quartz.x), Float(quartz.y), &hit) == .success,
                  var element = hit else { continue }

            for _ in 0..<16 {
                if let candidate = candidate(from: element, probeIndex: probeIndex, quartzOriginY: quartzOriginY) {
                    output.append(candidate)
                }
                guard let parent = elementAttribute(kAXParentAttribute as CFString, from: element) else { break }
                element = parent
            }
        }
        return output
    }

    private func candidate(from element: AXUIElement, probeIndex: Int, quartzOriginY: CGFloat) -> ScrollCaptureTargetCandidate? {
        guard let scrollBar = elementAttribute(kAXVerticalScrollBarAttribute as CFString, from: element),
              let value = numberAttribute(kAXValueAttribute as CFString, from: scrollBar) else { return nil }
        let minimum = numberAttribute(kAXMinValueAttribute as CFString, from: scrollBar) ?? 0
        let maximum = numberAttribute(kAXMaxValueAttribute as CFString, from: scrollBar) ?? 1
        guard value.isFinite, minimum.isFinite, maximum.isFinite, maximum > minimum,
              let position = pointAttribute(kAXPositionAttribute as CFString, from: element),
              let size = sizeAttribute(kAXSizeAttribute as CFString, from: element) else { return nil }
        return ScrollCaptureTargetCandidate(
            identity: CFHash(element),
            screenRect: ScrollCaptureScreenCoordinates.appKitRect(
                quartzPosition: position,
                size: size,
                quartzOriginY: quartzOriginY
            ),
            minimum: minimum,
            maximum: maximum,
            firstProbeIndex: probeIndex
        )
    }

    private func copiedAttribute(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        guard let value = copiedAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func numberAttribute(_ attribute: CFString, from element: AXUIElement) -> Double? {
        (copiedAttribute(attribute, from: element) as? NSNumber)?.doubleValue
    }

    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        guard let value = copiedAttribute(attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint,
              AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        guard let value = copiedAttribute(attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize,
              AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
```

- [ ] **Step 5: Run detector tests and verify they pass**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/ScrollCaptureTargetDetectorTests
```

Expected: `ScrollCaptureTargetDetectorTests` passes with 5 tests and no failures.

- [ ] **Step 6: Commit target detection**

```bash
git add platforms/mac/Sources/ScrollCapture/ScrollCaptureTargetDetector.swift platforms/mac/Tests/ScrollCaptureTargetDetectorTests.swift platforms/mac/xxsnap.xcodeproj/project.pbxproj
git commit -m "feat(mac): detect scrollable capture regions"
```

---

### Task 2: Snap the scroll selection and show green eligibility feedback

**Files:**
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift:92-169,344-401`
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift:640-950,2168-2370,11420-11465,15694-15725`
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift:150-430,9600-10050`

- [ ] **Step 1: Write failing overlay and coordinator tests**

Add tests covering all transition outcomes:

```swift
func testScrollCaptureResolvedTargetSnapsSelectionAndUsesGreenChrome() throws {
    let image = solidImage(size: NSSize(width: 1_000, height: 800), color: .white)
    let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
    let original = NSRect(x: 50, y: 40, width: 900, height: 700)
    let resolvedLocal = NSRect(x: 300, y: 120, width: 650, height: 560)
    window.test_setLockedSelectionRect(original)
    window.test_beginScrollCapture()

    let seed = try XCTUnwrap(window.test_applyScrollCaptureTargetLocalRect(resolvedLocal))

    XCTAssertEqual(window.test_lockedSelectionRect, resolvedLocal)
    XCTAssertEqual(seed.snapshotRect, resolvedLocal)
    XCTAssertEqual(window.test_selectionBorderColor, .systemGreen)
}

func testScrollCaptureFallbackKeepsOriginalSelectionBlue() {
    let image = solidImage(size: NSSize(width: 800, height: 600), color: .white)
    let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
    let original = NSRect(x: 80, y: 60, width: 600, height: 420)
    window.test_setLockedSelectionRect(original)
    window.test_beginScrollCapture()

    window.test_markScrollCaptureTargetFallback()

    XCTAssertEqual(window.test_lockedSelectionRect, original)
    XCTAssertNotEqual(window.test_selectionBorderColor, .systemGreen)
}

func testScrollCaptureCancelRestoresOriginalSelectionAfterSnap() throws {
    let image = solidImage(size: NSSize(width: 800, height: 600), color: .white)
    let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
    let original = NSRect(x: 40, y: 40, width: 700, height: 500)
    window.test_setLockedSelectionRect(original)
    window.test_beginScrollCapture()
    _ = try XCTUnwrap(window.test_applyScrollCaptureTargetLocalRect(NSRect(x: 220, y: 100, width: 500, height: 400)))

    window.restoreAfterScrollCaptureCancellation()

    XCTAssertEqual(window.test_lockedSelectionRect, original)
    XCTAssertNotEqual(window.test_selectionBorderColor, .systemGreen)
}
```

Add this fake and coordinator test; it proves that creating/installing an ordinary
selection does not run detection, while the scroll-tool request runs it exactly
once and seeds the session with the snapped rectangle:

```swift
private final class FakeScrollCaptureTargetDetector: ScrollCaptureTargetDetecting {
    var region: NSRect?
    private(set) var calls: [(selection: NSRect, processIdentifier: pid_t)] = []

    func scrollableRegion(in selection: NSRect, processIdentifier: pid_t) -> NSRect? {
        calls.append((selection, processIdentifier))
        return region
    }
}

@MainActor
func testCaptureCoordinatorDetectsOnlyAfterScrollToolRequestAndUsesResolvedSeed() async throws {
    let seed = scrollCaptureSeedForCoordinatorTests()
    let overlay = SelectionOverlayWindow(backgroundImage: seed.frozenImage) { _ in }
    let detector = FakeScrollCaptureTargetDetector()
    let resolvedLocal = seed.snapshotRect.insetBy(dx: 40, dy: 30)
    detector.region = overlay.convertToScreen(resolvedLocal)
    var sessionSeed: ScrollCaptureSeed?
    let coordinator = CaptureCoordinator(
        permissionCoordinator: PermissionCoordinator(),
        screenCaptureService: ScreenCaptureService(),
        scrollCaptureSessionFactory: { capturedSeed, _ in
            sessionSeed = capturedSeed
            return FakeScrollCaptureSession(seed: capturedSeed)
        },
        scrollCapturePresentationFactory: { _ in FakeScrollCapturePresentation() },
        frontmostApplicationResolver: { .current },
        applicationActivator: { _ in },
        scrollCaptureTargetDetector: detector
    )

    coordinator.test_installOverlayWindow(overlay)
    XCTAssertEqual(detector.calls.count, 0)

    coordinator.test_requestScrollCapture(seed: seed)
    await Task.yield()

    XCTAssertEqual(detector.calls.count, 1)
    XCTAssertEqual(detector.calls.first?.selection, seed.screenRect)
    XCTAssertEqual(sessionSeed?.snapshotRect, resolvedLocal)
    XCTAssertEqual(sessionSeed?.screenRect, detector.region)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testScrollCaptureResolvedTargetSnapsSelectionAndUsesGreenChrome -only-testing:xxsnapTests/SelectionToolbarStateTests/testScrollCaptureFallbackKeepsOriginalSelectionBlue -only-testing:xxsnapTests/SelectionToolbarStateTests/testScrollCaptureCancelRestoresOriginalSelectionAfterSnap -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorDetectsOnlyAfterScrollToolRequestAndUsesResolvedSeed
```

Expected: failures because the target-state and apply/restore APIs do not exist.

- [ ] **Step 3: Add overlay target state and color semantics**

Add a state independent from `ScrollCaptureOverlayState`:

```swift
private enum ScrollCaptureTargetVisualState {
    case inactive
    case resolving
    case resolved
    case fallback
}

private let defaultSelectionColor = NSColor(
    calibratedRed: 83 / 255,
    green: 120 / 255,
    blue: 232 / 255,
    alpha: 1
)
private var scrollCaptureTargetVisualState: ScrollCaptureTargetVisualState = .inactive
private var scrollCaptureOriginalSelectionRect: NSRect?

private var selectionChromeColor: NSColor {
    scrollCaptureTargetVisualState == .resolved ? .systemGreen : defaultSelectionColor
}
```

Use `selectionChromeColor` in both `drawSelectionBorder` and `drawSelectionHandles`; do not touch `ScrollCapturePresentationController.viewportIndicatorView`.

- [ ] **Step 4: Refactor seed creation and implement snap/remap/restore**

Extract the existing crop and seed construction from `beginScrollCapture()`:

```swift
private func makeScrollCaptureSeed(for snapshotRect: NSRect) -> ScrollCaptureSeed? {
    guard let window,
          let backgroundImage,
          let crop = pixelAlignedCrop(image: backgroundImage, to: snapshotRect.standardized) else { return nil }
    return ScrollCaptureSeed(
        screenRect: window.convertToScreen(crop.drawRect).standardized,
        snapshotRect: snapshotRect.standardized,
        frozenImage: crop.image,
        annotations: annotations,
        eraserMasks: eraserMasks
    )
}
```

Expose these exact window/view entry points so coordinate ownership is explicit:

```swift
// SelectionOverlayWindow: receives Accessibility's global AppKit rectangle.
func applyScrollCaptureTarget(screenRect: NSRect) -> ScrollCaptureSeed? {
    guard let overlayView = contentView as? SelectionOverlayView else { return nil }
    let windowRect = convertFromScreen(screenRect.standardized)
    let localRect = overlayView.convert(windowRect, from: nil).standardized
    return overlayView.applyScrollCaptureTarget(localRect: localRect)
}

func markScrollCaptureTargetFallback() {
    (contentView as? SelectionOverlayView)?.markScrollCaptureTargetFallback()
}

// SelectionOverlayView: owns selection, annotation, mask, and seed state.
func applyScrollCaptureTarget(localRect: NSRect) -> ScrollCaptureSeed?
func markScrollCaptureTargetFallback()
```

Add DEBUG accessors named `test_applyScrollCaptureTargetLocalRect`,
`test_markScrollCaptureTargetFallback`, `test_lockedSelectionRect`, and
`test_selectionBorderColor`; each delegates to the corresponding production state
without reimplementing it.

Before the first request, save `scrollCaptureOriginalSelectionRect`, set `.resolving`, and emit the original seed. For a resolved local rect, preserve overlay-space positions for every annotation and mask, call `applySelectionWheelResize`, remap masks with `SelectionToolbarState.localAnnotationRectsPreservingOverlayPositions`, set `.resolved`, and return a newly cropped seed. Reject a null, sub-8pt, or out-of-original-selection rect.

Restore by applying the same preservation mapping back to `scrollCaptureOriginalSelectionRect`, then clear the saved rect and set `.inactive`. A fallback changes only the visual state to `.fallback`.

- [ ] **Step 5: Inject the detector into `CaptureCoordinator` and resolve before geometry/session creation**

Add:

```swift
private let scrollCaptureTargetDetector: any ScrollCaptureTargetDetecting
```

Extend the initializer with a default:

```swift
scrollCaptureTargetDetector: any ScrollCaptureTargetDetecting = ScrollCaptureTargetDetector()
```

At the beginning of `requestScrollCapture(seed:)`, after the lifecycle guard but
before `setScrollCaptureCapturing()`, control geometry, presentation, and session
creation, resolve the target application first, then:

```swift
var resolvedSeed = seed
if let processIdentifier = targetApplication?.processIdentifier,
   let target = scrollCaptureTargetDetector.scrollableRegion(
       in: seed.screenRect,
       processIdentifier: processIdentifier
   ),
   let adjusted = overlay.applyScrollCaptureTarget(screenRect: target) {
    resolvedSeed = adjusted
} else {
    overlay.markScrollCaptureTargetFallback()
}

let captureSeed = ScrollCaptureSeed(
    screenRect: resolvedSeed.screenRect,
    snapshotRect: resolvedSeed.snapshotRect,
    frozenImage: resolvedSeed.frozenImage,
    annotations: resolvedSeed.annotations,
    eraserMasks: resolvedSeed.eraserMasks,
    targetApplicationProcessIdentifier: targetApplication?.processIdentifier
)
```

All geometry, preview placement, step points, and capture operations below this block must use `captureSeed`. Log one line with original rect, resolved rect, PID, and fallback/resolved state.

- [ ] **Step 6: Run focused overlay/coordinator tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/SelectionToolbarStateTests/testScrollCaptureResolvedTargetSnapsSelectionAndUsesGreenChrome -only-testing:xxsnapTests/SelectionToolbarStateTests/testScrollCaptureFallbackKeepsOriginalSelectionBlue -only-testing:xxsnapTests/SelectionToolbarStateTests/testScrollCaptureCancelRestoresOriginalSelectionAfterSnap -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorDetectsOnlyAfterScrollToolRequestAndUsesResolvedSeed -only-testing:xxsnapTests/SelectionToolbarStateTests/testCaptureCoordinatorStartsOneScrollSessionAndRoutesPresentationUpdates
```

Expected: all new and existing focused tests pass.

- [ ] **Step 7: Commit selection integration**

```bash
git add platforms/mac/Sources/App/CaptureCoordinator.swift platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "fix(mac): snap scroll capture to chat content"
```

---

### Task 3: Select 30% or 50% automatic step distance by region height

**Files:**
- Modify: `platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift:238-369`
- Modify: `platforms/mac/Tests/ScrollCaptureSessionTests.swift:1-80`

- [ ] **Step 1: Replace the fixed-overlap test with explicit small/large policy tests**

Add:

```swift
func testAutomaticStepDistanceUsesThirtyPercentBelowSixHundredPoints() {
    XCTAssertEqual(ScrollCaptureSession.stepDistance(forViewportHeight: 599), 179.7, accuracy: 0.001)
}

func testAutomaticStepDistanceUsesFiftyPercentAtSixHundredPoints() {
    XCTAssertEqual(ScrollCaptureSession.stepDistance(forViewportHeight: 600), 300, accuracy: 0.001)
    XCTAssertEqual(ScrollCaptureSession.stepDistance(forViewportHeight: 900), 450, accuracy: 0.001)
}
```

Keep the existing 60pt session assertion at `18`, and add a session created with an 800pt seed that records a `400` point step.

- [ ] **Step 2: Run tests and verify the policy API is missing**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/ScrollCaptureSessionTests
```

Expected: build failure for missing `stepDistance(forViewportHeight:)`.

- [ ] **Step 3: Implement the named binary policy**

Replace the fixed ratio with:

```swift
private static let largeViewportThreshold: CGFloat = 600
private static let compactViewportRatio: CGFloat = 0.30
private static let largeViewportRatio: CGFloat = 0.50

static func stepDistance(forViewportHeight height: CGFloat) -> CGFloat {
    let ratio = height >= largeViewportThreshold
        ? largeViewportRatio
        : compactViewportRatio
    return max(1, height * ratio)
}
```

In `performStep`, calculate:

```swift
let distance = Self.stepDistance(forViewportHeight: seed.screenRect.height)
```

- [ ] **Step 4: Run the full scroll session suite**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/ScrollCaptureSessionTests
```

Expected: all `ScrollCaptureSessionTests` pass, including 30% small chat and 50% tall webpage cases.

- [ ] **Step 5: Commit dynamic steps**

```bash
git add platforms/mac/Sources/ScrollCapture/ScrollCaptureSession.swift platforms/mac/Tests/ScrollCaptureSessionTests.swift
git commit -m "fix(mac): adapt scroll step to capture height"
```

---

### Task 4: Mark true segment boundaries in shared preview and final composition

**Files:**
- Modify: `core/include/snipory/core/scroll/ScrollStitchSession.h:38-65`
- Modify: `core/src/scroll/ScrollStitchSession.cpp:1736-2030`
- Modify: `core/tests/TestScrollStitchSession.cpp`

- [ ] **Step 1: Write failing core seam tests**

Add these test slots:

```cpp
void paintsOneWhiteRowAtAcceptedDownwardSegmentBoundaryWithoutChangingHeight();
void paintsMappedWhiteRowInDownsampledPreview();
void duplicateFrameDoesNotCreateAnotherSeam();
void upwardSegmentsKeepSeamsInNaturalDocumentOrder();
```

Use `documentViewport` and `blueAt` already present in the test file. Set
`config.seamWhiteCoverage = 1.0`, disable fixed-band, fixed-side, and scrollbar
detection, then append document offsets `0` and `60` with a downward hint. The
first complete segment contributes rows `0...139`; the accepted strip contributes
rows `140...199`, so the exact final assertion is:

```cpp
void TestScrollStitchSession::paintsOneWhiteRowAtAcceptedDownwardSegmentBoundaryWithoutChangingHeight()
{
    auto config = defaultConfig();
    config.enableFixedBandDetection = false;
    config.enableFixedSideDetection = false;
    config.scrollbarMaximumWidth = 0;
    config.seamWhiteCoverage = 1.0;
    ScrollStitchSession session(config);

    QCOMPARE(session.append(documentViewport(0), ScrollDirection::Down).kind,
        AppendKind::AcceptedInitial);
    QCOMPARE(session.append(documentViewport(60), ScrollDirection::Down).kind,
        AppendKind::AcceptedAppend);

    const auto final = session.finalize();
    QCOMPARE(final.height, 200);
    QCOMPARE(blueAt(final, 37, 139), documentPixel(37, 139));
    QCOMPARE(blueAt(final, 37, 140), std::uint8_t {255});
    QCOMPARE(blueAt(final, 37, 141), documentPixel(37, 141));
}
```

For preview, append offsets `0` and `60`, call `preview(100)`, assert its height is
`100`, and assert mapped row `70` is white while rows `69` and `71` are not. For
duplicate, save `finalize()` after the accepted second frame, append that same
frame again, assert `DuplicateDiscarded`, and assert height and pixels are exactly
unchanged. For upward order, append offsets `120`, `60`, and `0` with an upward
hint, assert final height `260`, and assert the two natural-document seam rows
`60` and `120` are white; assert their immediate neighbors retain document data.

- [ ] **Step 2: Run the core test and verify it fails**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build --target test_scroll_stitch_session
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ctest --test-dir build -R test_scroll_stitch_session --output-on-failure
```

Expected: compile failure because `seamWhiteCoverage` is missing, then assertion failures until composition is implemented.

- [ ] **Step 3: Add validated seam coverage configuration**

In `ScrollStitchConfig` add:

```cpp
double seamWhiteCoverage = 0.0;
```

Extend config validation with `validUnit(config.seamWhiteCoverage)`. Zero preserves existing core behavior for non-macOS consumers and unit tests that do not opt in.

- [ ] **Step 4: Implement span boundaries and BGRA white blending**

Add a helper that returns ordered output span lengths for pending-up, committed segments, and pending-down. Convert lengths to seam rows by accumulating every span after the first.

Use this exact pixel rule and leave alpha unchanged:

```cpp
void blendWhite(std::uint8_t* row, int width, double coverage)
{
    for (int x = 0; x < width; ++x) {
        auto* pixel = row + static_cast<std::size_t>(x) * 4U;
        for (std::size_t channel = 0; channel < 3U; ++channel) {
            const double value = pixel[channel]
                + (255.0 - pixel[channel]) * coverage;
            pixel[channel] = static_cast<std::uint8_t>(std::lround(value));
        }
    }
}
```

In `copyFinalPixels`, mark a row when the top-down `outputRow` appears in the seam-row set. Copy source pixels first, then blend the destination row. Do not insert rows or change `outputHeight`.

In `previewWithSize`, render the preview normally, map each source seam with:

```cpp
const int previewY = std::min(
    previewHeight - 1,
    static_cast<int>(
        static_cast<std::int64_t>(sourceSeam) * previewHeight / sourceHeight));
```

Blend that preview row after resampling so aggressive downsampling cannot erase the marker.

- [ ] **Step 5: Run the focused and full core suites**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ctest --test-dir build --output-on-failure
```

Expected: `8/8` core tests pass; output dimensions remain unchanged.

- [ ] **Step 6: Commit core seam composition**

```bash
git add core/include/snipory/core/scroll/ScrollStitchSession.h core/src/scroll/ScrollStitchSession.cpp core/tests/TestScrollStitchSession.cpp
git commit -m "feat(core): render subtle scroll capture seams"
```

---

### Task 5: Convert 0.1pt to source-scale coverage in the macOS bridge

**Files:**
- Modify: `platforms/mac/Sources/Bridge/ScrollCaptureBridge.mm:47-65,460-490`
- Modify: `platforms/mac/Tests/ScrollCaptureBridgeTests.swift:230-280`

- [ ] **Step 1: Update the bridge seam test to require 0.1pt-equivalent coverage**

Split the existing seam-pixel preservation test into 1× and 2× cases. For a source channel value `v`, expected output is:

```swift
func expectedSeamChannel(_ value: UInt8, scale: CGFloat) -> UInt8 {
    let coverage = min(1, 0.1 * scale)
    return UInt8((CGFloat(value) + (255 - CGFloat(value)) * coverage).rounded())
}
```

Assert:

- 1× final seam uses 10% white coverage.
- 2× final seam uses 20% white coverage.
- Neighboring rows are unchanged.
- Preview and final each contain a seam at the mapped boundary.
- The final pixel height is still the exact stitched document height.

- [ ] **Step 2: Run bridge tests and verify expected pixels fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/ScrollCaptureBridgeTests
```

Expected: seam pixel assertions fail because the bridge currently creates a core session without seam coverage.

- [ ] **Step 3: Pass backing-scale coverage when the first frame creates the session**

Change `makeSession` to accept the scale:

```objc
std::unique_ptr<ScrollStitchSession> makeSession(
    std::size_t maximumAcceptedBytes,
    CGFloat sourceScale)
{
    ScrollStitchConfig config;
    config.maximumAcceptedBytes = maximumAcceptedBytes;
    config.seamWhiteCoverage = std::clamp(
        0.1 * static_cast<double>(sourceScale),
        0.0,
        1.0);
    return std::make_unique<ScrollStitchSession>(config);
}
```

Call it only after `frameFromImage` has returned a valid `sourceScale`:

```objc
implementation->session = makeSession(
    implementation->maximumAcceptedBytes,
    sourceScale);
```

Do not change `imageFromFrame`, `mappedFinalImage`, preview panel layout, or `viewportIndicatorView` styling.

- [ ] **Step 4: Run bridge and presentation suites**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/ScrollCaptureBridgeTests -only-testing:xxsnapTests/ScrollCapturePresentationTests
```

Expected: both suites pass; existing blue viewport indicator assertions remain unchanged.

- [ ] **Step 5: Commit the bridge scale behavior**

```bash
git add platforms/mac/Sources/Bridge/ScrollCaptureBridge.mm platforms/mac/Tests/ScrollCaptureBridgeTests.swift
git commit -m "fix(mac): match seam weight across display scales"
```

---

### Task 6: Verify end-to-end behavior and update the manual contract

**Files:**
- Modify: `platforms/mac/Tests/manual-capture-checklist.md`

- [ ] **Step 1: Add manual checklist rows for the approved behavior**

Add explicit rows:

```markdown
| C1 | Whole chat window, Accessibility available | Click Scroll Capture | Selection snaps to the main message scroll area; fixed sidebar/title/input are excluded; outline and handles are green. | 待人工 |
| C2 | Non-scrollable region or Accessibility unavailable | Click Scroll Capture | Original selection stays unchanged and blue; existing fallback capture remains available. | 待人工 |
| C3 | Scroll region height 599pt | One automatic step | Step distance is 30% of region height. | 待人工 |
| C4 | Scroll region height 600pt or taller | One automatic step | Step distance is 50% of region height. | 待人工 |
| C5 | Retina and non-Retina stitched output | Inspect preview and exported PNG at 100% | Each accepted segment boundary has the same subtle white 0.1pt-equivalent seam; no blue seam appears. | 待人工 |
| C6 | Left preview and viewport indicator | Start and finish capture | Preview remains on the existing left side and the viewport indicator remains blue with its existing geometry. | 待人工 |
```

- [ ] **Step 2: Run all focused automated verification**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ctest --test-dir build --output-on-failure
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/ScrollCaptureTargetDetectorTests -only-testing:xxsnapTests/ScrollCaptureBridgeTests -only-testing:xxsnapTests/ScrollCapturePresentationTests -only-testing:xxsnapTests/ScrollCaptureSessionTests
```

Expected: core `8/8` and every focused macOS scroll-capture test pass.

- [ ] **Step 3: Run the full macOS test target and compare against baseline**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

Expected: no new failures in scroll capture, target detection, preview, selection snap, or seam output. If the known environment-sensitive baseline failures recur, extract the summary with:

```bash
latest_result=$(/usr/bin/find build/xcode-derived/Logs/Test -name '*.xcresult' -print0 | /usr/bin/xargs -0 ls -td | /usr/bin/head -n 1)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcresulttool get test-results summary --path "$latest_result"
```

Report those separately; do not weaken new scroll-capture assertions to hide them.

- [ ] **Step 4: Build and restart the exact tested debug app**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/.worktrees/scroll-capture-impl/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap"
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/.worktrees/scroll-capture-impl/build/xcode-derived/Build/Products/Debug/XxSnap.app
pgrep -af "XxSnap.app/Contents/MacOS/XxSnap"
```

Expected: one process from this worktree's `build/xcode-derived` path.

- [ ] **Step 5: Commit the verification checklist**

```bash
git add platforms/mac/Tests/manual-capture-checklist.md
git commit -m "docs(mac): verify chat scroll capture targeting"
```

- [ ] **Step 6: Confirm final repository state**

Run:

```bash
git status --short --branch
git log --oneline -8
```

Expected: `fix/scroll-capture-chat-regions` is clean and contains one focused commit per task.
