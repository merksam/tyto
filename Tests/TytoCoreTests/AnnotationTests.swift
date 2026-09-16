import CoreGraphics
import Foundation
import Testing
@testable import TytoCore

private let style = ShapeStyle(color: .red, strokeWidth: 4, fontSize: 32)

@Suite struct ShapeHitTests {
    @Test func lineHitsNearSegmentOnly() {
        let s = Shape(kind: .line, start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 100, y: 0), style: style)
        #expect(s.hitTest(PixelPoint(x: 50, y: 5), tolerance: 4))
        #expect(!s.hitTest(PixelPoint(x: 50, y: 12), tolerance: 4))
        #expect(!s.hitTest(PixelPoint(x: 120, y: 0), tolerance: 4))
    }

    @Test func rectHitsBorderNotInterior() {
        let s = Shape(kind: .rect, start: PixelPoint(x: 10, y: 10), end: PixelPoint(x: 110, y: 110), style: style)
        #expect(s.hitTest(PixelPoint(x: 10, y: 60), tolerance: 4))
        #expect(s.hitTest(PixelPoint(x: 60, y: 112), tolerance: 4))
        #expect(!s.hitTest(PixelPoint(x: 60, y: 60), tolerance: 4))
        #expect(!s.hitTest(PixelPoint(x: 200, y: 200), tolerance: 4))
    }

    @Test func ellipseHitsRing() {
        let s = Shape(kind: .ellipse, start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 200, y: 100), style: style)
        #expect(s.hitTest(PixelPoint(x: 200, y: 50), tolerance: 4))
        #expect(s.hitTest(PixelPoint(x: 100, y: 1), tolerance: 4))
        #expect(!s.hitTest(PixelPoint(x: 100, y: 50), tolerance: 4))
        #expect(!s.hitTest(PixelPoint(x: 0, y: 0), tolerance: 4))
    }

    @Test func blurTextBadgeHitInsideBounds() {
        let blur = Shape(kind: .blur, start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 50, y: 50), style: style)
        #expect(blur.hitTest(PixelPoint(x: 25, y: 25), tolerance: 0))
        let text = Shape(kind: .text, start: PixelPoint(x: 100, y: 100), end: .zero, style: style,
                         text: "hi", textSize: PixelSize(width: 40, height: 20))
        #expect(text.hitTest(PixelPoint(x: 120, y: 110), tolerance: 0))
        #expect(!text.hitTest(PixelPoint(x: 150, y: 110), tolerance: 0))
        let badge = Shape(kind: .badge, start: PixelPoint(x: 300, y: 300), end: .zero, style: style, number: 1)
        #expect(badge.hitTest(PixelPoint(x: 300 + badge.badgeRadius - 1, y: 300), tolerance: 0))
        #expect(!badge.hitTest(PixelPoint(x: 300 + badge.badgeRadius + 5, y: 300), tolerance: 0))
    }

    @Test func degenerateShapes() {
        #expect(Shape(kind: .rect, start: PixelPoint(x: 5, y: 5), end: PixelPoint(x: 7, y: 40), style: style).isDegenerate)
        #expect(!Shape(kind: .rect, start: PixelPoint(x: 5, y: 5), end: PixelPoint(x: 50, y: 40), style: style).isDegenerate)
        #expect(Shape(kind: .arrow, start: PixelPoint(x: 5, y: 5), end: PixelPoint(x: 7, y: 6), style: style).isDegenerate)
        #expect(Shape(kind: .text, start: .zero, end: .zero, style: style, text: "  ").isDegenerate)
    }
}

@Suite struct DocumentTests {
    @Test func badgesNumberByCreationAndRenumberOnDelete() {
        var d = AnnotationDocument()
        let b1 = Shape(kind: .badge, start: .zero, end: .zero, style: style, number: d.nextBadgeNumber)
        d.add(b1)
        let b2 = Shape(kind: .badge, start: .zero, end: .zero, style: style, number: d.nextBadgeNumber)
        d.add(b2)
        let b3 = Shape(kind: .badge, start: .zero, end: .zero, style: style, number: d.nextBadgeNumber)
        d.add(b3)
        #expect(d.shapes.map(\.number) == [1, 2, 3])
        d.remove(id: b2.id)
        #expect(d.shapes.map(\.number) == [1, 2])
        #expect(d.nextBadgeNumber == 3)
    }

