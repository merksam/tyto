import AppKit
import CoreGraphics
import Foundation
import OwlCore

enum DebugCommands {
    static func handle(_ req: DebugRequest, app: AppDelegate) async -> DebugResponse {
        do {
            return try await run(req, app: app)
        } catch {
            return .failure("\(error)")
        }
    }

    private static func run(_ req: DebugRequest, app: AppDelegate) async throws -> DebugResponse {
        let capturer = app.capturer
        let overlay = app.overlay!

        switch req.cmd {
        case "ping":
            return .success([
                "pid": JSONValue(Int(getpid())),
                "version": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"),
                "screenCapturePermission": .bool(Permissions.hasScreenCapture),
                "sessionActive": .bool(overlay.isActive),
            ])

        case "displays":
            return .success(["displays": .array(capturer.displays().map(displayJSON))])

        case "capture":
            let ids = try resolveDisplays(req.display, capturer: capturer)
            var options = SessionOptions()
            options.displayIDs = ids
            options.interactive = !(req.test ?? false)
            try await overlay.beginSession(options: options)
            return .success(overlay.lastTimings.json.merging(stateJSON(overlay)) { a, _ in a })

        case "select":
            guard let x = req.x, let y = req.y, let w = req.w, let h = req.h else {
                throw OwlError.badRequest("select needs x y w h")
            }
            let id = try req.display.map { try resolveSingle($0, capturer: capturer) }
            try overlay.setSelection(PixelRect(x: x, y: y, width: w, height: h), on: id)
            return .success(stateJSON(overlay))

        case "state":
            return .success(stateJSON(overlay))

        case "copy":
            let (rect, image) = try overlay.copy()
            return .success([
                "rect": rectJSON(rect),
                "width": JSONValue(image.width),
                "height": JSONValue(image.height),
                "copyMS": overlay.lastTimings.json["copyMS"] ?? .null,
            ])

        case "export":
            guard let path = req.path else { throw OwlError.badRequest("export needs a path") }
            let (rect, image) = try overlay.exportImage()
            try PNGEncoder.write(image, to: URL(fileURLWithPath: path))
            return .success(["path": .string(path), "rect": rectJSON(rect),
                             "width": JSONValue(image.width), "height": JSONValue(image.height)])

        case "cancel":
            overlay.cancel()
            return .success()

        case "savefile":
            guard let path = req.path else { throw OwlError.badRequest("savefile needs a path") }
            try overlay.saveToFile(URL(fileURLWithPath: path))
            return .success(["path": .string(path)])

        case "windows":
            guard let s = overlay.session else { throw OwlError.noSession }
            let id = try activeDisplay(overlay, req.display, capturer: capturer)
            let rects = s.windowRects[id] ?? []
            return .success(["display": JSONValue(Int(id)), "count": JSONValue(rects.count),
                             "windows": .array(rects.map(rectJSON))])

        case "enumwindows":
            // Enumerate on-screen windows for a display without starting a session (non-disruptive).
            let id = try resolveSingle(req.display ?? "main", capturer: capturer)
            guard let d = capturer.displays().first(where: { $0.id == id }) else { throw OwlError.unknownDisplay("\(id)") }
            let rects = capturer.windowRects(on: d)
            return .success(["display": JSONValue(Int(id)), "count": JSONValue(rects.count),
                             "windows": .array(rects.prefix(12).map(rectJSON))])

        case "injectwindow":
            guard let x = req.x, let y = req.y, let w = req.w, let h = req.h else {
                throw OwlError.badRequest("injectwindow needs x y w h")
            }
            let id = try activeDisplay(overlay, req.display, capturer: capturer)
            overlay.testInjectWindow(PixelRect(x: x, y: y, width: w, height: h), on: id)
            return .success(stateJSON(overlay))

        case "hover":
            guard let x = req.x, let y = req.y else { throw OwlError.badRequest("hover needs x y") }
            let id = try activeDisplay(overlay, req.display, capturer: capturer)
            overlay.hover(at: PixelPoint(x: x, y: y), on: id)
            return .success(stateJSON(overlay))

        // MARK: Editor

        case "tool":
            guard let name = req.value, let t = Tool(rawValue: name) else {
                throw OwlError.badRequest("tool needs one of \(Tool.allCases.map(\.rawValue))")
            }
            overlay.setTool(t)
            return .success(stateJSON(overlay))

        case "color":
            guard let name = req.value, let c = RGBAColor.named(name) else {
                throw OwlError.badRequest("color needs one of \(RGBAColor.palette.map(\.name))")
            }
            overlay.setColor(c)
            return .success(stateJSON(overlay))

        case "width":
            guard let name = req.value, let w = WidthPreset(rawValue: name) else {
                throw OwlError.badRequest("width needs one of \(WidthPreset.allCases.map(\.rawValue))")
            }
            overlay.setWidth(w)
            return .success(stateJSON(overlay))

        case "draw":
            guard let x = req.x, let y = req.y, let x2 = req.x2, let y2 = req.y2 else {
                throw OwlError.badRequest("draw needs x1 y1 x2 y2")
            }
            let id = try activeDisplay(overlay, req.display, capturer: capturer)
            overlay.press(at: PixelPoint(x: x, y: y), on: id)
            // A few intermediate points, like a real drag.
            for step in 1...4 {
                let t = Double(step) / 4
                overlay.drag(to: PixelPoint(x: x + Int(Double(x2 - x) * t), y: y + Int(Double(y2 - y) * t)), on: id)
            }
            overlay.release(on: id)
            return .success(stateJSON(overlay))

        case "click":
            guard let x = req.x, let y = req.y else { throw OwlError.badRequest("click needs x y") }
            let id = try activeDisplay(overlay, req.display, capturer: capturer)
            overlay.click(at: PixelPoint(x: x, y: y), on: id)
            return .success(stateJSON(overlay))

        case "text":
            guard let x = req.x, let y = req.y, let text = req.value else { throw OwlError.badRequest("text needs x y and a string") }
            overlay.addText(text, at: PixelPoint(x: x, y: y))
            return .success(stateJSON(overlay))

        case "uitool":
            guard let name = req.value, let i = Int(name) else { throw OwlError.badRequest("uitool needs a segment index") }
            try overlay.testClickToolSegment(i)
            return .success(stateJSON(overlay))

        case "undo":
            overlay.undo()
            return .success(stateJSON(overlay))

        case "redo":
            overlay.redo()
            return .success(stateJSON(overlay))

        case "delete":
            overlay.deleteSelectedShape()
            return .success(stateJSON(overlay))

        case "shapes":
            guard let s = overlay.session else { throw OwlError.noSession }
            return .success(["shapes": .array(s.document.shapes.map(shapeJSON)), "selected": s.document.selectedID.map { .string($0.uuidString) } ?? .null])

        case "set":
            guard let key = req.key, let value = req.value else { throw OwlError.badRequest("set needs key value") }
            switch key {
            case "copyAsFile": Settings.copyAsFile = ["1", "true", "on", "yes"].contains(value.lowercased())
            default: throw OwlError.badRequest("unknown setting \(key)")
            }
            return .success(["copyAsFile": .bool(Settings.copyAsFile)])

        case "snapshot":
            guard let path = req.path else { throw OwlError.badRequest("snapshot needs a path") }
            let id = try resolveSingle(req.display ?? "main", capturer: capturer)
            guard let display = capturer.displays().first(where: { $0.id == id }) else {
                throw OwlError.unknownDisplay("\(id)")
            }
            try await capturer.writeDisplayPNG(display: display, to: URL(fileURLWithPath: path))
            return .success(["path": .string(path), "display": JSONValue(Int(id))])

        case "clipboard":
            guard let path = req.path else { throw OwlError.badRequest("clipboard needs a path") }
            guard let png = Clipboard.readPNG() else { throw OwlError.clipboardEmpty }
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            var data: [String: JSONValue] = ["path": .string(path), "bytes": JSONValue(png.count)]
            if let size = PNGEncoder.size(ofPNG: png) {
                data["width"] = JSONValue(size.width)
                data["height"] = JSONValue(size.height)
            }
            let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
            data["fileURLs"] = .array(urls.map { .string($0.path) })
            return .success(data)

        case "timings":
            return .success(overlay.lastTimings.json)

        case "quit":
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return .success()

        default:
            throw OwlError.badRequest("unknown command \(req.cmd)")
        }
    }

