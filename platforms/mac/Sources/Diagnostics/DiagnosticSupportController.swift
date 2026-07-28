import AppKit
import UniformTypeIdentifiers

@MainActor
final class DiagnosticSupportController {
    private let logStore: DiagnosticLogStore
    private let exporter: DiagnosticBundleExporter
    private let settingsStore: any AppSettingsStoring

    init(
        logStore: DiagnosticLogStore,
        exporter: DiagnosticBundleExporter,
        settingsStore: any AppSettingsStoring
    ) {
        self.logStore = logStore
        self.exporter = exporter
        self.settingsStore = settingsStore
    }

    func exportDiagnostics() {
        let strings = PreferencesStrings(language: settingsStore.load().language)
        let panel = NSSavePanel()
        panel.title = strings.diagnosticExportPanelTitle
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedArchiveName()
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            try exporter.export(to: destinationURL)
            logStore.record(
                category: .export,
                level: .info,
                event: "diagnostic_export_completed"
            )
            showAlert(
                title: strings.diagnosticExportSucceededTitle,
                message: strings.diagnosticExportSucceededMessage
            )
        } catch {
            logStore.record(
                category: .export,
                level: .error,
                event: "diagnostic_export_failed",
                metadata: ["error_type": String(describing: type(of: error))]
            )
            showAlert(
                title: strings.diagnosticExportFailedTitle,
                message: strings.diagnosticExportFailedMessage
            )
        }
    }

    private func suggestedArchiveName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "XxSnap-Diagnostics-\(formatter.string(from: Date())).zip"
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
