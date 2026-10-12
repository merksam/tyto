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

    /// Carbon modifier mask -> NSEvent modifier flags, for a menu item's key equivalent.
    static func modifierFlags(from carbonMods: UInt32) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if carbonMods & UInt32(cmdKey) != 0 { f.insert(.command) }
        if carbonMods & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if carbonMods & UInt32(optionKey) != 0 { f.insert(.option) }
        if carbonMods & UInt32(controlKey) != 0 { f.insert(.control) }
        return f
    }

    static func keyName(code: UInt32, fallback: String) -> String {
        let named: [Int: String] = [
            kVK_Return: "⏎", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
            kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let n = named[Int(code)] { return n }
        return fallback.uppercased()
    }

    /// What the key types on the current layout with nothing else held, in the form a menu item
    /// key equivalent takes: the plain character ("9", not "("), or AppKit's code for a key that
    /// types none, arrows and function keys. Nil when the layout has nothing for the key.
    static func keyEquivalent(for code: UInt32) -> String? {
        if let f = functionKeys[Int(code)] { return f }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { buf -> OSStatus in
            guard let base = buf.baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(base.assumingMemoryBound(to: UCKeyboardLayout.self), UInt16(code),
                                  UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length == 1, let scalar = Unicode.Scalar(chars[0]),
              !CharacterSet.controlCharacters.contains(scalar), !CharacterSet.whitespaces.contains(scalar)
        else { return nil }
        return String(Character(scalar)).lowercased()
    }

    private static let functionKeys: [Int: String] = {
        func key(_ code: Int) -> String { String(Character(Unicode.Scalar(UInt32(code))!)) }
        return [
            kVK_Return: "\r", kVK_Tab: "\t", kVK_Space: " ", kVK_Delete: "\u{8}", kVK_Escape: "\u{1B}",
            kVK_ForwardDelete: key(NSDeleteFunctionKey), kVK_Home: key(NSHomeFunctionKey), kVK_End: key(NSEndFunctionKey),
            kVK_PageUp: key(NSPageUpFunctionKey), kVK_PageDown: key(NSPageDownFunctionKey),
            kVK_LeftArrow: key(NSLeftArrowFunctionKey), kVK_RightArrow: key(NSRightArrowFunctionKey),
            kVK_UpArrow: key(NSUpArrowFunctionKey), kVK_DownArrow: key(NSDownArrowFunctionKey),
            kVK_F1: key(NSF1FunctionKey), kVK_F2: key(NSF2FunctionKey), kVK_F3: key(NSF3FunctionKey),
            kVK_F4: key(NSF4FunctionKey), kVK_F5: key(NSF5FunctionKey), kVK_F6: key(NSF6FunctionKey),
            kVK_F7: key(NSF7FunctionKey), kVK_F8: key(NSF8FunctionKey), kVK_F9: key(NSF9FunctionKey),
            kVK_F10: key(NSF10FunctionKey), kVK_F11: key(NSF11FunctionKey), kVK_F12: key(NSF12FunctionKey),
        ]
    }()
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
        // The plain key, so ⇧⌘9 reads "⇧⌘9" and not "⇧⌘(".
        let plain = HotkeyFormat.keyEquivalent(for: code) ?? event.charactersIgnoringModifiers ?? "?"
        let display = HotkeyFormat.modifierSymbols(mods) + HotkeyFormat.keyName(code: code, fallback: plain)
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
