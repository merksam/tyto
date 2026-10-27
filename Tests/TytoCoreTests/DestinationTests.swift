import Foundation
import Testing
@testable import TytoCore

@Suite struct DestinationListTests {
    @Test func roundTripsAndCarriesItsVersion() throws {
        var list = DestinationList()
        list.upsert(Destination(name: "devbox", kind: .script, script: "devbox.sh", preset: .ssh,
                                fields: ["host": "devbox", "folder": "clips"], clipboard: .resultAndImage))
        list.upsert(Destination(name: "Share", kind: .share, shareService: .airDrop))
        let data = try list.encoded()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == DestinationList.formatVersion)
        #expect(DestinationList.decode(data) == list)
    }

    @Test func refusesANewerFormatAndGarbage() throws {
        var json = try #require(JSONSerialization.jsonObject(with: DestinationList().encoded()) as? [String: Any])
        json["version"] = DestinationList.formatVersion + 1
        #expect(DestinationList.decode(try JSONSerialization.data(withJSONObject: json)) == nil)
        #expect(DestinationList.decode(Data("not json".utf8)) == nil)
    }

    @Test func firstIsDefaultAndRemovingTheDefaultMovesIt() {
        var list = DestinationList()
        let a = Destination(name: "a", kind: .script, script: "a.sh")
        let b = Destination(name: "b", kind: .script, script: "b.sh")
        list.upsert(a)
        list.upsert(b)
        #expect(list.defaultDestination?.id == a.id)
        list.setDefault(id: b.id)
        #expect(list.defaultDestination?.id == b.id)
        list.remove(id: b.id)
        #expect(list.defaultDestination?.id == a.id)
        list.remove(id: a.id)
        #expect(list.defaultDestination == nil)
    }

    @Test func upsertReplacesInPlace() {
        var list = DestinationList()
        var a = Destination(name: "a", kind: .script, script: "a.sh")
        list.upsert(a)
        a.name = "renamed"
        list.upsert(a)
        #expect(list.destinations.map(\.name) == ["renamed"])
    }

    @Test func findsByNameIgnoringCaseOrById() {
        var list = DestinationList()
        let a = Destination(name: "DevBox", kind: .script, script: "devbox.sh")
        list.upsert(a)
        #expect(list.destination(matching: "devbox")?.id == a.id)
        #expect(list.destination(matching: a.id.uuidString)?.id == a.id)
        #expect(list.destination(matching: "other") == nil)
        #expect(list.isNameTaken("DEVBOX"))
        #expect(!list.isNameTaken("devbox", except: a.id))
    }

    @Test func adoptsHandWrittenScriptsOnceAndRemembersRemovals() {
        var list = DestinationList()
        list.upsert(Destination(name: "devbox", kind: .script, script: "devbox.sh", preset: .ssh))
        let scripts = ["devbox.sh", "upload.py", "devbox.rb"]
        let first = list.adoptScripts(scripts)
        #expect(first)
        #expect(list.destinations.map(\.name) == ["devbox", "devbox 2", "upload"])
        let again = list.adoptScripts(scripts)
        #expect(!again)

        let upload = list.destination(matching: "upload")!
        list.remove(id: upload.id)
        let afterRemoval = list.adoptScripts(scripts)
        #expect(!afterRemoval)
        #expect(list.destination(matching: "upload") == nil)

        // Once the file is gone, a new one by that name is a new script.
        list.adoptScripts(["devbox.sh", "devbox.rb"])
        list.adoptScripts(["devbox.sh", "devbox.rb", "upload.py"])
        #expect(list.destination(matching: "upload") != nil)
    }

    @Test func scriptFileNamesNeedNoQuoting() {
        #expect(Destination.scriptFileName(for: "devbox") == "devbox.sh")
        #expect(Destination.scriptFileName(for: "My S3 — bucket!") == "my-s3-bucket.sh")
        #expect(Destination.scriptFileName(for: "  ") == "destination.sh")
        #expect(Destination.scriptFileName(for: "Знімки") == "destination.sh")
    }
}

@Suite struct ActivityLogTests {
    private func record(_ seconds: TimeInterval, _ name: String = "devbox") -> SendRecord {
        SendRecord(date: Date(timeIntervalSince1970: seconds), destination: name, ok: true, detail: "~/clips/\(Int(seconds)).png")
    }

