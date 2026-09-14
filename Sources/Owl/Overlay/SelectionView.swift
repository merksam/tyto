import AppKit
import OwlCore
import QuartzCore

protocol SelectionViewDelegate: AnyObject {
    func selectionView(_ view: SelectionView, pressAt pixel: PixelPoint)
    func selectionView(_ view: SelectionView, dragTo pixel: PixelPoint)
    func selectionViewDidRelease(_ view: SelectionView)
    func selectionView(_ view: SelectionView, clickAt pixel: PixelPoint)
    func selectionView(_ view: SelectionView, keyDown event: NSEvent)
    func selectionView(_ view: SelectionView, keyEquivalent event: NSEvent) -> Bool
    func selectionView(_ view: SelectionView, commitText text: String, at pixel: PixelPoint)
}

/// Layer-backed view showing the frozen frame, the dim mask with the selection cut out,
/// the selection border, resize handles and the size label, plus the annotation view,
/// the floating toolbar and the inline text editor. Nothing here redraws a bitmap for the
/// region chrome: every update is a CAShapeLayer path change composited by the GPU.
final class SelectionView: NSView, NSGestureRecognizerDelegate {
    weak var delegate: SelectionViewDelegate?
    private(set) var displayID: CGDirectDisplayID = 0
    private(set) var geometry = DisplayGeometry(pointSize: .zero, scale: 1)

    let annotationView = AnnotationView(frame: .zero)

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let sizeLabel = CATextLayer()
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    private var textEditor: AnnotationTextView?
    private var textEditorPixelOrigin = PixelPoint.zero

    static let handleSizePoints: CGFloat = 8
    static let handleSlopPoints: CGFloat = 6

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let root = layer else { return }
        root.backgroundColor = NSColor.black.cgColor

        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .nearest
        imageLayer.minificationFilter = .linear

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1

        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        handlesLayer.lineWidth = 1

        sizeLabel.font = labelFont
        sizeLabel.fontSize = labelFont.pointSize
        sizeLabel.foregroundColor = NSColor.white.cgColor
        sizeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        sizeLabel.cornerRadius = 4
        sizeLabel.alignmentMode = .center
        sizeLabel.isHidden = true

        // Order matters: image, then annotations (a subview, so its layer sits above imageLayer
        // but below the chrome layers added afterwards), then dim/border/handles/label.
        root.addSublayer(imageLayer)
        annotationView.isHidden = true
        addSubview(annotationView)
        for l in [dimLayer, borderLayer, handlesLayer, sizeLabel] { root.addSublayer(l) }

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.isCancellableByScrollGesture = false
        pan.delegate = self
        addGestureRecognizer(pan)
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        click.delegate = self
        addGestureRecognizer(click)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Session content

    func configure(snapshot: DisplaySnapshot, delegate: SelectionViewDelegate) {
        self.delegate = delegate
        displayID = snapshot.displayID
        geometry = snapshot.geometry
        let scale = snapshot.geometry.scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [imageLayer, dimLayer, borderLayer, handlesLayer, sizeLabel] { l.contentsScale = scale }
        imageLayer.contents = snapshot.image
        CATransaction.commit()
        annotationView.base = snapshot.image
        annotationView.geometry = snapshot.geometry
        needsLayout = true
    }

    /// Drops the frozen frame so the (large) image is released between sessions.
    func clearContents() {
        cancelTextEditing()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        CATransaction.commit()
        annotationView.base = nil
        annotationView.document = AnnotationDocument()
        annotationView.isHidden = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [imageLayer, dimLayer, borderLayer, handlesLayer] { l.frame = bounds }
        CATransaction.commit()
    }

    // MARK: Rendering

    struct RenderState {
        var selection: SelectionModel?
        var document = AnnotationDocument()
        var showToolbar = false
        var tool: Tool = .rect
        var color: RGBAColor = .red
        var width: WidthPreset = .medium
        var canUndo = false
        var canRedo = false
    }

    func render(_ state: RenderState) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let m = state.selection, let r = m.rect, !r.isEmpty else {
            dimLayer.path = CGPath(rect: bounds, transform: nil)
            borderLayer.path = nil
            handlesLayer.path = nil
            sizeLabel.isHidden = true
            annotationView.isHidden = true
            return
        }

        let pr = geometry.rect(fromPixelRect: r)
        let dim = CGMutablePath()
        dim.addRect(bounds)
        dim.addRect(pr)
        dimLayer.path = dim
        borderLayer.path = CGPath(rect: pr.insetBy(dx: -0.5, dy: -0.5), transform: nil)

