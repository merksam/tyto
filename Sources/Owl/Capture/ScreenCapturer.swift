import AppKit
import CoreGraphics
import OwlCore
import ScreenCaptureKit

nonisolated struct DisplayInfo: Sendable {
    let id: CGDirectDisplayID
    let name: String
    /// AppKit screen frame (global points, origin bottom-left of the main display).
    let frame: CGRect
    let scale: CGFloat
    let isMain: Bool

    var geometry: DisplayGeometry { DisplayGeometry(pointSize: frame.size, scale: scale) }
}

/// One display's frozen frame plus the geometry needed to map points to its pixels.
nonisolated struct DisplaySnapshot: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let geometry: DisplayGeometry
    let image: CGImage
}

/// Screenshot capture through ScreenCaptureKit's rect API (macOS 26+). Capturing by rect
/// avoids the slow SCShareableContent lookup entirely.
final class ScreenCapturer {
    func displays() -> [DisplayInfo] {
        let mainID = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen in
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(num.uint32Value)
            return DisplayInfo(id: id, name: screen.localizedName, frame: screen.frame,
                               scale: screen.backingScaleFactor, isMain: id == mainID)
        }
    }

    /// On-screen normal windows overlapping `display`, front-to-back, as display-local pixel rects.
    /// Used for snap-to-window. Owl's own windows are excluded by PID.
    func windowRects(on display: DisplayInfo) -> [PixelRect] {
        let selfPID = Int(getpid())
        let displayBounds = CGDisplayBounds(display.id)  // global CG points, top-left origin
        let scale = display.scale
        let pxBounds = display.geometry.pixelBounds
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var rects: [PixelRect] = []
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { continue }  // normal windows only
            if let pid = info[kCGWindowOwnerPID as String] as? Int, pid == selfPID { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let global = cgRect(from: boundsDict) else { continue }
            // Global CG points -> display-local pixels.
            let localX = (global.minX - displayBounds.minX) * scale
            let localY = (global.minY - displayBounds.minY) * scale
            let rect = PixelRect(x: Int(localX.rounded()), y: Int(localY.rounded()),
                                 width: Int((global.width * scale).rounded()),
                                 height: Int((global.height * scale).rounded()))
                .intersection(pxBounds)
            if rect.width >= 40 && rect.height >= 40 { rects.append(rect) }
        }
        return rects
    }

    private nonisolated func cgRect(from dict: [String: Any]) -> CGRect? {
        var rect = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(dict as CFDictionary, &rect) else { return nil }
        return rect
    }

    /// Captures the given displays concurrently. Result order matches the input order.
    func capture(displays: [DisplayInfo]) async throws -> [DisplaySnapshot] {
        guard !displays.isEmpty else { throw OwlError.noDisplays }
        let order = displays.map(\.id)
        let snapshots = try await withThrowingTaskGroup(of: DisplaySnapshot.self) { group in
            for d in displays {
                group.addTask { try await Self.captureOne(d) }
            }
            var out: [DisplaySnapshot] = []
            for try await s in group { out.append(s) }
            return out
        }
        return snapshots.sorted { (order.firstIndex(of: $0.displayID) ?? 0) < (order.firstIndex(of: $1.displayID) ?? 0) }
    }

    /// Test harness: writes a PNG of one display as it currently looks, including Owl's own windows.
    func writeDisplayPNG(display: DisplayInfo, to url: URL) async throws {
        let snap = try await Self.captureOne(display)
        try PNGEncoder.write(snap.image, to: url)
    }

    nonisolated static func captureOne(_ d: DisplayInfo) async throws -> DisplaySnapshot {
        let geometry = d.geometry
        let size = geometry.pixelSize
        let config = SCScreenshotConfiguration()
        config.width = size.width
        config.height = size.height
        config.showsCursor = false
        config.displayIntent = .local
        config.dynamicRange = .sdr
        config.includeChildWindows = true
        // CGDisplayBounds is in global CG coordinates (points, origin top-left of the main display),
        // which is the space the rect API expects.
        let bounds = CGDisplayBounds(d.id)
        let start = ContinuousClock.now
        let output = try await SCScreenshotManager.captureScreenshot(rect: bounds, configuration: config)
        guard let image = output.sdrImage else { throw OwlError.captureReturnedNoImage }
        let ms = (ContinuousClock.now - start).milliseconds
        Log.capture.info("captured display \(d.id) \(image.width)x\(image.height) in \(ms, format: .fixed(precision: 1)) ms")
        return DisplaySnapshot(displayID: d.id, screenFrame: d.frame, geometry: geometry, image: image)
    }
}
