# Local Eraser Mask Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把矩形橡皮擦从“删除相交标注”改为“独立 mask 局部擦除标注层”，并确保点擦除、现有标注工具、马赛克预览和导出性能不被拖慢。

**Architecture:** 新增 `EraserMask` 数据模型，mask 只记录局部矩形和受影响 annotation id，不修改原截图，也不拆分现有标注对象。矩形擦除提交时创建 mask；被 mask 命中的标注进入 damaged 状态，不再允许选中/拖动/编辑，但仍可被点擦除整体删除。渲染层新增带 mask 的独立入口，默认无 mask 时继续走当前 `render(image:annotations:)` 快路径。

**Tech Stack:** Swift/AppKit, XCTest, CoreGraphics, xxsnap mac overlay, existing Xcode project `platforms/mac/xxsnap.xcodeproj`.

---

## File Structure

- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
  - Add `AnnotationID`, `EraserMask`, `CaptureSelectionResult.eraserMasks`.
  - Add `CaptureAnnotation.id` with a default UUID.
  - Add masked renderer overload `render(image:annotations:eraserMasks:)`.
  - Keep existing `render(image:annotations:)` unchanged as the default no-mask fast path.
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
  - Store `eraserMasks` separately from `annotations`.
  - Change rectangle eraser commit to add a mask instead of deleting annotations.
  - Add undo/redo history cases for mask add and clear-all.
  - Skip damaged annotations in normal selection/edit hit testing.
  - Allow point eraser to delete damaged annotations and prune their mask references.
  - Pass `eraserMasks` into `CaptureSelectionResult`.
  - Apply masks during overlay drawing and mosaic composite cache keys.
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift`
  - Use the new renderer overload when copying/saving annotated captures.
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`
  - Update rectangle eraser tests from deletion semantics to mask semantics.
  - Add renderer, overlay, undo/redo, clear-all, damaged-selection, mosaic, export, and regression tests.

## Performance Contract

- No mask, no overhead: when `eraserMasks.isEmpty`, `CaptureAnnotationRenderer.render(image:annotations:eraserMasks:)` must immediately call `render(image:annotations:)`.
- No per-frame full recomposite unless mask exists: `SelectionOverlayWindow.drawAnnotations()` uses current drawing path when `eraserMasks.isEmpty`.
- Local mask only: rectangle eraser computes affected annotations once on mouse-up, stores annotation ids, and does no continuous hit testing during drag.
- Mosaic cache keys include a compact mask signature only when masks exist.
- Point eraser remains an object-delete path and must not invoke masked rendering.

## Task 1: Add Stable Annotation IDs And Mask Model

**Files:**
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing model tests**

Add these tests near the existing eraser tests in `SelectionToolbarStateTests`.

```swift
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
```

- [ ] **Step 2: Run tests and confirm they fail**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testCaptureAnnotationsReceiveStableUniqueIDs -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserMaskStoresLocalRectAndAffectedAnnotationIDs test
```

Expected: FAIL with compile errors for missing `CaptureAnnotation.id` and `EraserMask`.

- [ ] **Step 3: Implement the model**

In `CaptureAnnotationRenderer.swift`, add the id type and mask struct before `CaptureAnnotation`.

```swift
typealias AnnotationID = UUID

struct EraserMask: Equatable {
    var id: UUID = UUID()
    var rect: NSRect
    var affectedAnnotationIDs: Set<AnnotationID>
}
```

Change `CaptureAnnotation` to include a default id.

```swift
struct CaptureAnnotation {
    var id: AnnotationID = UUID()
    var kind: CaptureAnnotationKind
    var rect: NSRect
    var style: CaptureAnnotationStyle
    var rotationAngle: CGFloat = 0
    var arrowLine: CaptureArrowLine?
    var brushPath: CaptureBrushPath?
    var markerLine: CaptureMarkerLine?
    var text: String?
    var numberMarkType: CaptureNumberMarkType?
    var numberSequenceIndex: Int?
    var numberSequenceIsManual = false
    var magnifierShape: CaptureMagnifierShape?
    var magnifierZoom: CGFloat?
    var mosaicStroke: CaptureMosaicStroke?
    var mosaicRedaction: CaptureMosaicRedaction?
}
```

Change `CaptureSelectionResult`.

```swift
struct CaptureSelectionResult {
    var screenRect: NSRect
    var snapshotRect: NSRect
    var annotations: [CaptureAnnotation]
    var eraserMasks: [EraserMask] = []
    var action: CaptureCompletionAction
}
```

- [ ] **Step 4: Run tests and confirm they pass**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testCaptureAnnotationsReceiveStableUniqueIDs -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserMaskStoresLocalRectAndAffectedAnnotationIDs test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): add eraser mask model"
```

