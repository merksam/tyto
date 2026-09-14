import AppKit
import OwlCore
import QuartzCore

enum KeyCommand { case cancel, copy }

protocol SelectionViewDelegate: AnyObject {
    func selectionView(_ view: SelectionView, pressAt pixel: PixelPoint)
    func selectionView(_ view: SelectionView, dragTo pixel: PixelPoint)
    func selectionViewDidRelease(_ view: SelectionView)
    func selectionView(_ view: SelectionView, keyCommand: KeyCommand)
}

/// Layer-backed view showing the frozen frame, the dim mask with the selection cut out,
/// the selection border, resize handles and the size label. Nothing here redraws a bitmap:
/// every update is a CAShapeLayer path change composited by the GPU.
final class SelectionView: NSView {
    weak var delegate: SelectionViewDelegate?
    private(set) var displayID: CGDirectDisplayID = 0
    private(set) var geometry = DisplayGeometry(pointSize: .zero, scale: 1)

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let sizeLabel = CATextLayer()
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

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

        for l in [imageLayer, dimLayer, borderLayer, handlesLayer, sizeLabel] { root.addSublayer(l) }

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.isCancellableByScrollGesture = false
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
        needsLayout = true
    }

    /// Drops the frozen frame so the (large) image is released between sessions.
    func clearContents() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [imageLayer, dimLayer, borderLayer, handlesLayer] { l.frame = bounds }
        CATransaction.commit()
    }

    func render(_ model: SelectionModel?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let m = model, let r = m.rect, !r.isEmpty else {
            dimLayer.path = CGPath(rect: bounds, transform: nil)
            borderLayer.path = nil
            handlesLayer.path = nil
            sizeLabel.isHidden = true
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
}
