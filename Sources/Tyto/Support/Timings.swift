import Foundation
import TytoCore

nonisolated extension Duration {
    var milliseconds: Double {
        let c = components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
}

/// Wall-clock budget tracking for one capture session, exposed via `tytoctl timings`.
struct CaptureTimings: Sendable {
    var requestedAt: Date?
    var displays = 0
    /// Hotkey/request → all displays captured.
    var captureMS: Double?
    /// Hotkey/request → overlay windows ordered front and flushed.
    var overlayMS: Double?
    /// Copy command → clipboard written.
    var copyMS: Double?

    var json: [String: JSONValue] {
        var d: [String: JSONValue] = ["displays": JSONValue(displays)]
        if let t = requestedAt { d["requestedAt"] = .string(ISO8601DateFormatter().string(from: t)) }
        if let v = captureMS { d["captureMS"] = .number((v * 10).rounded() / 10) }
        if let v = overlayMS { d["overlayMS"] = .number((v * 10).rounded() / 10) }
        if let v = copyMS { d["copyMS"] = .number((v * 10).rounded() / 10) }
        return d
    }
}