## Task 2: Add Masked Renderer Fast Path And Pixel Coverage

**Files:**
- Modify: `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing renderer tests**

Add renderer tests near existing `CaptureAnnotationRenderer.render` tests.

```swift
func testRendererWithoutEraserMasksMatchesExistingRenderPath() throws {
    let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
    var style = CaptureAnnotationStyle()
    style.strokeColor = .red
    style.fillEnabled = true
    style.fillColor = .red
    let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 40, height: 30), style: style)

    let existing = CaptureAnnotationRenderer.render(image: image, annotations: [annotation])
    let maskedEntry = CaptureAnnotationRenderer.render(image: image, annotations: [annotation], eraserMasks: [])

    XCTAssertEqual(try rgbaPixel(in: existing, at: NSPoint(x: 20, y: 20)), try rgbaPixel(in: maskedEntry, at: NSPoint(x: 20, y: 20)))
}

func testRendererAppliesEraserMaskOnlyToAffectedAnnotationLayer() throws {
    let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
    var redStyle = CaptureAnnotationStyle()
    redStyle.strokeColor = .red
    redStyle.fillEnabled = true
    redStyle.fillColor = .red
    var blueStyle = CaptureAnnotationStyle()
    blueStyle.strokeColor = .blue
    blueStyle.fillEnabled = true
    blueStyle.fillColor = .blue

    let red = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 40, height: 30), style: redStyle)
    let blue = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 50, y: 10, width: 20, height: 30), style: blueStyle)
    let mask = EraserMask(rect: NSRect(x: 18, y: 18, width: 12, height: 12), affectedAnnotationIDs: [red.id])

    let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [red, blue], eraserMasks: [mask])

    XCTAssertEqual(try rgbaPixel(in: rendered, at: NSPoint(x: 22, y: 22))?.hexRGB, "#FFFFFF")
    XCTAssertEqual(try rgbaPixel(in: rendered, at: NSPoint(x: 14, y: 14))?.hexRGB, "#FF0000")
    XCTAssertEqual(try rgbaPixel(in: rendered, at: NSPoint(x: 58, y: 22))?.hexRGB, "#0000FF")
}
```

- [ ] **Step 2: Run tests and confirm they fail**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testRendererWithoutEraserMasksMatchesExistingRenderPath -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testRendererAppliesEraserMaskOnlyToAffectedAnnotationLayer test
```

Expected: FAIL with missing renderer overload.

- [ ] **Step 3: Implement masked renderer**

Keep the existing method unchanged and add the overload.

```swift
static func render(image: NSImage, annotations: [CaptureAnnotation], eraserMasks: [EraserMask]) -> NSImage {
    guard !eraserMasks.isEmpty else {
        return render(image: image, annotations: annotations)
    }
    guard !annotations.isEmpty else {
        return image
    }

    return renderImage(image: image, annotations: annotations, eraserMasks: eraserMasks) ?? image
}
```

Refactor the current `renderImage(image:annotations:)` to draw through a helper, then add the masked variant.

```swift
private static func renderImage(
    image: NSImage,
    annotations: [CaptureAnnotation],
    eraserMasks: [EraserMask] = []
) -> NSImage? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = makeRenderContext(width: cgImage.width, height: cgImage.height, colorSpace: colorSpace) else {
        return nil
    }

    context.interpolationQuality = .none
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

    let scaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
    let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)

    if eraserMasks.isEmpty {
        drawAnnotations(annotations, in: context, sourceImage: cgImage, scaleX: scaleX, scaleY: scaleY)
    } else if let layer = makeAnnotationLayer(
        width: cgImage.width,
        height: cgImage.height,
        colorSpace: colorSpace,
        sourceImage: cgImage,
        annotations: annotations,
        eraserMasks: eraserMasks,
        scaleX: scaleX,
        scaleY: scaleY
    ) {
        context.draw(layer, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    }

    guard let renderedImage = context.makeImage() else {
        return nil
    }

    return NSImage(cgImage: renderedImage, size: image.size)
}

private static func drawAnnotations(
    _ annotations: [CaptureAnnotation],
    in context: CGContext,
    sourceImage: CGImage,
    scaleX: CGFloat,
    scaleY: CGFloat
) {
    for annotation in annotations {
        if isMosaicAnnotation(annotation) {
            drawMosaicAnnotation(annotation, in: context, scaleX: scaleX, scaleY: scaleY)
        } else {
            draw(annotation, in: context, sourceImage: sourceImage, scaleX: scaleX, scaleY: scaleY)
        }
    }
}
```

