import AppKit

/// Inline text editor for the text tool. Return commits, Shift+Return inserts a newline, Esc cancels.
final class AnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    static func make(at origin: CGPoint, maxWidth: CGFloat, font: NSFont, color: NSColor) -> AnnotationTextView {
        let container = NSTextContainer(size: CGSize(width: maxWidth, height: 100_000))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)

        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let tv = AnnotationTextView(frame: CGRect(x: origin.x, y: origin.y, width: 20, height: lineHeight),
                                    textContainer: container)
        tv.isRichText = false
        tv.isFieldEditor = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.font = font
        tv.textColor = color
        tv.insertionPointColor = color
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.minSize = CGSize(width: 20, height: lineHeight)
        tv.maxSize = CGSize(width: maxWidth, height: 100_000)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.wantsLayer = true
        // A faint outline so the editor is visible on any background.
        tv.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        tv.layer?.borderWidth = 1
        tv.layer?.cornerRadius = 2
        tv.layer?.shadowColor = NSColor.black.cgColor
        tv.layer?.shadowOpacity = 0.9
        tv.layer?.shadowRadius = 1
        tv.layer?.shadowOffset = .zero
        return tv
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                super.insertNewline(nil)
            } else {
                onCommit?()
            }
            return
        }
        if selector == #selector(cancelOperation(_:)) {
            onCancel?()
            return
        }
        super.doCommand(by: selector)
    }
}
