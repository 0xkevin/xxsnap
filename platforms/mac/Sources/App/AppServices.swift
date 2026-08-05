import AppKit
import Foundation
import ServiceManagement
import Vision

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

@MainActor
protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ isEnabled: Bool) async throws
    func openSystemSettings()
}

@MainActor
final class LaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

struct RecognizedTextCandidate: Equatable {
    let text: String
    let boundingBox: CGRect
}

private struct RecognizedTextGlyph {
    let offset: Int
    let text: String
    let boundingBox: CGRect
}

private struct DetailedRecognizedText {
    var text: String
    let boundingBox: CGRect
    let glyphs: [RecognizedTextGlyph]
}

private struct RecognizedTextRun {
    let text: String
    let boundingBox: CGRect
}

private struct TextReplacement {
    let offsets: ClosedRange<Int>
    let text: String
}

struct QRCodeCandidate: Equatable {
    let payload: String
    let boundingBox: CGRect
}

protocol QRCodeRecognizing {
    func recognizeQRCode(in image: NSImage) async throws -> QRCodeCandidate?
}

enum QRCodeRecognitionError: LocalizedError, Equatable {
    case imageConversionFailed
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Unable to read image data for QR code recognition."
        case .requestFailed:
            return "QR code recognition failed."
        }
    }
}

final class QRCodeRecognitionService: QRCodeRecognizing {
    func recognizeQRCode(in image: NSImage) async throws -> QRCodeCandidate? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw QRCodeRecognitionError.imageConversionFailed
        }
        return try await recognizeQRCode(in: cgImage)
    }

    func recognizeQRCode(in cgImage: CGImage) async throws -> QRCodeCandidate? {
        let candidates: [QRCodeCandidate] = try await withCheckedThrowingContinuation {
            continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if error != nil {
                    continuation.resume(throwing: QRCodeRecognitionError.requestFailed)
                    return
                }
                let observations = (request.results as? [VNBarcodeObservation]) ?? []
                let candidates = observations.compactMap { observation -> QRCodeCandidate? in
                    guard observation.symbology == .qr,
                          let payload = observation.payloadStringValue
                    else {
                        return nil
                    }
                    return QRCodeCandidate(
                        payload: payload,
                        boundingBox: observation.boundingBox
                    )
                }
                continuation.resume(returning: candidates)
            }
            request.symbologies = [.qr]

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: QRCodeRecognitionError.requestFailed)
            }
        }
        return Self.preferredCandidate(from: candidates)
    }

    static func preferredCandidate(from candidates: [QRCodeCandidate]) -> QRCodeCandidate? {
        candidates
            .map {
                QRCodeCandidate(
                    payload: $0.payload.trimmingCharacters(in: .whitespacesAndNewlines),
                    boundingBox: $0.boundingBox
                )
            }
            .filter { !$0.payload.isEmpty }
            .sorted { lhs, rhs in
                let lhsArea = lhs.boundingBox.width * lhs.boundingBox.height
                let rhsArea = rhs.boundingBox.width * rhs.boundingBox.height
                if lhsArea != rhsArea {
                    return lhsArea > rhsArea
                }
                return distanceFromCenterSquared(lhs.boundingBox)
                    < distanceFromCenterSquared(rhs.boundingBox)
            }
            .first
    }

    private static func distanceFromCenterSquared(_ rect: CGRect) -> CGFloat {
        let deltaX = rect.midX - 0.5
        let deltaY = rect.midY - 0.5
        return deltaX * deltaX + deltaY * deltaY
    }
}

protocol OCRTextRecognizing {
    func recognizeText(in image: NSImage) async throws -> String
}

enum OCRTextRecognitionError: LocalizedError, Equatable {
    case imageConversionFailed
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Unable to read image data for text recognition."
        case .requestFailed:
            return "Text recognition failed."
        }
    }
}

