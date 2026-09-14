import CoreGraphics
import Foundation

/// A point in display pixel space. Origin is the top-left corner of the display.
public struct PixelPoint: Hashable, Sendable, Codable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public static let zero = PixelPoint(x: 0, y: 0)
}

public struct PixelSize: Hashable, Sendable, Codable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

/// An integer rectangle in display pixel space, origin top-left.
/// All selection and annotation geometry is stored in this space so crops are never blurry.
public struct PixelRect: Hashable, Sendable, Codable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public init(origin: PixelPoint, size: PixelSize) {
        self.init(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    public static let zero = PixelRect(x: 0, y: 0, width: 0, height: 0)

    public var isEmpty: Bool { width <= 0 || height <= 0 }
    public var minX: Int { x }
    public var minY: Int { y }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var midX: Int { x + width / 2 }
    public var midY: Int { y + height / 2 }
    public var origin: PixelPoint { PixelPoint(x: x, y: y) }
    public var size: PixelSize { PixelSize(width: width, height: height) }
    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// The normalized rectangle spanning two arbitrary corner points.
    public static func spanning(_ a: PixelPoint, _ b: PixelPoint) -> PixelRect {
        PixelRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    public func contains(_ p: PixelPoint) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    /// Intersection with another rect. Empty (zero-sized) if they do not overlap.
    public func intersection(_ o: PixelRect) -> PixelRect {
        let x0 = max(minX, o.minX), y0 = max(minY, o.minY)
        let x1 = min(maxX, o.maxX), y1 = min(maxY, o.maxY)
        guard x1 > x0, y1 > y0 else { return PixelRect(x: x0, y: y0, width: 0, height: 0) }
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func offset(dx: Int, dy: Int) -> PixelRect {
        PixelRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// Shifts (rather than shrinks) the rect so it lies inside `bounds`.
    /// If it is larger than `bounds` on an axis it is clamped to the bounds on that axis.
    public func moved(within bounds: PixelRect) -> PixelRect {
        var r = self
        r.width = min(r.width, bounds.width)
        r.height = min(r.height, bounds.height)
        r.x = min(max(r.x, bounds.minX), bounds.maxX - r.width)
        r.y = min(max(r.y, bounds.minY), bounds.maxY - r.height)
        return r
    }
}

/// Size and scale of one display, used to convert between AppKit points and pixels.
/// Point coordinates here are in a top-left-origin space (a flipped NSView covering the screen).
public struct DisplayGeometry: Hashable, Sendable {
    public let pointSize: CGSize
    public let scale: CGFloat

    public init(pointSize: CGSize, scale: CGFloat) {
        self.pointSize = pointSize
        self.scale = scale
    }

    public var pixelSize: PixelSize {
        PixelSize(width: Int((pointSize.width * scale).rounded()),
                  height: Int((pointSize.height * scale).rounded()))
    }

    public var pixelBounds: PixelRect { PixelRect(origin: .zero, size: pixelSize) }

    /// Floors to the pixel under the point. The far edge (x == width) is allowed so a drag to the
    /// right/bottom edge can include the last row/column.
    public func pixel(fromPoint p: CGPoint) -> PixelPoint {
        let px = Int((p.x * scale).rounded(.down))
        let py = Int((p.y * scale).rounded(.down))
        let size = pixelSize
        return PixelPoint(x: min(max(px, 0), size.width), y: min(max(py, 0), size.height))
    }

    public func point(fromPixel p: PixelPoint) -> CGPoint {
        CGPoint(x: CGFloat(p.x) / scale, y: CGFloat(p.y) / scale)
    }

    public func rect(fromPixelRect r: PixelRect) -> CGRect {
        CGRect(x: CGFloat(r.x) / scale, y: CGFloat(r.y) / scale,
               width: CGFloat(r.width) / scale, height: CGFloat(r.height) / scale)
    }
}
