import AppKit

struct WindowSelectionCandidate: Equatable {
    var id: CGWindowID
    var ownerPID: pid_t
    var layer: Int
    var alpha: CGFloat
    var bounds: NSRect
    var name: String?
}

enum WindowSelectionState {
    static func currentCandidates(desktopFrame: NSRect) -> [WindowSelectionCandidate] {
        let screenFrames = NSScreen.screens.map(\.frame)
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        var candidates = systemUICandidates(
            screenFrames: screenFrames,
            visibleFrames: visibleFrames,
            desktopFrame: desktopFrame
        )

        guard
            let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return candidates
        }

        candidates.append(contentsOf: windowInfo.compactMap { info in
            guard
                let id = info[kCGWindowNumber as String] as? NSNumber,
                let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                let layer = info[kCGWindowLayer as String] as? NSNumber,
                let alpha = info[kCGWindowAlpha as String] as? NSNumber,
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else {
                return nil
            }

            let appKitRect = screenRectFromQuartz(bounds, desktopFrame: desktopFrame)
            return WindowSelectionCandidate(
                id: CGWindowID(id.uint32Value),
                ownerPID: pid_t(ownerPID.int32Value),
                layer: layer.intValue,
                alpha: CGFloat(alpha.doubleValue),
                bounds: appKitRect,
                name: info[kCGWindowName as String] as? String
            )
        })

        return candidates
    }

    static func systemUICandidates(screenFrames: [NSRect], visibleFrames: [NSRect], desktopFrame: NSRect) -> [WindowSelectionCandidate] {
        let minimumSystemUISize: CGFloat = 12
        var candidates: [WindowSelectionCandidate] = []

        for (index, pair) in zip(screenFrames, visibleFrames).enumerated() {
            let screenFrame = pair.0.standardized
            let visibleFrame = pair.1.standardized.intersection(screenFrame)
            guard !screenFrame.isEmpty, !visibleFrame.isEmpty else {
                continue
            }

            let topInset = max(0, screenFrame.maxY - visibleFrame.maxY)
            if topInset >= minimumSystemUISize {
                let rect = NSRect(
                    x: screenFrame.minX,
                    y: visibleFrame.maxY,
                    width: screenFrame.width,
                    height: topInset
                )
                candidates.append(systemUICandidate(
                    id: syntheticWindowID(base: 0xFFFE0000, index: index),
                    layer: 24,
                    bounds: localRect(from: rect, desktopFrame: desktopFrame),
                    name: "Menubar"
                ))
            }

            let bottomInset = max(0, visibleFrame.minY - screenFrame.minY)
            if bottomInset >= minimumSystemUISize {
                let rect = NSRect(
                    x: screenFrame.minX,
                    y: screenFrame.minY,
                    width: screenFrame.width,
                    height: bottomInset
                )
                candidates.append(systemUICandidate(
                    id: syntheticWindowID(base: 0xFFFD0000, index: index),
                    layer: 20,
                    bounds: localRect(from: rect, desktopFrame: desktopFrame),
                    name: "Dock"
                ))
            }

            let leftInset = max(0, visibleFrame.minX - screenFrame.minX)
            if leftInset >= minimumSystemUISize {
                let rect = NSRect(
                    x: screenFrame.minX,
                    y: visibleFrame.minY,
                    width: leftInset,
                    height: visibleFrame.height
                )
                candidates.append(systemUICandidate(
                    id: syntheticWindowID(base: 0xFFFC0000, index: index),
                    layer: 20,
                    bounds: localRect(from: rect, desktopFrame: desktopFrame),
                    name: "Dock"
                ))
            }

            let rightInset = max(0, screenFrame.maxX - visibleFrame.maxX)
            if rightInset >= minimumSystemUISize {
                let rect = NSRect(
                    x: visibleFrame.maxX,
                    y: visibleFrame.minY,
                    width: rightInset,
                    height: visibleFrame.height
                )
                candidates.append(systemUICandidate(
                    id: syntheticWindowID(base: 0xFFFB0000, index: index),
                    layer: 20,
                    bounds: localRect(from: rect, desktopFrame: desktopFrame),
                    name: "Dock"
                ))
            }
        }

        return candidates
    }

    static func bestWindow(
        at point: NSPoint,
        candidates: [WindowSelectionCandidate],
        desktopFrame: NSRect,
        currentProcessID: pid_t
    ) -> WindowSelectionCandidate? {
        candidates
            .filter { isSelectable($0, desktopFrame: desktopFrame, currentProcessID: currentProcessID) }
            .first { $0.bounds.contains(point) }
    }

    private static func isSelectable(_ candidate: WindowSelectionCandidate, desktopFrame: NSRect, currentProcessID: pid_t) -> Bool {
        guard candidate.ownerPID != currentProcessID else {
            return false
        }
        guard candidate.alpha > 0.05 else {
            return false
        }

        let clipped = candidate.bounds.intersection(desktopFrame)
        guard !clipped.isEmpty else {
            return false
        }

        if isSystemBar(candidate, clippedTo: clipped, desktopFrame: desktopFrame) {
            return true
        }

        guard candidate.layer == 0 else {
            return false
        }

        return clipped.width >= 48 && clipped.height >= 48
    }

    private static func screenRectFromQuartz(_ rect: CGRect, desktopFrame: NSRect) -> NSRect {
        NSRect(
            x: rect.minX - desktopFrame.minX,
            y: desktopFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func localRect(from screenRect: NSRect, desktopFrame: NSRect) -> NSRect {
        NSRect(
            x: screenRect.minX - desktopFrame.minX,
            y: screenRect.minY - desktopFrame.minY,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    private static func systemUICandidate(id: CGWindowID, layer: Int, bounds: NSRect, name: String) -> WindowSelectionCandidate {
        WindowSelectionCandidate(
            id: id,
            ownerPID: 0,
            layer: layer,
            alpha: 1,
            bounds: bounds,
            name: name
        )
    }

    private static func syntheticWindowID(base: UInt32, index: Int) -> CGWindowID {
        CGWindowID(base + UInt32(index))
    }

    private static func isSystemBar(_ candidate: WindowSelectionCandidate, clippedTo clipped: NSRect, desktopFrame: NSRect) -> Bool {
        switch candidate.name {
        case "Menubar", "Menu Bar":
            return candidate.layer >= 24
                && clipped.width >= 48
                && clipped.height >= 12
        case "Dock":
            let fillsDesktop = abs(clipped.width - desktopFrame.width) < 1
                && abs(clipped.height - desktopFrame.height) < 1
            return candidate.layer >= 20
                && !fillsDesktop
                && clipped.width >= 12
                && clipped.height >= 12
        default:
            return false
        }
    }
}
