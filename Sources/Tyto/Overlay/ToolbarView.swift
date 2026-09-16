import AppKit
import TytoCore

protocol ToolbarDelegate: AnyObject {
    func toolbar(_ toolbar: ToolbarView, didPick tool: Tool)
    func toolbar(_ toolbar: ToolbarView, didPick color: RGBAColor)
    func toolbar(_ toolbar: ToolbarView, didPick width: WidthPreset)
    func toolbarDidRequestUndo(_ toolbar: ToolbarView)
    func toolbarDidRequestRedo(_ toolbar: ToolbarView)
    func toolbarDidRequestSave(_ toolbar: ToolbarView)
    func toolbarDidRequestCopy(_ toolbar: ToolbarView)
    func toolbarDidRequestCancel(_ toolbar: ToolbarView)
}

/// Floating Liquid Glass tool strip shown next to the selection.
final class ToolbarView: NSView {
    weak var delegate: ToolbarDelegate?

    private let glass = NSGlassEffectView()
    private let stack = NSStackView()
    private let tools = NSSegmentedControl()
    private let colors = NSSegmentedControl()
    private let widths = NSSegmentedControl()
    private var selectedColorIndex = 0
    private var selectedWidthIndex = 1
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let saveButton = NSButton()
    private let copyButton = NSButton()
    private let cancelButton = NSButton()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true

        glass.style = .regular
        glass.effectIsInteractive = true
        glass.cornerRadius = 16

        configureSegments()

        Self.configureIconButton(undoButton, symbol: "arrow.uturn.backward", tip: "Undo (⌘Z)")
        undoButton.target = self; undoButton.action = #selector(undoTapped)
        Self.configureIconButton(redoButton, symbol: "arrow.uturn.forward", tip: "Redo (⇧⌘Z)")
        redoButton.target = self; redoButton.action = #selector(redoTapped)

        saveButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
        saveButton.bezelStyle = .glass
        saveButton.controlSize = .large
        saveButton.toolTip = "Save to file… (⌘S)"
        saveButton.target = self
        saveButton.action = #selector(saveTapped)

        copyButton.title = "Copy"
        copyButton.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Copy")
        copyButton.imagePosition = .imageLeading
        copyButton.bezelStyle = .glass
        copyButton.controlSize = .large
        copyButton.toolTip = "Copy to clipboard (⏎ or ⌘C)"
        copyButton.target = self; copyButton.action = #selector(copyTapped)

        cancelButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel")
        cancelButton.bezelStyle = .glass
        cancelButton.controlSize = .large
        cancelButton.toolTip = "Cancel (Esc)"
        cancelButton.target = self; cancelButton.action = #selector(cancelTapped)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        for v in [tools, Self.separator(), colors, Self.separator(), widths, Self.separator(),
                  undoButton, redoButton, Self.separator(), saveButton, copyButton, cancelButton] {
            stack.addArrangedSubview(v)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = stack
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var preferredSize: CGSize { stack.fittingSize }

    /// Test hook: fire the tool segment the same way a real click does (selection + action).
    func testClickTool(_ index: Int) {
        guard index >= 0, index < tools.segmentCount else { return }
        tools.selectedSegment = index
        tools.performClick(nil)
    }


    func setState(tool: Tool, color: RGBAColor, width: WidthPreset, canUndo: Bool, canRedo: Bool) {
        tools.selectedSegment = Tool.allCases.firstIndex(of: tool) ?? 0
        let colorIndex = RGBAColor.palette.firstIndex { $0.color == color } ?? 0
        if colorIndex != selectedColorIndex {
            selectedColorIndex = colorIndex
            refreshColorSwatches()
        }
        colors.selectedSegment = colorIndex
        let widthIndex = WidthPreset.allCases.firstIndex(of: width) ?? 1
        if widthIndex != selectedWidthIndex {
            selectedWidthIndex = widthIndex
            refreshWidthDots()
        }
        widths.selectedSegment = WidthPreset.allCases.firstIndex(of: width) ?? 1
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    // MARK: Building blocks

    private func configureSegments() {
        tools.segmentCount = Tool.allCases.count
        for (i, t) in Tool.allCases.enumerated() {
            tools.setImage(NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title), forSegment: i)
            tools.setToolTip("\(t.title) (\(t.key.uppercased()))", forSegment: i)
            tools.setWidth(30, forSegment: i)
        }
        tools.trackingMode = .selectOne
        tools.controlSize = .large
        // Liquid Glass draws selection very faintly; tint it so the active tool is obvious.
        tools.selectedSegmentBezelColor = .controlAccentColor
        tools.target = self; tools.action = #selector(toolChanged)

        colors.segmentCount = RGBAColor.palette.count
        for (i, entry) in RGBAColor.palette.enumerated() {
            colors.setToolTip(entry.name.capitalized, forSegment: i)
            colors.setWidth(26, forSegment: i)
        }
        refreshColorSwatches()
        colors.trackingMode = .selectOne
        colors.controlSize = .large
        colors.target = self; colors.action = #selector(colorChanged)

        widths.segmentCount = WidthPreset.allCases.count
        for (i, w) in WidthPreset.allCases.enumerated() {
            widths.setToolTip(w.rawValue.capitalized, forSegment: i)
            widths.setWidth(26, forSegment: i)
        }
        refreshWidthDots()
        widths.trackingMode = .selectOne
        widths.controlSize = .large
        widths.selectedSegmentBezelColor = .controlAccentColor
        widths.target = self; widths.action = #selector(widthChanged)
    }

    /// The selected swatch is drawn larger with a bright ring, so the active colour is legible
    /// against the glass without tinting the segment (which would distort the colour itself).
    private func refreshColorSwatches() {
        for (i, entry) in RGBAColor.palette.enumerated() {
            colors.setImage(Self.dot(color: entry.color.nsColor, diameter: i == selectedColorIndex ? 17 : 12,
                                     selected: i == selectedColorIndex), forSegment: i)
        }
    }

    /// Drawn rather than templated so the active width is a bright dot against dimmer ones.
    private func refreshWidthDots() {
        for (i, _) in WidthPreset.allCases.enumerated() {
            let selected = i == selectedWidthIndex
            widths.setImage(Self.dot(color: selected ? .white : NSColor.labelColor.withAlphaComponent(0.55),
                                     diameter: 4 + CGFloat(i) * 4), forSegment: i)
        }
    }

    private static func configureIconButton(_ b: NSButton, symbol: String, tip: String) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.bezelStyle = .glass
        b.controlSize = .large
        b.toolTip = tip
    }

    private static func separator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return v
    }

    static func dot(color: NSColor, diameter: CGFloat, selected: Bool = false) -> NSImage {
        let size = CGSize(width: 20, height: 20)
        return NSImage(size: size, flipped: false) { rect in
            let r = CGRect(x: (rect.width - diameter) / 2, y: (rect.height - diameter) / 2,
                           width: diameter, height: diameter)
            if selected {
                NSColor.white.setStroke()
                let halo = NSBezierPath(ovalIn: r.insetBy(dx: -2.5, dy: -2.5))
                halo.lineWidth = 2
                halo.stroke()
            }
            color.setFill()
            NSBezierPath(ovalIn: r).fill()
            if diameter >= 10 {   // outline only the colour swatches, not the small width dots
                NSColor.black.withAlphaComponent(selected ? 0.45 : 0.25).setStroke()
                let ring = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
                ring.lineWidth = 1
                ring.stroke()
            }
            return true
        }
    }

    // MARK: Actions

    @objc private func toolChanged() {
        delegate?.toolbar(self, didPick: Tool.allCases[tools.selectedSegment])
    }

    @objc private func colorChanged() {
        delegate?.toolbar(self, didPick: RGBAColor.palette[colors.selectedSegment].color)
    }

    @objc private func widthChanged() {
        delegate?.toolbar(self, didPick: WidthPreset.allCases[widths.selectedSegment])
    }

    @objc private func undoTapped() { delegate?.toolbarDidRequestUndo(self) }
    @objc private func redoTapped() { delegate?.toolbarDidRequestRedo(self) }
    @objc private func saveTapped() { delegate?.toolbarDidRequestSave(self) }
    @objc private func copyTapped() { delegate?.toolbarDidRequestCopy(self) }
    @objc private func cancelTapped() { delegate?.toolbarDidRequestCancel(self) }
}
