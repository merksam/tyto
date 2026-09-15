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
    case saved(URL)
    case cancelled
}

/// Owns one overlay window per display, the region selection and the annotation editor state
/// of the current session. All input, from the views and from the debug harness, funnels through
/// `press/drag/release/click` so both paths exercise the same logic.
final class OverlayController: SelectionViewDelegate, ToolbarDelegate {
    enum DragMode {
        case none
        case region
        case drawing(UUID)
        case movingShape(UUID, last: PixelPoint, recorded: Bool)
    }

    struct Session {
        let options: SessionOptions
        var snapshots: [CGDirectDisplayID: DisplaySnapshot] = [:]
        var order: [CGDirectDisplayID] = []
        var activeDisplay: CGDirectDisplayID?
        var selection: SelectionModel?
        var windowRects: [CGDirectDisplayID: [PixelRect]] = [:]
        var hoverRect: PixelRect?
        var document = AnnotationDocument()
        var history = History<AnnotationDocument>()
        var dragMode: DragMode = .none
        var previousApp: NSRunningApplication?
        var previousPresentation: NSApplication.PresentationOptions = []
        var cursorPushed = false
    }

    private let capturer: ScreenCapturer
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private let toolbarPanel = ToolbarPanel()
    private var sessionSerial = 0
    private(set) var session: Session?
    private(set) var lastTimings = CaptureTimings()
    var onSessionEnd: ((SessionOutcome) -> Void)?

    private(set) var tool: Tool = Settings.defaultTool
    private(set) var color: RGBAColor = Settings.defaultColor
    private(set) var width: WidthPreset = Settings.defaultWidth

    init(capturer: ScreenCapturer) {
        self.capturer = capturer
        toolbarPanel.annotationToolbar.delegate = self
    }

    var isActive: Bool { session != nil }

    // MARK: Session lifecycle

