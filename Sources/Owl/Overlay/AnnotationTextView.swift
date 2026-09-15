import AppKit
import OwlCore

/// Inline text editor for the text tool. Return commits, Shift+Return inserts a newline, Esc cancels.
final class AnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    static func make(at origin: CGPoint, maxWidth: CGFloat, font: NSFont, color: NSColor,
                     haloSource: RGBAColor) -> AnnotationTextView {
        let container = NSTextContainer(size: CGSize(width: maxWidth, height: 100_000))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)

        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        // Match the renderer's glyph inset so the text does not shift when it is committed.
        let pad = CGFloat(AnnotationRenderer.textPadding(fontSize: Double(font.pointSize)))
        let tv = AnnotationTextView(frame: CGRect(x: origin.x, y: origin.y,
                                                  width: 20 + 2 * pad, height: lineHeight + 2 * pad),
                                    textContainer: container)
        tv.isRichText = false
        tv.isFieldEditor = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = CGSize(width: pad, height: pad)
        tv.font = font
        tv.textColor = color
        tv.insertionPointColor = color
        // Same halo the renderer draws, so weight and legibility look identical while typing.
        let halo = NSShadow()
        halo.shadowColor = NSColor(cgColor: AnnotationRenderer.haloColor(for: haloSource))
        halo.shadowBlurRadius = CGFloat(AnnotationRenderer.haloBlur(fontSize: Double(font.pointSize)))
        halo.shadowOffset = .zero
        tv.typingAttributes = [.font: font, .foregroundColor: color, .shadow: halo]
        tv.defaultParagraphStyle = nil
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.minSize = CGSize(width: 20 + 2 * pad, height: lineHeight + 2 * pad)
        tv.maxSize = CGSize(width: maxWidth, height: 100_000)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.wantsLayer = true
        // A faint frame marks the editing box; the text itself carries the halo, so the view
        // gets no layer shadow (that would double up on the text and read as extra weight).
        tv.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        tv.layer?.borderWidth = 1
        tv.layer?.cornerRadius = 2
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