Add the isolated annotation layer. Draw unaffected annotations directly; draw affected annotations into a temporary per-annotation layer, clear only that annotation's masks, then composite it back. This preserves stacking order without allowing one mask to erase unrelated overlapping annotations.

```swift
private static func makeAnnotationLayer(
    width: Int,
    height: Int,
    colorSpace: CGColorSpace,
    sourceImage: CGImage,
    annotations: [CaptureAnnotation],
    eraserMasks: [EraserMask],
    scaleX: CGFloat,
    scaleY: CGFloat
) -> CGImage? {
    guard let layerContext = makeRenderContext(width: width, height: height, colorSpace: colorSpace) else {
        return nil
    }
    layerContext.interpolationQuality = .none

    for annotation in annotations {
        let masksForAnnotation = eraserMasks.filter { $0.affectedAnnotationIDs.contains(annotation.id) }
        guard !masksForAnnotation.isEmpty else {
            drawAnnotations([annotation], in: layerContext, sourceImage: sourceImage, scaleX: scaleX, scaleY: scaleY)
            continue
        }
        guard let annotationImage = makeMaskedAnnotationImage(
            width: width,
            height: height,
            colorSpace: colorSpace,
            sourceImage: sourceImage,
            annotation: annotation,
            eraserMasks: masksForAnnotation,
            scaleX: scaleX,
            scaleY: scaleY
        ) else {
            continue
        }
        layerContext.draw(annotationImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    return layerContext.makeImage()
}

private static func makeMaskedAnnotationImage(
    width: Int,
    height: Int,
    colorSpace: CGColorSpace,
    sourceImage: CGImage,
    annotation: CaptureAnnotation,
    eraserMasks: [EraserMask],
    scaleX: CGFloat,
    scaleY: CGFloat
) -> CGImage? {
    guard let context = makeRenderContext(width: width, height: height, colorSpace: colorSpace) else {
        return nil
    }
    context.interpolationQuality = .none
    drawAnnotations([annotation], in: context, sourceImage: sourceImage, scaleX: scaleX, scaleY: scaleY)

    context.saveGState()
    context.setBlendMode(.clear)
    for mask in eraserMasks {
        let pixelRect = CGRect(
            x: mask.rect.minX * scaleX,
            y: mask.rect.minY * scaleY,
            width: mask.rect.width * scaleX,
            height: mask.rect.height * scaleY
        ).standardized
        context.fill(pixelRect)
    }
    context.restoreGState()

    return context.makeImage()
}
```

- [ ] **Step 4: Run tests and confirm they pass**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testRendererWithoutEraserMasksMatchesExistingRenderPath -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testRendererAppliesEraserMaskOnlyToAffectedAnnotationLayer test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): render eraser masks on annotation layer"
```

## Task 3: Change Rectangle Eraser To Create Masks

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Update rectangle eraser tests to mask semantics**

Rename and replace the current deletion assertions.

```swift
func testEraserRectangleCreatesLocalMaskAndKeepsAnnotations() throws {
    let window = SelectionOverlayWindow(backgroundImage: nil) { _ in }
    let selection = NSRect(x: 100, y: 100, width: 300, height: 220)
    window.test_setLockedSelectionRect(selection)
    window.test_setAnnotations([
        CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 35, y: 45, width: 60, height: 60), style: CaptureAnnotationStyle()),
        CaptureAnnotation(kind: .ellipse, rect: NSRect(x: 120, y: 75, width: 70, height: 60), style: CaptureAnnotationStyle()),
        CaptureAnnotation(kind: .text, rect: NSRect(x: 210, y: 125, width: 64, height: 36), style: CaptureAnnotationStyle(), text: "keep")
    ])
    window.test_activateEraserTool()
    window.test_mouseDown(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))
    window.test_mouseUp(at: try XCTUnwrap(window.test_eraserRectangleOptionPoint()))

    window.test_drag(from: NSPoint(x: 120, y: 130), to: NSPoint(x: 300, y: 225))

    XCTAssertEqual(window.test_annotationCount, 3)
    XCTAssertEqual(window.test_eraserMaskCount, 1)
    XCTAssertEqual(window.test_eraserMask(at: 0)?.rect, NSRect(x: 20, y: 30, width: 180, height: 95))
    XCTAssertEqual(window.test_damagedAnnotationCount, 2)

    window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command])
    XCTAssertEqual(window.test_annotationCount, 3)
    XCTAssertEqual(window.test_eraserMaskCount, 0)
    XCTAssertEqual(window.test_damagedAnnotationCount, 0)

    window.test_keyDown(keyCode: 6, charactersIgnoringModifiers: "z", modifierFlags: [.command, .shift])
    XCTAssertEqual(window.test_annotationCount, 3)
    XCTAssertEqual(window.test_eraserMaskCount, 1)
    XCTAssertEqual(window.test_damagedAnnotationCount, 2)
}
```

Add a representative kind test replacing the old line/mosaic deletion semantics.

```swift
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
```

- [ ] **Step 2: Run tests and confirm they fail**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserRectangleCreatesLocalMaskAndKeepsAnnotations -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserRectangleCreatesMaskForLineBrushAndMosaicAnnotations test
```