    func beginSession(options: SessionOptions) async throws {
        guard session == nil else { throw OwlError.sessionAlreadyActive }
        // Every capture starts from the configured defaults (colour, tool, width).
        tool = Settings.defaultTool
        color = Settings.defaultColor
        width = Settings.defaultWidth
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
            // Test mode never takes key focus, so Esc cannot reach it; make sure it also cannot
            // swallow clicks, otherwise a leftover overlay looks like a frozen screen.
            window.ignoresMouseEvents = !options.interactive
            window.setFrame(snap.screenFrame, display: false)
            window.selectionView.frame = CGRect(origin: .zero, size: snap.screenFrame.size)
            window.selectionView.configure(snapshot: snap, delegate: self)
            window.selectionView.annotationView.drawsSelectionChrome = true
            window.selectionView.render(SelectionView.RenderState())
            window.orderFrontRegardless()
            s.snapshots[snap.displayID] = snap
        }
        for d in wanted { s.windowRects[d.id] = capturer.windowRects(on: d) }
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
            if let keyWindow { keyWindow.makeFirstResponder(keyWindow.selectionView) }
            NSCursor.crosshair.push()
            session?.cursorPushed = true
        }

        sessionSerial += 1
        if !options.interactive {
            // Safety net: if a harness run dies mid-session, don't leave the screen covered.
            let serial = sessionSerial
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.session != nil, self.sessionSerial == serial else { return }
                Log.overlay.error("test-mode session auto-cancelled after 30s")
                self.cancel()
            }
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

    /// Renders the composite of the frozen frame and the annotations for the active selection.
    func exportImage() throws -> (rect: PixelRect, image: CGImage) {
        guard let s = session else { throw OwlError.noSession }
        guard let id = s.activeDisplay, let rect = s.selection?.rect, !rect.isEmpty,
              let snap = s.snapshots[id] else { throw OwlError.noSelection }
        guard let image = AnnotationRenderer.export(s.document, base: snap.image, crop: rect,
                                                    pixelScale: Double(snap.geometry.scale)) else {
            throw OwlError.cropFailed
        }
        return (rect, image)
    }

    /// Composites, writes to the clipboard and ends the session.
    @discardableResult
    func copy() throws -> (rect: PixelRect, image: CGImage) {
        if let s = session, let id = s.activeDisplay, let v = windows[id]?.selectionView, v.isEditingText {
            v.commitTextEditing()
        }
        let (rect, image) = try exportImage()
        guard let id = session?.activeDisplay else { throw OwlError.noSession }
        let start = ContinuousClock.now
        try Clipboard.write(image: image, alsoAsFile: Settings.copyAsFile)
        CaptureHistory.record(image)
        lastTimings.copyMS = (ContinuousClock.now - start).milliseconds
        Log.overlay.info("copied \(image.width)x\(image.height) in \(self.lastTimings.copyMS ?? 0, format: .fixed(precision: 1)) ms")
        end(.copied(rect: rect, displayID: id))
        return (rect, image)
    }

    private func teardown(_ s: Session, reactivatePrevious: Bool) {
        toolbarPanel.orderOut(nil)
        for id in s.order {
            guard let w = windows[id] else { continue }
            w.orderOut(nil)
            w.selectionView.clearContents()
        }
        if s.options.interactive {
            NSApp.presentationOptions = s.previousPresentation
            if s.cursorPushed { NSCursor.pop() }
            if reactivatePrevious { s.previousApp?.activate() }
        }
    }

    private func end(_ outcome: SessionOutcome) {
        guard let s = session else { return }
        teardown(s, reactivatePrevious: true)
        session = nil
        onSessionEnd?(outcome)
    }

    static func timestampedName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Owl \(f.string(from: Date())).png"
    }

    /// Cmd+S: render the composite, dismiss the overlay, and present a save panel over ~/Pictures/Owl.
    func save() {
        guard let s = session else { return }
        if let id = s.activeDisplay, let v = windows[id]?.selectionView, v.isEditingText { v.commitTextEditing() }
        let image: CGImage
        do { image = try exportImage().image } catch {
            Log.overlay.error("save failed to render: \(String(describing: error))")
            return
        }
        let previousApp = s.previousApp
        let interactive = s.options.interactive
        teardown(s, reactivatePrevious: false)
        session = nil

        guard interactive else { onSessionEnd?(.cancelled); return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        // Seed the panel from the configured folder; the URL it returns carries its own
        // sandbox extension, so the write afterwards needs no scope of ours.
        let (dir, name) = Settings.withSaveDirectoryAccess { dir -> (URL, String) in
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return (dir, CaptureHistory.uniqueURL(in: dir, name: Self.timestampedName()).lastPathComponent)
        }
        panel.directoryURL = dir
        panel.nameFieldStringValue = name
        let response = panel.runModal()
        var saved: URL?
        if response == .OK, let url = panel.url {
            do { try PNGEncoder.write(image, to: url); saved = url; CaptureHistory.note(url) }
            catch { Log.overlay.error("save failed to write: \(String(describing: error))") }
        }
        previousApp?.activate()
        onSessionEnd?(saved.map(SessionOutcome.saved) ?? .cancelled)
    }

    /// Test path: render the composite, write it to `url`, and end the session (no panel).
    func saveToFile(_ url: URL) throws {
        let (_, image) = try exportImage()
        // Grants access when `url` is inside the bookmarked folder; harmless otherwise.
        try Settings.withSaveDirectoryAccess { _ in try PNGEncoder.write(image, to: url) }
        CaptureHistory.note(url)
        end(.saved(url))
    }

    // MARK: Editor state

    func setTool(_ t: Tool) {
        tool = t
        renderActive()
    }

    func setColor(_ c: RGBAColor) {
        color = c
        if var s = session, var shape = s.document.selectedShape {
            s.history.record(s.document)
            shape.style.color = c
            s.document.update(shape)
            session = s
        }
        renderActive()
    }

    func setWidth(_ w: WidthPreset) {
        width = w
        if var s = session, var shape = s.document.selectedShape, let snap = s.snapshots[s.activeDisplay ?? 0] {
            s.history.record(s.document)
            let style = w.style(color: shape.style.color, scale: snap.geometry.scale)
            shape.style = style
            if shape.kind == .text { shape.textSize = AnnotationRenderer.measureText(shape.text, fontSize: style.fontSize) }
            s.document.update(shape)
            session = s
        }
        renderActive()
    }

    func undo() {
        guard var s = session, let prev = s.history.undo(current: s.document) else { return }
        s.document = prev
        session = s
        renderActive()
    }

    func redo() {
        guard var s = session, let next = s.history.redo(current: s.document) else { return }
        s.document = next
        session = s
        renderActive()
    }

    func deleteSelectedShape() {
        guard var s = session, let id = s.document.selectedID else { return }
        s.history.record(s.document)
        s.document.remove(id: id)
        session = s
        renderActive()
    }

    /// Adds a text shape directly (harness path; the interactive path goes through the inline editor).
    func addText(_ text: String, at p: PixelPoint) {
        guard var s = session, let id = s.activeDisplay, let snap = s.snapshots[id] else { return }
        let style = width.style(color: color, scale: snap.geometry.scale)
        let shape = Shape(kind: .text, start: p, end: p, style: style, text: text,
                          textSize: AnnotationRenderer.measureText(text, fontSize: style.fontSize))
        guard !shape.isDegenerate else { return }
        s.history.record(s.document)
        s.document.add(shape)
        session = s
        renderActive()
    }

    /// Programmatic region selection for the test harness (and future "re-select last region").
    func setSelection(_ rect: PixelRect, on displayID: CGDirectDisplayID?) throws {
        guard var s = session else { throw OwlError.noSession }
        guard let id = displayID ?? s.activeDisplay ?? s.order.first,
              let snap = s.snapshots[id] else { throw OwlError.unknownDisplay("\(String(describing: displayID))") }
        if s.activeDisplay != id { s.document = AnnotationDocument(); s.history.clear() }
        var model = SelectionModel(bounds: snap.geometry.pixelBounds)
        model.set(rect)
        s.activeDisplay = id
        s.selection = model
        session = s
        renderAll()
    }

    // MARK: Input routing (shared by the views and the debug harness)

    /// Cursor moved with no button down: highlight the window under it (snap candidate),
    /// but only before any selection exists and while not dragging.
    func hover(at p: PixelPoint, on displayID: CGDirectDisplayID) {
        guard var s = session else { return }
        if case .none = s.dragMode {} else { return }
        let hasSelection = (s.activeDisplay == displayID) && (s.selection?.hasSelection == true)
        if hasSelection {
            if s.hoverRect != nil { s.hoverRect = nil; session = s; renderActive() }
            return
        }
        let candidate = s.windowRects[displayID]?.first { $0.contains(p) }
        if candidate != s.hoverRect || s.activeDisplay != displayID {
            s.activeDisplay = displayID
            s.hoverRect = candidate
            session = s
            renderActive()
        }
    }

    func clearHover() {
        guard var s = session, s.hoverRect != nil else { return }
        s.hoverRect = nil
        session = s
        renderActive()
    }

    func press(at p: PixelPoint, on displayID: CGDirectDisplayID) {
        guard var s = session, let snap = s.snapshots[displayID] else { return }
        if let v = windows[displayID]?.selectionView, v.isEditingText { v.commitTextEditing(); s = session! }
        let scale = snap.geometry.scale
        if s.activeDisplay != displayID || s.selection == nil {
            s.activeDisplay = displayID
            s.selection = SelectionModel(bounds: snap.geometry.pixelBounds)
            s.document = AnnotationDocument()
            s.history.clear()
        }
        let slop = Int((SelectionView.handleSlopPoints * scale).rounded())
        let hit = s.selection!.hitTest(p, slop: slop)
        s.hoverRect = nil

        switch hit {
        case .handle, .outside:
            if case .outside = hit {
                s.document = AnnotationDocument()
                s.history.clear()
            }
            s.dragMode = .region
            s.selection!.press(at: p, slop: slop)
        case .inside:
            switch tool {
            case .select:
                if let shape = s.document.topmostShape(at: p, tolerance: slop) {
                    s.document.selectedID = shape.id
                    s.dragMode = .movingShape(shape.id, last: p, recorded: false)
                } else {
                    s.document.selectedID = nil
                    s.dragMode = .region
                    s.selection!.press(at: p, slop: slop)
                }
            case .text:
                s.dragMode = .none
            case .badge:
                s.history.record(s.document)
                let shape = Shape(kind: .badge, start: p, end: p, style: width.style(color: color, scale: scale),
                                  number: s.document.nextBadgeNumber)
                s.document.add(shape)
                s.document.selectedID = nil
                s.dragMode = .movingShape(shape.id, last: p, recorded: true)
            default:
                guard let kind = tool.shapeKind else { break }
                s.history.record(s.document)
                let shape = Shape(kind: kind, start: p, end: p, style: width.style(color: color, scale: scale))
                s.document.add(shape)
                s.document.selectedID = nil
                s.dragMode = .drawing(shape.id)
            }
        }
        session = s
        renderAll()
    }

    func drag(to raw: PixelPoint, on displayID: CGDirectDisplayID) {
        guard var s = session, s.activeDisplay == displayID else { return }
        switch s.dragMode {
        case .none:
            return
        case .region:
            s.selection?.drag(to: raw)
        case .drawing(let id):
            guard var shape = s.document.shape(id: id), let bounds = s.selection?.rect else { return }
            shape.end = Self.clamp(raw, to: bounds)
            s.document.update(shape)
        case .movingShape(let id, let last, let recorded):
            guard let shape = s.document.shape(id: id) else { return }
            let dx = raw.x - last.x, dy = raw.y - last.y
            if dx == 0 && dy == 0 { return }
            if !recorded { s.history.record(s.document) }
            s.document.update(shape.moved(dx: dx, dy: dy))
            s.dragMode = .movingShape(id, last: raw, recorded: true)
        }
        session = s
        renderActive()
    }

    func release(on displayID: CGDirectDisplayID) {
        guard var s = session, s.activeDisplay == displayID else { return }
        switch s.dragMode {
        case .none:
            break
        case .region:
            s.selection?.release()
        case .drawing(let id):
            if let shape = s.document.shape(id: id), shape.isDegenerate {
                s.document.remove(id: id)
                _ = s.history.undo(current: s.document)
                s.history.clear()
            }
        case .movingShape:
            break
        }
        s.dragMode = .none
        session = s
        renderAll()
    }

    func click(at p: PixelPoint, on displayID: CGDirectDisplayID) {
        guard var s = session, let snap = s.snapshots[displayID] else { return }
        let scale = snap.geometry.scale
        let slop = Int((SelectionView.handleSlopPoints * scale).rounded())
        if let v = windows[displayID]?.selectionView, v.isEditingText {
            v.commitTextEditing()
            return
        }
        let hasSelection = (s.activeDisplay == displayID) && (s.selection?.hasSelection == true)
        if !hasSelection {
            if let candidate = s.windowRects[displayID]?.first(where: { $0.contains(p) }) {
                try? setSelection(candidate, on: displayID)
            }
            return
        }
        guard s.activeDisplay == displayID, let model = s.selection, model.hitTest(p, slop: slop) == .inside else { return }
        switch tool {
        case .select:
            s.document.selectedID = s.document.topmostShape(at: p, tolerance: slop)?.id
        case .text:
            s.document.selectedID = nil
            session = s
            renderAll()
            if s.options.interactive, let v = windows[displayID]?.selectionView, let rect = model.rect {
                v.beginTextEditing(at: p, maxPixelX: rect.maxX, fontPoints: width.fontPoints, color: color)
            }
            return
        case .badge:
            s.history.record(s.document)
            s.document.add(Shape(kind: .badge, start: p, end: p, style: width.style(color: color, scale: scale),
                                 number: s.document.nextBadgeNumber))
            s.document.selectedID = nil
        default:
            s.document.selectedID = nil
        }
        session = s
        renderAll()
    }

    private static func clamp(_ p: PixelPoint, to r: PixelRect) -> PixelPoint {
        PixelPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    // MARK: Rendering

    private func renderState(for id: CGDirectDisplayID, session s: Session) -> SelectionView.RenderState {
        var state = SelectionView.RenderState()
        guard id == s.activeDisplay else { return state }
        state.selection = s.selection
        state.hoverRect = s.hoverRect
        state.document = s.document
        state.showToolbar = s.selection?.hasSelection == true
        state.tool = tool
        state.color = color
        state.width = width
        state.canUndo = s.history.canUndo
        state.canRedo = s.history.canRedo
        return state
    }

    private func renderAll() {
        guard let s = session else { return }
        for id in s.order {
            windows[id]?.selectionView.render(renderState(for: id, session: s))
        }
        updateToolbarPanel(session: s)
    }

    private func renderActive() {
        guard let s = session, let id = s.activeDisplay else { return }
        windows[id]?.selectionView.render(renderState(for: id, session: s))
        updateToolbarPanel(session: s)
    }

    /// Positions the floating toolbar panel over the active display's selection, or hides it.
    private func updateToolbarPanel(session s: Session) {
        guard s.options.interactive else { return }
        guard let id = s.activeDisplay, let window = windows[id], let selection = s.selection else {
            toolbarPanel.orderOut(nil)
            return
        }
        toolbarPanel.annotationToolbar.setState(tool: tool, color: color, width: width,
                                      canUndo: s.history.canUndo, canRedo: s.history.canRedo)
        toolbarPanel.layoutToolbar()
        let size = toolbarPanel.preferredSize
        let view = window.selectionView
        guard let rect = view.toolbarRect(for: selection, size: size) else {
            toolbarPanel.orderOut(nil)
            return
        }
        // rect.origin is the toolbar's top-left in the flipped view; convert it to a screen point.
        let winPoint = view.convert(CGPoint(x: rect.minX, y: rect.minY), to: nil)
        let screenTopLeft = window.convertPoint(toScreen: winPoint)
        let frame = CGRect(x: screenTopLeft.x, y: screenTopLeft.y - size.height, width: size.width, height: size.height)
        toolbarPanel.level = window.level
        toolbarPanel.setFrame(frame, display: true)
        toolbarPanel.orderFrontRegardless()
    }

    func testInjectWindow(_ rect: PixelRect, on displayID: CGDirectDisplayID) {
        guard var s = session else { return }
        s.windowRects[displayID, default: []].insert(rect, at: 0)
        session = s
    }

    func testClickToolSegment(_ index: Int) throws {
        guard session != nil else { throw OwlError.noSession }
        toolbarPanel.annotationToolbar.testClickTool(index)
    }

    // MARK: SelectionViewDelegate

    func selectionView(_ view: SelectionView, pressAt pixel: PixelPoint) { press(at: pixel, on: view.displayID) }
    func selectionView(_ view: SelectionView, dragTo pixel: PixelPoint) { drag(to: pixel, on: view.displayID) }
    func selectionViewDidRelease(_ view: SelectionView) { release(on: view.displayID) }
    func selectionView(_ view: SelectionView, clickAt pixel: PixelPoint) { click(at: pixel, on: view.displayID) }
    func selectionView(_ view: SelectionView, hoverAt pixel: PixelPoint) { hover(at: pixel, on: view.displayID) }
    func selectionViewDidExit(_ view: SelectionView) { clearHover() }

    func selectionView(_ view: SelectionView, commitText text: String, at pixel: PixelPoint) {
        addText(text, at: pixel)
    }

    func selectionView(_ view: SelectionView, keyDown event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            if view.isEditingText { view.cancelTextEditing(); return }
            if session?.document.selectedID != nil {
                session?.document.selectedID = nil
                renderActive()
            } else {
                cancel()
            }
        case 36, 76: // Return, keypad Enter
            do { try copy() } catch { Log.overlay.error("copy failed: \(String(describing: error))") }
        case 51, 117: // Delete, forward delete
            deleteSelectedShape()
        default:
            let mods = event.modifierFlags.intersection([.command, .control, .option])
            guard mods.isEmpty, let ch = event.charactersIgnoringModifiers?.lowercased(),
                  let t = Tool.allCases.first(where: { $0.key == ch }) else { return }
            setTool(t)
        }
    }

    func selectionView(_ view: SelectionView, keyEquivalent event: NSEvent) -> Bool {
        guard !view.isEditingText else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ch = event.charactersIgnoringModifiers?.lowercased()
        switch (mods, ch) {
        case (.command, "c"):
            do { try copy() } catch { Log.overlay.error("copy failed: \(String(describing: error))") }
            return true
        case (.command, "s"):
            save()
            return true
        case (.command, "z"):
            undo()
            return true
        case ([.command, .shift], "z"):
            redo()
            return true
        default:
            return false
        }
    }

    // MARK: ToolbarDelegate

    func toolbar(_ toolbar: ToolbarView, didPick tool: Tool) { setTool(tool) }
    func toolbar(_ toolbar: ToolbarView, didPick color: RGBAColor) { setColor(color) }
    func toolbar(_ toolbar: ToolbarView, didPick width: WidthPreset) { setWidth(width) }
    func toolbarDidRequestUndo(_ toolbar: ToolbarView) { undo() }
    func toolbarDidRequestRedo(_ toolbar: ToolbarView) { redo() }
    func toolbarDidRequestCopy(_ toolbar: ToolbarView) {
        do { try copy() } catch { Log.overlay.error("copy failed: \(String(describing: error))") }
    }
    func toolbarDidRequestSave(_ toolbar: ToolbarView) { save() }
    func toolbarDidRequestCancel(_ toolbar: ToolbarView) { cancel() }
}
