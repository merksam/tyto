import AppKit

/// A short note at the bottom of the screen about a send. The overlay is gone by the time a
/// send finishes, so this stands on its own: where it went and what is on the clipboard now,
/// or why it failed. It never takes a click or focus.
@MainActor final class SendHUD {
    enum Style { case progress, success, failure }

    private let panel: NSPanel
    private let glass = NSGlassEffectView()
    private let stack = NSStackView()
    private let icon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let label = NSTextField(wrappingLabelWithString: "")
    private var serial = 0

    /// The last message shown, for the debug harness.
    private(set) var lastMessage: String?

    init() {
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 300, height: 44),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        // Above the overlay, which sits at the screen saver level, so a "no destination" note
        // shows while it is still up.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        spinner.style = .spinning
        spinner.controlSize = .small
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byTruncatingMiddle
        label.preferredMaxLayoutWidth = 380

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 16)
        for v in [spinner, icon, label] { stack.addArrangedSubview(v) }
        glass.style = .regular
        glass.cornerRadius = 14
        glass.contentView = stack
        panel.contentView = glass
    }

    func show(_ text: String, style: Style) {
        serial += 1
        lastMessage = text
        label.stringValue = text
        spinner.isHidden = style != .progress
        icon.isHidden = style == .progress
        if style == .progress { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        switch style {
        case .progress: break
        case .success:
            icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Sent")
            icon.contentTintColor = .systemGreen
        case .failure:
            icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Failed")
            icon.contentTintColor = .systemOrange
        }

        let size = stack.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(CGRect(x: (visible.midX - size.width / 2).rounded(), y: visible.minY + 96,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        // A progress note stays until the outcome replaces it; the runner gives up after 60 s.
        let seconds: Double? = switch style {
        case .progress: nil
        case .success: 2.5
        case .failure: 6
        }
        guard let seconds else { return }
        let shown = serial
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.serial == shown else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.serial == shown else { return }
                    self.panel.orderOut(nil)
                }
            })
        }
    }
}
