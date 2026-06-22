import AppKit
import XCTest
@testable import Snipory

final class SniporyMacTests: XCTestCase {
    func testAnnotationRendererDrawsRectangleOntoImage() throws {
        let image = NSImage(size: NSSize(width: 40, height: 40))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 40).fill()
        image.unlockFocus()

        var style = CaptureAnnotationStyle()
        style.fillEnabled = true
        style.strokeColor = .systemRed
        style.fillColor = .systemRed

        let rendered = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 20, height: 20), style: style)]
        )

        XCTAssertEqual(pixelColor(in: rendered, x: 40, y: 40)?.alphaComponent, 1)
    }

    func testAnnotationRendererDrawsArrowLineOntoImage() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 80, height: 50),
            pixelWidth: 80,
            pixelHeight: 50
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 4

        let annotation = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 10, y: 12, width: 60, height: 30),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 10, y: 12),
                end: NSPoint(x: 70, y: 36),
                control: NSPoint(x: 42, y: 42),
                startArrowType: .none,
                endArrowType: .normal
            )
        )

        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [annotation])

        XCTAssertNotEqual(try rgbaBytes(in: rendered), try rgbaBytes(in: image))
    }

    func testAnnotationRendererDrawsBrushPathOntoImage() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 80, height: 50),
            pixelWidth: 80,
            pixelHeight: 50,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 5

        let rendered = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [
                CaptureAnnotation(
                    kind: .brush,
                    rect: NSRect(x: -12, y: 14, width: 80, height: 18),
                    style: style,
                    brushPath: CaptureBrushPath(points: [
                        NSPoint(x: -12, y: 14),
                        NSPoint(x: 20, y: 24),
                        NSPoint(x: 68, y: 32),
                    ])
                ),
            ]
        )

        XCTAssertEqual(rendered.size, image.size)
        XCTAssertGreaterThan(redPixelCount(in: rendered, within: NSRect(x: 0, y: 10, width: 76, height: 28)), 80)
    }

    func testBrushPathStrokePatternChangesRenderedPixels() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 120, height: 40),
            pixelWidth: 120,
            pixelHeight: 40,
            fill: .white
        )
        var solidStyle = CaptureAnnotationStyle()
        solidStyle.strokeColor = .systemRed
        solidStyle.strokeWidth = 5

        var dashedStyle = solidStyle
        dashedStyle.strokePattern = .dashLong

        let brushPath = CaptureBrushPath(points: [
            NSPoint(x: 8, y: 20),
            NSPoint(x: 60, y: 20),
            NSPoint(x: 112, y: 20),
        ])
        let solid = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [CaptureAnnotation(kind: .brush, rect: brushPath.boundingRect, style: solidStyle, brushPath: brushPath)]
        )
        let dashed = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [CaptureAnnotation(kind: .brush, rect: brushPath.boundingRect, style: dashedStyle, brushPath: brushPath)]
        )

        XCTAssertNotEqual(try rgbaBytes(in: solid), try rgbaBytes(in: dashed))
    }

    func testDashPatternSpacingScalesWithStrokeWidth() {
        let thin = CaptureStrokePattern.dashLong.dashPattern(strokeWidth: 2)
        let thick = CaptureStrokePattern.dashLong.dashPattern(strokeWidth: 7)

        XCTAssertGreaterThan(thick[0], thin[0])
        XCTAssertGreaterThan(thick[1], 7)
    }

    func testThirdStrokePatternIsDotted() {
        let dotted = CaptureStrokePattern.dashNarrow.dashPattern(strokeWidth: 6)

        XCTAssertLessThan(dotted[0], 1)
        XCTAssertGreaterThan(dotted[1], 6)
    }

    func testFourthStrokePatternIsLongDashDot() {
        let dashDot = CaptureStrokePattern.dashLongShort.dashPattern(strokeWidth: 6)

        XCTAssertGreaterThan(dashDot[0], 10)
        XCTAssertLessThan(dashDot[2], 1)
        XCTAssertEqual(CaptureStrokePattern.dashLongShort.title, "一长一点的虚线线条")
    }

    func testSvg2ArrowVectorsMatchReferenceIcons() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 64, height: 48),
            pixelWidth: 64,
            pixelHeight: 48
        )

        for arrowType in [CaptureArrowType.normal, .solidArrow, .hollowArrow] {
            XCTAssertEqual(
                try renderArrowVectorSignature(image: image, arrowType: arrowType),
                try referenceArrowSignature(image: image, arrowType: arrowType),
                "\(arrowType)"
            )
        }
    }

    func testSpecialArrowTypesAffectActualRenderedArrowBodies() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 120, height: 120),
            pixelWidth: 120,
            pixelHeight: 120,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 4

        let normalArrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 20, y: 12, width: 0, height: 80),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 20, y: 12),
                end: NSPoint(x: 20, y: 92),
                control: NSPoint(x: 20, y: 52),
                startArrowType: .none,
                endArrowType: .normal
            )
        )
        let solidArrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 50, y: 12, width: 0, height: 80),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 50, y: 12),
                end: NSPoint(x: 50, y: 92),
                control: NSPoint(x: 50, y: 52),
                startArrowType: .none,
                endArrowType: .solidArrow
            )
        )
        let hollowArrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 80, y: 12, width: 0, height: 80),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 80, y: 12),
                end: NSPoint(x: 80, y: 92),
                control: NSPoint(x: 80, y: 52),
                startArrowType: .none,
                endArrowType: .hollowArrow
            )
        )

        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [normalArrow, solidArrow, hollowArrow])
        try save(image: rendered, to: "/tmp/snipory-arrow-debug.png")

        XCTAssertGreaterThan(redPixelCount(in: rendered, within: NSRect(x: 13, y: 12, width: 14, height: 77)), 300)
        XCTAssertGreaterThan(redPixelCount(in: rendered, within: NSRect(x: 43, y: 19, width: 14, height: 69)), 300)
        XCTAssertGreaterThan(redPixelCount(in: rendered, within: NSRect(x: 73, y: 19, width: 14, height: 69)), 150)

        let hollowCenter = try XCTUnwrap(rgbaPixel(in: rendered, x: 80, y: 70))
        XCTAssertGreaterThan(hollowCenter.red, 200)
        XCTAssertGreaterThan(hollowCenter.green, 200)
        XCTAssertGreaterThan(hollowCenter.blue, 200)

        XCTAssertGreaterThan(redPixelCount(in: rendered, within: NSRect(x: 73, y: 58, width: 14, height: 28)), 100)
    }

    func testSpecialArrowBodiesFollowCurveControlPoint() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 180, height: 180),
            pixelWidth: 180,
            pixelHeight: 180,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 4

        for (index, type) in [CaptureArrowType.solidArrow, .hollowArrow].enumerated() {
            let offset = CGFloat(index) * 34
            let arrowLine = CaptureArrowLine(
                start: NSPoint(x: 34 + offset, y: 20),
                end: NSPoint(x: 34 + offset, y: 160),
                control: NSPoint(x: 134 + offset, y: 90),
                startArrowType: .none,
                endArrowType: type
            )
            let arrow = CaptureAnnotation(
                kind: .arrowLine,
                rect: arrowLine.boundingRect,
                style: style,
                arrowLine: arrowLine
            )
            let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [arrow])

            XCTAssertGreaterThan(
                redPixelCount(in: rendered, within: NSRect(x: 84 + offset, y: 84, width: 18, height: 18)),
                8,
                "\(type) body should bend through the quadratic curve control point"
            )
        }
    }

    func testHollowArrowCurveRendersStrokedOutlineWithSolidTail() throws {
        let signature = try renderCurvedArrowVectorSignature(arrowType: .hollowArrow, strokeWidth: 4)
        let pathPixels = stride(from: 0, to: signature.count, by: 4).filter { index in
            signature[index] < 120 && signature[index + 1] < 120 && signature[index + 2] < 120 && signature[index + 3] > 0
        }

        XCTAssertGreaterThan(pathPixels.count, 80)
    }

    func testThinNormalArrowBodyTouchesArrowHead() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 80, height: 120),
            pixelWidth: 80,
            pixelHeight: 120,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 2

        let arrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 40, y: 12, width: 0, height: 80),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 40, y: 12),
                end: NSPoint(x: 40, y: 92),
                control: NSPoint(x: 40, y: 52),
                startArrowType: .none,
                endArrowType: .normal
            )
        )

        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [arrow])
        let joinPixel = try XCTUnwrap(rgbaPixel(in: rendered, x: 40, y: 82))
        XCTAssertLessThan(joinPixel.green, 120)
        XCTAssertLessThan(joinPixel.blue, 120)
    }

    func testStartArrowTypesMatchReversedEndArrowWithoutExtraTipDot() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 120, height: 140),
            pixelWidth: 120,
            pixelHeight: 140,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 4

        for type in [CaptureArrowType.normal, .solidArrow, .hollowArrow] {
            let startArrowLine = CaptureArrowLine(
                start: NSPoint(x: 60, y: 24),
                end: NSPoint(x: 60, y: 112),
                control: NSPoint(x: 60, y: 68),
                startArrowType: type,
                endArrowType: .none
            )
            let reversedEndArrowLine = CaptureArrowLine(
                start: startArrowLine.end,
                end: startArrowLine.start,
                control: startArrowLine.control,
                startArrowType: .none,
                endArrowType: type
            )

            let startRendered = CaptureAnnotationRenderer.render(
                image: image,
                annotations: [CaptureAnnotation(kind: .arrowLine, rect: startArrowLine.boundingRect, style: style, arrowLine: startArrowLine)]
            )
            let reversedEndRendered = CaptureAnnotationRenderer.render(
                image: image,
                annotations: [CaptureAnnotation(kind: .arrowLine, rect: reversedEndArrowLine.boundingRect, style: style, arrowLine: reversedEndArrowLine)]
            )

            XCTAssertEqual(
                try rgbaBytes(in: startRendered),
                try rgbaBytes(in: reversedEndRendered),
                "\(type) used as a start arrow should not leave extra body pixels at the tip"
            )
        }
    }

    func testSpecialArrowHeadsRemainIntegratedWithTheirBodies() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 120, height: 120),
            pixelWidth: 120,
            pixelHeight: 120,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 4

        let solidArrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 45, y: 12, width: 0, height: 80),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 45, y: 12),
                end: NSPoint(x: 45, y: 92),
                control: NSPoint(x: 45, y: 52),
                startArrowType: .none,
                endArrowType: .solidArrow
            )
        )
        let hollowArrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 78, y: 12, width: 0, height: 80),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 78, y: 12),
                end: NSPoint(x: 78, y: 92),
                control: NSPoint(x: 78, y: 52),
                startArrowType: .none,
                endArrowType: .hollowArrow
            )
        )

        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [solidArrow, hollowArrow])

        XCTAssertGreaterThan(redPixelCount(in: rendered, within: NSRect(x: 38, y: 80, width: 14, height: 16)), 40)
        XCTAssertGreaterThan(redPixelCount(in: rendered, within: NSRect(x: 70, y: 82, width: 16, height: 14)), 16)
    }

    func testHollowArrowOutlineStaysVisibleAndRespondsToStrokeWidth() throws {
        let normal = try hollowArrowOutlineThickness(strokeWidth: 4)
        XCTAssertGreaterThanOrEqual(normal.body, 1, "stroke 4 body/head: \(normal)")
        XCTAssertGreaterThanOrEqual(normal.head, 2, "stroke 4 body/head: \(normal)")

        let thick = try hollowArrowOutlineThickness(strokeWidth: 6)
        XCTAssertGreaterThanOrEqual(thick.body, normal.body, "stroke 4 body/head: \(normal), stroke 6 body/head: \(thick)")
        XCTAssertGreaterThanOrEqual(thick.head, 2, "stroke 4 body/head: \(normal), stroke 6 body/head: \(thick)")
    }

    func testHollowArrowHeadTailExtendsBehindTip() throws {
        let bodySpan = try arrowTransverseSpan(
            type: .hollowArrow,
            strokeWidth: 4,
            start: NSPoint(x: 60, y: 12),
            end: NSPoint(x: 60, y: 92),
            control: NSPoint(x: 60, y: 52),
            fraction: 0.35,
            canvasSize: NSSize(width: 120, height: 120)
        )
        let headSpan = try arrowTransverseSpan(
            type: .hollowArrow,
            strokeWidth: 4,
            start: NSPoint(x: 60, y: 12),
            end: NSPoint(x: 60, y: 92),
            control: NSPoint(x: 60, y: 52),
            fraction: 0.82,
            canvasSize: NSSize(width: 120, height: 120)
        )

        XCTAssertGreaterThan(headSpan, bodySpan)
    }

    func testHollowArrowTailKeepsSlimStrokedEnding() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 120, height: 120),
            pixelWidth: 120,
            pixelHeight: 120,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 4
        let arrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 60, y: 12, width: 0, height: 80),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 60, y: 12),
                end: NSPoint(x: 60, y: 92),
                control: NSPoint(x: 60, y: 52),
                startArrowType: .none,
                endArrowType: .hollowArrow
            )
        )

        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [arrow])
        let landingRun = try averageRedRunLength(in: rendered, y: 12, xRange: 54...66)

        XCTAssertLessThanOrEqual(landingRun, 2, "hollow arrow tail should stay slim, not become a wide flat cap: \(landingRun)")
    }

    func testHollowArrowTailKeepsSlimStrokeBehindTip() throws {
        let rendered = try renderVerticalHollowArrow(
            start: NSPoint(x: 60, y: 12),
            end: NSPoint(x: 60, y: 92),
            startArrowType: .none,
            endArrowType: .hollowArrow
        )

        let runs = try (12...16).map { y in
            try averageRedRunLength(in: rendered, y: y, xRange: 54...66)
        }

        XCTAssertLessThanOrEqual(runs[0], 2, "hollow arrow tail tip should stay slim: \(runs)")
        XCTAssertLessThanOrEqual(runs[1], 2, "hollow arrow tail should not start with a wide flat cap: \(runs)")
        XCTAssertLessThanOrEqual(runs[2], 2, "hollow arrow tail should stay as a slim stroked outline: \(runs)")
    }

    func testHollowArrowTailDoesNotLeaveDashedGapBehindTip() throws {
        let rendered = try renderVerticalHollowArrow(
            start: NSPoint(x: 60, y: 12),
            end: NSPoint(x: 60, y: 92),
            startArrowType: .none,
            endArrowType: .hollowArrow
        )

        let missingRows = try (23...39).filter { y in
            try averageRedRunLength(in: rendered, y: y, xRange: 54...66) == 0
        }

        XCTAssertTrue(missingRows.isEmpty, "hollow arrow tail should not break into dashed gaps: \(missingRows)")
    }

    func testHollowArrowTailStaysContinuousUntilBodyOpens() throws {
        let rendered = try renderVerticalHollowArrow(
            start: NSPoint(x: 60, y: 12),
            end: NSPoint(x: 60, y: 92),
            startArrowType: .none,
            endArrowType: .hollowArrow
        )

        let missingRows = try (23...62).filter { y in
            try averageRedRunLength(in: rendered, y: y, xRange: 51...69) == 0
        }

        XCTAssertTrue(missingRows.isEmpty, "hollow arrow tail should stay continuous into the body: \(missingRows)")
    }

    func testDownwardHollowArrowTopTailDoesNotDetachFromBody() throws {
        let rendered = try renderVerticalHollowArrow(
            start: NSPoint(x: 60, y: 92),
            end: NSPoint(x: 60, y: 12),
            startArrowType: .none,
            endArrowType: .hollowArrow
        )

        let missingRows = try (62...81).filter { y in
            try averageRedRunLength(in: rendered, y: y, xRange: 51...69) == 0
        }

        XCTAssertTrue(missingRows.isEmpty, "downward hollow arrow top tail should not detach from the body: \(missingRows)")
    }

    func testHollowEndArrowTailMatchesSolidPointedTail() throws {
        let solid = try renderVerticalHollowArrow(
            start: NSPoint(x: 60, y: 12),
            end: NSPoint(x: 60, y: 92),
            startArrowType: .none,
            endArrowType: .solidArrow
        )
        let hollow = try renderVerticalHollowArrow(
            start: NSPoint(x: 60, y: 12),
            end: NSPoint(x: 60, y: 92),
            startArrowType: .none,
            endArrowType: .hollowArrow
        )

        let solidTailRun = try averageRedRunLength(in: solid, y: 23, xRange: 54...66)
        let hollowTailRun = try averageRedRunLength(in: hollow, y: 23, xRange: 54...66)

        XCTAssertLessThanOrEqual(
            hollowTailRun,
            max(4, solidTailRun + 3),
            "hollow end arrow tail should land as sharply as the solid arrow tail: solid \(solidTailRun), hollow \(hollowTailRun)"
        )
    }

    func testHollowArrowTailBecomesHollowAfterShortSolidTip() throws {
        let rendered = try renderVerticalHollowArrow(
            start: NSPoint(x: 60, y: 12),
            end: NSPoint(x: 60, y: 92),
            startArrowType: .none,
            endArrowType: .hollowArrow
        )

        XCTAssertFalse(
            try isRedPixel(in: rendered, x: 60, y: 44),
            "hollow arrow tail should only keep the first short pointed tip solid, then reopen into a hollow center"
        )
    }

    func testDiagonalStartHollowArrowTailDoesNotExposeFlatCut() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 220, height: 220),
            pixelWidth: 220,
            pixelHeight: 220,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 4

        let arrowLine = CaptureArrowLine(
            start: NSPoint(x: 40, y: 180),
            end: NSPoint(x: 180, y: 40),
            control: NSPoint(x: 100, y: 34),
            startArrowType: .hollowArrow,
            endArrowType: .none
        )
        let arrow = CaptureAnnotation(kind: .arrowLine, rect: arrowLine.boundingRect, style: style, arrowLine: arrowLine)
        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [arrow])

        let tailRuns = try (39...46).map { y in
            try averageRedRunLength(in: rendered, y: y, xRange: 130...210)
        }

        XCTAssertLessThanOrEqual(
            tailRuns.max() ?? 0,
            24,
            "diagonal start hollow arrow tail should not expose a long flat cut: \(tailRuns)"
        )
    }

    func testHollowArrowHeadShoulderSpreadsLikeSnipasteReference() throws {
        let shoulderSpan = try arrowTransverseSpanAtLengthFraction(type: .hollowArrow, strokeWidth: 4, fraction: 0.90)

        XCTAssertGreaterThanOrEqual(shoulderSpan, 9)
        XCTAssertLessThanOrEqual(shoulderSpan, 20)
    }

    func testSolidAndHollowSpecialArrowsShareHeadAndBodyDimensions() throws {
        let solidHead = try arrowTransverseSpanAtLengthFraction(type: .solidArrow, strokeWidth: 4, fraction: 0.90)
        let hollowHead = try arrowTransverseSpanAtLengthFraction(type: .hollowArrow, strokeWidth: 4, fraction: 0.90)
        let solidBody = try arrowTransverseSpanAtLengthFraction(type: .solidArrow, strokeWidth: 4, fraction: 0.55)
        let hollowBody = try arrowTransverseSpanAtLengthFraction(type: .hollowArrow, strokeWidth: 4, fraction: 0.55)

        XCTAssertGreaterThanOrEqual(hollowHead, solidHead, "solid/hollow head span: \(solidHead), \(hollowHead)")
        XCTAssertLessThanOrEqual(hollowHead - solidHead, 6, "solid/hollow head span: \(solidHead), \(hollowHead)")
        XCTAssertGreaterThanOrEqual(hollowBody, solidBody, "solid/hollow body span: \(solidBody), \(hollowBody)")
        XCTAssertLessThanOrEqual(hollowBody - solidBody, 3, "solid/hollow body span: \(solidBody), \(hollowBody)")
    }

    func testSpecialArrowBodiesUseMatchingStraightTaperBeforeHead() throws {
        for type in [CaptureArrowType.solidArrow, .hollowArrow] {
            let earlyBody = try arrowTransverseSpanAtLengthFraction(type: type, strokeWidth: 4, fraction: 0.25)
            let lateBody = try arrowTransverseSpanAtLengthFraction(type: type, strokeWidth: 4, fraction: 0.62)

            XCTAssertLessThan(earlyBody, lateBody, "\(type) body should widen toward the head: \(earlyBody), \(lateBody)")
            XCTAssertGreaterThanOrEqual(lateBody, 4.5, "\(type) body should read as a triangular wedge: \(lateBody)")
            XCTAssertLessThanOrEqual(lateBody, 10, "\(type) body should not be too fat: \(lateBody)")
        }

        let solidLateBody = try arrowTransverseSpanAtLengthFraction(type: .solidArrow, strokeWidth: 4, fraction: 0.62)
        let hollowLateBody = try arrowTransverseSpanAtLengthFraction(type: .hollowArrow, strokeWidth: 4, fraction: 0.62)
        XCTAssertLessThanOrEqual(abs(solidLateBody - hollowLateBody), 3, "solid/hollow body spans: \(solidLateBody), \(hollowLateBody)")
    }

    func testSpecialArrowBodiesEndInPointedTriangleTail() throws {
        for type in [CaptureArrowType.solidArrow, .hollowArrow] {
            let tailSpan = try arrowTransverseSpanAtLengthFraction(type: type, strokeWidth: 4, fraction: 0.08)
            let bodySpan = try arrowTransverseSpanAtLengthFraction(type: type, strokeWidth: 4, fraction: 0.55)

            XCTAssertLessThanOrEqual(tailSpan, 4, "\(type) tail should be pointed: \(tailSpan)")
            XCTAssertGreaterThan(bodySpan, tailSpan * 2.5, "\(type) body should open from the pointed tail: \(tailSpan), \(bodySpan)")
        }
    }

    func testSpecialArrowsKeepCompactHeadsWithSlimTriangularBodies() throws {
        let normalHeadSpan = try arrowTransverseSpanAtLengthFraction(type: .normal, strokeWidth: 4, fraction: 0.90)

        for type in [CaptureArrowType.solidArrow, .hollowArrow] {
            let headSpan = try arrowTransverseSpanAtLengthFraction(type: type, strokeWidth: 4, fraction: 0.90)
            let tailSpan = try arrowTransverseSpanAtLengthFraction(type: type, strokeWidth: 4, fraction: 0.08)
            let midBodySpan = try arrowTransverseSpanAtLengthFraction(type: type, strokeWidth: 4, fraction: 0.62)

            XCTAssertLessThanOrEqual(headSpan, normalHeadSpan + 6, "\(type) should keep a compact arrow head: \(headSpan), normal: \(normalHeadSpan)")
            XCTAssertLessThanOrEqual(midBodySpan, 10, "\(type) body should be a slim triangle, not a fat wedge: \(midBodySpan)")
            XCTAssertGreaterThan(midBodySpan, tailSpan * 2.5, "\(type) body should widen from the pointed tail: \(tailSpan), \(midBodySpan)")
        }
    }

    func testHollowArrowHeadShoulderStaysProportionalOnShortLines() throws {
        let shoulderSpan = try arrowTransverseSpan(
            type: .hollowArrow,
            strokeWidth: 4,
            start: NSPoint(x: 60, y: 12),
            end: NSPoint(x: 60, y: 92),
            control: NSPoint(x: 60, y: 52),
            fraction: 0.82,
            canvasSize: NSSize(width: 120, height: 120)
        )

        XCTAssertLessThanOrEqual(shoulderSpan, 24)
    }

    func testDiagonalArrowVariantsMatchReferenceShapes() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 420, height: 180),
            pixelWidth: 420,
            pixelHeight: 180,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = 4

        let normalArrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 48, y: 28, width: 84, height: 114),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 48, y: 28),
                end: NSPoint(x: 132, y: 142),
                control: NSPoint(x: 90, y: 85),
                startArrowType: .none,
                endArrowType: .normal
            )
        )
        let solidArrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 178, y: 28, width: 84, height: 114),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 178, y: 28),
                end: NSPoint(x: 262, y: 142),
                control: NSPoint(x: 220, y: 85),
                startArrowType: .none,
                endArrowType: .solidArrow
            )
        )
        let hollowArrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 308, y: 28, width: 84, height: 114),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 308, y: 28),
                end: NSPoint(x: 392, y: 142),
                control: NSPoint(x: 350, y: 85),
                startArrowType: .none,
                endArrowType: .hollowArrow
            )
        )

        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [normalArrow, solidArrow, hollowArrow])
        try save(image: rendered, to: "/tmp/snipory-diagonal-arrows-debug.png")
        let normalTailSide = try XCTUnwrap(rgbaPixel(in: rendered, x: 47, y: 30))
        XCTAssertLessThan(normalTailSide.green, 220)
        XCTAssertLessThan(normalTailSide.blue, 220)

        let solidTailSide = try XCTUnwrap(rgbaPixel(in: rendered, x: 177, y: 30))
        XCTAssertGreaterThan(solidTailSide.red, 240)
        XCTAssertGreaterThan(solidTailSide.green, 240)
        XCTAssertGreaterThan(solidTailSide.blue, 240)

        let solidBodyCenter = try XCTUnwrap(rgbaPixel(in: rendered, x: 220, y: 85))
        XCTAssertLessThan(solidBodyCenter.green, 120)
        XCTAssertLessThan(solidBodyCenter.blue, 120)

        XCTAssertGreaterThan(
            brightPixelCount(in: rendered, within: NSRect(x: 346, y: 82, width: 8, height: 8)),
            12
        )

        XCTAssertGreaterThan(redPixelCount(in: rendered, within: NSRect(x: 342, y: 70, width: 28, height: 30)), 60)

        XCTAssertGreaterThan(redPixelCount(in: rendered, within: NSRect(x: 44, y: 24, width: 16, height: 18)), 55)
        XCTAssertLessThan(redPixelCount(in: rendered, within: NSRect(x: 174, y: 24, width: 16, height: 18)), 50)
        let solidSlimBodyPixels = redPixelCount(in: rendered, within: NSRect(x: 212, y: 74, width: 18, height: 18))
        XCTAssertGreaterThan(solidSlimBodyPixels, 70)
        XCTAssertLessThan(solidSlimBodyPixels, 120)
        XCTAssertLessThan(redPixelCount(in: rendered, within: NSRect(x: 82, y: 74, width: 18, height: 18)), 110)
    }

    @MainActor
    func testCropPreservesRetinaPixelDimensions() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 100, height: 50),
            pixelWidth: 200,
            pixelHeight: 100
        )

        let cropped = try XCTUnwrap(
            CaptureCoordinator.crop(image: image, rect: NSRect(x: 10, y: 5, width: 40, height: 20))
        )
        let cgImage = try XCTUnwrap(cropped.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(cropped.size, NSSize(width: 40, height: 20))
        XCTAssertEqual(cgImage.width, 80)
        XCTAssertEqual(cgImage.height, 40)
    }

    func testAnnotationRendererPreservesRetinaPixelDimensions() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 40, height: 40),
            pixelWidth: 80,
            pixelHeight: 80
        )
        var style = CaptureAnnotationStyle()
        style.fillEnabled = true
        style.strokeColor = .systemRed
        style.fillColor = .systemRed

        let rendered = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [CaptureAnnotation(kind: .rectangle, rect: NSRect(x: 10, y: 10, width: 20, height: 20), style: style)]
        )
        let cgImage = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(rendered.size, NSSize(width: 40, height: 40))
        XCTAssertEqual(cgImage.width, 80)
        XCTAssertEqual(cgImage.height, 80)
    }

    func testSketchStrokePatternsRenderDifferentPixelsFromMechanicalStrokes() throws {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 80, height: 50),
            pixelWidth: 80,
            pixelHeight: 50
        )
        let rect = NSRect(x: 12, y: 12, width: 56, height: 26)

        let solid = try renderSignature(image: image, rect: rect, strokePattern: .solid)
        let sketchSolid = try renderSignature(image: image, rect: rect, strokePattern: .sketchSolid)
        XCTAssertNotEqual(sketchSolid, solid)

        let dashed = try renderSignature(image: image, rect: rect, strokePattern: .dashLong)
        let sketchDashed = try renderSignature(image: image, rect: rect, strokePattern: .sketchDashed)
        XCTAssertNotEqual(sketchDashed, dashed)
    }

    func testToolbarSvgIconsAreBundledAndReadable() throws {
        for resource in ["arrow-line", "pencil-tool", "shape-marker", "mosaic-tool", "settings-more"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: resource, withExtension: "svg"))
            XCTAssertNotNil(NSImage(contentsOf: url), resource)
        }
    }

    private func makeBitmapImage(
        pointSize: NSSize,
        pixelWidth: Int,
        pixelHeight: Int,
        fill: NSColor = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
    ) throws -> NSImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(fill.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        let cgImage = try XCTUnwrap(context.makeImage())
        return NSImage(cgImage: cgImage, size: pointSize)
    }

    private func renderVerticalHollowArrow(
        start: NSPoint,
        end: NSPoint,
        startArrowType: CaptureArrowType,
        endArrowType: CaptureArrowType,
        strokeWidth: CGFloat = 4
    ) throws -> NSImage {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 120, height: 120),
            pixelWidth: 120,
            pixelHeight: 120,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = strokeWidth
        let arrowLine = CaptureArrowLine(
            start: start,
            end: end,
            control: NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2),
            startArrowType: startArrowType,
            endArrowType: endArrowType
        )
        let arrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: arrowLine.boundingRect,
            style: style,
            arrowLine: arrowLine
        )
        return CaptureAnnotationRenderer.render(image: image, annotations: [arrow])
    }

    private func renderSignature(
        image: NSImage,
        rect: NSRect,
        strokePattern: CaptureStrokePattern
    ) throws -> [UInt8] {
        var style = CaptureAnnotationStyle()
        style.strokeColor = .black
        style.strokeWidth = 2
        style.strokePattern = strokePattern
        style.fillEnabled = false

        let rendered = CaptureAnnotationRenderer.render(
            image: image,
            annotations: [CaptureAnnotation(kind: .rectangle, rect: rect, style: style)]
        )
        return try rgbaBytes(in: rendered)
    }

    private func renderArrowVectorSignature(
        image: NSImage,
        arrowType: CaptureArrowType
    ) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(
                CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(NSColor.black.cgColor)

            let vectorPath = try XCTUnwrap(
                CaptureArrowVectorGeometry.cgPath(
                    for: arrowType,
                    tip: CGPoint(x: 48, y: 24),
                    direction: CGVector(dx: 1, dy: 0),
                    scale: 1
                )
            )
            context.addPath(vectorPath.path)
            context.drawPath(using: vectorPath.evenOddFill ? .eoFill : .fill)
        }

        return bytes
    }

    private func save(image: NSImage, to path: String) throws {
        try pngData(in: image).write(to: URL(fileURLWithPath: path))
    }

    private func pixelColor(in image: NSImage, x: Int, y: Int) -> NSColor? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.colorAt(x: x, y: y)
    }

    private func referenceArrowSignature(
        image: NSImage,
        arrowType: CaptureArrowType
    ) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(
                CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(NSColor.black.cgColor)

            let tip = CGPoint(x: 48, y: 24)
            let scale: CGFloat = 1
            let path = CGMutablePath()
            let fillRule: CGPathFillRule

            switch arrowType {
            case .normal:
                fillRule = .evenOdd
                appendClosedSubpath(
                    to: path,
                    points: [
                        CGPoint(x: 12, y: 8),
                        CGPoint(x: 20, y: 12),
                        CGPoint(x: 12, y: 16),
                        CGPoint(x: 13.4784, y: 13),
                        CGPoint(x: 4, y: 13),
                        CGPoint(x: 4, y: 11),
                        CGPoint(x: 13.4784, y: 11),
                    ],
                    tip: tip,
                    scale: scale
                )
            case .solidArrow:
                fillRule = .winding
                appendClosedSubpath(
                    to: path,
                    points: [
                        CGPoint(x: 12.979733, y: 14.0133576),
                        CGPoint(x: 11.9712417, y: 16.0147138),
                        CGPoint(x: 20, y: 12.0457356),
                        CGPoint(x: 11.9712417, y: 8.01471379),
                        CGPoint(x: 12.979733, y: 10.0250492),
                        CGPoint(x: 4, y: 12.0457356),
                    ],
                    tip: tip,
                    scale: scale
                )
            case .hollowArrow:
                fillRule = .winding
                appendClosedSubpath(
                    to: path,
                    points: [
                        CGPoint(x: 12.979733, y: 14.0133576),
                        CGPoint(x: 11.9712417, y: 16.0147138),
                        CGPoint(x: 20, y: 12.0457356),
                        CGPoint(x: 11.9712417, y: 8.01471379),
                        CGPoint(x: 12.979733, y: 10.0250492),
                        CGPoint(x: 4, y: 12.0457356),
                    ],
                    tip: tip,
                    scale: scale
                )
                let strokedPath = path.copy(
                    strokingWithWidth: max(0.5, 0.5 * scale),
                    lineCap: .butt,
                    lineJoin: .miter,
                    miterLimit: 4
                )
                context.addPath(strokedPath)
                context.drawPath(using: .fill)
                return
            case .none, .bar, .dot, .diamond:
                XCTFail("Unsupported test arrow type: \(arrowType)")
                return
            }

            context.addPath(path)
            context.drawPath(using: fillRule == .evenOdd ? .eoFill : .fill)
        }

        return bytes
    }

    private func renderCurvedArrowVectorSignature(
        arrowType: CaptureArrowType,
        strokeWidth: CGFloat
    ) throws -> [UInt8] {
        let vectorPath = try XCTUnwrap(
            CaptureArrowVectorGeometry.cgPathAlongCurve(
                for: arrowType,
                start: CGPoint(x: 34, y: 20),
                control: CGPoint(x: 134, y: 90),
                end: CGPoint(x: 34, y: 160),
                strokeWidth: strokeWidth
            )
        )
        return try renderPathSignature(path: vectorPath.path, evenOddFill: vectorPath.evenOddFill)
    }

    private func referenceStrokedHollowCurveSignature(strokeWidth: CGFloat) throws -> [UInt8] {
        let solidPath = try XCTUnwrap(
            CaptureArrowVectorGeometry.cgPathAlongCurve(
                for: .solidArrow,
                start: CGPoint(x: 34, y: 20),
                control: CGPoint(x: 134, y: 90),
                end: CGPoint(x: 34, y: 160),
                strokeWidth: strokeWidth
            )
        )
        let strokedPath = solidPath.path.copy(
            strokingWithWidth: max(1, strokeWidth * 0.5),
            lineCap: .butt,
            lineJoin: .miter,
            miterLimit: 4
        )
        return try renderPathSignature(path: strokedPath, evenOddFill: false)
    }

    private func renderPathSignature(path: CGPath, evenOddFill: Bool) throws -> [UInt8] {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 180, height: 180),
            pixelWidth: 180,
            pixelHeight: 180,
            fill: .white
        )
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)

        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(
                CGContext(
                    data: buffer.baseAddress,
                    width: cgImage.width,
                    height: cgImage.height,
                    bitsPerComponent: 8,
                    bytesPerRow: cgImage.width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(path)
            context.drawPath(using: evenOddFill ? .eoFill : .fill)
        }

        return bytes
    }

    private func renderReferenceDiagonalArrowVariants(
        image: NSImage,
        style: CaptureAnnotationStyle,
        arrows: [(line: CaptureArrowLine, type: CaptureArrowType)]
    ) throws -> NSImage {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        context.setStrokeColor((style.strokeColor.usingColorSpace(.sRGB) ?? style.strokeColor).cgColor)
        context.setFillColor((style.strokeColor.usingColorSpace(.sRGB) ?? style.strokeColor).cgColor)

        for arrow in arrows {
            drawReferenceArrowLine(
                arrow.line,
                type: arrow.type,
                strokeWidth: style.strokeWidth,
                in: context
            )
        }

        let rendered = try XCTUnwrap(context.makeImage())
        return NSImage(cgImage: rendered, size: image.size)
    }

    private func drawReferenceArrowLine(
        _ arrowLine: CaptureArrowLine,
        type: CaptureArrowType,
        strokeWidth: CGFloat,
        in context: CGContext
    ) {
        let start = CGPoint(x: arrowLine.start.x, y: arrowLine.start.y)
        let control = CGPoint(x: arrowLine.control.x, y: arrowLine.control.y)
        let end = CGPoint(x: arrowLine.end.x, y: arrowLine.end.y)

        switch type {
        case .normal:
            let headLength = max(18, strokeWidth * 4.6)
            let headInset = headLength * 0.62
            let bodyEnd = referenceCurvePoint(
                start: start,
                control: control,
                end: end,
                distanceFromEnd: headInset
            )
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: bodyEnd, control: control)
            context.saveGState()
            context.setLineWidth(strokeWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
            drawReferenceArrowHead(
                tip: end,
                direction: referenceDirection(atEndOf: arrowLine),
                lineWidth: strokeWidth,
                in: context
            )
        case .solidArrow:
            if let path = referenceTaperedArrowPath(
                start: start,
                control: control,
                end: end,
                tailHalfWidth: max(0.6, strokeWidth * 0.08),
                neckHalfWidth: max(4.4, strokeWidth * 0.95),
                endInset: referenceSpecialArrowHeadOverlapInset(for: .solidArrow, strokeWidth: strokeWidth)
            ) {
                context.addPath(path)
                context.fillPath()
            }
        case .hollowArrow:
            let neckHalfWidth = max(4.6, strokeWidth * 1.0)
            let outlineHalfWidth = min(neckHalfWidth * 0.32, max(0.9, strokeWidth * 0.28))
            let endInset = referenceSpecialArrowHeadOverlapInset(for: .hollowArrow, strokeWidth: strokeWidth)
            if let outer = referenceTaperedArrowPath(
                start: start,
                control: control,
                end: end,
                tailHalfWidth: max(0.8, strokeWidth * 0.12),
                neckHalfWidth: neckHalfWidth,
                endInset: endInset
            ), let inner = referenceTaperedArrowPath(
                start: start,
                control: control,
                end: end,
                tailHalfWidth: 0,
                neckHalfWidth: max(0.75, neckHalfWidth - outlineHalfWidth * 2),
                endInset: endInset + max(1.5, strokeWidth * 0.35),
                startInset: max(6, strokeWidth * 1.8)
            ) {
                let path = CGMutablePath()
                path.addPath(outer)
                path.addPath(inner)
                context.addPath(path)
                context.drawPath(using: .eoFill)
            }
        case .none, .bar, .dot, .diamond:
            XCTFail("Unsupported test arrow type: \(type)")
        }
    }

    private func referenceSpecialArrowHeadOverlapInset(for type: CaptureArrowType, strokeWidth: CGFloat) -> CGFloat {
        let scale = max(0.8, strokeWidth / 2)
        let headBack = (20 - 11.45) * scale
        switch type {
        case .solidArrow, .hollowArrow:
            return max(2.5, headBack * 0.45)
        case .none, .bar, .dot, .diamond, .normal:
            return 0
        }
    }

    private func referenceTaperedArrowPath(
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        tailHalfWidth: CGFloat,
        neckHalfWidth: CGFloat,
        endInset: CGFloat,
        startInset: CGFloat = 0
    ) -> CGPath? {
        let frames = referenceCurveFrames(start: start, control: control, end: end)
        guard let last = frames.last, last.distance > 0.001 else {
            return nil
        }

        let totalDistance = last.distance
        let shaftEndDistance = max(startInset, totalDistance - endInset)
        let sampleSpan = max(0, shaftEndDistance - startInset)
        let sampleCount = max(10, Int(sampleSpan / 8))
        var left: [CGPoint] = []
        var right: [CGPoint] = []

        for index in 0...sampleCount {
            let progress = CGFloat(index) / CGFloat(sampleCount)
            let distance = startInset + sampleSpan * progress
            let frame = referenceInterpolatedFrame(at: distance, frames: frames)
            let eased = 1 - pow(1 - progress, 2)
            let halfWidth = tailHalfWidth + (neckHalfWidth - tailHalfWidth) * eased
            let normal = CGVector(dx: -frame.tangent.dy, dy: frame.tangent.dx)
            left.append(CGPoint(x: frame.point.x + normal.dx * halfWidth, y: frame.point.y + normal.dy * halfWidth))
            right.append(CGPoint(x: frame.point.x - normal.dx * halfWidth, y: frame.point.y - normal.dy * halfWidth))
        }

        let path = CGMutablePath()
        guard let first = left.first else {
            return nil
        }
        path.move(to: first)
        left.dropFirst().forEach { path.addLine(to: $0) }
        right.reversed().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private func drawReferenceArrowHead(
        tip: CGPoint,
        direction: CGVector,
        lineWidth: CGFloat,
        in context: CGContext
    ) {
        let scale = max(0.8, lineWidth / 2)
        let path = CGMutablePath()
        let points = [
            CGPoint(x: 12, y: 8),
            CGPoint(x: 20, y: 12),
            CGPoint(x: 12, y: 16),
            CGPoint(x: 13.4784, y: 13),
            CGPoint(x: 11.45, y: 12),
            CGPoint(x: 13.4784, y: 11),
        ]

        let length = hypot(direction.dx, direction.dy)
        let unit = CGVector(dx: direction.dx / max(0.001, length), dy: direction.dy / max(0.001, length))
        let perpendicular = CGVector(dx: -unit.dy, dy: unit.dx)
        func transformed(_ point: CGPoint) -> CGPoint {
            let back = (20 - point.x) * scale
            let offset = (point.y - 12) * scale
            return CGPoint(
                x: tip.x - unit.dx * back + perpendicular.dx * offset,
                y: tip.y - unit.dy * back + perpendicular.dy * offset
            )
        }

        guard let first = points.first else {
            return
        }
        path.move(to: transformed(first))
        points.dropFirst().forEach { path.addLine(to: transformed($0)) }
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }

    private struct ReferenceCurveFrame {
        let point: CGPoint
        let tangent: CGVector
        let distance: CGFloat
    }

    private func referenceCurveFrames(start: CGPoint, control: CGPoint, end: CGPoint) -> [ReferenceCurveFrame] {
        let chord = hypot(end.x - start.x, end.y - start.y)
        let steps = max(32, Int(ceil(chord / 3)))
        var frames: [ReferenceCurveFrame] = []
        frames.reserveCapacity(steps + 1)
        var previous = start
        var distance: CGFloat = 0

        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let point = referenceQuadraticPoint(start: start, control: control, end: end, t: t)
            if index > 0 {
                distance += hypot(point.x - previous.x, point.y - previous.y)
            }
            let derivative = referenceQuadraticDerivative(start: start, control: control, end: end, t: t)
            let tangent = referenceNormalized(derivative) ?? CGVector(dx: 1, dy: 0)
            frames.append(ReferenceCurveFrame(point: point, tangent: tangent, distance: distance))
            previous = point
        }
        return frames
    }

    private func referenceInterpolatedFrame(at targetDistance: CGFloat, frames: [ReferenceCurveFrame]) -> ReferenceCurveFrame {
        guard let first = frames.first, let last = frames.last else {
            return ReferenceCurveFrame(point: .zero, tangent: CGVector(dx: 1, dy: 0), distance: 0)
        }
        if targetDistance <= 0 {
            return first
        }
        if targetDistance >= last.distance {
            return last
        }

        for index in 1..<frames.count {
            let current = frames[index]
            let previous = frames[index - 1]
            if current.distance >= targetDistance {
                let span = max(0.001, current.distance - previous.distance)
                let t = (targetDistance - previous.distance) / span
                let tangent = referenceNormalized(
                    CGVector(
                        dx: previous.tangent.dx + (current.tangent.dx - previous.tangent.dx) * t,
                        dy: previous.tangent.dy + (current.tangent.dy - previous.tangent.dy) * t
                    )
                ) ?? current.tangent
                return ReferenceCurveFrame(
                    point: CGPoint(
                        x: previous.point.x + (current.point.x - previous.point.x) * t,
                        y: previous.point.y + (current.point.y - previous.point.y) * t
                    ),
                    tangent: tangent,
                    distance: targetDistance
                )
            }
        }

        return last
    }

    private func referenceCurvePoint(start: CGPoint, control: CGPoint, end: CGPoint, distanceFromEnd: CGFloat) -> CGPoint {
        let frames = referenceCurveFrames(start: start, control: control, end: end)
        let totalDistance = frames.last?.distance ?? 0
        return referenceInterpolatedFrame(at: max(0, totalDistance - distanceFromEnd), frames: frames).point
    }

    private func referenceDirection(atEndOf line: CaptureArrowLine) -> CGVector {
        let derivative = referenceQuadraticDerivative(
            start: CGPoint(x: line.start.x, y: line.start.y),
            control: CGPoint(x: line.control.x, y: line.control.y),
            end: CGPoint(x: line.end.x, y: line.end.y),
            t: 1
        )
        return referenceNormalized(derivative) ?? CGVector(dx: 1, dy: 0)
    }

    private func referenceQuadraticPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let oneMinusT = 1 - t
        return CGPoint(
            x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
            y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
        )
    }

    private func referenceQuadraticDerivative(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGVector {
        CGVector(
            dx: 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x),
            dy: 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
        )
    }

    private func referenceNormalized(_ vector: CGVector) -> CGVector? {
        let length = hypot(vector.dx, vector.dy)
        guard length > 0.001 else {
            return nil
        }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    private func appendClosedSubpath(
        to path: CGMutablePath,
        points: [CGPoint],
        tip: CGPoint,
        scale: CGFloat
    ) {
        guard let first = points.first else {
            return
        }

        path.move(to: transformedSvgArrowPoint(first, tip: tip, scale: scale))
        points.dropFirst().forEach {
            path.addLine(to: transformedSvgArrowPoint($0, tip: tip, scale: scale))
        }
        path.closeSubpath()
    }

    private func appendArrowFilled2Subpath(
        to path: CGMutablePath,
        tip: CGPoint,
        scale: CGFloat,
        insetScale: CGFloat
    ) {
        let points = [
            CGPoint(x: 12.979733, y: 14.0133576),
            CGPoint(x: 11.9712417, y: 16.0147138),
            CGPoint(x: 20, y: 12.0457356),
            CGPoint(x: 11.9712417, y: 8.01471379),
            CGPoint(x: 12.979733, y: 10.0250492),
            CGPoint(x: 4, y: 12.0457356),
        ]
        guard let first = points.first else {
            return
        }
        let axisY: CGFloat = 12.0457356
        func inset(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x,
                y: axisY + (point.y - axisY) * insetScale
            )
        }

        path.move(to: transformedSvgArrowPoint(inset(first), tip: tip, scale: scale))
        points.dropFirst().forEach {
            path.addLine(to: transformedSvgArrowPoint(inset($0), tip: tip, scale: scale))
        }
        path.closeSubpath()
    }

    private func transformedSvgArrowPoint(_ point: CGPoint, tip: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: tip.x - (20 - point.x) * scale,
            y: tip.y + (point.y - 12) * scale
        )
    }

    private func rgbaBytes(in image: NSImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(
                CGContext(
                    data: buffer.baseAddress,
                    width: cgImage.width,
                    height: cgImage.height,
                    bitsPerComponent: 8,
                    bytesPerRow: cgImage.width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return bytes
    }

    private func pngData(in image: NSImage) throws -> Data {
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func rgbaPixel(in image: NSImage, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else {
            return nil
        }

        let bytes = try rgbaBytes(in: image)
        let index = ((cgImage.height - 1 - y) * cgImage.width + x) * 4
        return (
            red: bytes[index],
            green: bytes[index + 1],
            blue: bytes[index + 2],
            alpha: bytes[index + 3]
        )
    }

    private func redPixelCount(in image: NSImage, within rect: NSRect) -> Int {
        guard
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let bytes = try? rgbaBytes(in: image)
        else {
            return 0
        }

        let minX = max(0, Int(rect.minX))
        let maxX = min(cgImage.width, Int(ceil(rect.maxX)))
        let minY = max(0, Int(rect.minY))
        let maxY = min(cgImage.height, Int(ceil(rect.maxY)))

        guard minX < maxX, minY < maxY else {
            return 0
        }

        var count = 0
        for x in minX..<maxX {
            for y in minY..<maxY {
                let index = ((cgImage.height - 1 - y) * cgImage.width + x) * 4
                let red = bytes[index]
                let green = bytes[index + 1]
                let blue = bytes[index + 2]
                let alpha = bytes[index + 3]
                if red > 180, green < 120, blue < 120, alpha > 0 {
                    count += 1
                }
            }
        }
        return count
    }

    private func brightPixelCount(in image: NSImage, within rect: NSRect) -> Int {
        guard
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let bytes = try? rgbaBytes(in: image)
        else {
            return 0
        }

        let minX = max(0, Int(rect.minX))
        let maxX = min(cgImage.width, Int(ceil(rect.maxX)))
        let minY = max(0, Int(rect.minY))
        let maxY = min(cgImage.height, Int(ceil(rect.maxY)))

        guard minX < maxX, minY < maxY else {
            return 0
        }

        var count = 0
        for x in minX..<maxX {
            for y in minY..<maxY {
                let index = ((cgImage.height - 1 - y) * cgImage.width + x) * 4
                let red = bytes[index]
                let green = bytes[index + 1]
                let blue = bytes[index + 2]
                let alpha = bytes[index + 3]
                if red > 235, green > 235, blue > 235, alpha > 0 {
                    count += 1
                }
            }
        }
        return count
    }

    private func hollowArrowOutlineThickness(strokeWidth: CGFloat) throws -> (body: Int, head: Int) {
        let image = try makeBitmapImage(
            pointSize: NSSize(width: 120, height: 120),
            pixelWidth: 120,
            pixelHeight: 120,
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = strokeWidth
        let arrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: NSRect(x: 60, y: 12, width: 0, height: 80),
            style: style,
            arrowLine: CaptureArrowLine(
                start: NSPoint(x: 60, y: 12),
                end: NSPoint(x: 60, y: 92),
                control: NSPoint(x: 60, y: 52),
                startArrowType: .none,
                endArrowType: .hollowArrow
            )
        )
        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [arrow])
        let headSampleY = Int(round(92 - max(15, strokeWidth * 3.4)))
        return (
            body: try averageRedRunLength(in: rendered, y: 42, xRange: 48...72),
            head: try averageRedRunLength(in: rendered, y: headSampleY, xRange: 48...72)
        )
    }

    private func arrowTransverseSpanAtLengthFraction(
        type: CaptureArrowType,
        strokeWidth: CGFloat,
        fraction: CGFloat
    ) throws -> CGFloat {
        try arrowTransverseSpan(
            type: type,
            strokeWidth: strokeWidth,
            start: NSPoint(x: 308, y: 28),
            end: NSPoint(x: 392, y: 142),
            control: NSPoint(x: 350, y: 85),
            fraction: fraction,
            canvasSize: NSSize(width: 420, height: 180)
        )
    }

    private func arrowTransverseSpan(
        type: CaptureArrowType,
        strokeWidth: CGFloat,
        start: NSPoint,
        end: NSPoint,
        control: NSPoint,
        fraction: CGFloat,
        canvasSize: NSSize
    ) throws -> CGFloat {
        let image = try makeBitmapImage(
            pointSize: canvasSize,
            pixelWidth: Int(canvasSize.width),
            pixelHeight: Int(canvasSize.height),
            fill: .white
        )
        var style = CaptureAnnotationStyle()
        style.strokeColor = .systemRed
        style.strokeWidth = strokeWidth
        let arrow = CaptureAnnotation(
            kind: .arrowLine,
            rect: CaptureArrowLine(
                start: start,
                end: end,
                control: control,
                startArrowType: .none,
                endArrowType: type
            ).boundingRect,
            style: style,
            arrowLine: CaptureArrowLine(
                start: start,
                end: end,
                control: control,
                startArrowType: .none,
                endArrowType: type
            )
        )
        let rendered = CaptureAnnotationRenderer.render(image: image, annotations: [arrow])
        let cgImage = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: rendered)
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let length = hypot(direction.dx, direction.dy)
        let unit = CGVector(dx: direction.dx / length, dy: direction.dy / length)
        let normal = CGVector(dx: -unit.dy, dy: unit.dx)
        let sampleDistance = length * fraction
        let sampleHalfWindow = length * 0.03
        var minOffset = CGFloat.greatestFiniteMagnitude
        var maxOffset = -CGFloat.greatestFiniteMagnitude

        for x in 0..<cgImage.width {
            for y in 0..<cgImage.height {
                let index = ((cgImage.height - 1 - y) * cgImage.width + x) * 4
                guard bytes[index] > 180, bytes[index + 1] < 120, bytes[index + 2] < 120, bytes[index + 3] > 0 else {
                    continue
                }
                let relative = CGVector(dx: CGFloat(x) - start.x, dy: CGFloat(y) - start.y)
                let along = relative.dx * unit.dx + relative.dy * unit.dy
                guard abs(along - sampleDistance) <= sampleHalfWindow else {
                    continue
                }
                let offset = relative.dx * normal.dx + relative.dy * normal.dy
                minOffset = min(minOffset, offset)
                maxOffset = max(maxOffset, offset)
            }
        }

        guard minOffset < CGFloat.greatestFiniteMagnitude, maxOffset > -CGFloat.greatestFiniteMagnitude else {
            return 0
        }
        return maxOffset - minOffset
    }

    private func averageRedRunLength(in image: NSImage, y: Int, xRange: ClosedRange<Int>) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: image)
        var runs: [Int] = []
        var currentRun = 0
        for x in xRange {
            let index = ((cgImage.height - 1 - y) * cgImage.width + x) * 4
            let isRed = bytes[index] > 180 && bytes[index + 1] < 120 && bytes[index + 2] < 120 && bytes[index + 3] > 0
            if isRed {
                currentRun += 1
            } else if currentRun > 0 {
                runs.append(currentRun)
                currentRun = 0
            }
        }
        if currentRun > 0 {
            runs.append(currentRun)
        }
        return runs.isEmpty ? 0 : Int(round(Double(runs.reduce(0, +)) / Double(runs.count)))
    }

    private func isRedPixel(in image: NSImage, x: Int, y: Int) throws -> Bool {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bytes = try rgbaBytes(in: image)
        let index = ((cgImage.height - 1 - y) * cgImage.width + x) * 4
        return bytes[index] > 180 && bytes[index + 1] < 120 && bytes[index + 2] < 120 && bytes[index + 3] > 0
    }

}