    // MARK: helpers

    private static func activeDisplay(_ overlay: OverlayController, _ spec: String?, capturer: ScreenCapturer) throws -> CGDirectDisplayID {
        if let spec { return try resolveSingle(spec, capturer: capturer) }
        guard let s = overlay.session else { throw OwlError.noSession }
        guard let id = s.activeDisplay ?? s.order.first else { throw OwlError.noDisplays }
        return id
    }

    private static func resolveDisplays(_ spec: String?, capturer: ScreenCapturer) throws -> [CGDirectDisplayID]? {
        guard let spec, spec != "all" else { return nil }
        return [try resolveSingle(spec, capturer: capturer)]
    }

    private static func resolveSingle(_ spec: String, capturer: ScreenCapturer) throws -> CGDirectDisplayID {
        let displays = capturer.displays()
        switch spec {
        case "main":
            guard let d = displays.first(where: \.isMain) else { throw OwlError.unknownDisplay(spec) }
            return d.id
        case "secondary":
            guard let d = displays.first(where: { !$0.isMain }) else { throw OwlError.unknownDisplay("no secondary display attached") }
            return d.id
        default:
            guard let n = UInt32(spec), displays.contains(where: { $0.id == n }) else { throw OwlError.unknownDisplay(spec) }
            return n
        }
    }

