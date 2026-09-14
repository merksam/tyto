import AppKit

final class StatusMenu: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let onCapture: () -> Void

    init(onCapture: @escaping () -> Void) {
        self.onCapture = onCapture
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Owl")
        item.button?.toolTip = "Owl — ⌘⇧9 to capture"

        let capture = NSMenuItem(title: "Capture Region", action: #selector(captureAction), keyEquivalent: "9")
        capture.keyEquivalentModifierMask = [.command, .shift]
        capture.target = self
        menu.addItem(capture)
        menu.addItem(.separator())

        permissionItem.isEnabled = false
        menu.addItem(permissionItem)
        let open = NSMenuItem(title: "Open Screen Recording Settings…", action: #selector(openSettings), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Owl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissionItem.title = Permissions.hasScreenCapture
            ? "Screen Recording: allowed"
            : "Screen Recording: not allowed (relaunch after granting)"
    }

    @objc private func captureAction() { onCapture() }
    @objc private func openSettings() { Permissions.openScreenCaptureSettings() }
}
