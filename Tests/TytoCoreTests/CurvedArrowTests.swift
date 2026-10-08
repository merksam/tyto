import CoreGraphics
import Foundation
import Testing
@testable import TytoCore

private let style = ShapeStyle(color: .red, strokeWidth: 4, fontSize: 32)

private func arrow(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Shape {
    Shape(kind: .arrow, start: PixelPoint(x: x0, y: y0), end: PixelPoint(x: x1, y: y1), style: style)
}

@Suite struct CurvedArrowTests {
    @Test func bendingThroughAPointPutsTheMiddleThere() {
        let s = arrow(0, 0, 100, 0).bent(through: PixelPoint(x: 50, y: 30), straightenWithin: 3)
        #expect(s.control == PixelPoint(x: 50, y: 60))
        #expect(s.curveMidpoint == PixelPoint(x: 50, y: 30))
        // Ends never move.
        #expect(s.start == PixelPoint(x: 0, y: 0) && s.end == PixelPoint(x: 100, y: 0))
    }

    @Test func draggingBackNearTheChordStraightens() {
        let bent = arrow(0, 0, 100, 0).bent(through: PixelPoint(x: 50, y: 30), straightenWithin: 3)
        #expect(bent.control != nil)
        let straight = bent.bent(through: PixelPoint(x: 50, y: 2), straightenWithin: 3)
        #expect(straight.control == nil)
        #expect(straight.curveMidpoint == PixelPoint(x: 50, y: 0))
    }

    @Test func hitTestFollowsTheCurveNotTheChord() {
        let s = arrow(0, 0, 100, 0).bent(through: PixelPoint(x: 50, y: 30), straightenWithin: 3)
        #expect(s.hitTest(PixelPoint(x: 50, y: 30), tolerance: 4), "on the curve")
        #expect(s.hitTest(PixelPoint(x: 25, y: 22), tolerance: 4), "quarter way along, where the curve is")
        #expect(!s.hitTest(PixelPoint(x: 50, y: 0), tolerance: 4), "the chord is not the shaft any more")
    }

    @Test func boundsAndMoveIncludeTheControlPoint() {
        let s = arrow(0, 0, 100, 0).bent(through: PixelPoint(x: 50, y: 30), straightenWithin: 3)
        #expect(s.bounds.maxY >= 60, "bounds cover the control point so selection chrome encloses the curve")
        let moved = s.moved(dx: 10, dy: 5)
        #expect(moved.control == PixelPoint(x: 60, y: 65))
        #expect(moved.curveMidpoint == PixelPoint(x: 60, y: 35))
    }

    @Test func straightArrowsFromBefore12DecodeWithNoControl() throws {
        // A straight arrow encodes without a `control` key, which is also what every document
        // written before 1.2 looks like; both must decode as straight.
        let data = try JSONEncoder().encode(arrow(0, 0, 100, 0))
        #expect(!String(decoding: data, as: UTF8.self).contains("control"))
        let back = try JSONDecoder().decode(Shape.self, from: data)
        #expect(back.control == nil)

        let bent = arrow(0, 0, 100, 0).bent(through: PixelPoint(x: 50, y: 30), straightenWithin: 3)
        let round = try JSONDecoder().decode(Shape.self, from: JSONEncoder().encode(bent))
        #expect(round.control == PixelPoint(x: 50, y: 60))
    }

    @Test func rendererPaintsTheCurveAndLeavesTheChordAlone() {
        let base = RendererTests.grayBase(200, 200)
        var doc = AnnotationDocument()
        doc.add(arrow(20, 100, 180, 100).bent(through: PixelPoint(x: 100, y: 40), straightenWithin: 3))
        let out = AnnotationRenderer.export(doc, base: base, crop: PixelRect(x: 0, y: 0, width: 200, height: 200), pixelScale: 2)!
        let onCurve = RendererTests.pixel(out, 100, 40)
        let onChord = RendererTests.pixel(out, 100, 100)
        #expect(onCurve.r > 200 && onCurve.g < 100, "the shaft passes through the bend point")
        #expect(abs(onChord.r - 128) < 6, "nothing is drawn along the straight line between the ends")
    }
}