    @Test func keepsTheLastTwentyNewestFirst() {
        var log = ActivityLog()
        for i in 1...25 { log.add(record(TimeInterval(i))) }
        #expect(log.records.count == 20)
        #expect(log.records.first?.date == Date(timeIntervalSince1970: 25))
        #expect(log.records.last?.date == Date(timeIntervalSince1970: 6))
    }

    @Test func aSlowSendLandsWhereItsDatePutsIt() {
        var log = ActivityLog()
        log.add(record(10))
        log.add(record(30))
        log.add(record(20))
        #expect(log.records.map(\.date.timeIntervalSince1970) == [30, 20, 10])
    }

    @Test func roundTrips() throws {
        var log = ActivityLog()
        log.add(SendRecord(date: Date(timeIntervalSince1970: 1), destination: "s3", ok: false, detail: "denied"))
        #expect(ActivityLog.decode(try log.encoded()) == log)
    }
}

@Suite struct ScriptContractTests {
    @Test func passesThePNGThenTheName() {
        #expect(ScriptContract.arguments(png: "/tmp/a b/x.png", suggestedName: "tyto-1.png") == ["/tmp/a b/x.png", "tyto-1.png"])
    }

    @Test func suggestedNameIsATimestampWithoutSpaces() {
        let date = Date(timeIntervalSince1970: 1_793_121_270)   // 2026-10-27 17:14:30 UTC
        let name = ScriptContract.suggestedName(for: date, in: TimeZone(identifier: "UTC")!)
        #expect(name == "tyto-20261027-171430.png")
        #expect(!name.contains(" "))
        #expect(ScriptContract.suggestedName(for: date, in: TimeZone(identifier: "Europe/Kyiv")!) == "tyto-20261027-191430.png")
    }

    @Test func successIsTheFirstLineOfStdout() {
        let out = Data("~/clips/a.png\r\nmore\n".utf8)
        #expect(ScriptContract.outcome(.exited(0), stdout: out, stderr: Data("noise\n".utf8)) == .sent(result: "~/clips/a.png"))
        #expect(ScriptContract.outcome(.exited(0), stdout: Data(), stderr: Data()) == .sent(result: ""))
    }

    @Test func failureIsTheLastLineOfStderr() {
        let err = Data("warning: x\nscp: clips: Permission denied\n\n".utf8)
        #expect(ScriptContract.outcome(.exited(1), stdout: Data("partial\n".utf8), stderr: err)
                == .failed(reason: "scp: clips: Permission denied"))
        #expect(ScriptContract.outcome(.exited(3), stdout: Data(), stderr: Data()) == .failed(reason: "exited with status 3"))
        #expect(ScriptContract.outcome(.failedToRun("not executable"), stdout: Data(), stderr: Data())
                == .failed(reason: "not executable"))
    }

    @Test func aTimeoutIsAFailureWhateverWasPrinted() {
        #expect(ScriptContract.timeout == .seconds(60))
        #expect(ScriptContract.outcome(.timedOut, stdout: Data("~/clips/a.png\n".utf8), stderr: Data())
                == .failed(reason: "no answer after 60 s"))
    }

    @Test func readsTheExitStatusOutOfTheTaskError() {
        #expect(ScriptTermination.from(errorReason: "Script task exited with status 3") == .exited(3))
        #expect(ScriptTermination.from(errorReason: "The file couldn’t be opened.") == .failedToRun("The file couldn’t be opened."))
    }
}

@Suite struct SendFeedbackTests {
    @Test func saysWhatWasCopied() {
        let path = SendOutcome.sent(result: "~/clips/tyto-20261027-171430.png")
        #expect(SendFeedback.message(destination: "devbox", outcome: path, clipboard: .text) == "Sent to devbox · path copied")
        #expect(SendFeedback.message(destination: "s3", outcome: .sent(result: "https://x/y.png"), clipboard: .textAndImage)
                == "Sent to s3 · link and image copied")
        #expect(SendFeedback.message(destination: "devbox", outcome: path, clipboard: .none) == "Sent to devbox")
        #expect(SendFeedback.message(destination: "devbox", outcome: path, clipboard: .skipped)
                == "Sent to devbox · path not copied, the clipboard changed")
        #expect(SendFeedback.message(destination: "devbox", outcome: .failed(reason: "Permission denied"), clipboard: .none)
                == "devbox failed: Permission denied")
    }

    @Test func tellsLinksFromPaths() {
        #expect(SendFeedback.resultKind("https://example.com/a.png") == "link")
        #expect(SendFeedback.resultKind("s3://bucket/a.png") == "link")
        #expect(SendFeedback.resultKind("/srv/clips/a.png") == "path")
        #expect(SendFeedback.resultKind("ok") == "result")
        #expect(SendFeedback.resultKind("see: ://x") == "result")
    }
}