    @Test func topmostPrefersLaterShapesAndIgnoresBlurUnderOthers() {
        var d = AnnotationDocument()
        let below = Shape(kind: .rect, start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 100, y: 100), style: style)
        let above = Shape(kind: .rect, start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 100, y: 100), style: style)
        d.add(below); d.add(above)
        #expect(d.topmostShape(at: PixelPoint(x: 0, y: 50), tolerance: 2)?.id == above.id)
        let blur = Shape(kind: .blur, start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 100, y: 100), style: style)
        d.add(blur)
        #expect(d.topmostShape(at: PixelPoint(x: 0, y: 50), tolerance: 2)?.id == above.id)
        #expect(d.topmostShape(at: PixelPoint(x: 50, y: 50), tolerance: 2)?.id == blur.id)
        #expect(d.renderOrder.first?.id == blur.id)
    }

    @Test func removeClearsSelection() {
        var d = AnnotationDocument()
        let s = Shape(kind: .line, start: .zero, end: PixelPoint(x: 10, y: 10), style: style)
        d.add(s); d.selectedID = s.id
        let removed = d.remove(id: s.id)
        #expect(removed)
        #expect(d.selectedID == nil)
        let removedAgain = d.remove(id: s.id)
        #expect(!removedAgain)
    }
}

@Suite struct HistoryTests {
    @Test func undoRedoRoundTrip() {
        var h = History<Int>()
        var state = 0
        h.record(state); state = 1
        h.record(state); state = 2
        #expect(h.canUndo && !h.canRedo)
        state = h.undo(current: state)!
        #expect(state == 1)
        state = h.undo(current: state)!
        #expect(state == 0)
        #expect(h.undo(current: state) == nil)
        state = h.redo(current: state)!
        #expect(state == 1)
        h.record(state); state = 5
        #expect(!h.canRedo)
    }
}

@Suite struct RendererTests {
    static func grayBase(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // A bright stripe at the top (top-left origin!) to detect vertical flips.
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h - 10, width: w, height: 10))
        return ctx.makeImage()!
    }

    static func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        var buf = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Draw the whole image offset so that (x, y) in top-left coordinates lands on the single pixel.
        ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
        return (Int(buf[0]), Int(buf[1]), Int(buf[2]))
    }

    @Test func exportKeepsOrientationAndSize() {
        let base = Self.grayBase(200, 200)
        let out = AnnotationRenderer.export(AnnotationDocument(), base: base, crop: PixelRect(x: 50, y: 0, width: 100, height: 100), pixelScale: 2)!
        #expect(out.width == 100 && out.height == 100)
        let top = Self.pixel(out, 10, 2)
        let mid = Self.pixel(out, 10, 50)
        #expect(top.r > 240, "white stripe must stay at the top after export")
        #expect(abs(mid.r - 128) < 6)
    }

    @Test func rectStrokeLandsOnItsEdge() {
        let base = Self.grayBase(200, 200)
        var doc = AnnotationDocument()
        doc.add(Shape(kind: .rect, start: PixelPoint(x: 20, y: 20), end: PixelPoint(x: 120, y: 120), style: style))
        let out = AnnotationRenderer.export(doc, base: base, crop: PixelRect(x: 0, y: 0, width: 200, height: 200), pixelScale: 2)!
        let edge = Self.pixel(out, 20, 70)
        let inside = Self.pixel(out, 70, 70)
        #expect(edge.r > 200 && edge.g < 100, "left edge should be red")
        #expect(abs(inside.r - 128) < 6, "interior untouched")
    }

    @Test func blurChangesPixelsInsideOnly() {
        // Base with a checkerboard so averaging visibly changes values.
        let w = 120, h = 120
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                let on = ((x / 2 + y / 2) % 2) == 0
                ctx.setFillColor(CGColor(srgbRed: on ? 1 : 0, green: on ? 1 : 0, blue: on ? 1 : 0, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
        let base = ctx.makeImage()!
        var doc = AnnotationDocument()
        doc.add(Shape(kind: .blur, start: PixelPoint(x: 20, y: 20), end: PixelPoint(x: 80, y: 80), style: style))
        let out = AnnotationRenderer.export(doc, base: base, crop: PixelRect(x: 0, y: 0, width: w, height: h), pixelScale: 2)!
        let inside = Self.pixel(out, 50, 50)
        let outside = Self.pixel(out, 100, 100)
        #expect(inside.r > 40 && inside.r < 215, "mosaic averages black and white to gray")
        #expect(outside.r < 10 || outside.r > 245, "outside stays checkerboard")
    }

    @Test func textMeasuresAndDraws() {
        let size = AnnotationRenderer.measureText("Hello", fontSize: 32)
        #expect(size.width > 40 && size.height >= 32)
        let two = AnnotationRenderer.measureText("a\nb", fontSize: 32)
        #expect(two.height > size.height)
        let base = Self.grayBase(300, 100)
        var doc = AnnotationDocument()
        doc.add(Shape(kind: .text, start: PixelPoint(x: 10, y: 10), end: .zero, style: style, text: "Hello", textSize: size))
        let out = AnnotationRenderer.export(doc, base: base, crop: PixelRect(x: 0, y: 0, width: 300, height: 100), pixelScale: 2)!
        var reddish = 0
        for x in stride(from: 10, to: 10 + size.width, by: 2) {
            for y in stride(from: 10, to: 10 + size.height, by: 2) {
                let p = Self.pixel(out, x, y)
                if p.r > 150 && p.g < 110 { reddish += 1 }
            }
        }
        #expect(reddish > 20, "some pixels in the text box must carry the text colour")
    }
}
