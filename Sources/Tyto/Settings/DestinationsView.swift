import AppKit
import SwiftUI
import TytoCore

/// What the New/Edit sheet holds until Save.
struct DestinationDraft: Identifiable {
    enum Kind: Hashable {
        case preset(PresetID)
        case handWritten
        case share

        var title: String {
            switch self {
            case .preset(let p): p.title
            case .handWritten: "Your own script"
            case .share: "Share sheet"
            }
        }
    }

    let id: UUID
    let isNew: Bool
    var kind: Kind
    var name = ""
    /// One bag for every preset's fields, so switching presets in a new sheet keeps what was typed.
    var values: [String: String] = [:]
    var script: String?
    var clipboard = ClipboardChoice.result
    var shareService = ShareService.picker

    static let newKinds: [Kind] = PresetID.allCases.map(Kind.preset) + [.share]

    init() {
        id = UUID()
        isNew = true
        kind = .preset(.ssh)
        for p in PresetID.allCases { values.merge(p.normalized([:])) { a, _ in a } }
    }

    init(_ d: Destination) {
        id = d.id
        isNew = false
        kind = d.kind == .share ? .share : d.preset.map(Kind.preset) ?? .handWritten
        name = d.name
        values = d.fields
        script = d.script
        clipboard = d.clipboard
        shareService = d.shareService ?? .picker
    }

    var suggestedName: String {
        switch kind {
        case .preset(let p): p.suggestedName(values)
        case .handWritten: script.map { ($0 as NSString).deletingPathExtension } ?? "Script"
        case .share: shareService == .picker ? "Share" : shareService.title
        }
    }

    var resolvedName: String {
        let typed = name.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? suggestedName : typed
    }
}

@MainActor final class DestinationsModel: ObservableObject {
    enum SaveResult { case saved, cancelled, failed(String) }

    @Published private(set) var list = Settings.destinationList
    @Published private(set) var activity = Settings.sendActivity.records
    @Published private(set) var scripts: [String] = []
    @Published var draft: DestinationDraft?
    let scriptsFolderPath = ScriptsFolder.url?.path ?? "not available"

    /// Rescans the scripts folder: a script dropped in by hand shows up here.
    func refresh() {
        scripts = ScriptsFolder.scriptNames()
        list = ScriptsFolder.adoptNewScripts()
        activity = Settings.sendActivity.records
    }

    func reload() {
        list = Settings.destinationList
        activity = Settings.sendActivity.records
    }

    func scriptExists(_ d: Destination) -> Bool {
        d.script.map(scripts.contains) ?? false
    }

    func makeDefault(_ d: Destination) { change { $0.setDefault(id: d.id) } }
    func remove(_ d: Destination) { change { $0.remove(id: d.id) } }

    private func change(_ body: (inout DestinationList) -> Void) {
        var l = Settings.destinationList
        body(&l)
        Settings.destinationList = l
        reload()
    }

    /// Writes the script only when it has to: a new destination, changed fields or a missing
    /// file. Renaming one or changing what it copies needs no save panel, and a generated
    /// script the user has since edited by hand survives that.
    func save(_ draft: DestinationDraft) -> SaveResult {
        var list = Settings.destinationList
        let name = draft.resolvedName
        if list.isNameTaken(name, except: draft.id) { return .failed("Another destination is already called \(name).") }
        var d = list.destination(id: draft.id) ?? Destination(id: draft.id, name: name, kind: .script)
        d.name = name
        d.clipboard = draft.clipboard
        switch draft.kind {
        case .share:
            d.kind = .share
            d.shareService = draft.shareService
        case .handWritten:
            guard let script = draft.script else { return .failed("Choose a script.") }
            d.kind = .script
            d.script = script
        case .preset(let preset):
            let values = preset.normalized(draft.values)
            if let problem = preset.validate(values).first {
                let label = preset.fields.first { $0.key == problem.key }?.label ?? problem.key
                return .failed("\(label): \(problem.value)")
            }
            let missing = d.script.map { !ScriptsFolder.scriptNames().contains($0) } ?? true
            if draft.isNew || d.preset != preset || d.fields != values || missing {
                do {
                    guard let file = try ScriptsFolder.install(preset.render(values),
                                                               suggestedName: d.script ?? Destination.scriptFileName(for: name)) else {
                        return .cancelled
                    }
                    d.script = file
                } catch {
                    return .failed(String(describing: error))
                }
                // The panel was modal; whatever happened meanwhile is in the stored list.
                list = Settings.destinationList
            }
            d.kind = .script
            d.preset = preset
            d.fields = values
        }
        list.upsert(d)
        Settings.destinationList = list
        refresh()
        return .saved
    }

    func copy(_ record: SendRecord) { Clipboard.write(text: record.detail) }
}

struct DestinationsView: View {
    @ObservedObject var model: DestinationsModel

