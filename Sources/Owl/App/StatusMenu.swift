import AppKit

final class StatusMenu: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let copyAsFileItem = NSMenuItem(title: "Also Copy as File", action: #selector(toggleCopyAsFile), keyEquivalent: "")
    private let recentItem = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
    private let recentMenu = NSMenu()
    private let onCapture: () -> Void
    private let onOpenSettings: () -> Void

    init(onCapture: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onOpenSettings = onOpenSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Owl")
        item.button?.toolTip = "Owl — capture a region"

        let capture = NSMenuItem(title: "Capture Region", action: #selector(captureAction), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        menu.addItem(.separator())

        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        menu.addItem(.separator())

        permissionItem.isEnabled = false
        menu.addItem(permissionItem)
        let open = NSMenuItem(title: "Open Screen Recording Settings…", action: #selector(openScreenSettings), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        copyAsFileItem.target = self
        menu.addItem(copyAsFileItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Owl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == self.menu else { return }
        permissionItem.title = Permissions.hasScreenCapture
            ? "Screen Recording: allowed"
            : "Screen Recording: not allowed (relaunch after granting)"
        copyAsFileItem.state = Settings.copyAsFile ? .on : .off
        rebuildRecentMenu()
    }

    private func rebuildRecentMenu() {
        // Thumbnails and modification dates read the files, so hold the scope for the rebuild.
        Settings.withSaveDirectoryAccess { _ in rebuildRecentMenuInScope() }
    }

    private func rebuildRecentMenuInScope() {
        recentMenu.removeAllItems()
        let recent = CaptureHistory.recent
        if recent.isEmpty {
            let empty = NSMenuItem(title: "No recent captures", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            let df = DateFormatter()
            df.dateFormat = "MMM d, HH:mm:ss"
            for url in recent.prefix(12) {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                let mi = NSMenuItem(title: df.string(from: date), action: #selector(copyRecent(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = url
                mi.image = thumbnail(for: url)
                mi.toolTip = url.lastPathComponent
                recentMenu.addItem(mi)
            }
            recentMenu.addItem(.separator())
            let reveal = NSMenuItem(title: "Open Captures Folder", action: #selector(openFolder), keyEquivalent: "")
            reveal.target = self
            recentMenu.addItem(reveal)
            let clear = NSMenuItem(title: "Clear Recent List", action: #selector(clearRecent), keyEquivalent: "")
            clear.target = self
            recentMenu.addItem(clear)
        }
    }

    private func thumbnail(for url: URL) -> NSImage? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        let h: CGFloat = 24
        let ratio = img.size.width / max(img.size.height, 1)
        let thumb = NSImage(size: CGSize(width: h * ratio, height: h))
        thumb.lockFocus()
        img.draw(in: CGRect(origin: .zero, size: thumb.size))
        thumb.unlockFocus()
        return thumb
    }

    @objc private func captureAction() { onCapture() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func openScreenSettings() { Permissions.openScreenCaptureSettings() }
    @objc private func toggleCopyAsFile() { Settings.copyAsFile.toggle() }
    @objc private func openFolder() {
        Settings.withSaveDirectoryAccess { dir in
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(dir)
        }
    }
    @objc private func clearRecent() { CaptureHistory.clear() }

    /// Re-copy a past capture to the clipboard so it can be pasted again.
    @objc private func copyRecent(_ sender: NSMenuItem) {
        Settings.withSaveDirectoryAccess { _ in copyRecentInScope(sender) }
    }

    private func copyRecentInScope(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let img = NSImage(contentsOf: url),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return }
        try? Clipboard.write(image: cg, alsoAsFile: Settings.copyAsFile)
    }
}