@Suite struct PresetTests {
    @Test func everyPlaceholderHasAField() {
        for preset in PresetID.allCases {
            #expect(preset.placeholders == Set(preset.fields.map(\.key)), "\(preset)")
        }
    }

    @Test func quotingRoundTripsThroughSh() throws {
        for value in ["plain", "", "it's", #"say "hi""#, "$(touch pwned)", "`touch pwned`", "a b\tc",
                      "two\nlines", "$HOME ~ * ; & | \\ '\\''", "Знімки 🦉"] {
            let out = try ScriptHarness().shell("v=\(Shell.quote(value)); printf '%s' \"$v\"")
            #expect(out == value)
        }
    }

    @Test func aValueThatLooksLikeAPlaceholderStaysText() {
        let script = PresetID.ssh.render(["host": "{{folder}}", "folder": "clips"])
        #expect(script.contains("host='{{folder}}'\n"))
        #expect(script.contains("folder='clips'\n"))
    }

    @Test func validates() {
        #expect(PresetID.ssh.validate(["host": "devbox", "folder": "clips"]).isEmpty)
        #expect(PresetID.ssh.validate(["host": " ", "folder": "clips"]) == ["host": "Required."])
        #expect(PresetID.ssh.validate(["host": "dev\nbox", "folder": "clips"]) == ["host": "Must be a single line."])
        #expect(PresetID.ssh.validate(["host": "devbox", "folder": "clips", "baseURL": "example.com"])["baseURL"] != nil)
        #expect(PresetID.s3.validate(["bucket": "b", "expiresIn": "604801"])["expiresIn"] != nil)
        #expect(PresetID.s3.validate(["bucket": "b", "expiresIn": "soon"])["expiresIn"] != nil)
        #expect(PresetID.s3.validate(["bucket": "b"]).isEmpty)   // the expiry has a default
        #expect(PresetID.webhook.validate(["url": "https://example.com/u"]).isEmpty)
        #expect(PresetID.custom.validate([:]).isEmpty)
    }

    @Test func suggestsANameFromTheFields() {
        #expect(PresetID.ssh.suggestedName(["host": "devbox"]) == "devbox")
        #expect(PresetID.s3.suggestedName(["bucket": "shots"]) == "shots")
        #expect(PresetID.webhook.suggestedName(["url": "https://hooks.example.com/u"]) == "hooks.example.com")
        #expect(PresetID.webhook.suggestedName([:]) == "Webhook")
    }

    @Test func everyPresetIsValidSh() throws {
        let h = try ScriptHarness()
        for preset in PresetID.allCases {
            let path = try h.write(preset.render(["host": "h", "folder": "f", "bucket": "b", "url": "https://x"]))
            #expect(try h.run(["-n", path]).status == 0, "\(preset)")
        }
    }
}

/// Runs each preset for real with /bin/sh, with fake ssh, scp, aws, curl and security first on
/// PATH. The fakes record the exact arguments they get, so these tests show that whatever a
/// field holds reaches the tool as one literal argument and never runs as code.
@Suite struct PresetScriptTests {
    /// Quotes, spaces, both forms of command substitution, a separator and a variable.
    static let evil = #"it's "a" $(touch pwned1) `touch pwned2` ; touch pwned3 && $HOME"#
    static let name = "tyto-20261027-171430.png"

