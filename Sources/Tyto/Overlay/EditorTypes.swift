import AppKit
import TytoCore

enum Tool: String, CaseIterable, Sendable {
    case select, rect, ellipse, line, arrow, text, blur, badge

    var title: String {
        switch self {
        case .select: "Select"
        case .rect: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .arrow: "Arrow"
        case .text: "Text"
        case .blur: "Blur"
        case .badge: "Number"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .text: "textformat"
        case .blur: "square.grid.3x3.fill"
        case .badge: "1.circle"
        }
    }

    /// Single-letter keyboard shortcut while the overlay is up.
    var key: String {
        switch self {
        case .select: "v"
        case .rect: "r"
        case .ellipse: "e"
        case .line: "l"
        case .arrow: "a"
        case .text: "t"
        case .blur: "b"
        case .badge: "n"
        }
    }

    var shapeKind: ShapeKind? {
        switch self {
        case .select: nil
        case .rect: .rect
        case .ellipse: .ellipse
        case .line: .line
        case .arrow: .arrow
        case .text: .text
        case .blur: .blur
        case .badge: .badge
        }
    }
}

enum WidthPreset: String, CaseIterable, Sendable {
    case thin, medium, thick

    var strokePoints: CGFloat {
        switch self {
        case .thin: 6
        case .medium: 12
        case .thick: 21
        }
    }

    var fontPoints: CGFloat {
        switch self {
        case .thin: 14
        case .medium: 18
        case .thick: 26
        }
    }

    func style(color: RGBAColor, scale: CGFloat) -> ShapeStyle {
        ShapeStyle(color: color, strokeWidth: Double(strokePoints * scale), fontSize: Double(fontPoints * scale))
    }
}

extension RGBAColor {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}
