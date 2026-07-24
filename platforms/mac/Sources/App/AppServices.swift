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

enum UpdateCheckResult: Equatable {
    case placeholderUpToDate
}

protocol UpdateChecking {
    func checkForUpdates() async -> UpdateCheckResult
}

struct PlaceholderUpdateChecker: UpdateChecking {
    func checkForUpdates() async -> UpdateCheckResult {
        .placeholderUpToDate
    }
}

struct RecognizedTextCandidate: Equatable {
    let text: String
    let boundingBox: CGRect
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
                    guard let text = observation.topCandidates(1).first?.string else {
                        return nil
                    }
                    return RecognizedTextCandidate(text: text, boundingBox: observation.boundingBox)
                }
                continuation.resume(returning: Self.join(candidates))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

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