    private static func displayJSON(_ d: DisplayInfo) -> JSONValue {
        let px = d.geometry.pixelSize
        return .object([
            "id": JSONValue(Int(d.id)),
            "name": .string(d.name),
            "main": .bool(d.isMain),
            "pointWidth": JSONValue(Double(d.frame.width)),
            "pointHeight": JSONValue(Double(d.frame.height)),
            "originX": JSONValue(Double(d.frame.origin.x)),
            "originY": JSONValue(Double(d.frame.origin.y)),
            "scale": JSONValue(Double(d.scale)),
            "pixelWidth": JSONValue(px.width),
            "pixelHeight": JSONValue(px.height),
        ])
    }

    private static func rectJSON(_ r: PixelRect) -> JSONValue {
        .object(["x": JSONValue(r.x), "y": JSONValue(r.y), "width": JSONValue(r.width), "height": JSONValue(r.height)])
    }

    private static func shapeJSON(_ s: Shape) -> JSONValue {
        var d: [String: JSONValue] = [
            "id": .string(s.id.uuidString),
            "kind": .string(s.kind.rawValue),
            "start": .object(["x": JSONValue(s.start.x), "y": JSONValue(s.start.y)]),
            "end": .object(["x": JSONValue(s.end.x), "y": JSONValue(s.end.y)]),
            "bounds": rectJSON(s.bounds),
            "color": .string(s.style.color.name ?? "custom"),
            "strokeWidth": JSONValue(s.style.strokeWidth),
        ]
        if s.kind == .text { d["text"] = .string(s.text) }
        if s.kind == .badge { d["number"] = JSONValue(s.number) }
        return .object(d)
    }

    private static func stateJSON(_ overlay: OverlayController) -> [String: JSONValue] {
        var d: [String: JSONValue] = [
            "tool": .string(overlay.tool.rawValue),
            "color": .string(overlay.color.name ?? "custom"),
            "width": .string(overlay.width.rawValue),
        ]
        guard let s = overlay.session else {
            d["sessionActive"] = .bool(false)
            return d
        }
        d["sessionActive"] = .bool(true)
        d["interactive"] = .bool(s.options.interactive)
        d["displays"] = .array(s.order.map { JSONValue(Int($0)) })
        d["activeDisplay"] = s.activeDisplay.map { JSONValue(Int($0)) } ?? .null
        if let sel = s.selection {
            d["selection"] = sel.rect.map(rectJSON) ?? .null
            d["phase"] = .string(String(describing: sel.phase))
        } else {
            d["selection"] = .null
        }
        d["hoverRect"] = s.hoverRect.map(rectJSON) ?? .null
        d["shapeCount"] = JSONValue(s.document.shapes.count)
        d["selectedShape"] = s.document.selectedID.map { .string($0.uuidString) } ?? .null
        d["canUndo"] = .bool(s.history.canUndo)
        d["canRedo"] = .bool(s.history.canRedo)
        return d
    }
}
