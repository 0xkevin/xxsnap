import CoreGraphics

protocol ScreenCapturePermissionCoordinating: AnyObject {
    func hasScreenCapturePermission() -> Bool
    func shouldShowScreenCaptureGuidance() -> Bool
    @discardableResult func requestScreenCapturePermissionOnce() -> Bool
}

final class PermissionCoordinator: ScreenCapturePermissionCoordinating {
    private static var didShowScreenCaptureGuidance = false
    private var didRequestPermission = false

    func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func shouldShowScreenCaptureGuidance() -> Bool {
        if hasScreenCapturePermission() {
            Self.didShowScreenCaptureGuidance = false
            return false
        }

        guard !Self.didShowScreenCaptureGuidance else {
            return false
        }

        Self.didShowScreenCaptureGuidance = true
        return true
    }

    @discardableResult
    func requestScreenCapturePermissionOnce() -> Bool {
        if hasScreenCapturePermission() {
            return true
        }

        guard !didRequestPermission else {
            return false
        }

        didRequestPermission = true
        return CGRequestScreenCaptureAccess()
    }
}