    @Test func sshCopiesWithScpAndPrintsTheRemotePath() throws {
        let h = try ScriptHarness()
        try h.fake("scp", "log scp \"$@\"")
        try h.fake("ssh", "log ssh \"$@\"")
        let script = try h.write(PresetID.ssh.render(["host": Self.evil, "folder": Self.evil]))
        let r = try h.run([script, h.png, Self.name])
        #expect(r.status == 0, "\(r.stderr)")
        #expect(r.stdout == "~/\(Self.evil)/\(Self.name)\n")
        #expect(h.calls("scp") == [["-q", "-o", "BatchMode=yes", "-o", "ConnectTimeout=20", "--", h.png,
                                    "\(Self.evil):\(Self.evil)/\(Self.name)"]])
        #expect(h.calls("ssh").isEmpty)
        #expect(h.pwned.isEmpty)
    }

    @Test func sshMakesAMissingFolderThroughTheRemoteShellSafely() throws {
        let h = try ScriptHarness()
        // The first copy fails as if the folder were missing; ssh then runs its command
        // through a real shell, the way the remote end would.
        try h.fake("scp", """
            log scp "$@"
            if [ ! -e "$TYTO_TEST_LOG/scp-once" ]; then touch "$TYTO_TEST_LOG/scp-once"; echo "no such folder" >&2; exit 1; fi
            """)
        try h.fake("ssh", """
            log ssh "$@"
            for last in "$@"; do :; done
            cd "$TYTO_TEST_REMOTE" && sh -c "$last"
            """)
        let script = try h.write(PresetID.ssh.render(["host": "devbox", "folder": "~/" + Self.evil]))
        let r = try h.run([script, h.png, Self.name])
        #expect(r.status == 0, "\(r.stderr)")
        #expect(r.stdout == "~/\(Self.evil)/\(Self.name)\n")
        #expect(h.calls("scp").count == 2)
        #expect(h.calls("ssh").first?.prefix(6) == ["-o", "BatchMode=yes", "-o", "ConnectTimeout=20", "--", "devbox"])
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: h.remote.appendingPathComponent(Self.evil).path, isDirectory: &isDir) && isDir.boolValue)
        #expect(h.pwned.isEmpty)
    }

    @Test func sshPrintsALinkWithABaseURLAndAnAbsolutePathAsIs() throws {
        let h = try ScriptHarness()
        try h.fake("scp", "log scp \"$@\"")
        let linked = try h.run([try h.write(PresetID.ssh.render(["host": "h", "folder": "/srv/clips", "baseURL": "https://x.example/c/"])), h.png, Self.name])
        #expect(linked.stdout == "https://x.example/c/\(Self.name)\n")
        let absolute = try h.run([try h.write(PresetID.ssh.render(["host": "h", "folder": "/srv/clips/"])), h.png, Self.name])
        #expect(absolute.stdout == "/srv/clips/\(Self.name)\n")
    }

    @Test func sshFailureEndsWithTheToolsOwnReason() throws {
        let h = try ScriptHarness()
        try h.fake("scp", "echo 'scp: Connection refused' >&2; exit 1")
        try h.fake("ssh", "echo 'ssh: connect to host devbox port 22: Connection refused' >&2; exit 255")
        let r = try h.run([try h.write(PresetID.ssh.render(["host": "devbox", "folder": "clips"])), h.png, Self.name])
        #expect(r.status != 0)
        #expect(ScriptContract.outcome(.exited(r.status), stdout: Data(r.stdout.utf8), stderr: Data(r.stderr.utf8))
                == .failed(reason: "ssh: connect to host devbox port 22: Connection refused"))
    }

    @Test func s3UploadsWithTheProfileAndPresigns() throws {
        let h = try ScriptHarness()
        try h.fake("aws", """
            log aws "$@"
            case " $* " in *" presign "*) echo "https://signed.example/k?X-Amz-Signature=1" ;; *) echo "upload: done" ;; esac
            """)
        let values = ["bucket": "shots", "prefix": "/" + Self.evil + "/", "endpoint": Self.evil, "profile": Self.evil]
        let r = try h.run([try h.write(PresetID.s3.render(values)), h.png, Self.name])
        #expect(r.status == 0, "\(r.stderr)")
        #expect(r.stdout == "https://signed.example/k?X-Amz-Signature=1\n")
        let key = "\(Self.evil)/\(Self.name)"
        #expect(h.calls("aws") == [
            ["--profile", Self.evil, "--endpoint-url", Self.evil, "s3", "cp", "--only-show-errors",
             "--content-type", "image/png", h.png, "s3://shots/\(key)"],
            ["--profile", Self.evil, "--endpoint-url", Self.evil, "s3", "presign", "s3://shots/\(key)",
             "--expires-in", "604800"],
        ])
        #expect(h.pwned.isEmpty)
    }

    @Test func s3WithAPublicBaseURLNeedsNoPresign() throws {
        let h = try ScriptHarness()
        try h.fake("aws", "log aws \"$@\"")
        let r = try h.run([try h.write(PresetID.s3.render(["bucket": "shots", "publicBaseURL": "https://cdn.example/"])), h.png, Self.name])
        #expect(r.stdout == "https://cdn.example/\(Self.name)\n")
        #expect(h.calls("aws") == [["s3", "cp", "--only-show-errors", "--content-type", "image/png", h.png, "s3://shots/\(Self.name)"]])
    }

    @Test func webhookReadsTheTokenFromTheKeychainAndTheLinkFromTheReply() throws {
        let h = try ScriptHarness()
        try h.fake("security", "log security \"$@\"; echo 's3cr3t'")
        try h.fake("curl", """
            log curl "$@"
            cat > "$TYTO_TEST_LOG/curl-stdin"
            echo '{"data":{"link":"https://hook.example/x.png"}}'
            """)
        let values = ["url": Self.evil, "keychainItem": Self.evil, "jsonField": "data.link"]
        let r = try h.run([try h.write(PresetID.webhook.render(values)), h.png, Self.name])
        #expect(r.status == 0, "\(r.stderr)")
        #expect(r.stdout == "https://hook.example/x.png\n")
        #expect(h.calls("security") == [["find-generic-password", "-s", Self.evil, "-w"]])
        let curl = try #require(h.calls("curl").first)
        #expect(curl == ["--silent", "--show-error", "--fail-with-body", "--max-time", "50", "-H", "@-",
                         "-F", "file=@\(h.png);type=image/png;filename=\(Self.name)", "--", Self.evil])
        #expect(!curl.contains { $0.contains("s3cr3t") })
        #expect(try String(contentsOf: h.log.appendingPathComponent("curl-stdin"), encoding: .utf8) == "Authorization: Bearer s3cr3t\n")
        #expect(h.pwned.isEmpty)
    }

    @Test func webhookWithoutALinkFieldInTheReplyFails() throws {
        let h = try ScriptHarness()
        try h.fake("curl", "cat >/dev/null; echo '{\"ok\":true}'")
        let r = try h.run([try h.write(PresetID.webhook.render(["url": "https://x.example"])), h.png, Self.name])
        #expect(ScriptContract.outcome(.exited(r.status), stdout: Data(r.stdout.utf8), stderr: Data(r.stderr.utf8))
                == .failed(reason: "the reply has no url field"))
    }

    @Test func customPrintsTheFileUntilEdited() throws {
        let h = try ScriptHarness()
        let r = try h.run([try h.write(PresetID.custom.render([:])), h.png, Self.name])
        #expect(r.status == 0)
        #expect(r.stdout == h.png + "\n")
    }
}

