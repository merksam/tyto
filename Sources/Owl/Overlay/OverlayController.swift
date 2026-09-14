import AppKit
import OwlCore

struct SessionOptions: Sendable {
    /// nil = every display.
    var displayIDs: [CGDirectDisplayID]? = nil
    /// Interactive: activate the app, make a window key, hide hot corners, show a crosshair.
    /// Test mode turns all of that off so the harness never disturbs the user.
    var interactive = true

    static let interactive = SessionOptions()
}

enum SessionOutcome: Sendable {
    case copied(rect: PixelRect, displayID: CGDirectDisplayID)
    case cancelled
}

/// Owns one overlay window per display and the selection state of the current session.
final class OverlayController: SelectionViewDelegate {
    struct Session {
        let options: SessionOptions
        var snapshots: [CGDirectDisplayID: DisplaySnapshot] = [:]
        var order: [CGDirectDisplayID] = []
        var activeDisplay: CGDirectDisplayID?
        var selection: SelectionModel?
        var previousApp: NSRunningApplication?
        var previousPresentation: NSApplication.PresentationOptions = []
        var cursorPushed = false
    }

    private let capturer: ScreenCapturer
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private(set) var session: Session?
    private(set) var lastTimings = CaptureTimings()
    var onSessionEnd: ((SessionOutcome) -> Void)?

    init(capturer: ScreenCapturer) {
        self.capturer = capturer
    }

    var isActive: Bool { session != nil }

    // MARK: Session lifecycle

    func beginSession(options: SessionOptions) async throws {
        guard session == nil else { throw OwlError.sessionAlreadyActive }
        let start = ContinuousClock.now
        var timings = CaptureTimings()
        timings.requestedAt = Date()

        guard Permissions.hasScreenCapture else { throw OwlError.noScreenCapturePermission }
        let all = capturer.displays()
        let wanted = options.displayIDs.map { ids in all.filter { ids.contains($0.id) } } ?? all
        guard !wanted.isEmpty else { throw OwlError.noDisplays }

        // Capture first, before any UI work, so the frame is exactly what was on screen at the hotkey.
        let snapshots = try await capturer.capture(displays: wanted)
        timings.captureMS = (ContinuousClock.now - start).milliseconds
        timings.displays = snapshots.count

        var s = Session(options: options)
        s.order = wanted.map(\.id)
        s.previousApp = NSWorkspace.shared.frontmostApplication
        s.previousPresentation = NSApp.presentationOptions
        for snap in snapshots {
            let window = windows[snap.displayID] ?? OverlayWindow(screenFrame: snap.screenFrame)
            windows[snap.displayID] = window
            window.allowsKey = options.interactive
            window.setFrame(snap.screenFrame, display: false)
            window.selectionView.frame = CGRect(origin: .zero, size: snap.screenFrame.size)
            window.selectionView.configure(snapshot: snap, delegate: self)
            window.selectionView.render(nil)
            window.orderFrontRegardless()
            s.snapshots[snap.displayID] = snap
        }
        session = s

        if options.interactive {
            NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar, .disableScreenCornerInteractions]
            NSApp.activate()
            if !NSApp.isActive {
                // Cooperative activation can be refused; without key status Esc would never arrive.
                NSApp.activate(ignoringOtherApps: true)
            }
            let mouse = NSEvent.mouseLocation
            let keyWindow = s.order.compactMap { windows[$0] }.first { $0.frame.contains(mouse) }
                ?? s.order.first.flatMap { windows[$0] }
            keyWindow?.makeKeyAndOrderFront(nil)
            NSCursor.crosshair.push()
            session?.cursorPushed = true
        }

        for id in s.order { windows[id]?.displayIfNeeded() }
        CATransaction.flush()
        timings.overlayMS = (ContinuousClock.now - start).milliseconds
        lastTimings = timings
        Log.overlay.info("overlay up on \(s.order.count) display(s): capture \(timings.captureMS ?? 0, format: .fixed(precision: 1)) ms, total \(timings.overlayMS ?? 0, format: .fixed(precision: 1)) ms")
    }

    func cancel() {
        end(.cancelled)
    }

    /// Crops the active selection out of the frozen frame, writes it to the clipboard and ends the session.
    @discardableResult
    func copy() throws -> (rect: PixelRect, image: CGImage) {
        guard let s = session else { throw OwlError.noSession }
        guard let id = s.activeDisplay, let rect = s.selection?.rect, !rect.isEmpty,
              let snap = s.snapshots[id] else { throw OwlError.noSelection }
        guard let cropped = snap.image.cropping(to: rect.cgRect) else { throw OwlError.cropFailed }
        let start = ContinuousClock.now
        try Clipboard.write(image: cropped)
        lastTimings.copyMS = (ContinuousClock.now - start).milliseconds
        Log.overlay.info("copied \(cropped.width)x\(cropped.height) in \(self.lastTimings.copyMS ?? 0, format: .fixed(precision: 1)) ms")
        end(.copied(rect: rect, displayID: id))
        return (rect, cropped)
    }

    /// Programmatic selection for the test harness (and future "re-select last region").
    func setSelection(_ rect: PixelRect, on displayID: CGDirectDisplayID?) throws {
        guard var s = session else { throw OwlError.noSession }
        guard let id = displayID ?? s.activeDisplay ?? s.order.first,
              let snap = s.snapshots[id] else { throw OwlError.unknownDisplay("\(String(describing: displayID))") }
        var model = SelectionModel(bounds: snap.geometry.pixelBounds)
        model.set(rect)
        s.activeDisplay = id
        s.selection = model
        session = s
        renderAll()
    }

    private func end(_ outcome: SessionOutcome) {
        guard let s = session else { return }
        for id in s.order {
            guard let w = windows[id] else { continue }
            w.orderOut(nil)
            w.selectionView.clearContents()
        }
        if s.options.interactive {
            NSApp.presentationOptions = s.previousPresentation
            if s.cursorPushed { NSCursor.pop() }
            // Hand focus back so the user can ⌘V straight away.
            s.previousApp?.activate()
        }
        session = nil
        onSessionEnd?(outcome)
    }

    private func renderAll() {
        guard let s = session else { return }
        for id in s.order {
            windows[id]?.selectionView.render(id == s.activeDisplay ? s.selection : nil)
        }
    }

    private func renderActive() {
        guard let s = session, let id = s.activeDisplay else { return }
        windows[id]?.selectionView.render(s.selection)
    }

    // MARK: SelectionViewDelegate

    func selectionView(_ view: SelectionView, pressAt pixel: PixelPoint) {
        guard var s = session else { return }
        let id = view.displayID
        if s.activeDisplay != id || s.selection == nil {
            s.activeDisplay = id
            s.selection = SelectionModel(bounds: view.geometry.pixelBounds)
        }
        let slop = Int((SelectionView.handleSlopPoints * view.geometry.scale).rounded())
        s.selection?.press(at: pixel, slop: slop)
        session = s
        renderAll()
    }

    func selectionView(_ view: SelectionView, dragTo pixel: PixelPoint) {
        guard session?.activeDisplay == view.displayID else { return }
        session?.selection?.drag(to: pixel)
        renderActive()
    }

    func selectionViewDidRelease(_ view: SelectionView) {
        guard session?.activeDisplay == view.displayID else { return }
        session?.selection?.release()
        renderActive()
    }

    func selectionView(_ view: SelectionView, keyCommand: KeyCommand) {
        switch keyCommand {
        case .cancel:
            cancel()
        case .copy:
            do { try copy() } catch { Log.overlay.error("copy failed: \(String(describing: error))") }
        }
    }
}
