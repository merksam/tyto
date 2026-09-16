import Foundation

public enum Handle: String, CaseIterable, Sendable, Codable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// Pure state machine for the region selection: drag to create, drag handles to resize,
/// drag inside to move. Everything is in display pixel coordinates.
public struct SelectionModel: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case dragging(anchor: PixelPoint)
        case resizing(Handle, original: PixelRect)
        case moving(grabOffset: PixelPoint)
    }

    public enum Hit: Sendable, Equatable {
        case handle(Handle)
        case inside
        case outside
    }

    public let bounds: PixelRect
    public private(set) var rect: PixelRect?
    public private(set) var phase: Phase = .idle

    public init(bounds: PixelRect, rect: PixelRect? = nil) {
        self.bounds = bounds
        self.rect = rect
    }

    public var isInteracting: Bool { phase != .idle }
    public var hasSelection: Bool { rect.map { !$0.isEmpty } ?? false }

    public static func handleCenters(of r: PixelRect) -> [(Handle, PixelPoint)] {
        [
            (.topLeft, PixelPoint(x: r.minX, y: r.minY)),
            (.top, PixelPoint(x: r.midX, y: r.minY)),
            (.topRight, PixelPoint(x: r.maxX, y: r.minY)),
            (.right, PixelPoint(x: r.maxX, y: r.midY)),
            (.bottomRight, PixelPoint(x: r.maxX, y: r.maxY)),
            (.bottom, PixelPoint(x: r.midX, y: r.maxY)),
            (.bottomLeft, PixelPoint(x: r.minX, y: r.maxY)),
            (.left, PixelPoint(x: r.minX, y: r.midY)),
        ]
    }

    /// `slop` is the half-size, in pixels, of the square around a handle that counts as a hit.
    public func hitTest(_ p: PixelPoint, slop: Int) -> Hit {
        guard let r = rect, !r.isEmpty else { return .outside }
        for (h, c) in Self.handleCenters(of: r) where abs(p.x - c.x) <= slop && abs(p.y - c.y) <= slop {
            return .handle(h)
        }
        return r.contains(p) ? .inside : .outside
    }

    public mutating func press(at p: PixelPoint, slop: Int) {
        switch hitTest(p, slop: slop) {
        case .handle(let h):
            guard let r = rect else { return }
            phase = .resizing(h, original: r)
        case .inside:
            guard let r = rect else { return }
            phase = .moving(grabOffset: PixelPoint(x: p.x - r.x, y: p.y - r.y))
        case .outside:
            rect = nil
            phase = .dragging(anchor: clamp(p))
        }
    }

    public mutating func drag(to raw: PixelPoint) {
        let p = clamp(raw)
        switch phase {
        case .idle:
            return
        case .dragging(let anchor):
            rect = PixelRect.spanning(anchor, p)
        case .resizing(let h, let original):
            rect = Self.resize(original, handle: h, to: p)
        case .moving(let off):
            guard let r = rect else { return }
            rect = PixelRect(x: p.x - off.x, y: p.y - off.y, width: r.width, height: r.height)
                .moved(within: bounds)
        }
    }

    public mutating func release() {
        if let r = rect, r.isEmpty { rect = nil }
        phase = .idle
    }

    /// Programmatic selection (debug harness, future "last region"). Clamped to bounds.
    public mutating func set(_ r: PixelRect?) {
        rect = r.map { $0.intersection(bounds) }
        if rect?.isEmpty == true { rect = nil }
        phase = .idle
    }

    public mutating func clear() {
        rect = nil
        phase = .idle
    }

    private func clamp(_ p: PixelPoint) -> PixelPoint {
        PixelPoint(x: min(max(p.x, bounds.minX), bounds.maxX),
                   y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    static func resize(_ o: PixelRect, handle: Handle, to p: PixelPoint) -> PixelRect {
        let tl = PixelPoint(x: o.minX, y: o.minY)
        let tr = PixelPoint(x: o.maxX, y: o.minY)
        let bl = PixelPoint(x: o.minX, y: o.maxY)
        let br = PixelPoint(x: o.maxX, y: o.maxY)
        switch handle {
        case .topLeft: return .spanning(br, p)
        case .topRight: return .spanning(bl, p)
        case .bottomLeft: return .spanning(tr, p)
        case .bottomRight: return .spanning(tl, p)
        case .top: return .spanning(bl, PixelPoint(x: o.maxX, y: p.y))
        case .bottom: return .spanning(tl, PixelPoint(x: o.maxX, y: p.y))
        case .left: return .spanning(tr, PixelPoint(x: p.x, y: o.maxY))
        case .right: return .spanning(tl, PixelPoint(x: p.x, y: o.maxY))
        }
    }
}
