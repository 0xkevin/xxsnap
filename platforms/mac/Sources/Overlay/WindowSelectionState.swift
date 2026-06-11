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
        guard
            let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        return windowInfo.compactMap { info in
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
        }
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
        guard candidate.layer == 0, candidate.alpha > 0.05 else {
            return false
        }

        let clipped = candidate.bounds.intersection(desktopFrame)
        guard !clipped.isEmpty else {
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
}
