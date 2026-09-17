import AppKit

enum Clipboard {
    /// Writes one pasteboard item carrying both PNG (browsers, Slack, Electron apps) and
    /// TIFF (older Cocoa apps such as Mail and Preview prefer it). With `alsoAsFile`, a PNG is
    /// written to the caches folder and its URL added so Finder and file-only targets accept it.
    static func write(image: CGImage, alsoAsFile: Bool = false) throws {
        let png = try PNGEncoder.data(image)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        var objects: [NSPasteboardWriting] = [item]
        if alsoAsFile {
            let dir = fileCopyDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            pruneFileCopies()
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")   // fixed format needs a fixed locale
            f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let url = dir.appendingPathComponent("Tyto \(f.string(from: Date())).png")
            try png.write(to: url, options: .atomic)
            objects.append(url as NSURL)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(objects)
    }

    /// Temp copies for "also copy as file". Inside the app container when sandboxed, so macOS can
    /// hand the receiving app a sandbox extension for the URL we put on the pasteboard.
    static var fileCopyDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Clipboard", isDirectory: true)
    }

    /// Drops copies older than `age`; recent ones must survive so a later paste still resolves.
    static func pruneFileCopies(olderThan age: TimeInterval = 24 * 3600) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: fileCopyDirectory,
                                                        includingPropertiesForKeys: [.contentModificationDateKey],
                                                        options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for url in entries {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            if let modified, modified < cutoff { try? fm.removeItem(at: url) }
        }
    }

    /// Reads the clipboard image back as PNG data (test harness).
    static func readPNG() -> Data? {
        let pb = NSPasteboard.general
        if let png = pb.data(forType: .png) { return png }
        if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }
}