Expected: FAIL because rectangle eraser still deletes annotations and test helpers are missing.

- [ ] **Step 3: Add mask storage, helpers, and history cases**

Near the annotation history definitions in `SelectionOverlayWindow.swift`, extend history.

```swift
private enum AnnotationHistoryEntry {
    case add(annotation: CaptureAnnotation, index: Int)
    case delete(annotation: CaptureAnnotation, index: Int, masks: [EraserMask])
    case deleteMany(entries: [DeletedAnnotationEntry], masks: [EraserMask])
    case addEraserMask(mask: EraserMask)
}
```

Add mask state.

```swift
private var eraserMasks: [EraserMask] = []

private var damagedAnnotationIDs: Set<AnnotationID> {
    Set(eraserMasks.flatMap(\.affectedAnnotationIDs))
}
```

Update test-only extension.

```swift
var test_eraserMaskCount: Int {
    eraserMasks.count
}

func test_eraserMask(at index: Int) -> EraserMask? {
    eraserMasks.indices.contains(index) ? eraserMasks[index] : nil
}

var test_damagedAnnotationIDs: Set<AnnotationID> {
    damagedAnnotationIDs
}

var test_damagedAnnotationCount: Int {
    damagedAnnotationIDs.count
}
```

- [ ] **Step 4: Change rectangle commit to create a local mask**

Replace `commitEraserRectangle()`.

```swift
private func commitEraserRectangle() {
    guard let overlayRect = eraserRectanglePreviewRect, overlayRect.width >= 3, overlayRect.height >= 3 else {
        needsDisplay = true
        return
    }

    let affectedIDs = Set(
        annotations.compactMap { annotation in
            eraserRectangleIntersects(overlayRect, annotation: annotation) ? annotation.id : nil
        }
    )
    guard !affectedIDs.isEmpty,
          let localRect = localRectFromOverlayEraserRect(overlayRect)
    else {
        needsDisplay = true
        return
    }

    let mask = EraserMask(rect: localRect, affectedAnnotationIDs: affectedIDs)
    eraserMasks.append(mask)
    undoAnnotationEntries.append(.addEraserMask(mask: mask))
    clearRedoAnnotationHistory()
    selectedAnnotationIndex = nil
    editingTextAnnotationIndex = nil
    clearNumberEditing()
    clearPendingTextEdit()
    removeTextEditor()
    resetMosaicPreviewCaches()
    needsDisplay = true
}

private func localRectFromOverlayEraserRect(_ rect: NSRect) -> NSRect? {
    guard let lockedSelectionRect else {
        return nil
    }
    return NSRect(
        x: rect.minX - lockedSelectionRect.minX,
        y: rect.minY - lockedSelectionRect.minY,
        width: rect.width,
        height: rect.height
    ).standardized.intersection(NSRect(origin: .zero, size: lockedSelectionRect.size))
}
```

- [ ] **Step 5: Update undo/redo for mask add**

Add handling in `applyUndo(_:)`.

