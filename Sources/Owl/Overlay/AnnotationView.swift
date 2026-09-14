import AppKit
import OwlCore

/// Draws the annotation document over the selection. Its frame is the selection rect in points;
/// drawing happens in display pixel space through the shared renderer, so the screen shows exactly
/// what the export will contain. Transparent to mouse events: SelectionView routes all input.
final class AnnotationView: NSView {
    var document = AnnotationDocument() { didSet { needsDisplay = true } }
    var selectedID: UUID? { didSet { needsDisplay = true } }
    var base: CGImage?
    var geometry = DisplayGeometry(pointSize: .zero, scale: 1)
    /// Display pixel coordinate of this view's top-left corner.
    var pixelOrigin = PixelPoint.zero { didSet { needsDisplay = true } }
    var drawsSelectionChrome = true

    override var isFlipped: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        let s = geometry.scale
        ctx.scaleBy(x: 1 / s, y: 1 / s)
        ctx.translateBy(x: CGFloat(-pixelOrigin.x), y: CGFloat(-pixelOrigin.y))
        let options = RenderOptions(pixelScale: Double(s), selectedID: selectedID, drawSelectionChrome: drawsSelectionChrome)
        AnnotationRenderer.draw(document, into: ctx, base: base, options: options)
        ctx.restoreGState()
    }
}
