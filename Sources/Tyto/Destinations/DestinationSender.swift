import AppKit
import TytoCore

/// Everything after the overlay hands over a finished image: the file a script reads, the run,
/// the clipboard, the activity list and the HUD. Tyto never uploads anything itself; a script
/// destination runs the user's script, a share destination hands the file to the system.
@MainActor final class DestinationSender: NSObject {
    struct Report: Sendable {
        let destination: String
        let outcome: SendOutcome
        let clipboard: SendFeedback.ClipboardEffect
        let message: String
    }

    let hud = SendHUD()
    /// The owl in the menu bar: with the overlay gone, the share picker hangs from it.
    var shareAnchor: (() -> NSView?)?

    private struct PendingShare {
        let name: String
        let returnTo: NSRunningApplication?
        let picker: NSSharingServicePicker?
    }
    private var pendingShare: PendingShare?

    // MARK: Scripts

    func send(_ image: CGImage, to destination: Destination) -> Task<Report, Never> {
        // Whatever the user copies while the script runs wins over the result.
        let changeCount = NSPasteboard.general.changeCount
        hud.show("Sending to \(destination.name)…", style: .progress)
        Log.app.info("sending to \(destination.name)")
        return Task {
            let outcome = await self.runScript(image, destination)
            let effect = self.updateClipboard(outcome, choice: destination.clipboard, image: image, since: changeCount)
            let message = SendFeedback.message(destination: destination.name, outcome: outcome, clipboard: effect)
            self.record(destination.name, outcome)
            self.hud.show(message, style: outcome.ok ? .success : .failure)
            Log.app.info("send finished: \(message)")
            return Report(destination: destination.name, outcome: outcome, clipboard: effect, message: message)
        }
    }

    private func runScript(_ image: CGImage, _ destination: Destination) async -> SendOutcome {
        guard let script = destination.script, let url = ScriptsFolder.scriptURL(script) else {
            return .failed(reason: "no script chosen")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failed(reason: "\(script) is not in the scripts folder")
        }
        // NSUserUnixTask only calls such a file "not in the correct format".
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            return .failed(reason: "\(script) is not executable; chmod +x it")
        }
        let file: URL
        do {
            file = try Outbox.write(image)
        } catch {
            return .failed(reason: "could not write the PNG: \(error.localizedDescription)")
        }
        let run = await ScriptRunner.run(url, arguments: ScriptContract.arguments(png: file.path, suggestedName: file.lastPathComponent),
                                         timeout: ScriptContract.timeout)
        return ScriptContract.outcome(run.termination, stdout: run.stdout, stderr: run.stderr)
    }

    private func updateClipboard(_ outcome: SendOutcome, choice: ClipboardChoice, image: CGImage,
                                 since changeCount: Int) -> SendFeedback.ClipboardEffect {
        guard case .sent(let result) = outcome, !result.isEmpty, choice != .nothing else { return .none }
        guard NSPasteboard.general.changeCount == changeCount else { return .skipped }
        switch choice {
        case .result:
            Clipboard.write(text: result)
            return .text
        case .resultAndImage:
            do {
                try Clipboard.write(image: image, text: result)
                return .textAndImage
            } catch {
                Log.app.error("send: writing the image failed, copying the result alone: \(String(describing: error))")
                Clipboard.write(text: result)
                return .text
            }
        case .nothing:
            return .none
        }
    }

    private func record(_ name: String, _ outcome: SendOutcome) {
        var log = Settings.sendActivity
        switch outcome {
        case .sent(let result): log.add(SendRecord(date: Date(), destination: name, ok: true, detail: result))
        case .failed(let reason): log.add(SendRecord(date: Date(), destination: name, ok: false, detail: reason))
        }
        Settings.sendActivity = log
    }

    // MARK: Share sheet

    /// Hands the file to one service, or to the picker. The system does the sending and shows
    /// its own progress, so the HUD only speaks up when it fails.
    func share(_ image: CGImage, service: ShareService, name: String, returnTo app: NSRunningApplication?) {
        let file: URL
        do {
            file = try Outbox.write(image)
        } catch {
            hud.show("\(name) failed: could not write the PNG", style: .failure)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        if let serviceName = service.sharingServiceName, let s = NSSharingService(named: serviceName),
           s.canPerform(withItems: [file]) {
            pendingShare = PendingShare(name: name, returnTo: app, picker: nil)
            s.delegate = self
            s.perform(withItems: [file])
            return
        }
        // Give the menu bar a moment to come back from the overlay's auto-hide first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            guard let anchor = self.shareAnchor?(), anchor.window != nil else {
                self.hud.show("\(name) failed: nowhere to show the share menu", style: .failure)
                return
            }
            let picker = NSSharingServicePicker(items: [file])
            picker.delegate = self
            self.pendingShare = PendingShare(name: name, returnTo: app, picker: picker)
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    private func finishShare(_ outcome: SendOutcome?) {
        guard let pending = pendingShare else { return }
        pendingShare = nil
        if let outcome {
            record(pending.name, outcome)
            if case .failed = outcome {
                hud.show(SendFeedback.message(destination: pending.name, outcome: outcome, clipboard: .none), style: .failure)
            }
        }
        pending.returnTo?.activate()
    }
}

extension DestinationSender: NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        self
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { finishShare(nil) }   // dismissed
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finishShare(.sent(result: "Shared with \(sharingService.title)"))
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let e = error as NSError
        let cancelled = e.domain == NSCocoaErrorDomain && e.code == NSUserCancelledError
        finishShare(cancelled ? nil : .failed(reason: e.localizedDescription))
    }
}

extension ShareService {
    var sharingServiceName: NSSharingService.Name? {
        switch self {
        case .picker: nil
        case .airDrop: .sendViaAirDrop
        case .messages: .composeMessage
        case .mail: .composeEmail
        }
    }
}

/// The PNG a destination reads, named as the contract says. Not in the container's temp folder:
/// macOS keeps other processes out of an app's container, and a script, though it runs as the
/// user, is another process; scp got "Operation not permitted" there. ~/Pictures is the one
/// place Tyto may write without asking (the pictures entitlement), so the file goes into a
/// hidden folder beside the captures.
enum Outbox {
    static var directory: URL {
        Settings.defaultSaveDirectory.appendingPathComponent(".outbox", isDirectory: true)
    }

    /// One folder per send, so two sends in the same second keep their own file and `$1`
    /// always ends in `$2`.
    static func write(_ image: CGImage, at date: Date = Date()) throws -> URL {
        prune()
        let dir = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(ScriptContract.suggestedName(for: date))
        try PNGEncoder.write(image, to: url)
        return url
    }

    /// A day is longer than any script needs, and a slow one still finds its file.
    static func prune(olderThan age: TimeInterval = 24 * 3600) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                                                        options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for url in entries {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < cutoff { try? fm.removeItem(at: url) }
        }
    }
}
