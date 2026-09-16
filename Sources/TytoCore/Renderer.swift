import CoreGraphics
import CoreText
import Foundation

public struct RenderOptions: Sendable {
    /// Display backing scale; sizes system-ish details (blur block size, selection chrome).
    public var pixelScale: Double
    public var selectedID: UUID?
    public var drawSelectionChrome: Bool

    public init(pixelScale: Double, selectedID: UUID? = nil, drawSelectionChrome: Bool = false) {
        self.pixelScale = pixelScale
        self.selectedID = selectedID
        self.drawSelectionChrome = drawSelectionChrome
    }
}

/// The one renderer used for both the live overlay and the exported image.
/// Contract: `ctx` is a *flipped* context (origin top-left, y down) whose user space is display
/// pixels, i.e. the same space shapes are stored in. Callers translate/scale before calling.
public enum AnnotationRenderer {
    // MARK: Entry points

    public static func draw(_ doc: AnnotationDocument, into ctx: CGContext, base: CGImage?, options: RenderOptions) {
        for shape in doc.renderOrder {
            draw(shape, into: ctx, base: base, options: options)
        }
        if options.drawSelectionChrome, let id = options.selectedID, let s = doc.shape(id: id) {
            drawSelectionChrome(for: s, into: ctx, scale: options.pixelScale)
        }
    }

