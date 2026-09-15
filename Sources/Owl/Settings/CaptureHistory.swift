import AppKit
import OwlCore

/// Auto-saves finished captures to the save folder and keeps a recent list for the menu.
enum CaptureHistory {
    private static let key = "recentCaptures"
    private static let limit = 24

    /// Writes `image` to the save folder if auto-save is on, and records it. Returns the file URL.
    @discardableResult
    static func record(_ image: CGImage) -> URL? {
        guard Settings.autoSaveRecent else { return nil }
        // Directory creation, the uniqueness probes and the write all need the security scope.
        return Settings.withSaveDirectoryAccess { dir -> URL? in
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = Self.uniqueURL(in: dir, name: OverlayController.timestampedName())
                try PNGEncoder.write(image, to: url)
                prepend(url)
                Log.app.info("auto-saved capture to \(url.lastPathComponent)")
                return url
            } catch {
                Log.app.error("auto-save failed: \(String(describing: error))")
                return nil
            }
        }
    }

    /// Most-recent-first, filtered to files that still exist on disk.
    static var recent: [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        // fileExists returns false for paths the sandbox cannot reach, so probe inside the scope.
        return Settings.withSaveDirectoryAccess { _ in
            paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    /// Records an already-written file (e.g. a Cmd+S save) in the recent list without copying it.
    static func note(_ url: URL) {
        prepend(url)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Avoids overwriting when two captures land in the same second.
    static func uniqueURL(in dir: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    private static func prepend(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > limit { paths = Array(paths.prefix(limit)) }
        UserDefaults.standard.set(paths, forKey: key)
    }
}
