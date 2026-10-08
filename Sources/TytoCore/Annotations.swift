import CoreGraphics
import Foundation

public struct RGBAColor: Hashable, Sendable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let red = RGBAColor(r: 1.0, g: 0.23, b: 0.19)
    public static let orange = RGBAColor(r: 1.0, g: 0.58, b: 0.0)
    public static let yellow = RGBAColor(r: 1.0, g: 0.84, b: 0.04)
    public static let green = RGBAColor(r: 0.20, g: 0.78, b: 0.35)
    public static let blue = RGBAColor(r: 0.04, g: 0.52, b: 1.0)
    public static let purple = RGBAColor(r: 0.69, g: 0.32, b: 0.87)
    public static let white = RGBAColor(r: 1, g: 1, b: 1)
    public static let black = RGBAColor(r: 0.1, g: 0.1, b: 0.1)

    public static let palette: [(name: String, color: RGBAColor)] = [
        ("red", .red), ("orange", .orange), ("yellow", .yellow), ("green", .green),
        ("blue", .blue), ("purple", .purple), ("white", .white), ("black", .black),
    ]

    public static func named(_ name: String) -> RGBAColor? {
        palette.first { $0.name == name.lowercased() }?.color
    }

    public var name: String? { Self.palette.first { $0.color == self }?.name }

    /// Relative luminance, used to pick a contrasting outline for text.
    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// Stroke width and font size are stored in *pixels* so a shape renders identically on screen
/// and in the exported image.
public struct ShapeStyle: Hashable, Sendable, Codable {
    public var color: RGBAColor
    public var strokeWidth: Double
    public var fontSize: Double

    public init(color: RGBAColor, strokeWidth: Double, fontSize: Double) {
        self.color = color; self.strokeWidth = strokeWidth; self.fontSize = fontSize
    }
}

public enum ShapeKind: String, Sendable, Codable, CaseIterable {
    case rect, ellipse, line, arrow, text, blur, badge

    /// Created by dragging (as opposed to a single click).
    public var isDragCreated: Bool { self != .text && self != .badge }
}

