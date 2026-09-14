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

        case "cancel":
            overlay.cancel()
            return .success()

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

    private static func stateJSON(_ overlay: OverlayController) -> [String: JSONValue] {
        guard let s = overlay.session else { return ["sessionActive": .bool(false)] }
        var d: [String: JSONValue] = [
            "sessionActive": .bool(true),
            "interactive": .bool(s.options.interactive),
            "displays": .array(s.order.map { JSONValue(Int($0)) }),
            "activeDisplay": s.activeDisplay.map { JSONValue(Int($0)) } ?? .null,
        ]
        if let sel = s.selection {
            d["selection"] = sel.rect.map(rectJSON) ?? .null
            d["phase"] = .string(String(describing: sel.phase))
        } else {
            d["selection"] = .null
        }
        return d
    }
}