/// A scratch folder with a fake-tool bin directory, a log of calls and a stand-in remote home.
struct ScriptHarness {
    let root: URL
    let bin: URL
    let log: URL
    let remote: URL
    let png: String

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tyto-tests-\(UUID().uuidString)", isDirectory: true)
        bin = root.appendingPathComponent("bin", isDirectory: true)
        log = root.appendingPathComponent("log", isDirectory: true)
        remote = root.appendingPathComponent("remote", isDirectory: true)
        for d in [bin, log, remote] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        let file = root.appendingPathComponent("out box/\(PresetScriptTests.name)")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)
        png = file.path
    }

    /// A tool on PATH. `log NAME "$@"` records one call: arguments separated by RS, calls by GS.
    func fake(_ name: String, _ body: String) throws {
        let script = """
            #!/bin/sh
            log() { tool=$1; shift; for a in "$@"; do printf '%s\\036' "$a"; done >> "$TYTO_TEST_LOG/$tool"; printf '\\035' >> "$TYTO_TEST_LOG/$tool"; }
            \(body)

            """
        let url = bin.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func write(_ script: String) throws -> String {
        let url = root.appendingPathComponent("script-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func calls(_ tool: String) -> [[String]] {
        guard let text = try? String(contentsOf: log.appendingPathComponent(tool), encoding: .utf8) else { return [] }
        return text.split(separator: "\u{1D}", omittingEmptySubsequences: false).dropLast().map { call in
            call.split(separator: "\u{1E}", omittingEmptySubsequences: false).dropLast().map(String.init)
        }
    }

    /// Files a successful injection would have created, anywhere under the scratch folder.
    var pwned: [String] {
        let all = FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String] ?? []
        return all.filter { ($0 as NSString).lastPathComponent.hasPrefix("pwned") }
    }

    func run(_ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = arguments
        p.currentDirectoryURL = root
        p.environment = ["PATH": "\(bin.path):/usr/bin:/bin", "HOME": remote.path, "LANG": "en_US.UTF-8",
                         "TYTO_TEST_LOG": log.path, "TYTO_TEST_REMOTE": remote.path]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    func shell(_ command: String) throws -> String { try run(["-c", command]).stdout }
}