final class OCRTextRecognitionService: OCRTextRecognizing {
    func recognizeText(in image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRTextRecognitionError.imageConversionFailed
        }
        return try await recognizeText(in: cgImage)
    }

    func recognizeText(in cgImage: CGImage) async throws -> String {
        let horizontalText = try await recognizeHorizontalText(in: cgImage)
        guard (cgImage.height > cgImage.width || horizontalText.isEmpty),
              let verticalColumns = Self.horizontalizedVerticalTextColumns(from: cgImage)
        else {
            return horizontalText
        }

        var verticalText: [String] = []
        for column in verticalColumns {
            let automaticText = try await recognizeHorizontalText(in: column)
            var text = automaticText
            if automaticText.isEmpty || Self.containsHangul(automaticText),
               let koreanText = try? await recognizeHorizontalText(
                   in: column,
                   recognitionLanguages: ["ko-KR"]
               ),
               Self.textScore(koreanText) > Self.textScore(automaticText) {
                text = koreanText
            }
            text = Self.compactVerticalText(text)
            if !text.isEmpty {
                verticalText.append(text)
            }
        }
        let combinedVerticalText = verticalText.joined(separator: "\n")
        return Self.textScore(combinedVerticalText) > Self.textScore(horizontalText)
            ? combinedVerticalText
            : horizontalText
    }

    private func recognizeHorizontalText(
        in cgImage: CGImage,
        recognitionLanguages: [String]? = nil
    ) async throws -> String {
        var lines = try await recognizeHorizontalLines(
            in: cgImage,
            recognitionLanguages: recognitionLanguages
        )
        let text = Self.joinedText(from: lines)
        if recognitionLanguages == nil,
           Self.shouldAttemptEmbeddedKoreanRepair(text) {
            lines = await repairingEmbeddedKorean(in: lines, sourceImage: cgImage)
        }
        return Self.joinedText(from: lines)
    }

    static func shouldAttemptEmbeddedKoreanRepair(_ text: String) -> Bool {
        guard containsHanIdeograph(text), !containsHangul(text) else { return false }
        let groupingPairs: [(Character, Character)] = [
            ("(", ")"), ("（", "）"), ("[", "]"), ("【", "】"), ("{", "}"),
        ]
        return groupingPairs.contains { opening, closing in
            text.contains(opening) && text.contains(closing)
        }
    }

    private func recognizeHorizontalLines(
        in cgImage: CGImage,
        recognitionLanguages: [String]?
    ) async throws -> [DetailedRecognizedText] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    continuation.resume(throwing: OCRTextRecognitionError.requestFailed)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let candidates = observations.compactMap { observation -> DetailedRecognizedText? in
                    guard let recognizedText = observation.topCandidates(1).first else {
                        return nil
                    }
                    var glyphs: [RecognizedTextGlyph] = []
                    var index = recognizedText.string.startIndex
                    var offset = 0
                    while index < recognizedText.string.endIndex {
                        let nextIndex = recognizedText.string.index(after: index)
                        if let box = try? recognizedText.boundingBox(for: index..<nextIndex) {
                            glyphs.append(
                                RecognizedTextGlyph(
                                    offset: offset,
                                    text: String(recognizedText.string[index..<nextIndex]),
                                    boundingBox: box.boundingBox
                                )
                            )
                        }
                        index = nextIndex
                        offset += 1
                    }
                    return DetailedRecognizedText(
                        text: recognizedText.string,
                        boundingBox: observation.boundingBox,
                        glyphs: glyphs
                    )
                }
                continuation.resume(returning: candidates)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let recognitionLanguages {
                request.recognitionLanguages = recognitionLanguages
                request.automaticallyDetectsLanguage = false
            } else {
                request.automaticallyDetectsLanguage = true
            }

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: OCRTextRecognitionError.requestFailed)
            }
        }
    }

    private func repairingEmbeddedKorean(
        in lines: [DetailedRecognizedText],
        sourceImage: CGImage
    ) async -> [DetailedRecognizedText] {
        guard let koreanLines = try? await recognizeHorizontalLines(
            in: sourceImage,
            recognitionLanguages: ["ko-KR"]
        ) else {
            return lines
        }

        var replacements: [Int: [TextReplacement]] = [:]
        for run in koreanLines.flatMap(Self.hangulRuns).prefix(12) {
            guard let crop = Self.crop(sourceImage, around: run.boundingBox),
                  let cropLines = try? await recognizeHorizontalLines(
                    in: crop,
                    recognitionLanguages: nil
                  ),
                  Self.containsHangul(Self.joinedText(from: cropLines)),
                  let match = Self.bestReplacementMatch(for: run, in: lines)
            else {
                continue
            }
            replacements[match.lineIndex, default: []].append(
                TextReplacement(offsets: match.offsets, text: run.text)
            )
        }

        return lines.enumerated().map { index, line in
            guard let lineReplacements = replacements[index], !lineReplacements.isEmpty else {
                return line
            }
            var repaired = line
            repaired.text = Self.replacingText(in: line.text, with: lineReplacements)
            return repaired
        }
    }

    private struct Raster {
        let width: Int
        let height: Int
        let bytes: [UInt8]
        let background: (red: UInt8, green: UInt8, blue: UInt8)

        init?(image: CGImage) {
            width = image.width
            height = image.height
            guard width > 0, height > 0 else { return nil }

            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return nil
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = pixels

            let stepX = max(1, width / 80)
            let stepY = max(1, height / 80)
            var red: [UInt8] = []
            var green: [UInt8] = []
            var blue: [UInt8] = []
            for x in stride(from: 0, to: width, by: stepX) {
                Self.appendColor(atX: x, y: 0, width: width, pixels: pixels, red: &red, green: &green, blue: &blue)
                Self.appendColor(atX: x, y: height - 1, width: width, pixels: pixels, red: &red, green: &green, blue: &blue)
            }
            for y in stride(from: 0, to: height, by: stepY) {
                Self.appendColor(atX: 0, y: y, width: width, pixels: pixels, red: &red, green: &green, blue: &blue)
                Self.appendColor(atX: width - 1, y: y, width: width, pixels: pixels, red: &red, green: &green, blue: &blue)
            }
            background = (
                Self.median(red),
                Self.median(green),
                Self.median(blue)
            )
        }

        func isForeground(x: Int, y: Int) -> Bool {
            let offset = (y * width + x) * 4
            let difference = max(
                abs(Int(bytes[offset]) - Int(background.red)),
                abs(Int(bytes[offset + 1]) - Int(background.green)),
                abs(Int(bytes[offset + 2]) - Int(background.blue))
            )
            return difference >= 32 && bytes[offset + 3] >= 64
        }

        private static func appendColor(
            atX x: Int,
            y: Int,
            width: Int,
            pixels: [UInt8],
            red: inout [UInt8],
            green: inout [UInt8],
            blue: inout [UInt8]
        ) {
            let offset = (y * width + x) * 4
            guard offset >= 0, offset + 2 < pixels.count else { return }
            red.append(pixels[offset])
            green.append(pixels[offset + 1])
            blue.append(pixels[offset + 2])
        }

        private static func median(_ values: [UInt8]) -> UInt8 {
            guard !values.isEmpty else { return 255 }
            return values.sorted()[values.count / 2]
        }
    }

    private static func horizontalizedVerticalTextColumns(from image: CGImage) -> [CGImage]? {
        guard let raster = Raster(image: image) else { return nil }

        var columnProjection = [Int](repeating: 0, count: raster.width)
        for x in 0..<raster.width {
            for y in 0..<raster.height where raster.isForeground(x: x, y: y) {
                columnProjection[x] += 1
            }
        }
        let columnGap = max(4, min(28, raster.width / 14))
        let columns = activeRanges(
            projection: columnProjection,
            threshold: max(2, raster.height / 300),
            maximumGap: columnGap,
            minimumLength: 5
        )
        guard !columns.isEmpty else { return nil }

        var results: [CGImage] = []
        for column in columns.reversed() {
            let expandedColumn = expanded(
                column,
                padding: max(3, columnGap / 3),
                limit: raster.width
            )
            var rowProjection = [Int](repeating: 0, count: raster.height)
            for y in 0..<raster.height {
                for x in expandedColumn where raster.isForeground(x: x, y: y) {
                    rowProjection[y] += 1
                }
            }
            let rowGap = 4
            let rows = activeRanges(
                projection: rowProjection,
                threshold: max(2, expandedColumn.count / 35),
                maximumGap: rowGap,
                minimumLength: 5
            )
            guard rows.count >= 2 else { continue }

            let glyphRects = rows.map { row -> CGRect in
                let expandedRow = expanded(
                    row,
                    padding: max(3, rowGap / 2),
                    limit: raster.height
                )
                return CGRect(
                    x: expandedColumn.lowerBound,
                    y: expandedRow.lowerBound,
                    width: expandedColumn.count,
                    height: expandedRow.count
                )
            }
            if let horizontalized = horizontalizedImage(
                raster: raster,
                glyphRects: glyphRects
            ) {
                results.append(horizontalized)
            }
        }
        return results.isEmpty ? nil : results
    }

    private static func horizontalizedImage(
        raster: Raster,
        glyphRects: [CGRect]
    ) -> CGImage? {
        let largestGlyph = glyphRects.reduce(0) {
            max($0, Int(max($1.width, $1.height)))
        }
        let tileSize = max(24, largestGlyph + 12)
        let width = tileSize * glyphRects.count
        let height = tileSize
        guard width > 0 else { return nil }

        var output = [UInt8](repeating: 255, count: width * height * 4)
        for pixel in stride(from: 0, to: output.count, by: 4) {
            output[pixel] = raster.background.red
            output[pixel + 1] = raster.background.green
            output[pixel + 2] = raster.background.blue
            output[pixel + 3] = 255
        }

        for (index, rect) in glyphRects.enumerated() {
            let sourceX = Int(rect.minX)
            let sourceY = Int(rect.minY)
            let sourceWidth = Int(rect.width)
            let sourceHeight = Int(rect.height)
            let destinationX = index * tileSize + (tileSize - sourceWidth) / 2
            let destinationY = (tileSize - sourceHeight) / 2
            for y in 0..<sourceHeight {
                let sourceOffset = ((sourceY + y) * raster.width + sourceX) * 4
                let destinationOffset = (
                    (destinationY + y) * width + destinationX
                ) * 4
                output.replaceSubrange(
                    destinationOffset..<(destinationOffset + sourceWidth * 4),
                    with: raster.bytes[sourceOffset..<(sourceOffset + sourceWidth * 4)]
                )
            }
        }

        let data = Data(output) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func activeRanges(
        projection: [Int],
        threshold: Int,
        maximumGap: Int,
        minimumLength: Int
    ) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start: Int?
        var lastActive: Int?

        for (index, value) in projection.enumerated() where value >= threshold {
            if let lastActive, index - lastActive > maximumGap + 1 {
                if let start, lastActive + 1 - start >= minimumLength {
                    ranges.append(start..<(lastActive + 1))
                }
                start = index
            } else if start == nil {
                start = index
            }
            lastActive = index
        }
        if let start, let lastActive, lastActive + 1 - start >= minimumLength {
            ranges.append(start..<(lastActive + 1))
        }
        return ranges
    }

    private static func expanded(
        _ range: Range<Int>,
        padding: Int,
        limit: Int
    ) -> Range<Int> {
        max(0, range.lowerBound - padding)..<min(limit, range.upperBound + padding)
    }

    private static func textScore(_ text: String) -> Int {
        text.unicodeScalars.reduce(into: 0) { score, scalar in
            if CharacterSet.alphanumerics.contains(scalar) || scalar.value >= 0x2E80 {
                score += 1
            }
        }
    }

    private static func compactVerticalText(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x11FF,
                 0x3130...0x318F,
                 0xA960...0xA97F,
                 0xAC00...0xD7AF,
                 0xD7B0...0xD7FF:
                return true
            default:
                return false
            }
        }
    }

    private static func containsHanIdeograph(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private static func joinedText(from lines: [DetailedRecognizedText]) -> String {
        join(
            lines.map {
                RecognizedTextCandidate(text: $0.text, boundingBox: $0.boundingBox)
            }
        )
    }

    private static func hangulRuns(in line: DetailedRecognizedText) -> [RecognizedTextRun] {
        var runs: [RecognizedTextRun] = []
        var text = ""
        var boundingBox: CGRect?
        var previousOffset: Int?

        func finishRun() {
            if let boundingBox, !text.isEmpty {
                runs.append(RecognizedTextRun(text: text, boundingBox: boundingBox))
            }
            text = ""
            boundingBox = nil
            previousOffset = nil
        }

        for glyph in line.glyphs.sorted(by: { $0.offset < $1.offset }) {
            guard containsHangul(glyph.text) else {
                finishRun()
                continue
            }
            if let previousOffset, glyph.offset != previousOffset + 1 {
                finishRun()
            }
            text += glyph.text
            boundingBox = boundingBox?.union(glyph.boundingBox) ?? glyph.boundingBox
            previousOffset = glyph.offset
        }
        finishRun()
        return runs
    }

    private static func crop(_ image: CGImage, around boundingBox: CGRect) -> CGImage? {
        let padded = CGRect(
            x: max(0, boundingBox.minX - 0.025),
            y: max(0, boundingBox.minY - 0.06),
            width: min(1, boundingBox.maxX + 0.025) - max(0, boundingBox.minX - 0.025),
            height: min(1, boundingBox.maxY + 0.06) - max(0, boundingBox.minY - 0.06)
        )
        let imageRect = CGRect(
            x: padded.minX * CGFloat(image.width),
            y: (1 - padded.maxY) * CGFloat(image.height),
            width: padded.width * CGFloat(image.width),
            height: padded.height * CGFloat(image.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !imageRect.isNull, imageRect.width > 0, imageRect.height > 0 else {
            return nil
        }
        return image.cropping(to: imageRect)
    }

    private static func bestReplacementMatch(
        for run: RecognizedTextRun,
        in lines: [DetailedRecognizedText]
    ) -> (lineIndex: Int, offsets: ClosedRange<Int>)? {
        var bestMatch: (lineIndex: Int, offsets: ClosedRange<Int>, score: CGFloat)?

        for (lineIndex, line) in lines.enumerated() {
            let matchingGlyphs = line.glyphs.filter { glyph in
                guard isTextualGlyph(glyph.text) else { return false }
                let intersection = glyph.boundingBox.intersection(run.boundingBox)
                guard !intersection.isNull else { return false }
                let minimumArea = min(
                    glyph.boundingBox.width * glyph.boundingBox.height,
                    run.boundingBox.width * run.boundingBox.height
                )
                return minimumArea > 0
                    && (intersection.width * intersection.height) / minimumArea >= 0.2
            }
            guard let firstOffset = matchingGlyphs.map(\.offset).min(),
                  let lastOffset = matchingGlyphs.map(\.offset).max()
            else {
                continue
            }
            let score = matchingGlyphs.reduce(CGFloat.zero) { total, glyph in
                let intersection = glyph.boundingBox.intersection(run.boundingBox)
                return total + (intersection.isNull ? 0 : intersection.width * intersection.height)
            }
            if bestMatch == nil || score > bestMatch!.score {
                bestMatch = (lineIndex, firstOffset...lastOffset, score)
            }
        }
        return bestMatch.map { ($0.lineIndex, $0.offsets) }
    }

    private static func isTextualGlyph(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }

    private static func replacingText(
        in text: String,
        with replacements: [TextReplacement]
    ) -> String {
        let characters = Array(text)
        let sortedReplacements = replacements.sorted {
            $0.offsets.lowerBound < $1.offsets.lowerBound
        }
        var result = ""
        var offset = 0
        var replacementIndex = 0

        while offset < characters.count {
            while replacementIndex < sortedReplacements.count,
                  sortedReplacements[replacementIndex].offsets.upperBound < offset {
                replacementIndex += 1
            }
            if replacementIndex < sortedReplacements.count,
               sortedReplacements[replacementIndex].offsets.lowerBound == offset {
                let replacement = sortedReplacements[replacementIndex]
                result += replacement.text
                offset = min(characters.count, replacement.offsets.upperBound + 1)
                replacementIndex += 1
            } else {
                result.append(characters[offset])
                offset += 1
            }
        }
        return result
    }

    static func join(_ candidates: [RecognizedTextCandidate]) -> String {
        let lineThreshold: CGFloat = 0.03
        let sorted = candidates
            .map {
                RecognizedTextCandidate(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    boundingBox: $0.boundingBox
                )
            }
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
            if let lastIndex = lines.indices.last,
               let first = lines[lastIndex].first,
               abs(first.boundingBox.midY - candidate.boundingBox.midY) <= lineThreshold {
                lines[lastIndex].append(candidate)
            } else {
                lines.append([candidate])
            }
        }

        return lines.map { line in
            line.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
    }
}
