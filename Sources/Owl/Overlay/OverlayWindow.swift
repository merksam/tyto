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
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            selectionView.delegate?.selectionView(selectionView, keyCommand: .cancel)
        case 36, 76: // Return, keypad Enter
            selectionView.delegate?.selectionView(selectionView, keyCommand: .copy)
        default:
            break // swallow; no beep
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers == "c" {
            selectionView.delegate?.selectionView(selectionView, keyCommand: .copy)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
