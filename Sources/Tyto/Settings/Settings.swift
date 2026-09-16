import AppKit
import Carbon.HIToolbox
import TytoCore
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
        get { d.string(forKey: "defaultTool").flatMap(Tool.init(rawValue:)) ?? .arrow }
        set { d.set(newValue.rawValue, forKey: "defaultTool") }
    }

    static var defaultColor: RGBAColor {
        get { d.string(forKey: "defaultColor").flatMap(RGBAColor.named) ?? .red }
        set { d.set(newValue.name ?? "red", forKey: "defaultColor") }
    }

    static var defaultWidth: WidthPreset {
        get { d.string(forKey: "defaultWidth").flatMap(WidthPreset.init(rawValue:)) ?? .thin }
        set { d.set(newValue.rawValue, forKey: "defaultWidth") }
    }

    // MARK: Capture history

    /// When on, every copy or save also writes a PNG to the save folder and adds it to Recent Captures.
    static var autoSaveRecent: Bool {
        get { d.object(forKey: "autoSaveRecent") == nil ? true : d.bool(forKey: "autoSaveRecent") }
        set { d.set(newValue, forKey: "autoSaveRecent") }
    }

    /// Security-scoped bookmark of a user-chosen folder. A sandboxed app cannot keep access to a
    /// folder across launches from a plain path, so the bookmark is the stored form.
    private static let bookmarkKey = "saveDirectoryBookmark"

    /// Always reachable: the container's Pictures symlink plus the pictures entitlement cover it.
    static var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tyto", isDirectory: true)
    }

    /// The folder captures go to. Resolving a bookmark needs no access; wrap actual file work in
    /// `withSaveDirectoryAccess`.
    static var saveDirectory: URL { resolvedCustomDirectory()?.url ?? defaultSaveDirectory }

    static var hasCustomSaveDirectory: Bool { d.data(forKey: bookmarkKey) != nil }

    /// For display and JSON: the container's Pictures symlink resolved to its real path.
    static var saveDirectoryDisplayPath: String { saveDirectory.resolvingSymlinksInPath().path }

    /// Passing nil reverts to the default folder. Throws if the app cannot reach `url` (which is
    /// the sandbox working as intended: only an open-panel result, ~/Pictures or the container
    /// can be bookmarked).
    static func setSaveDirectory(_ url: URL?) throws {
        guard let url else { d.removeObject(forKey: bookmarkKey); return }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        d.set(data, forKey: bookmarkKey)
    }

    /// Brackets `body` with the security scope of the custom folder. The default folder is covered
    /// by the pictures entitlement and needs no scope.
    @discardableResult
    static func withSaveDirectoryAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        guard let resolved = resolvedCustomDirectory() else { return try body(defaultSaveDirectory) }
        let granted = resolved.url.startAccessingSecurityScopedResource()
        if !granted { Log.app.error("save folder: security scope not granted for \(resolved.url.path)") }
        defer { if granted { resolved.url.stopAccessingSecurityScopedResource() } }
        if resolved.stale, let fresh = try? resolved.url.bookmarkData(options: .withSecurityScope,
                                                                     includingResourceValuesForKeys: nil, relativeTo: nil) {
            d.set(fresh, forKey: bookmarkKey)  // refresh while access is held
        }
        return try body(resolved.url)
    }

    /// Resolves a fresh URL each call so start/stop access always pair on the same object.
    private static func resolvedCustomDirectory() -> (url: URL, stale: Bool)? {
        guard let data = d.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                              bookmarkDataIsStale: &stale)
            return (url, stale)
        } catch {
            // Keep the bookmark: an unmounted volume is transient, and the user can re-choose.
            Log.app.error("save folder bookmark unusable, using default: \(String(describing: error))")
            return nil
        }
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
    static let hotkeyChanged = Notification.Name("TytoHotkeyChanged")
}
