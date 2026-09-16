import Foundation

nonisolated enum TytoError: Error, CustomStringConvertible {
    case noScreenCapturePermission
    case sessionAlreadyActive
    case noSession
    case noDisplays
    case unknownDisplay(String)
    case captureReturnedNoImage
    case noSelection
    case cropFailed
    case encodeFailed
    case badRequest(String)
    case clipboardEmpty

    var description: String {
        switch self {
        case .noScreenCapturePermission: "Screen Recording permission not granted"
        case .sessionAlreadyActive: "a capture session is already active"
        case .noSession: "no capture session is active"
        case .noDisplays: "no displays matched"
        case .unknownDisplay(let s): "unknown display: \(s)"
        case .captureReturnedNoImage: "ScreenCaptureKit returned no image"
        case .noSelection: "nothing is selected"
        case .cropFailed: "cropping the frozen frame failed"
        case .encodeFailed: "image encoding failed"
        case .badRequest(let s): "bad request: \(s)"
        case .clipboardEmpty: "clipboard holds no image"
        }
    }
}
