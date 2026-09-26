import AppKit
import SwiftUI

/// First-launch window. Three things and then it never appears again: where the app lives,
/// the one permission everything depends on, and the shortcut. It exists because a menu bar
/// app with no window gives a new user nothing to look at, and because the Screen Recording
/// grant is invisible to `CGPreflightScreenCaptureAccess` until a relaunch: this window polls
/// ScreenCaptureKit instead, so the grant is noticed the moment it lands.
@MainActor final class WelcomeWindowController {
    private var window: NSWindow?
    private let model = WelcomeModel()

    var isVisible: Bool { window?.isVisible ?? false }

    func show(openSettings: @escaping () -> Void) {
        if window == nil {
            let view = WelcomeView(model: model, openSettings: openSettings, done: { [weak self] in self?.close() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Welcome to Tyto"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        model.refresh()
        model.startWatching()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        model.stopWatching()
        window?.orderOut(nil)
    }
}

@MainActor final class WelcomeModel: ObservableObject {
    @Published var granted = Permissions.hasScreenCapture
    @Published var hotkey = Settings.hotKeyDisplay
    @Published var launchAtLogin = Settings.launchAtLogin { didSet { Settings.launchAtLogin = launchAtLogin } }
    private var poll: Task<Void, Never>?

    func refresh() {
        granted = Permissions.hasScreenCapture
        hotkey = Settings.hotKeyDisplay
    }

    /// While the window is up and the grant is missing, ask ScreenCaptureKit once a second
    /// whether it has landed. The user toggles the switch in System Settings and comes back to
    /// a window that already says Allowed, with no relaunch anywhere in the story.
    func startWatching() {
        guard poll == nil, !granted else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                if await Permissions.probeScreenCapture() {
                    self?.granted = true
                    self?.poll = nil
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopWatching() {
        poll?.cancel()
        poll = nil
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    let openSettings: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Tyto").font(.title2.weight(.semibold))
                    Text("Three things, then it stays out of your way.").foregroundStyle(.secondary)
                }
            }

            WelcomeStep(number: 1, title: "It lives in the menu bar",
                        detail: "Look for the owl at the top right of the screen. There is no Dock icon and no main window.") {
                EmptyView()
            }

            WelcomeStep(number: 2, title: "Allow Screen Recording",
                        detail: model.granted
                            ? "macOS asks every screenshot app for this, once."
                            : "macOS asks every screenshot app for this, once. Grant it in System Settings and come back; this window notices on its own.") {
                HStack(spacing: 10) {
                    if model.granted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") { Permissions.openScreenCaptureSettings() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }

            WelcomeStep(number: 3, title: "Take a screenshot",
                        detail: "Press \(model.hotkey). The screen freezes at once; drag a region, mark it up, press Return, and it is on your clipboard.") {
                HStack(spacing: 14) {
                    Button("Change Shortcut…") { openSettings() }
                    Toggle("Launch Tyto at login", isOn: $model.launchAtLogin)
                }
            }

            HStack {
                Spacer()
                Button(model.granted ? "Done" : "Later") { done() }
            }
        }
        .padding(24)
        .frame(width: 500)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

private struct WelcomeStep<Content: View>: View {
    let number: Int
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                content()
            }
        }
    }
}
