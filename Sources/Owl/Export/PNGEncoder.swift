import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PNGEncoder {
    static func data(_ image: CGImage) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            throw OwlError.encodeFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw OwlError.encodeFailed }
        return out as Data
    }

    static func write(_ image: CGImage, to url: URL) throws {
        try data(image).write(to: url, options: .atomic)
    }

    static func size(ofPNG data: Data) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
}
