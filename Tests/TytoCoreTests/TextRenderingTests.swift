import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TytoCore

/// Text is drawn with a halo for legibility. An earlier version used a fill+stroke outline, which
/// thickened the glyphs (so committed text looked heavier than the inline editor) and closed the
/// counters of e/a/o into solid blobs. These tests pin the fixed behaviour.
@Suite struct TextRenderingTests {
    static let scale = 2.0

    static func render(_ text: String, fontSize: Double, color: RGBAColor, background: RGBAColor,
                       size: PixelSize) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(size.height))
        ctx.scaleBy(x: 1, y: -1)   // top-left origin, as in the app
        ctx.setFillColor(background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        var doc = AnnotationDocument()
        doc.add(Shape(kind: .text, start: PixelPoint(x: 10, y: 10), end: .zero,
                      style: ShapeStyle(color: color, strokeWidth: 4, fontSize: fontSize),
                      text: text, textSize: AnnotationRenderer.measureText(text, fontSize: fontSize)))
        AnnotationRenderer.draw(doc, into: ctx, base: nil, options: RenderOptions(pixelScale: scale))
        return ctx.makeImage()!
    }

    static func pixels(_ img: CGImage) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = CGContext(data: &buf, width: img.width, height: img.height, bitsPerComponent: 8,
                            bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return buf
    }

    /// The counter (enclosed hole) of a large "o" must still show the background, not a filled blob.
    @Test func letterCountersStayOpen() {
        let fontSize = 120.0
        let text = "o"
        let measured = AnnotationRenderer.measureText(text, fontSize: fontSize)
        let img = Self.render(text, fontSize: fontSize, color: .red, background: .white,
                         size: PixelSize(width: measured.width + 20, height: measured.height + 20))
        let buf = Self.pixels(img)
        // Sample the middle of the glyph, where the counter is.
        let pad = AnnotationRenderer.textPadding(fontSize: fontSize)
        let cx = 10 + Int(pad) + measured.width / 2 - Int(pad)
        let cy = 10 + Int(pad) + Int(AnnotationRenderer.lineHeight(fontSize: fontSize) * 0.55)
        let i = (cy * img.width + cx) * 4
        let (r, g, b) = (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]))
        // White background shows through: a filled counter would be dark (the old halo/stroke).
        #expect(r > 180 && g > 180 && b > 180,
                "counter of 'o' should show the background, got rgb(\(r),\(g),\(b))")
    }

    /// The halo must not thicken glyphs: inked area with and without it should be close.
    @Test func haloDoesNotThickenGlyphs() {
        let fontSize = 60.0
        let text = "age"
        let measured = AnnotationRenderer.measureText(text, fontSize: fontSize)
        let size = PixelSize(width: measured.width + 20, height: measured.height + 20)

        func inkedPixels(outlined: Bool) -> Int {
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            ctx.translateBy(x: 0, y: CGFloat(size.height)); ctx.scaleBy(x: 1, y: -1)
            ctx.setFillColor(RGBAColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            AnnotationRenderer.drawText(text, at: PixelPoint(x: 10, y: 10), fontSize: fontSize,
                                        color: .red, outlined: outlined, into: ctx)
            let buf = Self.pixels(ctx.makeImage()!)
            // Count only the red glyph fill. The halo is dark grey, so a "dark pixel" metric would
            // measure the halo instead of glyph thickness.
            var n = 0
            for p in stride(from: 0, to: buf.count, by: 4)
            where Int(buf[p]) > 150 && Int(buf[p + 1]) < 120 { n += 1 }
            return n
        }

        let plain = inkedPixels(outlined: false)
        let haloed = inkedPixels(outlined: true)
        #expect(plain > 0)
        // A stroked outline used to inflate this by far more; the halo is soft and barely adds ink.
        #expect(Double(haloed) < Double(plain) * 1.35,
                "halo inflated glyph ink from \(plain) to \(haloed)")
    }

    /// Writes a visual sheet when TYTO_TEXT_SHEET is set; not an assertion, just for eyeballing.
    @Test func visualSheet() throws {
        guard let path = ProcessInfo.processInfo.environment["TYTO_TEXT_SHEET"] else { return }
        let scale = Self.scale
        let (W, H) = (1100, 460)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W / 2, height: H))
        ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1))
        ctx.fill(CGRect(x: W / 2, y: 0, width: W / 2, height: H))
        for x in stride(from: 0, to: W, by: 20) {
            ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.58, blue: 0.66, alpha: 1))
            ctx.fill(CGRect(x: x, y: 340, width: 10, height: 120))
        }
        var doc = AnnotationDocument()
        var y = 24
        for (label, pts) in [("thin", 14.0), ("medium", 18.0), ("thick", 26.0)] {
            let fontSize = pts * scale
            let s = "\(label) — Regexp goose 0o8 age"
            for (i, color) in [RGBAColor.red, RGBAColor.white].enumerated() {
                doc.add(Shape(kind: .text, start: PixelPoint(x: i == 0 ? 16 : W / 2 + 16, y: y), end: .zero,
                              style: ShapeStyle(color: color, strokeWidth: 4, fontSize: fontSize),
                              text: s, textSize: AnnotationRenderer.measureText(s, fontSize: fontSize)))
            }
            y += Int(fontSize) + 44
        }
        let busy = "over a busy background"
        doc.add(Shape(kind: .text, start: PixelPoint(x: 16, y: 366), end: .zero,
                      style: ShapeStyle(color: .red, strokeWidth: 4, fontSize: 18 * scale),
                      text: busy, textSize: AnnotationRenderer.measureText(busy, fontSize: 18 * scale)))
        AnnotationRenderer.draw(doc, into: ctx, base: nil, options: RenderOptions(pixelScale: scale))
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                   UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        _ = CGImageDestinationFinalize(dest)
    }
}
