import Foundation

/// How a destination script ended, as far as Tyto could tell.
public enum ScriptTermination: Equatable, Sendable {
    case exited(Int32)
    /// It could not be started, or failed in a way that came without an exit status.
    case failedToRun(String)
    case timedOut

    /// NSUserUnixTask reports a non-zero exit only as an error whose reason reads "Script task
    /// exited with status 3". The status is worth keeping for the message when stderr is empty.
    public static func from(errorReason reason: String) -> ScriptTermination {
        if let r = reason.range(of: "exited with status "),
           let status = Int32(reason[r.upperBound...].prefix { $0.isNumber }) {
            return .exited(status)
        }
        return .failedToRun(reason)
    }
}

public enum SendOutcome: Equatable, Sendable {
    /// The first line the script printed; may be empty.
    case sent(result: String)
    case failed(reason: String)

    public var ok: Bool { if case .sent = self { true } else { false } }
}

/// What Tyto promises a destination script, and how it reads the answer.
public enum ScriptContract {
    public static let timeout: Duration = .seconds(60)

    /// `$1` the PNG, `$2` a suggested name for it.
    public static func arguments(png: String, suggestedName: String) -> [String] {
        [png, suggestedName]
    }

    /// `tyto-YYYYMMDD-HHMMSS.png`: sorts by time, and needs no quoting on any command line or
    /// in a URL, unlike the "Tyto 2026-10-27 at 17.14.30.png" the save folder uses.
    public static func suggestedName(for date: Date, in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "tyto-%04d%02d%02d-%02d%02d%02d.png",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Exit 0 is success and the first line of stdout is the result. Anything else is a
    /// failure, explained by the last line the script wrote to stderr.
    public static func outcome(_ termination: ScriptTermination, stdout: Data, stderr: Data) -> SendOutcome {
        switch termination {
        case .exited(0):
            let text = String(decoding: stdout, as: UTF8.self)
            let first = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).first ?? ""
            return .sent(result: first.trimmingCharacters(in: .whitespaces))
        case .exited(let status):
            return .failed(reason: lastLine(of: stderr) ?? "exited with status \(status)")
        case .failedToRun(let reason):
            return .failed(reason: lastLine(of: stderr) ?? reason)
        case .timedOut:
            return .failed(reason: "no answer after \(timeout.components.seconds) s")
        }
    }

    private static func lastLine(of data: Data) -> String? {
        String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }
}

/// The words for the HUD after a send.
public enum SendFeedback {
    public enum ClipboardEffect: String, Sendable {
        /// The destination copies nothing, or the result was empty.
        case none
        case text
        case textAndImage
        /// Something else was copied while the send ran, and that wins.
        case skipped
    }

    /// "Sent to devbox · path copied", "devbox failed: Permission denied".
    public static func message(destination: String, outcome: SendOutcome, clipboard: ClipboardEffect) -> String {
        switch outcome {
        case .failed(let reason):
            return "\(destination) failed: \(reason)"
        case .sent(let result):
            let what = resultKind(result)
            switch clipboard {
            case .none: return "Sent to \(destination)"
            case .text: return "Sent to \(destination) · \(what) copied"
            case .textAndImage: return "Sent to \(destination) · \(what) and image copied"
            case .skipped: return "Sent to \(destination) · \(what) not copied, the clipboard changed"
            }
        }
    }

    /// "link" for a URL, "path" for a file path, "result" for anything else a script printed.
    public static func resultKind(_ result: String) -> String {
        if let colon = result.range(of: "://"), !result[..<colon.lowerBound].isEmpty,
           result[..<colon.lowerBound].allSatisfy({ $0.isLetter || $0.isNumber || "+.-".contains($0) }) {
            return "link"
        }
        if result.hasPrefix("/") || result.hasPrefix("~") { return "path" }
        return "result"
    }
}
