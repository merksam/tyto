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
            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Owl", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let url = dir.appendingPathComponent("Owl \(f.string(from: Date())).png")
            try png.write(to: url, options: .atomic)
            objects.append(url as NSURL)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(objects)
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
