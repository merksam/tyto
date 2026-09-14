import AppKit
import Carbon.HIToolbox
import SwiftUI

enum HotkeyFormat {
    /// Carbon modifier mask -> symbol string (⌃⌥⇧⌘ order).
    static func modifierSymbols(_ carbonMods: UInt32) -> String {
        var out = ""
        if carbonMods & UInt32(controlKey) != 0 { out += "⌃" }
        if carbonMods & UInt32(optionKey) != 0 { out += "⌥" }
        if carbonMods & UInt32(shiftKey) != 0 { out += "⇧" }
        if carbonMods & UInt32(cmdKey) != 0 { out += "⌘" }
        return out
    }

    /// NSEvent modifier flags -> Carbon modifier mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func keyName(code: UInt32, fallback: String) -> String {
        let named: [Int: String] = [
            kVK_Return: "⏎", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
            kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        if let n = named[Int(code)] { return n }
        return fallback.uppercased()
    }
}

/// A control that records a global-hotkey combo. Click to arm, then press the combo.
final class HotkeyRecorderView: NSView {
    var onRecorded: ((_ code: UInt32, _ mods: UInt32, _ display: String) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var recording = false { didSet { refresh() } }
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 26) }
    override var acceptsFirstResponder: Bool { true }

    func refresh() {
        label.stringValue = recording ? "Press shortcut…" : Settings.hotKeyDisplay
        layer?.backgroundColor = (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                                             : NSColor.controlBackgroundColor).cgColor
        layer?.borderColor = (recording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        recording.toggle()
        if recording { startMonitor() } else { stopMonitor() }
    }

    private func startMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt32(kVK_Escape) { recording = false; stopMonitor(); return }
        let mods = HotkeyFormat.carbonModifiers(from: event.modifierFlags)
        guard mods != 0 else { NSSound.beep(); return }  // require a modifier
        let code = UInt32(event.keyCode)
        let display = HotkeyFormat.modifierSymbols(mods)
            + HotkeyFormat.keyName(code: code, fallback: event.charactersIgnoringModifiers ?? "?")
        recording = false
        stopMonitor()
        onRecorded?(code, mods, display)
        refresh()
    }
}

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var display: String

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let v = HotkeyRecorderView()
        v.onRecorded = { code, mods, display in
            Settings.hotKeyCode = code
            Settings.hotKeyModifiers = mods
            Settings.hotKeyDisplay = display
            self.display = display
            NotificationCenter.default.post(name: Settings.hotkeyChanged, object: nil)
        }
        return v
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        nsView.refresh()
    }
}
