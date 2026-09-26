import AppKit
import CoreGraphics
import ScreenCaptureKit

enum Permissions {
    /// Posted once when `probeScreenCapture()` first succeeds in this process.
    static let screenCaptureGranted = Notification.Name("tyto.screenCaptureGranted")

    /// Set when ScreenCaptureKit answered a content query in this process, which it only does
    /// with the grant in place. `CGPreflightScreenCaptureAccess` is fixed at process start, so
    /// without this a grant made while the app is running would be invisible to it until a
    /// relaunch, and `OverlayController.beginSession` would keep refusing on our own check.
    private(set) static var grantedDuringThisRun = false

    /// True once the user has granted Screen Recording to this bundle: either it was already
    /// there at launch, or it landed while running and the probe has seen it.
    static var hasScreenCapture: Bool { CGPreflightScreenCaptureAccess() || grantedDuringThisRun }

    /// Asks ScreenCaptureKit for the shareable content. That call is refused without the grant
    /// and re-checked by the system on every request, so it is the live truth. Cheap enough to
    /// poll once a second while the welcome window is up; not used on the capture path itself.
    static func probeScreenCapture() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            return false
        }
        if !grantedDuringThisRun {
            grantedDuringThisRun = true
            NotificationCenter.default.post(name: screenCaptureGranted, object: nil)
        }
        return true
    }

    /// Shows the system prompt (once) and returns whether access is already granted.
    @discardableResult
    static func requestScreenCapture() -> Bool { CGRequestScreenCaptureAccess() }

    static func openScreenCaptureSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
