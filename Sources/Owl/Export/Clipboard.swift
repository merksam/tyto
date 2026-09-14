import AppKit

enum Clipboard {
    /// Writes one pasteboard item carrying both PNG (browsers, Slack, Electron apps) and
    /// TIFF (older Cocoa apps such as Mail and Preview prefer it).
    static func write(image: CGImage) throws {
        let png = try PNGEncoder.data(image)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
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