```swift
case .delete(let annotation, let index, let masks):
    let insertionIndex = min(max(index, 0), annotations.count)
    annotations.insert(annotation, at: insertionIndex)
    eraserMasks.append(contentsOf: masks)
    selectedAnnotationIndex = insertionIndex
    finishAnnotationHistoryMutation(affectedKind: annotation.kind, selectedIndex: insertionIndex)
case .deleteMany(let entries, let masks):
    let sorted = entries.sorted { $0.index < $1.index }
    for entry in sorted {
        let insertionIndex = min(max(entry.index, 0), annotations.count)
        annotations.insert(entry.annotation, at: insertionIndex)
    }
    eraserMasks.append(contentsOf: masks)
    finishAnnotationHistoryMutation(affectedKinds: sorted.map(\.annotation.kind), selectedIndex: nil)
case .addEraserMask(let mask):
    eraserMasks.removeAll { $0.id == mask.id }
    finishAnnotationHistoryMutation(affectedKinds: annotations.filter { mask.affectedAnnotationIDs.contains($0.id) }.map(\.kind), selectedIndex: nil)
```

Add handling in `applyRedo(_:)`.

```swift
case .delete(let annotation, let index, let masks):
    let removalIndex: Int? = annotations.indices.contains(index) ? index : nil
    if let removalIndex {
        annotations.remove(at: removalIndex)
    }
    eraserMasks.removeAll { mask in
        mask.affectedAnnotationIDs.contains(annotation.id) || masks.contains(where: { $0.id == mask.id })
    }
    selectedAnnotationIndex = nil
    finishAnnotationHistoryMutation(affectedKind: annotation.kind, selectedIndex: nil)
case .deleteMany(let entries, let masks):
    for entry in entries.sorted(by: { $0.index > $1.index }) where annotations.indices.contains(entry.index) {
        annotations.remove(at: entry.index)
    }
    let deletedIDs = Set(entries.map(\.annotation.id))
    eraserMasks.removeAll { mask in
        !mask.affectedAnnotationIDs.isDisjoint(with: deletedIDs) || masks.contains(where: { $0.id == mask.id })
    }
    finishAnnotationHistoryMutation(affectedKinds: entries.map(\.annotation.kind), selectedIndex: nil)
case .addEraserMask(let mask):
    eraserMasks.append(mask)
    finishAnnotationHistoryMutation(affectedKinds: annotations.filter { mask.affectedAnnotationIDs.contains($0.id) }.map(\.kind), selectedIndex: nil)
```

Update current `deleteAnnotations(at:)` history append to include masks removed by those deleted annotations.

```swift
let removedAnnotationIDs = Set(entries.map(\.annotation.id))
let removedMasks = eraserMasks.filter { !$0.affectedAnnotationIDs.isDisjoint(with: removedAnnotationIDs) }
eraserMasks.removeAll { !$0.affectedAnnotationIDs.isDisjoint(with: removedAnnotationIDs) }
undoAnnotationEntries.append(.deleteMany(entries: entries, masks: removedMasks))
```

- [ ] **Step 6: Run tests and confirm they pass**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserRectangleCreatesLocalMaskAndKeepsAnnotations -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserRectangleCreatesMaskForLineBrushAndMosaicAnnotations test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): create local masks from rectangle eraser"
```

## Task 4: Block Editing Damaged Annotations While Preserving Point Delete

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing interaction tests**

```swift
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
```

- [ ] **Step 2: Run tests and confirm they fail**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testDamagedAnnotationCannotBeSelectedOrDragged -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testPointEraserCanDeleteDamagedAnnotationAndItsMasks test
```

Expected: FAIL because damaged annotations are still selectable and helper is missing.

- [ ] **Step 3: Add damaged helpers and selection guard**

Add helper methods.

```swift
private func isDamagedAnnotation(_ annotation: CaptureAnnotation) -> Bool {
    damagedAnnotationIDs.contains(annotation.id)
}

private func annotationIsEditable(at index: Int) -> Bool {
    annotations.indices.contains(index) && !isDamagedAnnotation(annotations[index])
}
```

Add test helper.

```swift
func test_addEraserMask(_ mask: EraserMask) {
    eraserMasks.append(mask)
    needsDisplay = true
}
```

Guard normal selection hit-test functions that return editable indices. Apply this pattern in `textAnnotationIndex(at:)`, `textAnnotationBorderIndex(at:)`, number control hit testing, shape/line/brush/mosaic selection hit testing, drag-start selection, and selected outline drawing.

```swift
for index in annotations.indices.reversed() where annotationIsEditable(at: index) && annotations[index].kind == .text {
    if textAnnotationHitContains(point: point, annotation: annotations[index]) {
        return index
    }
}
```

Do not add this guard to `eraserAnnotationIndex(at:)`; point eraser must still hit damaged annotations.

- [ ] **Step 4: Prune masks when deleting a damaged annotation**

