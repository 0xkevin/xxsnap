import AppKit
import XCTest
@testable import xxsnap

final class AnnotationToolPreferencesTests: XCTestCase {
    func testStoreRoundTripsEveryToolSettingAndKeepsScopesIndependent() throws {
        let (suite, defaults, store) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemPurple
        style.strokeWidth = 7
        style.strokePattern = .dashLongShort
        style.fillEnabled = true
        style.fillColor = .systemOrange
        style.cornerRadius = 9
        style.textSize = 31
        style.textFontFamily = "Helvetica"
        style.textBold = true
        style.textItalic = true
        style.textOutlineEnabled = true
        style.textOutlineColor = .black
        let persistedStyle = PersistedAnnotationStyle(style)
        let preferences = AnnotationToolPreferences(
            shapeStyle: persistedStyle,
            arrowStyle: persistedStyle,
            brushStyle: persistedStyle,
            markerStyle: persistedStyle,
            mosaicStyle: persistedStyle,
            textStyle: persistedStyle,
            numberStyle: persistedStyle,
            magnifierStyle: persistedStyle,
            preferredShapeKind: "ellipse",
            preferredMosaicKind: "rectangle",
            startArrowType: CaptureArrowType.dot.rawValue,
            endArrowType: CaptureArrowType.hollowArrow.rawValue,
            eraserMode: "rectangle",
            magnifierShape: "circle",
            magnifierZoom: 4,
            numberMarkType: "check",
            mosaicRedactionType: "blur",
            gaussianBlurValue: 13,
            pixelMosaicValue: 17,
            customColor: PersistedAnnotationColor(.systemTeal)
        )

        store.save(preferences, scope: .capture)

        XCTAssertEqual(store.load(scope: .capture), preferences)
        XCTAssertNil(store.load(scope: .teachingPen))
        XCTAssertNil(store.load(scope: .longImage))
    }

    @MainActor
    func testOverlayRestoresIndependentStylesForEachToolAndContext() throws {
        let (suite, defaults, store) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .default,
            toolPreferencesStore: store
        ) { _ in }
        first.test_activateShapeTool(.rectangle)
        first.test_setCurrentStrokeWidth(2)
        first.test_setCurrentStrokePattern(.dashLong)
        first.test_activateShapeTool(.arrowLine)
        first.test_setCurrentStrokeWidth(6)
        first.test_setCurrentStrokePattern(.dashLongShort)
        first.test_activateMagnifierTool()
        first.test_setCurrentStrokeWidth(7)
        first.test_setMagnifierShape(.circle)
        first.test_setMagnifierZoom(4)

        let reopened = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .default,
            toolPreferencesStore: store
        ) { _ in }
        reopened.test_activateShapeTool(.rectangle)
        XCTAssertEqual(try XCTUnwrap(reopened.test_currentStyle).strokeWidth, 2)
        XCTAssertEqual(reopened.test_currentStrokePattern, .dashLong)
        reopened.test_activateShapeTool(.arrowLine)
        XCTAssertEqual(try XCTUnwrap(reopened.test_currentStyle).strokeWidth, 6)
        XCTAssertEqual(reopened.test_currentStrokePattern, .dashLongShort)
        reopened.test_activateMagnifierTool()
        XCTAssertEqual(try XCTUnwrap(reopened.test_currentStyle).strokeWidth, 7)
        XCTAssertEqual(reopened.test_currentMagnifierShape, .circle)
        XCTAssertEqual(reopened.test_currentMagnifierZoom, 4)

        let teachingPen = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .teachingPen(windowFrame: NSRect(x: 0, y: 0, width: 640, height: 420)),
            toolPreferencesStore: store
        ) { _ in }
        teachingPen.test_setCurrentStrokeWidth(5)

        let reopenedTeachingPen = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: .teachingPen(windowFrame: NSRect(x: 0, y: 0, width: 640, height: 420)),
            toolPreferencesStore: store
        ) { _ in }
        XCTAssertEqual(try XCTUnwrap(reopenedTeachingPen.test_currentStyle).strokeWidth, 5)

        let longImageConfiguration = SelectionOverlayConfiguration.longImageEditor(
            windowFrame: NSRect(x: 0, y: 0, width: 640, height: 420),
            selectionRect: NSRect(x: 20, y: 20, width: 600, height: 380)
        )
        let longImage = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: longImageConfiguration,
            toolPreferencesStore: store
        ) { _ in }
        longImage.test_activateShapeTool(.rectangle)
        longImage.test_setCurrentStrokeWidth(7)

        let reopenedLongImage = SelectionOverlayWindow(
            backgroundImage: nil,
            configuration: longImageConfiguration,
            toolPreferencesStore: store
        ) { _ in }
        reopenedLongImage.test_activateShapeTool(.rectangle)
        XCTAssertEqual(try XCTUnwrap(reopenedLongImage.test_currentStyle).strokeWidth, 7)

        reopened.test_activateShapeTool(.rectangle)
        XCTAssertEqual(try XCTUnwrap(reopened.test_currentStyle).strokeWidth, 2)
    }

    private func makeStore() -> (String, UserDefaults, AnnotationToolPreferencesStore) {
        let suite = "AnnotationToolPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (
            suite,
            defaults,
            AnnotationToolPreferencesStore(
                userDefaults: defaults,
                keyPrefix: "test.annotation-tools",
                isEnabled: true
            )
        )
    }
}
