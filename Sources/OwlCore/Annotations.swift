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

    public init(id: UUID = UUID(), kind: ShapeKind, start: PixelPoint, end: PixelPoint, style: ShapeStyle,
                text: String = "", textSize: PixelSize = PixelSize(width: 0, height: 0), number: Int = 0) {
        self.id = id; self.kind = kind; self.start = start; self.end = end; self.style = style
        self.text = text; self.textSize = textSize; self.number = number
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
            return PixelRect.spanning(start, end)
        }
    }

    /// True for drag-created shapes too small to be intentional.
    public var isDegenerate: Bool {
        switch kind {
        case .line, .arrow:
            return hypot(Double(end.x - start.x), Double(end.y - start.y)) < 4
        case .rect, .ellipse, .blur:
            let b = bounds
            return b.width < 4 || b.height < 4
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
        return s
    }

    public func hitTest(_ p: PixelPoint, tolerance: Int) -> Bool {
        let tol = Double(tolerance) + style.strokeWidth / 2
        switch kind {
        case .line, .arrow:
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

    public mutating func clear() {
        past.removeAll()
        future.removeAll()
    }
}
