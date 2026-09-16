import AppKit
import CoreGraphics

enum Permissions {
    /// True once the user has granted Screen Recording to this bundle (and the app was relaunched).
    static var hasScreenCapture: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (once) and returns whether access is already granted.
    @discardableResult
    static func requestScreenCapture() -> Bool { CGRequestScreenCaptureAccess() }

    static func openScreenCaptureSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
