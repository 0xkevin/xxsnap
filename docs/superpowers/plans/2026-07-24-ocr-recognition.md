# OCR Recognition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an independent macOS menu bar Capture Text workflow that uses offline Apple Vision OCR and copies recognized text to the pasteboard.

**Architecture:** Add a macOS-only OCR service around `VNRecognizeTextRequest`, then route a new `CaptureOverlayMode.textRecognition` through `CaptureCoordinator`. Add `HotKeyAction.recognizeText`, menu/preference strings, and a toolbar-free selection configuration so the OCR workflow stays separate from screenshot editing.

**Tech Stack:** Swift, AppKit, Carbon global hotkeys, Vision.framework, XCTest, xcodebuild.

---

### Task 1: Add Capture Text Strings And Hotkey Action

**Files:**
- Modify: `platforms/mac/Sources/App/CaptureHotKeyController.swift`
- Modify: `platforms/mac/Sources/App/PreferencesSettings.swift`
- Modify: `platforms/mac/Sources/App/PreferencesWindowController.swift`
- Modify: `platforms/mac/Tests/AppSettingsTests.swift`

- [ ] **Step 1: Write failing tests for strings and shortcut defaults**

Add tests to `platforms/mac/Tests/AppSettingsTests.swift`:

```swift
func testCaptureTextStringsUseRequestedEnglishName() {
    XCTAssertEqual(PreferencesStrings(language: .zhHans).captureText, "识别文字")
    XCTAssertEqual(PreferencesStrings(language: .english).captureText, "Capture Text")
    XCTAssertEqual(
        PreferencesStrings(language: .english).captureTextShortcutDetail,
        "Capture text from a selected screen area"
    )
}

func testCaptureTextDefaultShortcutIsCommand3() {
    XCTAssertEqual(HotKeyAction.recognizeText.defaultSettings.keyCode, UInt32(kVK_ANSI_3))
    XCTAssertEqual(HotKeyAction.recognizeText.defaultSettings.modifiers, UInt32(cmdKey))
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd /Users/kevin/Projects/open-source/Snipory/xxsnap
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/AppSettingsTests/testCaptureTextStringsUseRequestedEnglishName -only-testing:xxsnapTests/AppSettingsTests/testCaptureTextDefaultShortcutIsCommand3
```

Expected: fails because `captureText`, `captureTextShortcutDetail`, and `HotKeyAction.recognizeText` do not exist.

- [ ] **Step 3: Implement strings, default hotkey, and preferences row**

Update `HotKeyAction`:

```swift
case recognizeText
```

Map identifier and default:

```swift
case .recognizeText: return 4
case .recognizeText:
    return HotKeySettings(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey))
```

Add `PreferencesStrings` properties:

```swift
var captureText: String { isEnglish ? "Capture Text" : "识别文字" }
var captureTextShortcutDetail: String {
    isEnglish ? "Capture text from a selected screen area" : "框选屏幕区域并识别文字"
}
var captureTextFailed: String { isEnglish ? "Text recognition failed." : "文字识别失败。" }
var captureTextEmpty: String { isEnglish ? "No text recognized." : "未识别到文字。" }
var captureTextCopied: String { isEnglish ? "Text copied to clipboard." : "文字已复制到剪贴板。" }
```

Update `PreferencesWindowController.makeShortcutsPage()` to insert `recognizeText` between capture and teaching pen:

```swift
let captureTextRow = makeShortcutRow(
    action: .recognizeText,
    title: strings.captureText,
    detail: strings.captureTextShortcutDetail
)
let page = makeStandardPage(rows: [captureRow, captureTextRow, teachingPenRow, restoreRow])
```

- [ ] **Step 4: Run tests and commit**

Run the same `xcodebuild ... AppSettingsTests` command. Expected: pass.

Commit:

```bash
git add platforms/mac/Sources/App/CaptureHotKeyController.swift platforms/mac/Sources/App/PreferencesSettings.swift platforms/mac/Sources/App/PreferencesWindowController.swift platforms/mac/Tests/AppSettingsTests.swift
git commit -m "feat(mac): add Capture Text shortcut metadata"
```

### Task 2: Add Offline OCR Service

**Files:**
- Create: `platforms/mac/Sources/App/OCRTextRecognitionService.swift`
- Create: `platforms/mac/Tests/OCRTextRecognitionServiceTests.swift`

- [ ] **Step 1: Write failing sorting and joining tests**

Create `platforms/mac/Tests/OCRTextRecognitionServiceTests.swift`:

```swift
import CoreGraphics
import XCTest

final class OCRTextRecognitionServiceTests: XCTestCase {
    func testJoinCandidatesSortsTopToBottomThenLeftToRight() {
        let candidates = [
            RecognizedTextCandidate(text: "World", boundingBox: CGRect(x: 0.45, y: 0.70, width: 0.2, height: 0.1)),
            RecognizedTextCandidate(text: "Hello", boundingBox: CGRect(x: 0.10, y: 0.70, width: 0.2, height: 0.1)),
            RecognizedTextCandidate(text: "Second line", boundingBox: CGRect(x: 0.10, y: 0.40, width: 0.5, height: 0.1)),
        ]

        XCTAssertEqual(OCRTextRecognitionService.join(candidates), "Hello World\nSecond line")
    }

    func testJoinCandidatesTrimsEmptyTextAndWhitespace() {
        let candidates = [
            RecognizedTextCandidate(text: "  Alpha  ", boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1)),
            RecognizedTextCandidate(text: "   ", boundingBox: CGRect(x: 0.3, y: 0.8, width: 0.2, height: 0.1)),
            RecognizedTextCandidate(text: "Beta", boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.1)),
        ]

        XCTAssertEqual(OCRTextRecognitionService.join(candidates), "Alpha\nBeta")
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd /Users/kevin/Projects/open-source/Snipory/xxsnap
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/OCRTextRecognitionServiceTests
```

Expected: fails because the service and candidate type do not exist.

- [ ] **Step 3: Implement Vision service**

Create `OCRTextRecognitionService` with:

```swift
import AppKit
import Vision

struct RecognizedTextCandidate: Equatable {
    let text: String
    let boundingBox: CGRect
}

enum OCRTextRecognitionError: LocalizedError, Equatable {
    case imageConversionFailed
    case requestFailed
}

final class OCRTextRecognitionService {
    func recognizeText(in image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRTextRecognitionError.imageConversionFailed
        }
        return try await recognizeText(in: cgImage)
    }

    func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    continuation.resume(throwing: OCRTextRecognitionError.requestFailed)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let candidates = observations.compactMap { observation -> RecognizedTextCandidate? in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    return RecognizedTextCandidate(text: text, boundingBox: observation.boundingBox)
                }
                continuation.resume(returning: Self.join(candidates))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: OCRTextRecognitionError.requestFailed)
            }
        }
    }

    static func join(_ candidates: [RecognizedTextCandidate]) -> String {
        let lineThreshold: CGFloat = 0.03
        let sorted = candidates
            .map { RecognizedTextCandidate(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), boundingBox: $0.boundingBox) }
            .filter { !$0.text.isEmpty }
            .sorted {
                let yDelta = abs($0.boundingBox.midY - $1.boundingBox.midY)
                if yDelta > lineThreshold {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }

        var lines: [[RecognizedTextCandidate]] = []
        for candidate in sorted {
            if let last = lines.indices.last,
               let first = lines[last].first,
               abs(first.boundingBox.midY - candidate.boundingBox.midY) <= lineThreshold {
                lines[last].append(candidate)
            } else {
                lines.append([candidate])
            }
        }
        return lines.map { line in
            line.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run tests and commit**

Run the `OCRTextRecognitionServiceTests` command. Expected: pass.

Commit:

```bash
git add platforms/mac/Sources/App/OCRTextRecognitionService.swift platforms/mac/Tests/OCRTextRecognitionServiceTests.swift
git commit -m "feat(mac): add offline OCR text recognition service"
```

### Task 3: Add OCR Selection Mode And Pasteboard Flow

**Files:**
- Modify: `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- Modify: `platforms/mac/Sources/App/CaptureCoordinator.swift`
- Modify: `platforms/mac/Tests/xxsnapMacTests.swift`

