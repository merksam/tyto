import AppKit
import Carbon.HIToolbox
import OwlCore
import ServiceManagement

/// Persistent user settings. Colours/tools/widths are stored by their stable string identifiers.
enum Settings {
    private static let d = UserDefaults.standard

    // MARK: Clipboard

    static var copyAsFile: Bool {
        get { d.bool(forKey: "copyAsFile") }
        set { d.set(newValue, forKey: "copyAsFile") }
    }

    // MARK: Drawing defaults (applied at the start of every capture)

    static var defaultTool: Tool {
        get { d.string(forKey: "defaultTool").flatMap(Tool.init(rawValue:)) ?? .rect }
        set { d.set(newValue.rawValue, forKey: "defaultTool") }
    }

    static var defaultColor: RGBAColor {
        get { d.string(forKey: "defaultColor").flatMap(RGBAColor.named) ?? .red }
        set { d.set(newValue.name ?? "red", forKey: "defaultColor") }
    }

    static var defaultWidth: WidthPreset {
        get { d.string(forKey: "defaultWidth").flatMap(WidthPreset.init(rawValue:)) ?? .medium }
        set { d.set(newValue.rawValue, forKey: "defaultWidth") }
    }

    // MARK: Capture history

    /// When on, every copy or save also writes a PNG to the save folder and adds it to Recent Captures.
    static var autoSaveRecent: Bool {
        get { d.object(forKey: "autoSaveRecent") == nil ? true : d.bool(forKey: "autoSaveRecent") }
        set { d.set(newValue, forKey: "autoSaveRecent") }
    }

    static var saveDirectory: URL {
        get {
            if let path = d.string(forKey: "saveDirectory"), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Owl", isDirectory: true)
        }
        set { d.set(newValue.path, forKey: "saveDirectory") }
    }

    // MARK: Global hotkey (Carbon key code + Carbon modifier mask)

    static var hotKeyCode: UInt32 {
        get { d.object(forKey: "hotKeyCode") == nil ? UInt32(kVK_ANSI_9) : UInt32(d.integer(forKey: "hotKeyCode")) }
        set { d.set(Int(newValue), forKey: "hotKeyCode") }
    }

    static var hotKeyModifiers: UInt32 {
        get { d.object(forKey: "hotKeyModifiers") == nil ? UInt32(cmdKey | shiftKey) : UInt32(d.integer(forKey: "hotKeyModifiers")) }
        set { d.set(Int(newValue), forKey: "hotKeyModifiers") }
    }

    static var hotKeyDisplay: String {
        get { d.string(forKey: "hotKeyDisplay") ?? "⇧⌘9" }
        set { d.set(newValue, forKey: "hotKeyDisplay") }
    }

    // MARK: Launch at login (backed by the system service, not UserDefaults)

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.app.error("launch-at-login toggle failed: \(String(describing: error))")
            }
        }
    }

    /// Posted whenever the hotkey changes so the app re-registers it.
    static let hotkeyChanged = Notification.Name("OwlHotkeyChanged")
}