public struct Shape: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var kind: ShapeKind
    /// rect/ellipse/blur: one corner. line/arrow: tail. text: top-left. badge: center.
    public var start: PixelPoint
    /// rect/ellipse/blur: opposite corner. line/arrow: head. Unused for text/badge.
    public var end: PixelPoint
    public var style: ShapeStyle
    public var text: String
    /// Measured size of `text` at `style.fontSize`; kept on the shape so the model needs no font access.
    public var textSize: PixelSize
    public var number: Int
    /// Arrows only: the quadratic Bézier control point that bends the shaft. nil is a straight
    /// arrow, and what every document written before 1.2 decodes to.
    public var control: PixelPoint?

    public init(id: UUID = UUID(), kind: ShapeKind, start: PixelPoint, end: PixelPoint, style: ShapeStyle,
                text: String = "", textSize: PixelSize = PixelSize(width: 0, height: 0), number: Int = 0,
                control: PixelPoint? = nil) {
        self.id = id; self.kind = kind; self.start = start; self.end = end; self.style = style
        self.text = text; self.textSize = textSize; self.number = number; self.control = control
    }

    public var badgeRadius: Int { max(8, Int((style.fontSize * 0.72).rounded())) }

    /// Geometric bounds, not including stroke thickness.
    public var bounds: PixelRect {
        switch kind {
        case .text:
            return PixelRect(origin: start, size: textSize)
        case .badge:
            let r = badgeRadius
            return PixelRect(x: start.x - r, y: start.y - r, width: 2 * r, height: 2 * r)
        default:
            var r = PixelRect.spanning(start, end)
            if control != nil {
                // Tight bounds of the curve: its extremes are at the ends or where the
                // derivative is zero on each axis. The control point itself lies twice as far
                // out as the curve ever reaches, so spanning it would double the box.
                var xs = [start.x, end.x], ys = [start.y, end.y]
                for t in extremumParameters() {
                    let p = point(at: t)
                    xs.append(p.x); ys.append(p.y)
                }
                let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
                r = PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            return r
        }
    }

    /// True for drag-created shapes too small to be intentional.
    public var isDegenerate: Bool {
        switch kind {
        case .line, .arrow:
            return hypot(Double(end.x - start.x), Double(end.y - start.y)) < 4
        case .rect, .ellipse, .blur:
            let b = bounds
            // Deliberately not `||`: a long, very thin rectangle is an underline, which is a
            // shape somebody meant to draw.
            return max(b.width, b.height) < 4
        case .text:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .badge:
            return false
        }
    }

    public func moved(dx: Int, dy: Int) -> Shape {
        var s = self
        s.start = PixelPoint(x: start.x + dx, y: start.y + dy)
        s.end = PixelPoint(x: end.x + dx, y: end.y + dy)
        if let c = control { s.control = PixelPoint(x: c.x + dx, y: c.y + dy) }
        return s
    }

    public func hitTest(_ p: PixelPoint, tolerance: Int) -> Bool {
        let tol = Double(tolerance) + style.strokeWidth / 2
        switch kind {
        case .line, .arrow:
            if control != nil { return distanceToCurve(from: p) <= tol }
            return Self.distance(from: p, toSegment: start, end) <= tol
        case .rect:
            let b = bounds
            guard b.expanded(by: Int(tol.rounded(.up))).contains(p) else { return false }
            let inner = b.insetBy(Int(tol))
            return inner.isEmpty || !inner.contains(p)
        case .ellipse:
            let b = bounds
            let a = Double(b.width) / 2, c = Double(b.height) / 2
            guard a > 0, c > 0 else { return false }
            let nx = (Double(p.x) - (Double(b.minX) + a)) / a
            let ny = (Double(p.y) - (Double(b.minY) + c)) / c
            let v = (nx * nx + ny * ny).squareRoot()
            return abs(v - 1) * min(a, c) <= tol
        case .blur, .text, .badge:
            return bounds.expanded(by: tolerance).contains(p)
        }
    }

    static func distance(from p: PixelPoint, toSegment a: PixelPoint, _ b: PixelPoint) -> Double {
        let px = Double(p.x), py = Double(p.y)
        let ax = Double(a.x), ay = Double(a.y), bx = Double(b.x), by = Double(b.y)
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        var t = len2 == 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2
        t = min(max(t, 0), 1)
        let cx = ax + t * dx, cy = ay + t * dy
        return ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot()
    }

    // MARK: Curved arrows

    /// Point on the shaft at parameter `t` (0 = tail, 1 = head). Straight when `control` is nil.
    public func point(at t: Double) -> PixelPoint {
        let sx = Double(start.x), sy = Double(start.y), ex = Double(end.x), ey = Double(end.y)
        guard let c = control else {
            return PixelPoint(x: Int((sx + (ex - sx) * t).rounded()), y: Int((sy + (ey - sy) * t).rounded()))
        }
        let cx = Double(c.x), cy = Double(c.y), u = 1 - t
        return PixelPoint(x: Int((u * u * sx + 2 * u * t * cx + t * t * ex).rounded()),
                          y: Int((u * u * sy + 2 * u * t * cy + t * t * ey).rounded()))
    }

    /// Where the bend handle sits: the middle of the shaft, curved or not.
    public var curveMidpoint: PixelPoint { point(at: 0.5) }

    /// The shape with its shaft passing through `p` at the middle. Within `straightenWithin`
    /// pixels of the straight line between the ends it snaps straight instead, so dragging the
    /// handle back is how you undo a bend without reaching for ⌘Z.
    public func bent(through p: PixelPoint, straightenWithin: Int) -> Shape {
        var s = self
        if Self.distance(from: p, toSegment: start, end) <= Double(straightenWithin) {
            s.control = nil
            return s
        }
        // A quadratic Bézier passes through B(0.5) = (start + 2·control + end) / 4, so the
        // control point that puts the midpoint at p is 2p − (start + end) / 2. In Double and
        // rounded once: integer division would bias it by half a pixel whenever the ends sum
        // to an odd number, and the handle would jitter under the pointer.
        s.control = PixelPoint(x: Int((2 * Double(p.x) - Double(start.x + end.x) / 2).rounded()),
                               y: Int((2 * Double(p.y) - Double(start.y + end.y) / 2).rounded()))
        return s
    }

    /// Distance from `p` to the curved shaft, by sampling it as 24 straight pieces, which is
    /// within a pixel for any curve a hand can draw at screen sizes.
    func distanceToCurve(from p: PixelPoint) -> Double {
        var best = Double.infinity
        var prev = start
        for i in 1...24 {
            let next = point(at: Double(i) / 24)
            best = min(best, Self.distance(from: p, toSegment: prev, next))
            prev = next
        }
        return best
    }

    /// Length of the shaft along the curve (the chord for a straight arrow), sampled the same
    /// way. A tightly bent arrow is far longer than its chord, which matters for sizing the head.
    public var curveLength: Double {
        guard control != nil else { return hypot(Double(end.x - start.x), Double(end.y - start.y)) }
        var total = 0.0
        var prev = start
        for i in 1...24 {
            let next = point(at: Double(i) / 24)
            total += hypot(Double(next.x - prev.x), Double(next.y - prev.y))
            prev = next
        }
        return total
    }

    /// Parameters in (0, 1) where the curve turns around on the x or y axis: for a quadratic,
    /// t = (s − c) / (s − 2c + e) per axis, when that lands strictly inside the span.
    func extremumParameters() -> [Double] {
        guard let c = control else { return [] }
        var ts: [Double] = []
        for (s, cc, e) in [(start.x, c.x, end.x), (start.y, c.y, end.y)] {
            let denom = Double(s - 2 * cc + e)
            guard denom != 0 else { continue }
            let t = Double(s - cc) / denom
            if t > 0, t < 1 { ts.append(t) }
        }
        return ts
    }
}

