import AppKit
import Foundation

protocol AppUpdateDownloading: AnyObject {
    func download(
        release: AppUpdateRelease,
        progress: @escaping @MainActor (Double?) -> Void
    ) async throws -> URL
    func cancel()
}

final class AppUpdateDownloadService: NSObject, AppUpdateDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var downloadedFile: Result<URL, Error>?
    private var progressHandler: (@MainActor (Double?) -> Void)?
    private var downloadDirectory: URL?
    private var lastReportedProgress: Int?
    private let redirectDelegate = CommercialSessionDelegate()

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 7_200
        configuration.waitsForConnectivity = true
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    func download(
        release: AppUpdateRelease,
        progress: @escaping @MainActor (Double?) -> Void
    ) async throws -> URL {
        guard AppUpdateRelease.isAllowedDownloadURL(release.downloadURL) else {
            throw AppUpdateInstallationError.invalidDownload
        }
        return try await withCheckedThrowingContinuation { continuation in
            let taskToResume: URLSessionDownloadTask? = lock.withLock {
                guard task == nil else {
                    continuation.resume(throwing: AppUpdateInstallationError.invalidDownload)
                    return nil
                }
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("com.xxsnap.update-download", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                } catch {
                    continuation.resume(throwing: error)
                    return nil
                }
                var request = URLRequest(
                    url: release.downloadURL,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    timeoutInterval: 60
                )
                request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                self.continuation = continuation
                progressHandler = progress
                downloadDirectory = directory
                downloadedFile = nil
                lastReportedProgress = nil
                let downloadTask = session.downloadTask(with: request)
                task = downloadTask
                return downloadTask
            }
            taskToResume?.resume()
        }
    }

    func cancel() {
        lock.withLock { task }?.cancel()
    }

    private func finish(_ result: Result<URL, Error>) {
        let completion: (CheckedContinuation<URL, Error>, URL?)? = lock.withLock {
            guard let continuation else { return nil }
            let directory = downloadDirectory
            self.continuation = nil
            task = nil
            downloadedFile = nil
            progressHandler = nil
            downloadDirectory = nil
            lastReportedProgress = nil
            return (continuation, directory)
        }
        guard let (continuation, directory) = completion else { return }
        if case .failure = result, let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        continuation.resume(with: result)
    }
}

extension AppUpdateDownloadService: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let percent = totalBytesExpectedToWrite > 0
            ? min(100, Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100))
            : -1
        let handler: (@MainActor (Double?) -> Void)? = lock.withLock {
            guard percent != lastReportedProgress else { return nil }
            lastReportedProgress = percent
            return progressHandler
        }
        guard let handler else { return }
        let value: Double? = percent >= 0 ? Double(percent) / 100 : nil
        Task { @MainActor in handler(value) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let destination = lock.withLock {
            downloadDirectory?.appendingPathComponent("update.dmg")
        }
        guard let destination,
              let response = downloadTask.response as? HTTPURLResponse,
              response.statusCode == 200
        else {
            lock.withLock {
                downloadedFile = .failure(AppUpdateInstallationError.invalidDownload)
            }
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            lock.withLock { downloadedFile = .success(destination) }
        } catch {
            lock.withLock { downloadedFile = .failure(error) }
        }
    }
}

extension AppUpdateDownloadService: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(redirectDelegate.redirectedRequest(request, statusCode: response.statusCode))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                finish(.failure(AppUpdateInstallationError.cancelled))
            } else {
                finish(.failure(error))
            }
            return
        }
        let result = lock.withLock { downloadedFile }
        finish(result ?? .failure(AppUpdateInstallationError.invalidDownload))
    }
}

@MainActor
final class UpdateProgressWindowController: NSWindowController {
    enum Stage {
        case downloading(Double?)
        case verifying
        case installing
    }

    var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let cancelButton = NSButton()
    private let strings: PreferencesStrings

    init(version: String, strings: PreferencesStrings) {
        self.strings = strings
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 190),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        configureContent(version: version)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(stage: Stage) {
        switch stage {
        case let .downloading(progress):
            cancelButton.isEnabled = true
            if let progress {
                progressIndicator.stopAnimation(nil)
                progressIndicator.isIndeterminate = false
                progressIndicator.doubleValue = progress * 100
                statusLabel.stringValue = strings.updateDownloadingProgress(Int(progress * 100))
            } else {
                progressIndicator.isIndeterminate = true
                progressIndicator.startAnimation(nil)
                statusLabel.stringValue = strings.updateDownloading
            }
        case .verifying:
            showIndeterminate(status: strings.updateVerifying)
        case .installing:
            showIndeterminate(status: strings.updateInstalling)
        }
    }

    private func showIndeterminate(status: String) {
        cancelButton.isEnabled = false
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = status
    }

    private func configureContent(version: String) {
        guard let contentView = window?.contentView else { return }
        titleLabel.stringValue = strings.updateProgressTitle(version)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        progressIndicator.style = .bar
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.controlSize = .regular
        cancelButton.title = strings.cancelShortcutReplacement
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)

        let stack = NSStackView(views: [titleLabel, statusLabel, progressIndicator, cancelButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            progressIndicator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
        ])
        stack.setCustomSpacing(20, after: progressIndicator)
    }

    @objc private func cancelPressed() {
        cancelButton.isEnabled = false
        onCancel?()
    }
}