        var showHandles = true
        if case .dragging = m.phase { showHandles = false }
        if showHandles {
            let hs = Self.handleSizePoints
            let path = CGMutablePath()
            for (_, c) in SelectionModel.handleCenters(of: r) {
                let p = geometry.point(fromPixel: c)
                path.addRect(CGRect(x: p.x - hs / 2, y: p.y - hs / 2, width: hs, height: hs))
            }
            handlesLayer.path = path
        } else {
            handlesLayer.path = nil
        }

        let text = "\(r.width) × \(r.height)"
        let textSize = (text as NSString).size(withAttributes: [.font: labelFont])
        let w = ceil(textSize.width) + 12, h: CGFloat = 20
        var x = pr.minX, y = pr.minY - 6 - h
        if y < 4 { y = min(pr.minY + 6, bounds.height - h - 4) }
        x = min(max(x, 4), bounds.width - w - 4)
        sizeLabel.string = text
        sizeLabel.frame = CGRect(x: x, y: y, width: w, height: h)
        sizeLabel.isHidden = false

        annotationView.frame = pr
        annotationView.pixelOrigin = r.origin
        annotationView.document = state.document
        annotationView.selectedID = state.document.selectedID
        annotationView.isHidden = false
    }

    /// Desired toolbar frame in this view's flipped coordinates, or nil to hide it.
    func toolbarRect(for selection: SelectionModel, size: CGSize) -> CGRect? {
        guard let r = selection.rect, !r.isEmpty, selection.phase == .idle else { return nil }
        let pr = geometry.rect(fromPixelRect: r)
        var tx = pr.minX, ty = pr.maxY + 10
        if ty + size.height > bounds.height - 6 { ty = pr.minY - 10 - size.height }
        if ty < 6 { ty = pr.maxY - 10 - size.height }
        tx = min(max(tx, 6), bounds.width - size.width - 6)
        return CGRect(x: tx, y: ty, width: size.width, height: size.height)
    }

    // MARK: Text editing

    var isEditingText: Bool { textEditor != nil }

    func beginTextEditing(at pixel: PixelPoint, maxPixelX: Int, fontPoints: CGFloat, color: NSColor) {
        cancelTextEditing()
        let origin = geometry.point(fromPixel: pixel)
        let maxWidth = max(40, CGFloat(maxPixelX - pixel.x) / geometry.scale)
        let font = NSFont.boldSystemFont(ofSize: fontPoints)
        let tv = AnnotationTextView.make(at: origin, maxWidth: maxWidth, font: font, color: color)
        tv.onCommit = { [weak self] in self?.commitTextEditing() }
        tv.onCancel = { [weak self] in self?.cancelTextEditing() }
        addSubview(tv)
        textEditor = tv
        textEditorPixelOrigin = pixel
        window?.makeFirstResponder(tv)
    }

    func commitTextEditing() {
        guard let tv = textEditor else { return }
        let text = tv.string
        let origin = textEditorPixelOrigin
        tv.removeFromSuperview()
        textEditor = nil
        window?.makeFirstResponder(self)
        delegate?.selectionView(self, commitText: text, at: origin)
    }

    func cancelTextEditing() {
        guard let tv = textEditor else { return }
        tv.removeFromSuperview()
        textEditor = nil
        window?.makeFirstResponder(self)
    }

    // MARK: Input

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        if let tv = textEditor, tv.frame.contains(p) { return false }
        return true
    }

    @objc private func handlePan(_ g: NSPanGestureRecognizer) {
        let loc = g.location(in: self)
        switch g.state {
        case .began:
            // The recognizer begins after a movement threshold; recover the mouse-down point.
            let t = g.translation(in: self)
            let origin = CGPoint(x: loc.x - t.x, y: loc.y - t.y)
            delegate?.selectionView(self, pressAt: geometry.pixel(fromPoint: origin))
            delegate?.selectionView(self, dragTo: geometry.pixel(fromPoint: loc))
        case .changed:
            delegate?.selectionView(self, dragTo: geometry.pixel(fromPoint: loc))
        case .ended, .cancelled, .failed:
            delegate?.selectionView(self, dragTo: geometry.pixel(fromPoint: loc))
            delegate?.selectionViewDidRelease(self)
        default:
            break
        }
    }

    @objc private func handleClick(_ g: NSClickGestureRecognizer) {
        guard g.state == .ended else { return }
        delegate?.selectionView(self, clickAt: geometry.pixel(fromPoint: g.location(in: self)))
    }
}
