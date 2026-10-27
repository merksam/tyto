import Foundation

/// What ⇧⌘C puts on the clipboard after a send. The image itself only when asked: the point
/// of a destination is usually a path or a link, and ⌘C already copies the image.
public enum ClipboardChoice: String, Codable, CaseIterable, Sendable {
    case result, resultAndImage, nothing

    public var title: String {
        switch self {
        case .result: "The result"
        case .resultAndImage: "The result and the image"
        case .nothing: "Nothing"
        }
    }
}

/// A share destination hands the file to one system service, or to the picker that lists them
/// all (AirDrop, Messages, Notes, …).
public enum ShareService: String, Codable, CaseIterable, Sendable {
    case picker, airDrop, messages, mail

    public var title: String {
        switch self {
        case .picker: "Ask each time"
        case .airDrop: "AirDrop"
        case .messages: "Messages"
        case .mail: "Mail"
        }
    }
}

/// Somewhere a capture can be sent. Tyto never uploads anything itself: a script destination
/// runs a script the user installed, a share destination hands the file to the system.
public struct Destination: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case script, share }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// File name in the app's Application Scripts folder. Script destinations only.
    public var script: String?
    /// The preset that wrote the script and the values it was filled in with, so Edit can
    /// reopen the same sheet. nil for a script the user wrote by hand.
    public var preset: PresetID?
    public var fields: [String: String]
    public var clipboard: ClipboardChoice
    public var shareService: ShareService?

    public init(id: UUID = UUID(), name: String, kind: Kind, script: String? = nil, preset: PresetID? = nil,
                fields: [String: String] = [:], clipboard: ClipboardChoice = .result,
                shareService: ShareService? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.script = script; self.preset = preset
        self.fields = fields; self.clipboard = clipboard; self.shareService = shareService
    }

    /// A file name for a new script: the destination's name, lowercased, letters, digits and
    /// dashes only, so it needs no quoting anywhere it is typed.
    public static func scriptFileName(for name: String) -> String {
        var slug = ""
        for ch in name.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { slug.append(ch) }
            else if !slug.isEmpty, slug.last != "-" { slug.append("-") }
        }
        while slug.last == "-" { slug.removeLast() }
        return (slug.isEmpty ? "destination" : slug) + ".sh"
    }
}

/// Every destination plus which one is the default. Stored as one JSON value, versioned so a
/// later format can tell an old one apart instead of misreading it.
public struct DestinationList: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public var version = DestinationList.formatVersion
    public private(set) var destinations: [Destination] = []
    public private(set) var defaultID: UUID?
    /// Scripts the user removed from the list. Tyto can only read the scripts folder, so the
    /// file stays, and without this it would be adopted again on the next scan.
    public private(set) var dismissedScripts: [String] = []

    public init() {}

    /// The chosen default, or the first destination when that one is gone.
    public var defaultDestination: Destination? {
        destinations.first { $0.id == defaultID } ?? destinations.first
    }

    public func destination(id: UUID) -> Destination? { destinations.first { $0.id == id } }

    /// By id, or by name ignoring case: what `tytoctl send NAME` passes.
    public func destination(matching query: String) -> Destination? {
        if let id = UUID(uuidString: query), let d = destination(id: id) { return d }
        return destinations.first { $0.name.compare(query, options: .caseInsensitive) == .orderedSame }
    }

    /// Names label the Send button and its menu, so two destinations may not share one.
    public func isNameTaken(_ name: String, except id: UUID? = nil) -> Bool {
        destinations.contains { $0.id != id && $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    /// Replaces the destination with the same id, or appends it. The first one becomes the default.
    public mutating func upsert(_ destination: Destination) {
        if let i = destinations.firstIndex(where: { $0.id == destination.id }) {
            destinations[i] = destination
        } else {
            destinations.append(destination)
        }
        if let script = destination.script { dismissedScripts.removeAll { $0 == script } }
        if defaultID.flatMap(self.destination(id:)) == nil { defaultID = destinations.first?.id }
    }

    public mutating func remove(id: UUID) {
        guard let i = destinations.firstIndex(where: { $0.id == id }) else { return }
        let removed = destinations.remove(at: i)
        if let script = removed.script, !dismissedScripts.contains(script) { dismissedScripts.append(script) }
        if defaultID == id { defaultID = destinations.first?.id }
    }

    public mutating func setDefault(id: UUID) {
        guard destination(id: id) != nil else { return }
        defaultID = id
    }

    /// Scripts dropped into the folder by hand become destinations of their own, named after
    /// the file. Returns whether the list changed.
    @discardableResult
    public mutating func adoptScripts(_ names: [String]) -> Bool {
        let before = self
        let known = Set(destinations.compactMap(\.script))
        for file in names.sorted() where !known.contains(file) && !dismissedScripts.contains(file) {
            let base = (file as NSString).deletingPathExtension
            upsert(Destination(name: uniqueName(base.isEmpty ? file : base), kind: .script, script: file))
        }
        // A dismissal only holds while its file is there; a new file by that name is new.
        let present = Set(names)
        dismissedScripts.removeAll { !present.contains($0) }
        return self != before
    }

    private func uniqueName(_ base: String) -> String {
        guard isNameTaken(base) else { return base }
        var n = 2
        while isNameTaken("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// nil for data written by a newer Tyto, or for data that is not a list at all.
    public static func decode(_ data: Data) -> DestinationList? {
        guard let list = try? JSONDecoder().decode(DestinationList.self, from: data),
              list.version <= formatVersion else { return nil }
        return list
    }
}

/// One finished send, as the activity list shows it.
public struct SendRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var destination: String
    public var ok: Bool
    /// The result on success, the reason on failure.
    public var detail: String

    public init(id: UUID = UUID(), date: Date, destination: String, ok: Bool, detail: String) {
        self.id = id; self.date = date; self.destination = destination; self.ok = ok; self.detail = detail
    }
}

/// The last sends, newest first. Kept short on purpose: it answers "what did that just do",
/// it is not a history.
public struct ActivityLog: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public static let limit = 20

    public var version = ActivityLog.formatVersion
    public private(set) var records: [SendRecord] = []

    public init() {}

    /// Sends finish in any order, so a record goes where its date puts it, not simply on top.
    public mutating func add(_ record: SendRecord) {
        let i = records.firstIndex { $0.date <= record.date } ?? records.endIndex
        records.insert(record, at: i)
        if records.count > Self.limit { records.removeLast(records.count - Self.limit) }
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public static func decode(_ data: Data) -> ActivityLog? {
        guard let log = try? JSONDecoder().decode(ActivityLog.self, from: data),
              log.version <= formatVersion else { return nil }
        return log
    }
}