- [ ] **Step 1: Add failing tests for text recognition configuration**

Add tests that assert an OCR configuration hides the main toolbar and a coordinator created with fake OCR/copy handlers can process text without setting `lastCapture`.

- [ ] **Step 2: Implement `SelectionOverlayConfiguration.textRecognition`**

Add a configuration factory that hides all main toolbar controls and disables annotation tools:

```swift
static func textRecognition() -> SelectionOverlayConfiguration {
    var configuration = SelectionOverlayConfiguration.default
    configuration.hiddenMainToolbarButtons = [.scroll, .cancel, .pin]
    configuration.showsSelectionMeasurementControl = true
    configuration.allowsPassiveColorSampler = false
    configuration.usesArrowCursorWhenIdle = false
    return configuration
}
```

If save/copy buttons are not represented by `hiddenMainToolbarButtons`, add a `showsMainToolbarActions: Bool` property and make toolbar drawing/hit-testing skip save/copy/pin/scroll when false.

- [ ] **Step 3: Implement coordinator text mode**

Add `CaptureOverlayMode.textRecognition`, `startTextRecognition()`, OCR service injection, text pasteboard injection, and a branch in `handleSelection`:

```swift
func startTextRecognition() {
    startCapture(mode: .textRecognition)
}
```

In the completion branch, crop the selected image, call `ocrService.recognizeText(in:)`, and write non-empty text to pasteboard via:

```swift
private func copyTextToPasteboard(_ text: String) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
}
```

- [ ] **Step 4: Run focused tests and commit**

Run:

```bash
cd /Users/kevin/Projects/open-source/Snipory/xxsnap
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test -only-testing:xxsnapTests/xxsnapMacTests
```

Commit:

```bash
git add platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift platforms/mac/Sources/App/CaptureCoordinator.swift platforms/mac/Tests/xxsnapMacTests.swift
git commit -m "feat(mac): add Capture Text selection flow"
```

### Task 4: Wire Menu, AppDelegate, And Full Verification

**Files:**
- Modify: `platforms/mac/Sources/App/AppDelegate.swift`
- Modify: `platforms/mac/Sources/App/StatusItemController.swift`
- Modify: `platforms/mac/Tests/AppSettingsTests.swift`

- [ ] **Step 1: Wire handlers**

Pass `captureCoordinator.startTextRecognition()` into `CaptureHotKeyController`, and add `StatusItemController.captureText()` that calls the same method.

- [ ] **Step 2: Update status menu**

Insert the menu item between capture and teaching pen:

```swift
menu.addItem(makeHotKeyMenuItem(
    title: strings.captureText,
    action: #selector(captureText),
    hotKeyAction: .recognizeText
))
```

- [ ] **Step 3: Run full mac tests**

Run:

```bash
cd /Users/kevin/Projects/open-source/Snipory/xxsnap
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

- [ ] **Step 4: Build and manual smoke**

Run:

```bash
cd /Users/kevin/Projects/open-source/Snipory/xxsnap
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived build
```

Launch:

```bash
pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap" || true
open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app
```

Verify status menu shows `识别文字` / `Capture Text`, `Command + 3` starts selection, recognized text lands in the clipboard, blank selection does not clear clipboard, and normal screenshot still copies an image.

- [ ] **Step 5: Commit**

```bash
git add platforms/mac/Sources/App/AppDelegate.swift platforms/mac/Sources/App/StatusItemController.swift platforms/mac/Tests/AppSettingsTests.swift
git commit -m "feat(mac): wire Capture Text menu action"
```
