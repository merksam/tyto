import AppKit
import OwlCore
import SwiftUI

/// Observable mirror of `Settings` for the SwiftUI form.
@MainActor final class SettingsModel: ObservableObject {
    @Published var hotkeyDisplay = Settings.hotKeyDisplay
    @Published var defaultTool = Settings.defaultTool { didSet { Settings.defaultTool = defaultTool } }
    @Published var defaultColorName = Settings.defaultColor.name ?? "red" {
        didSet { if let c = RGBAColor.named(defaultColorName) { Settings.defaultColor = c } }
    }
    @Published var defaultWidth = Settings.defaultWidth { didSet { Settings.defaultWidth = defaultWidth } }
    @Published var autoSaveRecent = Settings.autoSaveRecent { didSet { Settings.autoSaveRecent = autoSaveRecent } }
    @Published var copyAsFile = Settings.copyAsFile { didSet { Settings.copyAsFile = copyAsFile } }
    @Published var launchAtLogin = Settings.launchAtLogin { didSet { Settings.launchAtLogin = launchAtLogin } }
    @Published var saveDirectory = Settings.saveDirectory.path

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            Settings.saveDirectory = url
            saveDirectory = url.path
        }
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsModel()

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Capture region") {
                    HotkeyRecorder(display: $model.hotkeyDisplay)
                        .frame(width: 160, height: 26)
                }
            }

            Section("Defaults for new captures") {
                Picker("Tool", selection: $model.defaultTool) {
                    ForEach(Tool.allCases.filter { $0 != .select }, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Color", selection: $model.defaultColorName) {
                    ForEach(RGBAColor.palette, id: \.name) { Text($0.name.capitalized).tag($0.name) }
                }
                Picker("Line thickness", selection: $model.defaultWidth) {
                    ForEach(WidthPreset.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }

            Section("Captures") {
                Toggle("Save every capture to a folder", isOn: $model.autoSaveRecent)
                LabeledContent("Save location") {
                    HStack {
                        Text(model.saveDirectory).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { model.chooseSaveDirectory() }
                    }
                }
                Toggle("Also copy as a file (for Finder and file drop targets)", isOn: $model.copyAsFile)
            }

            Section("General") {
                Toggle("Launch Owl at login", isOn: $model.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
