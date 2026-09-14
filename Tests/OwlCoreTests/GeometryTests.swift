import CoreGraphics
import Testing
@testable import OwlCore

@Suite struct PixelRectTests {
    @Test func spanningNormalizesCorners() {
        let r = PixelRect.spanning(PixelPoint(x: 100, y: 80), PixelPoint(x: 20, y: 200))
        #expect(r == PixelRect(x: 20, y: 80, width: 80, height: 120))
    }

    @Test func spanningSamePointIsEmpty() {
        #expect(PixelRect.spanning(PixelPoint(x: 5, y: 5), PixelPoint(x: 5, y: 5)).isEmpty)
    }

    @Test func intersectionClipsAndReportsEmpty() {
        let bounds = PixelRect(x: 0, y: 0, width: 100, height: 100)
        #expect(PixelRect(x: 50, y: 50, width: 100, height: 100).intersection(bounds)
                == PixelRect(x: 50, y: 50, width: 50, height: 50))
        #expect(PixelRect(x: 200, y: 200, width: 10, height: 10).intersection(bounds).isEmpty)
    }

    @Test func movedWithinShiftsInsteadOfShrinking() {
        let bounds = PixelRect(x: 0, y: 0, width: 100, height: 100)
        let r = PixelRect(x: 90, y: -10, width: 30, height: 30).moved(within: bounds)
        #expect(r == PixelRect(x: 70, y: 0, width: 30, height: 30))
        let big = PixelRect(x: 10, y: 10, width: 500, height: 20).moved(within: bounds)
        #expect(big == PixelRect(x: 0, y: 10, width: 100, height: 20))
    }

    @Test func containsIsHalfOpen() {
        let r = PixelRect(x: 10, y: 10, width: 10, height: 10)
        #expect(r.contains(PixelPoint(x: 10, y: 10)))
        #expect(r.contains(PixelPoint(x: 19, y: 19)))
        #expect(!r.contains(PixelPoint(x: 20, y: 10)))
    }
}

@Suite struct DisplayGeometryTests {
    let retina = DisplayGeometry(pointSize: CGSize(width: 1512, height: 982), scale: 2)
    let lowDPI = DisplayGeometry(pointSize: CGSize(width: 1920, height: 1080), scale: 1)

    @Test func pixelSizeRoundsFromPoints() {
        #expect(retina.pixelSize == PixelSize(width: 3024, height: 1964))
        #expect(lowDPI.pixelSize == PixelSize(width: 1920, height: 1080))
    }

    @Test func pointToPixelFloorsAndClamps() {
        #expect(retina.pixel(fromPoint: CGPoint(x: 10.7, y: 3.2)) == PixelPoint(x: 21, y: 6))
        #expect(retina.pixel(fromPoint: CGPoint(x: -5, y: -5)) == .zero)
        #expect(retina.pixel(fromPoint: CGPoint(x: 99999, y: 99999)) == PixelPoint(x: 3024, y: 1964))
    }

    @Test func pixelRectToPointsDividesByScale() {
        let r = retina.rect(fromPixelRect: PixelRect(x: 3, y: 5, width: 11, height: 7))
        #expect(r == CGRect(x: 1.5, y: 2.5, width: 5.5, height: 3.5))
    }

    @Test func nonIntegerScaleRoundTripsWithinOnePixel() {
        let g = DisplayGeometry(pointSize: CGSize(width: 1000, height: 500), scale: 1.5)
        let p = g.pixel(fromPoint: g.point(fromPixel: PixelPoint(x: 733, y: 401)))
        #expect(abs(p.x - 733) <= 1 && abs(p.y - 401) <= 1)
    }
}
