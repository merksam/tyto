import AppKit
import TytoCore
import UniformTypeIdentifiers

/// `~/Library/Application Scripts/com.yevhenii.tyto`, the one folder NSUserUnixTask runs
/// scripts from. The sandbox lets Tyto read it but not write it: scripts get there by hand, or
/// through a save panel the user confirms.
enum ScriptsFolder {
    static var url: URL? {
        try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: false)
    }

    /// Regular, visible files: anything the user put there may be a script.
    static func scriptNames() -> [String] {
        guard let url, let entries = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    static func scriptURL(_ name: String) -> URL? { url?.appendingPathComponent(name) }

    /// The stored list with any newly dropped-in scripts added, saved if that changed it.
    @discardableResult
    static func adoptNewScripts() -> DestinationList {
        var list = Settings.destinationList
        if list.adoptScripts(scriptNames()) { Settings.destinationList = list }
        return list
    }

    static func reveal() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    enum InstallError: Error, CustomStringConvertible {
        case unavailable
        case outsideFolder(String)
        case notExecutable(String)

        var description: String {
            switch self {
            case .unavailable: "The scripts folder is not available."
            case .outsideFolder(let folder): "Tyto can only run scripts from its scripts folder, \(folder). Save it there."
            case .notExecutable(let name): "Saved \(name), but could not make it executable. Run chmod +x on it in the scripts folder."
            }
        }
    }

    /// Asks where to save `script`, opening on the scripts folder. Returns the file name, or
    /// nil if the user cancelled. Writing here is only possible because the user clicked Save.
    static func install(_ script: String, suggestedName: String) throws -> String? {
        guard let folder = url else { throw InstallError.unavailable }
        let panel = NSSavePanel()
        panel.directoryURL = folder
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.shellScript]
        panel.canCreateDirectories = false
        panel.title = "Save Destination Script"
        panel.message = "Tyto runs destination scripts from this folder."
        panel.prompt = "Save Script"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let target = panel.url else { return nil }
        guard target.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
                == folder.resolvingSymlinksInPath().standardizedFileURL else {
            throw InstallError.outsideFolder(folder.path)
        }
        // Not atomic: an atomic write goes through a temporary file next to the target, and
        // the panel's grant covers the chosen path only.
        try Data(script.utf8).write(to: target)
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        } catch {
            throw InstallError.notExecutable(target.lastPathComponent)
        }
        Log.app.info("installed destination script \(target.lastPathComponent)")
        return target.lastPathComponent
    }
}
