import AppKit
import TytoCore
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
    @Published var screenCaptureGranted = Permissions.hasScreenCapture
    @Published var saveDirectory = Settings.saveDirectoryDisplayPath
    @Published var hasCustomSaveDirectory = Settings.hasCustomSaveDirectory

    func refreshPermissionState() { screenCaptureGranted = Permissions.hasScreenCapture }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Settings.saveDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // The panel result carries its own sandbox extension; bookmark it so the grant
            // survives relaunches.
            try Settings.setSaveDirectory(url)
        } catch {
            Log.app.error("could not use \(url.path) as the save folder: \(String(describing: error))")
        }
        refreshSaveDirectory()
    }

    func useDefaultSaveDirectory() {
        try? Settings.setSaveDirectory(nil)
        refreshSaveDirectory()
    }

    private func refreshSaveDirectory() {
        saveDirectory = Settings.saveDirectoryDisplayPath
        hasCustomSaveDirectory = Settings.hasCustomSaveDirectory
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsModel()

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    HStack {
                        Text(model.screenCaptureGranted ? "Allowed" : "Not allowed")
                            .foregroundStyle(model.screenCaptureGranted ? .secondary : Color.red)
                        Button("Open System Settings…") { Permissions.openScreenCaptureSettings() }
                    }
                }
                if !model.screenCaptureGranted {
                    Text("Tyto needs Screen Recording to capture the screen. Relaunch Tyto after granting it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

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
                        if model.hasCustomSaveDirectory {
                            Button("Use Default") { model.useDefaultSaveDirectory() }
                        }
                    }
                }
                Toggle("Also copy as a file (for Finder and file drop targets)", isOn: $model.copyAsFile)
            }

            Section("General") {
                Toggle("Launch Tyto at login", isOn: $model.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissionState()
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