public struct AnnotationDocument: Sendable, Equatable {
    public var shapes: [Shape] = []
    public var selectedID: UUID?

    public init() {}

    public var isEmpty: Bool { shapes.isEmpty }
    public var nextBadgeNumber: Int { shapes.filter { $0.kind == .badge }.count + 1 }
    public var selectedShape: Shape? { selectedID.flatMap(shape(id:)) }

    /// Blur always renders underneath every other annotation, regardless of creation order,
    /// so it can only ever hide screen content, never a mark.
    public var renderOrder: [Shape] {
        shapes.filter { $0.kind == .blur } + shapes.filter { $0.kind != .blur }
    }

    public func shape(id: UUID) -> Shape? { shapes.first { $0.id == id } }

    /// Topmost shape under the point (last drawn wins, blur loses to everything else).
    public func topmostShape(at p: PixelPoint, tolerance: Int) -> Shape? {
        renderOrder.reversed().first { $0.hitTest(p, tolerance: tolerance) }
    }

    public mutating func add(_ shape: Shape) {
        shapes.append(shape)
    }

    public mutating func update(_ shape: Shape) {
        guard let i = shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        shapes[i] = shape
    }

    @discardableResult
    public mutating func remove(id: UUID) -> Bool {
        guard let i = shapes.firstIndex(where: { $0.id == id }) else { return false }
        shapes.remove(at: i)
        if selectedID == id { selectedID = nil }
        renumberBadges()
        return true
    }

    /// Badges are numbered by creation order; deleting one closes the gap.
    public mutating func renumberBadges() {
        var n = 1
        for i in shapes.indices where shapes[i].kind == .badge {
            shapes[i].number = n
            n += 1
        }
    }
}

/// Snapshot-based undo/redo. Documents are small value types, so whole-state snapshots are cheap.
public struct History<State: Sendable>: Sendable {
    private var past: [State] = []
    private var future: [State] = []
    public let limit: Int

    public init(limit: Int = 200) { self.limit = limit }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// Call with the state *before* a mutation.
    public mutating func record(_ before: State) {
        past.append(before)
        if past.count > limit { past.removeFirst() }
        future.removeAll()
    }

    public mutating func undo(current: State) -> State? {
        guard let s = past.popLast() else { return nil }
        future.append(current)
        return s
    }

    public mutating func redo(current: State) -> State? {
        guard let s = future.popLast() else { return nil }
        past.append(current)
        return s
    }

    /// Drops the most recent recorded state without making it redoable. For a mutation that
    /// turned out not to have happened, so its record should leave no trace either way.
    /// Distinct from `clear()`, which throws away the whole history.
    public mutating func discardLastRecord() {
        _ = past.popLast()
    }

    public mutating func clear() {
        past.removeAll()
        future.removeAll()
    }
}
