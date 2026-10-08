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

    init?(key: Character) {
        guard let t = Tool.allCases.first(where: { $0.key == String(key) }) else { return nil }
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

/// The QWERTY letter on each physical letter key, for layouts whose keycaps are not Latin.
enum LatinKeyCodes {
    private static let table: [UInt16: Character] = [
        UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_C): "c", UInt16(kVK_ANSI_D): "d",
        UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_F): "f", UInt16(kVK_ANSI_G): "g", UInt16(kVK_ANSI_H): "h",
        UInt16(kVK_ANSI_I): "i", UInt16(kVK_ANSI_J): "j", UInt16(kVK_ANSI_K): "k", UInt16(kVK_ANSI_L): "l",
        UInt16(kVK_ANSI_M): "m", UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_O): "o", UInt16(kVK_ANSI_P): "p",
        UInt16(kVK_ANSI_Q): "q", UInt16(kVK_ANSI_R): "r", UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_T): "t",
        UInt16(kVK_ANSI_U): "u", UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_W): "w", UInt16(kVK_ANSI_X): "x",
        UInt16(kVK_ANSI_Y): "y", UInt16(kVK_ANSI_Z): "z",
    ]
    static func letter(for code: UInt16) -> Character? { table[code] }
}

extension NSEvent {
    /// The Latin letter this key press stands for, on any keyboard layout.
    ///
    /// The typed character wins when it is a Latin letter, so the shortcut follows the keycap on
    /// QWERTY, AZERTY, Dvorak and the rest. Only when the layout types something else — the A
    /// key under Cyrillic gives "ф" — does the physical key's QWERTY letter stand in. Matching
    /// on the key code alone was wrong the other way round: it broke every Latin layout whose
    /// letters sit in different places.
    var latinKey: Character? {
        if let s = charactersIgnoringModifiers?.lowercased(), s.count == 1, let c = s.first,
           c.isASCII, c.isLetter {
            return c
        }
        return LatinKeyCodes.letter(for: keyCode)
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
