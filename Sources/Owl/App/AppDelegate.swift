import AppKit
import OwlCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenu?
    private var hotkey: GlobalHotkey?
    private var debugServer: DebugServer?
    let capturer = ScreenCapturer()
    private(set) var overlay: OverlayController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(capturer: capturer)
        overlay.onSessionEnd = { outcome in
            Log.overlay.info("session ended: \(String(describing: outcome))")
        }
        statusMenu = StatusMenu { [weak self] in self?.requestCapture() }
        hotkey = GlobalHotkey(keyCode: GlobalHotkey.defaultKeyCode, modifiers: GlobalHotkey.defaultModifiers) { [weak self] in
            self?.requestCapture()
        }

        if DebugServer.isEnabled {
            let router = DebugCommandRouter(app: self)
            let server = DebugServer(path: DebugSocket.path, router: router)
            do {
                try server.start()
                debugServer = server
                Log.debug.info("debug socket listening at \(DebugSocket.path)")
            } catch {
                Log.debug.error("debug socket failed: \(String(describing: error))")
            }
        }

        if !Permissions.hasScreenCapture {
            Log.app.notice("Screen Recording not granted; requesting")
            Permissions.requestScreenCapture()
        }
        Log.app.info("Owl launched (pid \(getpid()))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugServer?.stop()
        hotkey?.unregister()
    }

    /// Hotkey / menu entry point: the interactive, all-displays session.
    /// Pressing the hotkey while a session is up cancels it: Carbon hotkeys work regardless of
    /// focus, so this is the escape hatch if the overlay ever fails to become key.
    func requestCapture() {
        if overlay.isActive {
            overlay.cancel()
            return
        }
        Task {
            do {
                try await overlay.beginSession(options: .interactive)
            } catch OwlError.noScreenCapturePermission {
                Permissions.requestScreenCapture()
            } catch {
                Log.app.error("capture failed: \(String(describing: error))")
            }
        }
    }
}