    /// Composites `crop` of `base` with the annotations into a new image at native pixel scale.
    public static func export(_ doc: AnnotationDocument, base: CGImage, crop: PixelRect, pixelScale: Double) -> CGImage? {
        guard !crop.isEmpty, let cropped = base.cropping(to: crop.cgRect) else { return nil }
        let space = base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        // Flip to a top-left origin so the context matches the shape coordinate space.
        ctx.translateBy(x: 0, y: CGFloat(crop.height))
        ctx.scaleBy(x: 1, y: -1)
        drawImage(cropped, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height), ctx)
        ctx.translateBy(x: CGFloat(-crop.x), y: CGFloat(-crop.y))
        draw(doc, into: ctx, base: base, options: RenderOptions(pixelScale: pixelScale))
        return ctx.makeImage()
    }

    // MARK: Text metrics

    public static func font(size: Double) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, CGFloat(size), nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(size), nil)
    }

    public static func lineHeight(fontSize: Double) -> Double {
        let f = font(size: fontSize)
        return ceil(CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f))
    }

    public static func measureText(_ text: String, fontSize: Double) -> PixelSize {
        let f = font(size: fontSize)
        let lh = lineHeight(fontSize: fontSize)
        let lines = text.components(separatedBy: "\n")
        var maxWidth = 0.0
        for line in lines {
            let attributed = NSAttributedString(string: line.isEmpty ? " " : line,
                                                attributes: [.init(kCTFontAttributeName as String): f])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            maxWidth = max(maxWidth, CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        }
        // Leave room for the outline stroke.
        let pad = ceil(fontSize * 0.08)
        return PixelSize(width: Int(ceil(maxWidth + 2 * pad)), height: Int(lh * Double(lines.count) + 2 * pad))
    }

    // MARK: Shapes

    static func draw(_ s: Shape, into ctx: CGContext, base: CGImage?, options: RenderOptions) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let color = s.style.color.cgColor
        let w = CGFloat(s.style.strokeWidth)
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)

        switch s.kind {
        case .rect:
            ctx.stroke(s.bounds.cgRect)
        case .ellipse:
            ctx.strokeEllipse(in: s.bounds.cgRect)
        case .line:
            ctx.move(to: s.start.cgPoint)
            ctx.addLine(to: s.end.cgPoint)
            ctx.strokePath()
        case .arrow:
            drawArrow(s, into: ctx)
        case .blur:
            if let base {
                let block = max(4, Int((8 * options.pixelScale).rounded()))
                drawPixelated(base, rect: s.bounds, block: block, ctx)
            }
        case .badge:
            drawBadge(s, into: ctx, scale: options.pixelScale)
        case .text:
            drawText(s.text, at: s.start, fontSize: s.style.fontSize, color: s.style.color,
                     outlined: true, into: ctx)
        }
    }

    static func drawArrow(_ s: Shape, into ctx: CGContext) {
        let a = s.start.cgPoint, b = s.end.cgPoint
        let dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0.5 else { return }
        let w = CGFloat(s.style.strokeWidth)
        let angle = atan2(dy, dx)
        let headLen = min(len, w * 3.5 + 6)
        let half = CGFloat.pi / 7
        let p1 = CGPoint(x: b.x - headLen * cos(angle - half), y: b.y - headLen * sin(angle - half))
        let p2 = CGPoint(x: b.x - headLen * cos(angle + half), y: b.y - headLen * sin(angle + half))
        // The shaft stops inside the head so its round cap never pokes past the tip.
        let shaftEnd = CGPoint(x: b.x - headLen * 0.75 * cos(angle), y: b.y - headLen * 0.75 * sin(angle))
        ctx.move(to: a)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()
        ctx.move(to: b)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    static func drawBadge(_ s: Shape, into ctx: CGContext, scale: Double) {
        let r = CGFloat(s.badgeRadius)
        let c = s.start.cgPoint
        let circle = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.fillEllipse(in: circle)
        let ring = max(1, CGFloat(1.5 * scale))
        ctx.setLineWidth(ring)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.strokeEllipse(in: circle.insetBy(dx: ring / 2, dy: ring / 2))
        let fontSize = s.style.fontSize * 0.8
        let textColor: RGBAColor = s.style.color.luminance > 0.6 ? .black : .white
        let size = measureText("\(s.number)", fontSize: fontSize)
        let origin = PixelPoint(x: Int((c.x - CGFloat(size.width) / 2).rounded()),
                                y: Int((c.y - CGFloat(size.height) / 2).rounded()))
        drawText("\(s.number)", at: origin, fontSize: fontSize, color: textColor, outlined: false, into: ctx)
    }

    /// Contrasting halo colour for text of this colour, used for legibility on any background.
    public static func haloColor(for color: RGBAColor) -> CGColor {
        color.luminance < 0.35
            ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.65)
            : CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55)
    }

    /// Halo blur radius for a given font size, shared with the inline editor so typing and the
    /// committed shape look identical.
    public static func haloBlur(fontSize: Double) -> Double { fontSize * 0.055 }

    /// Left/top inset of the glyphs inside a text shape's bounds; leaves room for the halo.
    public static func textPadding(fontSize: Double) -> Double { ceil(fontSize * 0.08) }

    static func drawText(_ text: String, at origin: PixelPoint, fontSize: Double, color: RGBAColor,
                         outlined: Bool, into ctx: CGContext) {
        let f = font(size: fontSize)
        let ascent = CTFontGetAscent(f)
        let lh = CGFloat(lineHeight(fontSize: fontSize))
        let pad = CGFloat(textPadding(fontSize: fontSize))
        let attrs: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): f,
            .init(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // The context is flipped; flip the text matrix back so glyphs render upright.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        let lines = text.components(separatedBy: "\n")
        func drawLines() {
            for (i, line) in lines.enumerated() {
                let attributed = NSAttributedString(string: line.isEmpty ? " " : line, attributes: attrs)
                let ctLine = CTLineCreateWithAttributedString(attributed)
                ctx.textPosition = CGPoint(x: CGFloat(origin.x) + pad,
                                           y: CGFloat(origin.y) + pad + ascent + CGFloat(i) * lh)
                CTLineDraw(ctLine, ctx)
            }
        }

        if outlined {
            // A halo rather than a stroked outline: a stroke thickens the glyphs (so text looked
            // heavier once committed) and closes the counters of e/a/o into blobs. The halo leaves
            // glyph weight untouched. Drawn twice for density, then once more clean on top.
            ctx.setShadow(offset: .zero, blur: CGFloat(haloBlur(fontSize: fontSize)), color: haloColor(for: color))
            drawLines()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
        drawLines()
    }

    /// Mosaic: average the region down to `block`-sized cells, then scale back up with no interpolation.
    static func drawPixelated(_ base: CGImage, rect: PixelRect, block: Int, _ ctx: CGContext) {
        let clipped = rect.intersection(PixelRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !clipped.isEmpty, let tile = base.cropping(to: clipped.cgRect) else { return }
        let sw = max(1, clipped.width / block), sh = max(1, clipped.height / block)
        let space = base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let small = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: space, bitmapInfo: info) else { return }
        small.interpolationQuality = .medium
        small.draw(tile, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let mosaic = small.makeImage() else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        drawImage(mosaic, in: clipped.cgRect, ctx)
        ctx.restoreGState()
    }

    static func drawSelectionChrome(for s: Shape, into ctx: CGContext, scale: Double) {
        let pad = Int((4 * scale).rounded()) + Int(s.style.strokeWidth / 2)
        let r = s.bounds.expanded(by: pad).cgRect
        ctx.saveGState()
        ctx.setLineWidth(CGFloat(scale))
        ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6))
        ctx.stroke(r)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.setLineDash(phase: 0, lengths: [CGFloat(4 * scale), CGFloat(4 * scale)])
        ctx.stroke(r)
        ctx.restoreGState()
    }

    /// Draws an image upright inside a flipped context.
    static func drawImage(_ image: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }
}