Update `deleteAnnotation(at:)`.

```swift
let removedMasks = removeMasksReferencing(annotationID: removed.id)
undoAnnotationEntries.append(.delete(annotation: removed, index: deletionIndex, masks: removedMasks))
```

```swift
private func removeMasksReferencing(annotationID: AnnotationID) -> [EraserMask] {
    let removed = eraserMasks.filter { $0.affectedAnnotationIDs.contains(annotationID) }
    eraserMasks.removeAll { $0.affectedAnnotationIDs.contains(annotationID) }
    return removed
}
```

- [ ] **Step 5: Run tests and confirm they pass**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testDamagedAnnotationCannotBeSelectedOrDragged -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testPointEraserCanDeleteDamagedAnnotationAndItsMasks test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): block editing erased annotations"
```

## Task 5: Apply Masks In Overlay Drawing And Mosaic Preview

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing visual tests**

```swift
func testOverlayAppliesLocalEraserMaskToAnnotationPixels() throws {
    let image = solidImage(size: NSSize(width: 320, height: 220), color: .white)
    let window = SelectionOverlayWindow(backgroundImage: image) { _ in }
    let selection = NSRect(x: 40, y: 30, width: 220, height: 140)
    var style = CaptureAnnotationStyle()
    style.strokeColor = .red
    style.fillEnabled = true
    style.fillColor = .red
    let annotation = CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 30, y: 30, width: 100, height: 70), style: style)
    window.test_setLockedSelectionRect(selection)
    window.test_setAnnotations([annotation])
    window.test_addEraserMask(EraserMask(rect: NSRect(x: 55, y: 45, width: 25, height: 25), affectedAnnotationIDs: [annotation.id]))

    let rendered = try XCTUnwrap(window.test_renderedOverlayImage())

    XCTAssertEqual(try rgbaPixel(in: rendered, at: NSPoint(x: selection.minX + 60, y: rendered.size.height - selection.minY - 50))?.hexRGB, "#FFFFFF")
    XCTAssertEqual(try rgbaPixel(in: rendered, at: NSPoint(x: selection.minX + 35, y: rendered.size.height - selection.minY - 35))?.hexRGB, "#FF0000")
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
    window.test_addEraserMask(EraserMask(rect: NSRect(x: 55, y: 45, width: 25, height: 25), affectedAnnotationIDs: [mosaic.id]))

    let rendered = try XCTUnwrap(window.test_renderedOverlayImage())
    let original = try XCTUnwrap(rgbaPixel(in: image, at: NSPoint(x: selection.minX + 60, y: selection.minY + 50)))
    let overlay = try XCTUnwrap(rgbaPixel(in: rendered, at: NSPoint(x: selection.minX + 60, y: rendered.size.height - selection.minY - 50)))

    XCTAssertLessThan(abs(Int(overlay.red) - Int(original.red)), 4)
    XCTAssertLessThan(abs(Int(overlay.green) - Int(original.green)), 4)
    XCTAssertLessThan(abs(Int(overlay.blue) - Int(original.blue)), 4)
}
```

- [ ] **Step 2: Run tests and confirm they fail**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testOverlayAppliesLocalEraserMaskToAnnotationPixels -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testOverlayEraserMaskRevealsOriginalScreenshotThroughMosaic test
```

Expected: FAIL because overlay drawing does not apply masks yet.

- [ ] **Step 3: Add masked overlay drawing path**

Keep existing draw path when there are no masks.

```swift
private func drawAnnotations() {
    guard !eraserMasks.isEmpty else {
        drawAnnotationsWithoutEraserMasks()
        return
    }
    drawAnnotationsWithEraserMasks()
}
```

Move the current body of `drawAnnotations()` into `drawAnnotationsWithoutEraserMasks()`.

Add the masked path by rendering the selected crop once and drawing it into the selection rect.

```swift
private func drawAnnotationsWithEraserMasks() {
    guard let lockedSelectionRect,
          let backgroundImage,
          let crop = crop(image: backgroundImage, to: lockedSelectionRect)
    else {
        drawAnnotationsWithoutEraserMasks()
        return
    }

    let localAnnotations = annotations.map(overlayAnnotation)
    let rendered = CaptureAnnotationRenderer.render(
        image: crop,
        annotations: localAnnotations,
        eraserMasks: eraserMasks
    )
    rendered.draw(in: lockedSelectionRect, from: NSRect(origin: .zero, size: rendered.size), operation: .sourceOver, fraction: 1)

    if let selectedIndex,
       annotations.indices.contains(selectedIndex),
       !isDamagedAnnotation(annotations[selectedIndex]),
       shouldDrawSelectedAnnotationOutline(annotations[selectedIndex]) {
        drawSelectedAnnotationOutline(annotations[selectedIndex])
    }
}
```

