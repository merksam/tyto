// Full-screen backdrop for staging App Store screenshots.
//
// Screenshots of a screenshot tool need something to capture. Rather than photograph the
// user's real desktop (which can never be published), this paints a controlled scene on a
// chosen display: a desktop gradient with a mock document window on top. Tyto's own UI in
// the resulting shots is entirely real; only the thing being captured is a prop.
//
// usage: swift scripts/stage.swift [main|secondary]   (Esc or SIGINT to quit)
import AppKit

final class StageView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds

        // Desktop: deep blue-violet gradient with a soft light source, like a default wallpaper.
        let grad = NSGradient(colors: [
            NSColor(srgbRed: 0.16, green: 0.20, blue: 0.38, alpha: 1),
            NSColor(srgbRed: 0.09, green: 0.11, blue: 0.22, alpha: 1),
            NSColor(srgbRed: 0.05, green: 0.06, blue: 0.13, alpha: 1),
        ])!
        grad.draw(in: b, angle: -80)
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let glow = NSGradient(colors: [NSColor(white: 1, alpha: 0.10), NSColor(white: 1, alpha: 0)])!
        glow.draw(in: CGRect(x: b.width * 0.42, y: -b.height * 0.25, width: b.width * 0.6, height: b.height * 0.8),
                  relativeCenterPosition: .zero)
        ctx.restoreGState()

        // Document window, centred, 16:10-ish so it sits nicely in a cropped screenshot.
        let w = b.width * 0.62, h = b.height * 0.66
        let win = CGRect(x: (b.width - w) / 2, y: (b.height - h) / 2 - b.height * 0.02, width: w, height: h)
        let radius = min(w, h) * 0.022

        NSColor(white: 0, alpha: 0.35).setFill()
        NSBezierPath(roundedRect: win.offsetBy(dx: 0, dy: h * 0.012).insetBy(dx: -w * 0.004, dy: -h * 0.004),
                     xRadius: radius, yRadius: radius).fill()
        NSColor(srgbRed: 0.99, green: 0.99, blue: 0.985, alpha: 1).setFill()
        let winPath = NSBezierPath(roundedRect: win, xRadius: radius, yRadius: radius)
        winPath.fill()

        // Title bar with traffic lights.
        ctx.saveGState()
        winPath.addClip()
        let barH = h * 0.075
        NSColor(srgbRed: 0.95, green: 0.95, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: win.minX, y: win.minY, width: w, height: barH)).fill()
        NSColor(white: 0.82, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: win.minX, y: win.minY + barH - 1, width: w, height: 1)).fill()
        let dot = barH * 0.26
        for (i, c) in [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                       NSColor(srgbRed: 1, green: 0.74, blue: 0.19, alpha: 1),
                       NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: CGRect(x: win.minX + barH * 0.55 + CGFloat(i) * dot * 1.9,
                                        y: win.minY + (barH - dot) / 2, width: dot, height: dot)).fill()
        }
        text("Quarterly Report", at: CGPoint(x: win.midX, y: win.minY + barH * 0.5), size: barH * 0.40,
             weight: .semibold, color: NSColor(white: 0.35, alpha: 1), centred: true)

        // Body: heading, paragraphs, a small bar chart and a details row worth annotating.
        let pad = w * 0.07
        var y = win.minY + barH + h * 0.075
        text("Engineering throughput", at: CGPoint(x: win.minX + pad, y: y), size: h * 0.034,
             weight: .bold, color: NSColor(white: 0.12, alpha: 1))
        y += h * 0.060
        for line in ["Deployment frequency rose to 24 per week this quarter, up from 9.",
                     "Median review time fell by half. The remaining bottleneck is the",
                     "staging queue, which still serialises every integration run."] {
            text(line, at: CGPoint(x: win.minX + pad, y: y), size: h * 0.021,
                 weight: .regular, color: NSColor(white: 0.32, alpha: 1))
            y += h * 0.036
        }

        y += h * 0.03
        let chartH = h * 0.30, chartW = w - pad * 2
        let values: [CGFloat] = [0.35, 0.48, 0.42, 0.66, 0.71, 0.94]
        let barW = chartW / CGFloat(values.count) * 0.52
        for (i, v) in values.enumerated() {
            let x = win.minX + pad + chartW / CGFloat(values.count) * (CGFloat(i) + 0.24)
            let bh = chartH * v
            let c = i == values.count - 1
                ? NSColor(srgbRed: 0.20, green: 0.52, blue: 0.96, alpha: 1)
                : NSColor(srgbRed: 0.76, green: 0.82, blue: 0.90, alpha: 1)
            c.setFill()
            NSBezierPath(roundedRect: CGRect(x: x, y: y + chartH - bh, width: barW, height: bh),
                         xRadius: barW * 0.18, yRadius: barW * 0.18).fill()
        }
        y += chartH + h * 0.05
        NSColor(white: 0.90, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: win.minX + pad, y: y, width: chartW, height: 1)).fill()
        y += h * 0.045
        text("Owner   a.kovalenko@example.com", at: CGPoint(x: win.minX + pad, y: y), size: h * 0.020,
             weight: .regular, color: NSColor(white: 0.40, alpha: 1))
        ctx.restoreGState()
    }

    private func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight,
                      color: NSColor, centred: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        ]
        let str = NSAttributedString(string: s, attributes: attrs)
        let sz = str.size()
        str.draw(at: CGPoint(x: centred ? p.x - sz.width / 2 : p.x, y: p.y - (centred ? sz.height / 2 : 0)))
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ n: Notification) {
        let wantSecondary = CommandLine.arguments.dropFirst().first != "main"
        let screens = NSScreen.screens
        let screen = (wantSecondary ? screens.first(where: { $0 != screens.first }) : screens.first)
            ?? screens[0]
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // Above the menu bar and every ordinary window, but below Tyto's overlay
        // (.screenSaver, 1000), so nothing of the user's real screen leaks into a shot.
        w.level = NSWindow.Level(rawValue: 900)
        w.isOpaque = true
        w.hasShadow = false
        w.ignoresMouseEvents = true          // never traps the pointer
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.contentView = StageView(frame: CGRect(origin: .zero, size: screen.frame.size))
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
        FileHandle.standardError.write(Data("stage up on \(screen.localizedName)\n".utf8))
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
