#if DEBUG
import AppKit
import CoreGraphics
import Foundation
import TytoCore

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
                "settingsWindowVisible": .bool(app.isSettingsWindowVisible),
                "welcomeWindowVisible": .bool(app.isWelcomeWindowVisible),
                "screenCaptureGrantedDuringRun": .bool(Permissions.grantedDuringThisRun),
            ])

        case "displays":
            return .success(["displays": .array(capturer.displays().map(displayJSON))])

        case "capture":
            let ids = try resolveDisplays(req.display, capturer: capturer)
            var options = SessionOptions()
            options.displayIDs = ids
            options.interactive = !(req.test ?? false)
            options.showsToolbar = req.toolbar ?? false
            try await overlay.beginSession(options: options)
            return .success(overlay.lastTimings.json.merging(stateJSON(overlay)) { a, _ in a })

        case "select":
            guard let x = req.x, let y = req.y, let w = req.w, let h = req.h else {
                throw TytoError.badRequest("select needs x y w h")
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
            // Returns the composite as base64 PNG; tytoctl writes the file (the app is sandboxed).
            let (rect, image) = try overlay.exportImage()
            let png = try PNGEncoder.data(image)
            return .success(["png": pngPayload(png), "rect": rectJSON(rect),
                             "bytes": JSONValue(png.count),
                             "width": JSONValue(image.width), "height": JSONValue(image.height)])

        case "cancel":
            overlay.cancel()
            return .success()

        case "savefile":
            guard let path = req.path else { throw TytoError.badRequest("savefile needs a path") }
            try overlay.saveToFile(URL(fileURLWithPath: path))
            return .success(["path": .string(path)])

        case "windows":
            guard let s = overlay.session else { throw TytoError.noSession }
            let id = try activeDisplay(overlay, req.display, capturer: capturer)
            let rects = s.windowRects[id] ?? []
            return .success(["display": JSONValue(Int(id)), "count": JSONValue(rects.count),
                             "windows": .array(rects.map(rectJSON))])

        case "enumwindows":
            // Enumerate on-screen windows for a display without starting a session (non-disruptive).
            let id = try resolveSingle(req.display ?? "main", capturer: capturer)
            guard let d = capturer.displays().first(where: { $0.id == id }) else { throw TytoError.unknownDisplay("\(id)") }
            let rects = capturer.windowRects(on: d)
            return .success(["display": JSONValue(Int(id)), "count": JSONValue(rects.count),
                             "windows": .array(rects.prefix(12).map(rectJSON))])

        case "injectwindow":
            guard let x = req.x, let y = req.y, let w = req.w, let h = req.h else {
                throw TytoError.badRequest("injectwindow needs x y w h")
            }
            let id = try activeDisplay(overlay, req.display, capturer: capturer)
            overlay.testInjectWindow(PixelRect(x: x, y: y, width: w, height: h), on: id)
            return .success(stateJSON(overlay))

        case "hover":
            guard let x = req.x, let y = req.y else { throw TytoError.badRequest("hover needs x y") }
            let id = try activeDisplay(overlay, req.display, capturer: capturer)
            overlay.hover(at: PixelPoint(x: x, y: y), on: id)
            return .success(stateJSON(overlay))

        // MARK: Editor

        case "tool":
            guard let name = req.value, let t = Tool(rawValue: name) else {
                throw TytoError.badRequest("tool needs one of \(Tool.allCases.map(\.rawValue))")
            }
            overlay.setTool(t)
            return .success(stateJSON(overlay))

        case "color":
            guard let name = req.value, let c = RGBAColor.named(name) else {
                throw TytoError.badRequest("color needs one of \(RGBAColor.palette.map(\.name))")
            }
            overlay.setColor(c)
            return .success(stateJSON(overlay))

        case "width":
            guard let name = req.value, let w = WidthPreset(rawValue: name) else {
                throw TytoError.badRequest("width needs one of \(WidthPreset.allCases.map(\.rawValue))")
            }
            overlay.setWidth(w)
            return .success(stateJSON(overlay))

        case "draw":
            guard let x = req.x, let y = req.y, let x2 = req.x2, let y2 = req.y2 else {
                throw TytoError.badRequest("draw needs x1 y1 x2 y2")
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
            guard let x = req.x, let y = req.y else { throw TytoError.badRequest("click needs x y") }
            let id = try activeDisplay(overlay, req.display, capturer: capturer)
            overlay.click(at: PixelPoint(x: x, y: y), on: id)
            return .success(stateJSON(overlay))

        case "text":
            guard let x = req.x, let y = req.y, let text = req.value else { throw TytoError.badRequest("text needs x y and a string") }
            overlay.addText(text, at: PixelPoint(x: x, y: y))
            return .success(stateJSON(overlay))

        case "uitool":
            guard let name = req.value, let i = Int(name) else { throw TytoError.badRequest("uitool needs a segment index") }
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
            guard let s = overlay.session else { throw TytoError.noSession }
            return .success(["shapes": .array(s.document.shapes.map(shapeJSON)), "selected": s.document.selectedID.map { .string($0.uuidString) } ?? .null])

        case "set":
            guard let key = req.key, let value = req.value else { throw TytoError.badRequest("set needs key value") }
            let on = ["1", "true", "on", "yes"].contains(value.lowercased())
            switch key {
            case "copyAsFile": Settings.copyAsFile = on
            case "hasLaunchedBefore": UserDefaults.standard.set(on, forKey: AppDelegate.hasLaunchedBeforeKey)
            case "autoSave": Settings.autoSaveRecent = on
            case "saveDir": try Settings.setSaveDirectory(value == "default" ? nil : URL(fileURLWithPath: value, isDirectory: true))
            case "defaultTool":
                guard let t = Tool(rawValue: value) else { throw TytoError.badRequest("bad tool") }
                Settings.defaultTool = t
            case "defaultColor":
                guard let c = RGBAColor.named(value) else { throw TytoError.badRequest("bad color") }
                Settings.defaultColor = c
            case "defaultWidth":
                guard let w = WidthPreset(rawValue: value) else { throw TytoError.badRequest("bad width") }
                Settings.defaultWidth = w
            case "defaultDestination":
                var list = ScriptsFolder.adoptNewScripts()
                guard let d = list.destination(matching: value) else { throw TytoError.unknownDestination(value) }
                list.setDefault(id: d.id)
                Settings.destinationList = list
                return .success(destinationsJSON(list))
            case "destinationClipboard":
                // What ⇧⌘C copies, for the default destination.
                var list = ScriptsFolder.adoptNewScripts()
                guard var d = list.defaultDestination else { throw TytoError.noDestination }
                guard let choice = ClipboardChoice(rawValue: value) else {
                    throw TytoError.badRequest("destinationClipboard needs one of \(ClipboardChoice.allCases.map(\.rawValue))")
                }
                d.clipboard = choice
                list.upsert(d)
                Settings.destinationList = list
                return .success(destinationsJSON(list))
            default: throw TytoError.badRequest("unknown setting \(key)")
            }
            return .success(settingsJSON())

        case "settings":
            return .success(settingsJSON())

        case "recent":
            let urls = CaptureHistory.recent
            return .success(["count": JSONValue(urls.count), "files": .array(urls.map { .string($0.path) })])

        case "testhistory":
            // Exercises CaptureHistory (auto-save + recent list) without a screen capture.
            let w = 120, h = 80
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let url = CaptureHistory.record(ctx.makeImage()!)
            return .success(["written": .string(url?.path ?? ""),
                             "recentCount": JSONValue(CaptureHistory.recent.count)])

        case "snapshot":
            // Returns the display as base64 PNG; tytoctl writes the file (the app is sandboxed).
            let id = try resolveSingle(req.display ?? "main", capturer: capturer)
            guard let display = capturer.displays().first(where: { $0.id == id }) else {
                throw TytoError.unknownDisplay("\(id)")
            }
            let png = try await capturer.displayPNG(display: display)
            var data: [String: JSONValue] = ["png": pngPayload(png),
                                             "bytes": JSONValue(png.count),
                                             "display": JSONValue(Int(id))]
            if let size = PNGEncoder.size(ofPNG: png) {
                data["width"] = JSONValue(size.width)
                data["height"] = JSONValue(size.height)
            }
            return .success(data)

        case "clipboard":
            // Returns the clipboard image as base64 PNG; tytoctl writes the file (the app is sandboxed).
            guard let png = Clipboard.readPNG() else { throw TytoError.clipboardEmpty }
            var data: [String: JSONValue] = ["png": pngPayload(png), "bytes": JSONValue(png.count)]
            if let size = PNGEncoder.size(ofPNG: png) {
                data["width"] = JSONValue(size.width)
                data["height"] = JSONValue(size.height)
            }
            let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
            data["fileURLs"] = .array(urls.map { .string($0.path) })
            return .success(data)

        // MARK: Destinations

        case "destinations":
            return .success(destinationsJSON(ScriptsFolder.adoptNewScripts()))

        case "send":
            // ⇧⌘C's own path: render, end the session, run the script, update the clipboard.
            // Waits for the outcome, so a test can check the result and the clipboard after.
            guard overlay.session != nil else { throw TytoError.noSession }
            let list = ScriptsFolder.adoptNewScripts()
            let target = try req.value.map { q in
                guard let d = list.destination(matching: q) else { throw TytoError.unknownDestination(q) }
                return d
            } ?? list.defaultDestination
            guard let target else { throw TytoError.noDestination }
            guard target.kind == .script else {
                throw TytoError.badRequest("\(target.name) is a share destination, which needs a person at the screen")
            }
            guard let task = try overlay.send(to: target.id) else { throw TytoError.badRequest("nothing was sent") }
            return sendResponse(reportJSON(await task.value))

        case "sendrecent":
            // Recent Captures → Send to <default>, for the newest capture.
            guard let url = CaptureHistory.recent.first else { throw TytoError.badRequest("no recent captures") }
            let list = ScriptsFolder.adoptNewScripts()
            let id = try req.value.map { q in
                guard let d = list.destination(matching: q) else { throw TytoError.unknownDestination(q) }
                guard d.kind == .script else { throw TytoError.badRequest("\(d.name) is a share destination") }
                return d.id
            }
            guard let task = app.sendRecent(url, to: id) else { throw TytoError.noDestination }
            var data = reportJSON(await task.value)
            data["capture"] = .string(url.path)
            return sendResponse(data)

        case "resetdestinations":
            // Forgets every destination and the activity list; scripts stay in the folder, and
            // come back as hand-written ones on the next scan unless they are removed too.
            Settings.destinationList = DestinationList()
            Settings.sendActivity = ActivityLog()
            return .success()

        case "sends":
            return .success(["sends": .array(Settings.sendActivity.records.map { r in
                .object(["date": .string(ISO8601DateFormatter().string(from: r.date)), "destination": .string(r.destination),
                         "ok": .bool(r.ok), "detail": .string(r.detail)])
            })])

        case "cliptext":
            // What a paste into a terminal gets, and every type on the same pasteboard item.
            let pb = NSPasteboard.general
            let types = pb.pasteboardItems?.first?.types.map { JSONValue.string($0.rawValue) } ?? []
            return .success(["text": pb.string(forType: .string).map(JSONValue.string) ?? .null,
                             "items": JSONValue(pb.pasteboardItems?.count ?? 0),
                             "types": .array(types),
                             "changeCount": JSONValue(pb.changeCount)])

        case "timings":
            return .success(overlay.lastTimings.json)

        case "welcome":
            app.openWelcome()
            return .success()

        case "bend":
            // Drags the selected arrow's middle handle to (x, y) through the real press/drag/
            // release path, so it exercises the handle hit test and the bend math together.
            guard let x = req.x, let y = req.y else { throw TytoError.badRequest("bend needs x y") }
            let id = try activeDisplay(overlay, req.display, capturer: capturer)
            guard let shape = overlay.session?.document.selectedShape, shape.kind == .arrow else {
                throw TytoError.badRequest("bend needs a selected arrow: tool select, then click on it")
            }
            overlay.press(at: shape.curveMidpoint, on: id)
            overlay.drag(to: PixelPoint(x: x, y: y), on: id)
            overlay.release(on: id)
            return .success(stateJSON(overlay))

        case "hint":
            app.showHint(req.value ?? "Tyto lives here.")
            return .success()

        case "quit":
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return .success()

        default:
            throw TytoError.badRequest("unknown command \(req.cmd)")
        }
    }

    // MARK: helpers

    /// PNG payload for the harness. The sandboxed app cannot write to caller-chosen paths, and
    /// other processes cannot read its container (TCC-protected), so the bytes go over the socket
    /// and tytoctl writes the file.
    private static func pngPayload(_ data: Data) -> JSONValue { .string(data.base64EncodedString()) }

    private static func activeDisplay(_ overlay: OverlayController, _ spec: String?, capturer: ScreenCapturer) throws -> CGDirectDisplayID {
        if let spec { return try resolveSingle(spec, capturer: capturer) }
        guard let s = overlay.session else { throw TytoError.noSession }
        guard let id = s.activeDisplay ?? s.order.first else { throw TytoError.noDisplays }
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
            guard let d = displays.first(where: \.isMain) else { throw TytoError.unknownDisplay(spec) }
            return d.id
        case "secondary":
            guard let d = displays.first(where: { !$0.isMain }) else { throw TytoError.unknownDisplay("no secondary display attached") }
            return d.id
        default:
            guard let n = UInt32(spec), displays.contains(where: { $0.id == n }) else { throw TytoError.unknownDisplay(spec) }
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

    private static func settingsJSON() -> [String: JSONValue] {
        [
            "copyAsFile": .bool(Settings.copyAsFile),
            "autoSaveRecent": .bool(Settings.autoSaveRecent),
            "saveDirectory": .string(Settings.saveDirectoryDisplayPath),
            "saveDirectoryIsCustom": .bool(Settings.hasCustomSaveDirectory),
            "saveDirectoryWritable": .bool(Settings.withSaveDirectoryAccess {
                FileManager.default.isWritableFile(atPath: $0.path)
            }),
            "defaultTool": .string(Settings.defaultTool.rawValue),
            "defaultColor": .string(Settings.defaultColor.name ?? "custom"),
            "defaultWidth": .string(Settings.defaultWidth.rawValue),
            "hotKeyDisplay": .string(Settings.hotKeyDisplay),
            "hotKeyCode": JSONValue(Int(Settings.hotKeyCode)),
            "launchAtLogin": .bool(Settings.launchAtLogin),
        ]
    }

    private static func destinationsJSON(_ list: DestinationList) -> [String: JSONValue] {
        let scripts = ScriptsFolder.scriptNames()
        return [
            "scriptsFolder": ScriptsFolder.url.map { .string($0.path) } ?? .null,
            "scripts": .array(scripts.map(JSONValue.string)),
            "default": list.defaultDestination.map { .string($0.name) } ?? .null,
            "destinations": .array(list.destinations.map { d in
                var o: [String: JSONValue] = [
                    "id": .string(d.id.uuidString), "name": .string(d.name), "kind": .string(d.kind.rawValue),
                    "clipboard": .string(d.clipboard.rawValue), "default": .bool(d.id == list.defaultDestination?.id),
                ]
                if let s = d.script { o["script"] = .string(s); o["scriptExists"] = .bool(scripts.contains(s)) }
                if let p = d.preset { o["preset"] = .string(p.rawValue) }
                if let s = d.shareService { o["shareService"] = .string(s.rawValue) }
                return .object(o)
            }),
        ]
    }

    /// A failed send fails the command too, so tytoctl exits non-zero, with the details kept.
    private static func sendResponse(_ data: [String: JSONValue]) -> DebugResponse {
        guard data["sent"] == .bool(false) else { return .success(data) }
        if case .string(let e)? = data["error"] { return DebugResponse(ok: false, error: e, data: data) }
        return DebugResponse(ok: false, error: "send failed", data: data)
    }

    private static func reportJSON(_ r: DestinationSender.Report) -> [String: JSONValue] {
        var d: [String: JSONValue] = ["destination": .string(r.destination), "sent": .bool(r.outcome.ok),
                                      "clipboard": .string(r.clipboard.rawValue), "message": .string(r.message)]
        switch r.outcome {
        case .sent(let result): d["result"] = .string(result)
        case .failed(let reason): d["error"] = .string(reason)
        }
        return d
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
#endif