If `crop(image:to:)` expects image-local coordinates, use `lockedSelectionRect` directly only when the background image has overlay coordinates. Otherwise add a conversion helper:

```swift
private func cropRectForLockedSelection() -> NSRect? {
    guard let lockedSelectionRect else {
        return nil
    }
    return lockedSelectionRect.standardized
}
```

- [ ] **Step 4: Include masks in mosaic cache keys**

Update the cache key helper used by `mosaicPreviewComposite(for:)`.

```swift
private func eraserMaskCacheSignature(for annotations: [CaptureAnnotation]) -> String {
    guard !eraserMasks.isEmpty else {
        return "no-mask"
    }
    let ids = Set(annotations.map(\.id))
    return eraserMasks
        .filter { !$0.affectedAnnotationIDs.isDisjoint(with: ids) }
        .map { mask in
            let rect = mask.rect.standardized
            return "\(mask.id.uuidString):\(Int(rect.minX)):\(Int(rect.minY)):\(Int(rect.width)):\(Int(rect.height))"
        }
        .joined(separator: ";")
}
```

Append this signature to the mosaic composite key only when masks exist.

```swift
if !eraserMasks.isEmpty {
    parts.append("eraserMasks=\(eraserMaskCacheSignature(for: annotations))")
}
```

- [ ] **Step 5: Run tests and confirm they pass**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testOverlayAppliesLocalEraserMaskToAnnotationPixels -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testOverlayEraserMaskRevealsOriginalScreenshotThroughMosaic test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): draw eraser masks in overlay"
```

## Task 6: Wire Masks Into Export And Clear-All

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift`
- Test: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Write failing export and clear-all tests**

```swift
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
```

- [ ] **Step 2: Run tests and confirm they fail**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testCaptureResultIncludesEraserMasks -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserClearAllRemovesAnnotationsAndMasksAndSupportsUndoRedo test
```

Expected: FAIL because finish and clear-all do not preserve masks.

- [ ] **Step 3: Pass masks through finish**

Update `finish(action:)`.

```swift
selectionDidFinish?(
    CaptureSelectionResult(
        screenRect: window.convertToScreen(lockedSelectionRect).standardized,
        snapshotRect: lockedSelectionRect.standardized,
        annotations: annotations,
        eraserMasks: eraserMasks,
        action: action
    )
)
```

- [ ] **Step 4: Update clear-all**

Replace the clear-all click action with a dedicated helper.

```swift
private func clearAllAnnotationsAndMasks() -> Bool {
    let entries = annotations.indices.map { DeletedAnnotationEntry(annotation: annotations[$0], index: $0) }
    let masks = eraserMasks
    guard !entries.isEmpty || !masks.isEmpty else {
        needsDisplay = true
        return false
    }
    annotations.removeAll()
    eraserMasks.removeAll()
    undoAnnotationEntries.append(.deleteMany(entries: entries, masks: masks))
    clearRedoAnnotationHistory()
    finishAnnotationHistoryMutation(affectedKinds: entries.map(\.annotation.kind), selectedIndex: nil)
    needsDisplay = true
    return true
}
```

Use it in `handleEraserOptionsClick`.

```swift
_ = clearAllAnnotationsAndMasks()
```

- [ ] **Step 5: Wire export renderer**

In `CaptureCoordinator.swift`, replace existing export render calls that use only annotations.

```swift
let rendered = CaptureAnnotationRenderer.render(
    image: snapshot,
    annotations: result.annotations,
    eraserMasks: result.eraserMasks
)
```

Use the same overload for copy and save paths. Leave unannotated no-mask exports unchanged by the renderer fast path.

- [ ] **Step 6: Run tests and confirm they pass**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testCaptureResultIncludesEraserMasks -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserClearAllRemovesAnnotationsAndMasksAndSupportsUndoRedo test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/App/CaptureCoordinator.swift platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "feat(mac): export eraser masks"
```

## Task 7: Regression And Performance Guard Tests

**Files:**
- Modify: `platforms/mac/Tests/SelectionToolbarStateTests.swift`

- [ ] **Step 1: Add focused regression tests for existing tools**

