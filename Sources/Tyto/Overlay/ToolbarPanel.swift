import AppKit

/// Floating, non-activating panel that hosts the annotation toolbar.
///
/// The toolbar lives in its own window, not inside the SelectionView, so its controls get normal
/// AppKit mouse tracking instead of competing with the canvas pan/click gesture recognizers. A
/// non-activating panel never becomes key, so the overlay window keeps keyboard focus for Esc,
/// Enter and the tool shortcuts while the toolbar's buttons still respond to clicks.
final class ToolbarPanel: NSPanel {
    let annotationToolbar = ToolbarView(frame: .zero)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 320, height: 44),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let container = NSView(frame: CGRect(origin: .zero, size: CGSize(width: 320, height: 44)))
        container.addSubview(annotationToolbar)
        contentView = container
    }

    var preferredSize: CGSize { annotationToolbar.preferredSize }

    func layoutToolbar() {
        let size = annotationToolbar.preferredSize
        annotationToolbar.frame = CGRect(origin: .zero, size: size)
        contentView?.frame = CGRect(origin: .zero, size: size)
    }
}
