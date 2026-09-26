import AppKit
import Carbon.HIToolbox
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

    /// Single-letter keyboard shortcut while the overlay is up, as shown in the toolbar tooltip.
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

    /// The physical key for `key`. Matching on this rather than on the typed character means
    /// the shortcut follows the keycap, so it works under Cyrillic and other non-Latin layouts,
    /// where the A key types "ф" and a character comparison never fires.
    var keyCode: UInt16 {
        switch self {
        case .select: UInt16(kVK_ANSI_V)
        case .rect: UInt16(kVK_ANSI_R)
        case .ellipse: UInt16(kVK_ANSI_E)
        case .line: UInt16(kVK_ANSI_L)
        case .arrow: UInt16(kVK_ANSI_A)
        case .text: UInt16(kVK_ANSI_T)
        case .blur: UInt16(kVK_ANSI_B)
        case .badge: UInt16(kVK_ANSI_N)
        }
    }

    init?(keyCode: UInt16) {
        guard let t = Tool.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = t
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
        case .thin: 18
        case .medium: 26
        case .thick: 38
        }
    }

    func style(color: RGBAColor, scale: CGFloat) -> ShapeStyle {
        ShapeStyle(color: color, strokeWidth: Double(strokePoints * scale), fontSize: Double(fontPoints * scale))
    }
}

extension RGBAColor {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}