    var body: some View {
        Form {
            Section {
                if model.list.destinations.isEmpty {
                    Text("Nothing yet. A destination sends a capture somewhere other than the clipboard: a folder on a server, a bucket, a webhook, AirDrop.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.list.destinations) { d in row(d) }
                }
                HStack {
                    Button("New Destination…") { model.draft = DestinationDraft() }
                    Spacer()
                    Button("Show Scripts Folder") { ScriptsFolder.reveal() }
                }
            } header: {
                Text("Destinations")
            } footer: {
                Text("⇧⌘C sends to the default. Tyto makes no network connections: a destination runs a script from \(model.scriptsFolderPath), as you, and that script may. Scripts you put there yourself show up here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Recent Sends") {
                if model.activity.isEmpty {
                    Text("Nothing sent yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.activity) { r in activityRow(r) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: Settings.destinationsChanged)) { _ in
            model.reload()
        }
        .sheet(item: $model.draft) { draft in
            DestinationSheet(model: model, draft: draft)
        }
    }

    private func row(_ d: Destination) -> some View {
        let isDefault = d.id == model.list.defaultDestination?.id
        return HStack(spacing: 10) {
            Image(systemName: d.kind == .share ? "square.and.arrow.up" : "terminal")
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name)
                Text(detail(d))
                    .font(.caption)
                    .foregroundStyle(d.kind == .script && !model.scriptExists(d) ? Color.red : .secondary)
            }
            Spacer()
            if isDefault {
                Text("Default")
                    .font(.caption)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            }
            Menu {
                Button("Edit…") { model.draft = DestinationDraft(d) }
                Button("Make Default") { model.makeDefault(d) }.disabled(isDefault)
                Divider()
                Button("Remove") { model.remove(d) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func detail(_ d: Destination) -> String {
        switch d.kind {
        case .share:
            return "Share sheet · \((d.shareService ?? .picker).title)"
        case .script:
            let script = d.script ?? "no script"
            let state = model.scriptExists(d) ? "copies \(d.clipboard.title.lowercased())" : "missing from the scripts folder"
            return "\(d.preset?.title ?? "Script") · \(script) · \(state)"
        }
    }

    private func activityRow(_ r: SendRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(r.ok ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(r.destination) · \(r.date.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(r.detail.isEmpty ? (r.ok ? "Sent" : "Failed") : r.detail)
                    .lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if r.ok, !r.detail.isEmpty {
                Button("Copy Result") { model.copy(r) }.controlSize(.small)
            }
        }
    }
}

/// New Destination and Edit: pick a preset, fill its fields, Save. For a preset Save renders
/// the script and asks where to put it, opening on the scripts folder.
private struct DestinationSheet: View {
    @ObservedObject var model: DestinationsModel
    @State var draft: DestinationDraft
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    if draft.isNew {
                        Picker("Type", selection: $draft.kind) {
                            ForEach(DestinationDraft.newKinds, id: \.self) { Text($0.title).tag($0) }
                        }
                    } else {
                        LabeledContent("Type", value: draft.kind.title)
                    }
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("Name", text: $draft.name, prompt: Text(draft.suggestedName))
                }

                switch draft.kind {
                case .preset(let preset):
                    if !preset.fields.isEmpty {
                        Section {
                            ForEach(preset.fields) { field in fieldRow(field) }
                        }
                    }
                case .handWritten:
                    Section {
                        Picker("Script", selection: $draft.script) {
                            ForEach(model.scripts, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                    }
                case .share:
                    Section {
                        Picker("Send with", selection: $draft.shareService) {
                            ForEach(ShareService.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }

                if draft.kind != .share {
                    Section {
                        Picker("⇧⌘C copies", selection: $draft.clipboard) {
                            ForEach(ClipboardChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if let error {
                    Text(error).foregroundStyle(.red).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saveTitle) { save() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: String {
        switch draft.kind {
        case .preset(let p): p.summary
        case .handWritten: "A script you put in the scripts folder yourself. Tyto runs it as it is."
        case .share: "Hands the capture to AirDrop, Messages, Mail or anything else in the share menu. Nothing is copied."
        }
    }

    /// "Save Script…" whenever Save will open the save panel.
    private var saveTitle: String {
        guard case .preset(let p) = draft.kind else { return "Save" }
        if draft.isNew { return "Save Script…" }
        let existing = model.list.destination(id: draft.id)
        let changed = existing?.preset != p || existing?.fields != p.normalized(draft.values)
        return changed ? "Save Script…" : "Save"
    }

    private func fieldRow(_ field: PresetField) -> some View {
        let binding = Binding(get: { draft.values[field.key] ?? "" }, set: { draft.values[field.key] = $0 })
        return VStack(alignment: .leading, spacing: 4) {
            TextField(field.label, text: binding, prompt: Text(field.placeholder))
                .autocorrectionDisabled()
            if let help = field.help {
                Text(help).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func save() {
        switch model.save(draft) {
        case .saved: dismiss()
        case .cancelled: break
        case .failed(let message): error = message
        }
    }
}
