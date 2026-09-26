import AppKit
import TytoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let hasLaunchedBeforeKey = "hasLaunchedBefore"
    private var statusMenu: StatusMenu?
    private var hotkey: GlobalHotkey?
    private var settingsWindowController: SettingsWindowController?
    private var welcomeWindowController: WelcomeWindowController?
    #if DEBUG
    private var debugServer: DebugServer?
    #endif
    let capturer = ScreenCapturer()
    private(set) var overlay: OverlayController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(capturer: capturer)
        overlay.onSessionEnd = { [weak self] outcome in
            Log.overlay.info("session ended: \(String(describing: outcome))")
            // A finished capture is the real end of onboarding: the permission is granted and
            // the user has found the shortcut. Nothing left to explain.
            switch outcome {
            case .copied, .saved:
                self?.markOnboarded()
            case .cancelled:
                // The overlay takes the welcome window off screen with it. If onboarding is
                // not over, a cancelled first attempt should land back where the user was.
                if let self, !UserDefaults.standard.bool(forKey: Self.hasLaunchedBeforeKey),
                   self.welcomeWindowController != nil {
                    self.openWelcome()
                }
            }
        }
        statusMenu = StatusMenu(onCapture: { [weak self] in self?.requestCapture() },
                                onOpenSettings: { [weak self] in self?.openSettings() })
        registerHotkey()
        NotificationCenter.default.addObserver(self, selector: #selector(hotkeyChanged),
                                               name: Settings.hotkeyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenCaptureGranted),
                                               name: Permissions.screenCaptureGranted, object: nil)

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

        // Onboarding, until the first finished capture. `hasLaunchedBefore` is set by
        // markOnboarded(), not here: someone who quits during the permission prompt should
        // see this again next time, not be left with an app that silently does nothing.
        if !UserDefaults.standard.bool(forKey: Self.hasLaunchedBeforeKey) {
            let granted = Permissions.hasScreenCapture
            if !granted {
                // Also what App Review sees first: a real window, with the permission prompt
                // landing over it rather than over nothing.
                openWelcome()
            }
            // The status item's button has no window yet at this point, and NSPopover.show does
            // nothing at all when anchored to a view that is not on screen. Wait a beat.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showHint(granted
                    ? "Tyto is ready. Press \(Settings.hotKeyDisplay) to take a screenshot."
                    : "Tyto lives here.")
            }
        }
        Clipboard.pruneFileCopies()
        Log.app.info("Tyto launched (pid \(getpid()))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        debugServer?.stop()
        #endif
        hotkey?.unregister()
    }

    @objc private func hotkeyChanged() { registerHotkey() }

    /// The grant landed while running. Say so at the icon; the welcome window, if up, already
    /// shows Allowed and stays until the first capture or Done.
    @objc private func screenCaptureGranted() {
        showHint("Tyto is ready. Press \(Settings.hotKeyDisplay) to take a screenshot.")
    }

    func registerHotkey() {
        hotkey?.unregister()
        hotkey = GlobalHotkey(keyCode: Settings.hotKeyCode, modifiers: Settings.hotKeyModifiers) { [weak self] in
            self?.requestCapture()
        }
    }

    var isSettingsWindowVisible: Bool { settingsWindowController?.isVisible ?? false }

    func openSettings() {
        if settingsWindowController == nil { settingsWindowController = SettingsWindowController() }
        settingsWindowController?.show()
    }

    var isWelcomeWindowVisible: Bool { welcomeWindowController?.isVisible ?? false }

    func openWelcome() {
        if welcomeWindowController == nil { welcomeWindowController = WelcomeWindowController() }
        welcomeWindowController?.show(openSettings: { [weak self] in self?.openSettings() })
    }

    func showHint(_ text: String) { statusMenu?.showHint(text) }

    /// Onboarding is over: remember it and take the welcome window down if it is still up.
    func markOnboarded() {
        UserDefaults.standard.set(true, forKey: Self.hasLaunchedBeforeKey)
        welcomeWindowController?.close()
    }

    /// Hotkey / menu entry point: the interactive, all-displays session.
    /// Pressing the hotkey while a session is up cancels it: Carbon hotkeys work regardless of
    /// focus, so this is the escape hatch if the overlay ever fails to become key.
    func requestCapture() {
        statusMenu?.closeHint()
        if overlay.isActive {
            overlay.cancel()
            return
        }
        Task {
            do {
                try await overlay.beginSession(options: .interactive)
            } catch TytoError.noScreenCapturePermission {
                Permissions.requestScreenCapture()
            } catch {
                Log.app.error("capture failed: \(String(describing: error))")
            }
        }
    }
}
