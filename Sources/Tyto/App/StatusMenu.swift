import AppKit

final class StatusMenu: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let copyAsFileItem = NSMenuItem(title: "Also Copy as File", action: #selector(toggleCopyAsFile), keyEquivalent: "")
    private let recentItem = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
    private let recentMenu = NSMenu()
    private let onCapture: () -> Void
    private let onCaptureOverMenu: () -> Void
    private let onOpenSettings: () -> Void
    private var hintPopover: NSPopover?

    /// Told when the menu opens (true) and closes (false).
    var onOpenChange: ((Bool) -> Void)?

    /// A short note anchored to the status item itself, so the arrow points at the real owl
    /// wherever the menu bar has put it. Goes away on its own or on a click elsewhere.
    func showHint(_ text: String, for seconds: TimeInterval = 8) {
        guard let button = item.button else { return }
        hintPopover?.performClose(nil)
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        // Size to the text: one short line gets one short line, not a 64pt box around it.
        let maxTextWidth: CGFloat = 232
        let fit = label.sizeThatFits(NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude))
        let textWidth = min(maxTextWidth, ceil(fit.width))
        label.frame = NSRect(x: 14, y: 10, width: textWidth, height: ceil(fit.height))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: textWidth + 28, height: ceil(fit.height) + 20))
        container.addSubview(label)
        // A click on the note itself dismisses it; the status item and the hotkey do too.
        container.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(closeHint)))
        let vc = NSViewController()
        vc.view = container
        let popover = NSPopover()
        // Not .transient: that closes the moment the app is not active, and an accessory app
        // never is. Clicks and the timer below take it down instead.
        popover.behavior = .applicationDefined
        popover.contentViewController = vc
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hintPopover = popover
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self, weak popover] in
            guard let popover, self?.hintPopover === popover else { return }
            popover.performClose(nil)
        }
    }

    @objc func closeHint() {
        hintPopover?.performClose(nil)
        hintPopover = nil
    }

    // MARK: Open state

    /// True while the status menu is tracking, i.e. open on screen.
    private(set) var isOpen = false
    private var closedAt: TimeInterval?

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == self.menu, !isOpen else { return }
        isOpen = true
        closeHint()
        onOpenChange?(true)
        startWatchingChord()
        Log.app.info("status menu opened")
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu == self.menu else { return }
        noteClosed()
    }

    /// Takes the menu down at once, without the fade.
    func dismiss() {
        menu.cancelTrackingWithoutAnimation()
        noteClosed()
    }

    private func noteClosed() {
        guard isOpen else { return }
        isOpen = false
        closedAt = ProcessInfo.processInfo.systemUptime
        stopWatchingChord()
        onOpenChange?(false)
        Log.app.info("status menu closed")
    }

    /// Seconds a capture should still wait for the menu's windows to leave the screen. Choosing
    /// an item fires its action while the menu is fading out, and a frame captured in that
    /// moment has the half-faded menu in it.
    var settleDelay: TimeInterval {
        guard let closedAt else { return 0 }
        return max(0, 0.25 - (ProcessInfo.processInfo.systemUptime - closedAt))
    }

    // MARK: The hotkey while the menu is open

    /// An open menu takes every key press for itself, and the window server would turn the
    /// hotkey chord into a hotkey event the menu never sees, queued until the menu closes. So
    /// while the menu is up the hotkey is not registered (see onOpenChange) and the keys are
    /// read directly instead, on a timer in the common run loop modes, which the tracking
    /// menu's run loop mode is one of. The capture then has the menu in the frame.
    private var chordTimer: Timer?
    private var chordWasDown = false

    private func startWatchingChord() {
        chordWasDown = chordIsDown()
        let timer = Timer(timeInterval: 0.025, target: self, selector: #selector(pollChord), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        chordTimer = timer
    }

    private func stopWatchingChord() {
        chordTimer?.invalidate()
        chordTimer = nil
    }

    @objc private func pollChord() {
        let down = chordIsDown()
        defer { chordWasDown = down }
        if down, !chordWasDown { onCaptureOverMenu() }
    }

    private func chordIsDown() -> Bool {
        HotkeyFormat.carbonModifiers(from: NSEvent.modifierFlags) == Settings.hotKeyModifiers
            && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(Settings.hotKeyCode))
    }

    init(onCapture: @escaping () -> Void, onCaptureOverMenu: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onCaptureOverMenu = onCaptureOverMenu
        self.onOpenSettings = onOpenSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let owl = OwlGlyph.image()
        owl.accessibilityDescription = "Tyto"
        item.button?.image = owl
        item.button?.toolTip = "Tyto — capture a region"

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

        menu.addItem(NSMenuItem(title: "Quit Tyto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == self.menu else { return }
        permissionItem.title = Permissions.hasScreenCapture
            ? "Screen Recording: allowed"
            : "Screen Recording: not allowed"
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

    /// Fits the capture inside a 72×24 box, keeping its aspect. Scaling to a fixed height alone
    /// let a wide strip, a whole toolbar say, turn into a thumbnail several times wider than
    /// the menu, which then stretched to match.
    private func thumbnail(for url: URL) -> NSImage? {
        guard let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else { return nil }
        let box = CGSize(width: 72, height: 24)
        let scale = min(box.width / img.size.width, box.height / img.size.height)
        let size = CGSize(width: max(1, (img.size.width * scale).rounded()),
                          height: max(1, (img.size.height * scale).rounded()))
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        img.draw(in: CGRect(origin: .zero, size: size))
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
