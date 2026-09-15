import AppKit
import OwlCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenu?
    private var hotkey: GlobalHotkey?
    private var settingsWindowController: SettingsWindowController?
    #if DEBUG
    private var debugServer: DebugServer?
    #endif
    let capturer = ScreenCapturer()
    private(set) var overlay: OverlayController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(capturer: capturer)
        overlay.onSessionEnd = { outcome in
            Log.overlay.info("session ended: \(String(describing: outcome))")
        }
        statusMenu = StatusMenu(onCapture: { [weak self] in self?.requestCapture() },
                                onOpenSettings: { [weak self] in self?.openSettings() })
        registerHotkey()
        NotificationCenter.default.addObserver(self, selector: #selector(hotkeyChanged),
                                               name: Settings.hotkeyChanged, object: nil)

        #if DEBUG
        do {
            let router = DebugCommandRouter(app: self)
            let server = DebugServer(path: DebugSocket.path, router: router)
            try server.start()
            debugServer = server
            Log.debug.info("debug socket listening at \(DebugSocket.path)")
        } catch {
            Log.debug.error("debug socket failed: \(String(describing: error))")
        }
        #endif

        if !Permissions.hasScreenCapture {
            Log.app.notice("Screen Recording not granted; requesting")
            Permissions.requestScreenCapture()
        }
        Log.app.info("Owl launched (pid \(getpid()))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        debugServer?.stop()
        #endif
        hotkey?.unregister()
    }

    @objc private func hotkeyChanged() { registerHotkey() }

    func registerHotkey() {
        hotkey?.unregister()
        hotkey = GlobalHotkey(keyCode: Settings.hotKeyCode, modifiers: Settings.hotKeyModifiers) { [weak self] in
            self?.requestCapture()
        }
    }

    func openSettings() {
        if settingsWindowController == nil { settingsWindowController = SettingsWindowController() }
        settingsWindowController?.show()
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
