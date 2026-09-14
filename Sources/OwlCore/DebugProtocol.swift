import Foundation

/// Newline-delimited JSON protocol between `owlctl` and the running app's debug socket.
public struct DebugRequest: Codable, Sendable {
    public var cmd: String
    /// "all" | "main" | "secondary" | "<CGDirectDisplayID>"
    public var display: String?
    public var x: Int?
    public var y: Int?
    public var w: Int?
    public var h: Int?
    public var path: String?
    /// Test mode: no app activation, no key window, no presentation-option changes.
    public var test: Bool?
    /// Second point for `draw` (x2, y2); free-form value for `tool`, `color`, `width`, `text`, `set`.
    public var x2: Int?
    public var y2: Int?
    public var value: String?
    public var key: String?

    public init(cmd: String) { self.cmd = cmd }
}

public struct DebugResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var data: [String: JSONValue]

    public init(ok: Bool, error: String? = nil, data: [String: JSONValue] = [:]) {
        self.ok = ok; self.error = error; self.data = data
    }

    public static func success(_ data: [String: JSONValue] = [:]) -> DebugResponse {
        DebugResponse(ok: true, data: data)
    }

    public static func failure(_ message: String) -> DebugResponse {
        DebugResponse(ok: false, error: message)
    }
}

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(_ i: Int) { self = .number(Double(i)) }
    public init(_ d: Double) { self = .number(d) }
    public init(_ s: String) { self = .string(s) }
    public init(_ b: Bool) { self = .bool(b) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

public enum DebugSocket {
    /// Shared by the app and owlctl. Overridable with OWL_DEBUG_SOCKET.
    public static var path: String {
        if let p = ProcessInfo.processInfo.environment["OWL_DEBUG_SOCKET"], !p.isEmpty { return p }
        return NSHomeDirectory() + "/Library/Application Support/Owl/debug.sock"
    }
}
