import AppKit

/// The menu bar owl: the app icon's face as a template image, so macOS tints it for light and
/// dark menu bars and for the pressed state. Drawn rather than shipped as a PNG so it is crisp
/// at every scale and there is one source of truth for the shape.
enum OwlGlyph {
    /// A barn owl's facial disc is heart-shaped: two lobes at the top, a point at the bottom,
    /// eyes in the lobes and a small beak between them. Eyes and beak are holes in the fill
    /// (even-odd), which is what reads as a face at 18 points.
    static func path(in size: CGFloat) -> NSBezierPath {
        let s = size / 18  // designed on an 18-point grid
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }

        let p = NSBezierPath()
        p.windingRule = .evenOdd
        // Face, clockwise from the bottom point.
        p.move(to: pt(9, 1.6))
        p.curve(to: pt(1.6, 10.6), controlPoint1: pt(4.6, 4.2), controlPoint2: pt(1.6, 7.0))
        p.curve(to: pt(9, 13.4), controlPoint1: pt(1.6, 15.2), controlPoint2: pt(6.4, 16.6))
        p.curve(to: pt(16.4, 10.6), controlPoint1: pt(11.6, 16.6), controlPoint2: pt(16.4, 15.2))
        p.curve(to: pt(9, 1.6), controlPoint1: pt(16.4, 7.0), controlPoint2: pt(13.4, 4.2))
        p.close()
        // Eyes. Generous on purpose: at 18 points they are what makes this a face and not a heart.
        let r: CGFloat = 2.45
        for cx in [5.6, 12.4] as [CGFloat] {
            p.appendOval(in: NSRect(x: (cx - r) * s, y: (10.4 - r) * s, width: 2 * r * s, height: 2 * r * s))
        }
        // Beak: a small downward triangle between the eyes.
        p.move(to: pt(7.8, 7.9))
        p.line(to: pt(10.2, 7.9))
        p.line(to: pt(9, 5.6))
        p.close()
        return p
    }

    static func image(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { _ in
            NSColor.black.setFill()
            path(in: pointSize).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
