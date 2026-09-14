import AppKit

/// Borderless full-screen window that shows one display's frozen frame above everything else.
final class OverlayWindow: NSWindow {
    /// False in test mode so the harness never steals keyboard focus from the user.
    var allowsKey = true
    let selectionView: SelectionView

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    init(screenFrame: CGRect) {
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: screenFrame.size))
        super.init(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = selectionView
        initialFirstResponder = selectionView
    }

    override func keyDown(with event: NSEvent) {
        // Text editing gets its keys through the responder chain, not here.
        selectionView.delegate?.selectionView(selectionView, keyDown: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if selectionView.delegate?.selectionView(selectionView, keyEquivalent: event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