Add one compact regression that draws existing tools after enabling and disabling eraser. This verifies eraser state stays isolated.

```swift
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
```

- [ ] **Step 2: Add no-mask fast-path renderer performance guard**

```swift
func testRendererNoMaskFastPathReturnsOriginalImageWhenNoAnnotations() {
    let image = solidImage(size: NSSize(width: 80, height: 60), color: .white)
    let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [], eraserMasks: [])

    XCTAssertTrue(rendered === image)
}
```

If `NSImage` identity comparison does not compile, use pointer identity through `rendered === image` only after confirming `NSImage` is a class in AppKit; otherwise compare `rendered.size` and pixel values and keep the fast path visible in code review.

- [ ] **Step 3: Run focused regression tests**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testExistingToolsStillCreateAnnotationsAfterUsingEraserTool -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testRendererNoMaskFastPathReturnsOriginalImageWhenNoAnnotations test
```

Expected: PASS.

- [ ] **Step 4: Run eraser regression cluster**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserToolClearsAndSuppressesColorSampler -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserOptionsSwitchRectangleModeAndCursor -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserRectangleDragShowsBlueDashedPreview -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserClickDeletesRectangleAnnotation -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEraserDeleteSupportsUndoAndRedo test
```

Expected: PASS.

- [ ] **Step 5: Run existing tool regression cluster**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testEyedropperSamplesVisibleAnnotationAndCopiesOnlyColor -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testMainToolbarPlacesEyedropperImmediatelyBeforeMosaic -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testOverlayWindowActivatesEraserToolWithPointModeOptionsToolbar -only-testing:xxsnapMacTests/SelectionToolbarStateTests/testNumberMarkDiameterTracksSnipasteReferenceSizes test
```

Expected: PASS.

- [ ] **Step 6: Run build**

Run:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add platforms/mac/Tests/SelectionToolbarStateTests.swift
git commit -m "test(mac): cover eraser mask regressions"
```

## Task 8: Manual Smoke Check And Final Branch State

**Files:**
- No source edits expected.

- [ ] **Step 1: Restart debug app**

Run:

```bash
pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app/Contents/MacOS/xxsnap" || true
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app
pgrep -af "xxsnap.app/Contents/MacOS/xxsnap"
```

Expected: app process is running.

- [ ] **Step 2: Manual smoke matrix**

Check these flows in the app:

```text
1. Draw rectangle, arrow line, brush, mosaic rectangle.
2. Select eraser > rectangle mode; drag a rectangle across the middle of each annotation.
3. Confirm erased area reveals screenshot/base pixels and annotations remain visible outside the erased area.
4. Confirm damaged annotations cannot be selected or dragged.
5. Confirm point eraser still deletes damaged annotations.
6. Confirm clear-all removes all annotations and masks.
7. Confirm undo/redo restores masks and annotations correctly.
8. Confirm eyedropper, text, number mark, shape, arrow, brush, mosaic still activate and draw after using eraser.
9. Confirm CPU does not spike or stay high while idle, moving mouse, and dragging rectangle preview.
```

- [ ] **Step 3: Final status check**

Run:

```bash
git status --short --branch
git log --oneline --decorate -5
```

Expected: branch is `feature/eraser-mask-local`, source changes are committed, and only known unrelated untracked files remain.

## Self-Review

- Spec coverage:
  - 独立 mask 层: Tasks 1, 2, 3, 5.
  - 不影响现有工具: Performance Contract, Task 7 regression clusters.
  - 矩形局部擦除: Tasks 3 and 5.
  - 马赛克、画笔、箭头线可局部擦除: Tasks 3 and 5.
  - 被擦过后不允许选中编辑: Task 4.
  - 点擦除仍可整体删除 damaged 标注: Task 4.
  - 清除所有同时清 masks: Task 6.
  - 复制/保存导出一致: Task 6.
  - 性能优先: Performance Contract, Task 2 no-mask fast path, Task 5 cache signature, Task 7 build/regression/performance smoke.
- Placeholder scan:
  - 未发现占位标记、延期实现说明或无范围的测试说明。Each task includes exact files, code snippets, commands, and expected result.
- Type consistency:
  - `AnnotationID`, `EraserMask`, `eraserMasks`, `damagedAnnotationIDs`, and `render(image:annotations:eraserMasks:)` are introduced before later tasks use them.
  - `CaptureSelectionResult.eraserMasks` is defaulted so existing memberwise call sites can be migrated incrementally.
  - History case names are consistent across undo/redo and clear-all tasks.
