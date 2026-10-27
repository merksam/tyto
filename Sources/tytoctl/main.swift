import Darwin
import Foundation
import TytoCore

let usage = """
usage: tytoctl <command> [options]

  ping                                  liveness + permission state
  displays                              list displays (id, name, main, size, scale)
  capture [--display SPEC] [--test] [--toolbar]
                                        freeze + show overlay; --test confines to SPEC, no focus
                                        change; --toolbar shows the toolbar for staged shots
  select X Y W H [--display SPEC]       set the selection in display pixels
  state                                 current session state
  copy                                  crop + copy to clipboard, end session
  cancel                                end session without copying
  export PATH                           render frozen frame + annotations to PATH without ending
  savefile PATH                         render composite, write to PATH, end session
  windows                               list snap-to-window candidate rects
  hover X Y                             set the snap-to-window hover candidate
  snapshot PATH [--display SPEC]        PNG of a display as it looks now (incl. Tyto's overlay)
  clipboard PATH                        write the clipboard image to PATH as PNG
  timings                               last session's latency numbers
  quit                                  terminate Tyto

  tool NAME                             select|rect|ellipse|line|arrow|text|blur|badge
  color NAME                            red|orange|yellow|green|blue|purple|white|black
  width NAME                            thin|medium|thick
  draw X1 Y1 X2 Y2                      press/drag/release with the current tool (display pixels)
  click X Y                             single click (select a shape, place a badge)
  text X Y STRING                       add a text annotation at X Y
  undo | redo | delete                  history / delete the selected shape
  shapes                                list annotations
  set KEY VALUE                         copyAsFile|autoSave on/off, saveDir PATH,
                                        defaultTool|defaultColor|defaultWidth NAME
  settings                              print current settings
  recent                                list recent captures

  destinations                          list destinations, the default and the scripts folder
  send [NAME]                           send the selection as ⇧⌘C does (default destination
                                        unless NAME); waits and reports the result, ends session
  sendrecent [NAME]                     send the newest recent capture (Recent Captures menu)
  sends                                 the activity list, newest first
  cliptext                              clipboard text and the types on its first item
  set defaultDestination NAME           make NAME the default
  set destinationClipboard CHOICE       what ⇧⌘C copies for the default: result|resultAndImage|nothing
  resetdestinations                     forget every destination and the activity list
  render PRESET [KEY=VALUE ...]         print a preset's script (local, no socket); presets:
                                        ssh host folder [baseURL] | s3 bucket [prefix endpoint
                                        profile publicBaseURL expiresIn] | webhook url
                                        [keychainItem jsonField] | custom

  container                             print the app's sandbox container Data directory (local, no socket)

SPEC: all | main | secondary | <CGDirectDisplayID>     (default: all for capture, main otherwise)
Socket: $TYTO_DEBUG_SOCKET or ~/Library/Containers/com.yevhenii.tyto/Data/tmp/tyto-debug.sock
"""

func die(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { die(usage) }
if cmd == "--help" || cmd == "-h" { print(usage); exit(0) }
if cmd == "container" { print(DebugSocket.containerDataDirectory); exit(0) }
args.removeFirst()

// The same rendering Settings → Destinations uses, so a script can be checked or installed by
// hand without the app.
if cmd == "render" {
    guard let name = args.first, let preset = PresetID(rawValue: name) else {
        die("render needs one of \(PresetID.allCases.map(\.rawValue).joined(separator: ", "))")
    }
    var values: [String: String] = [:]
    for pair in args.dropFirst() {
        guard let eq = pair.firstIndex(of: "=") else { die("render: \(pair) is not KEY=VALUE") }
        let key = String(pair[..<eq])
        guard preset.fields.contains(where: { $0.key == key }) else {
            die("render: \(preset.rawValue) has no field \(key); fields: \(preset.fields.map(\.key).joined(separator: ", "))")
        }
        values[key] = String(pair[pair.index(after: eq)...])
    }
    let problems = preset.validate(values)
    guard problems.isEmpty else {
        die(problems.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
    }
    print(preset.render(values), terminator: "")
    exit(0)
}

var request = DebugRequest(cmd: cmd)
var positional: [String] = []
var i = 0
while i < args.count {
    switch args[i] {
    case "--display":
        guard i + 1 < args.count else { die("--display needs a value") }
        request.display = args[i + 1]
        i += 2
    case "--test":
        request.test = true
        i += 1
    case "--toolbar":
        request.toolbar = true
        i += 1
    default:
        positional.append(args[i])
        i += 1
    }
}

switch cmd {
case "draw":
    guard positional.count == 4, let x = Int(positional[0]), let y = Int(positional[1]),
          let x2 = Int(positional[2]), let y2 = Int(positional[3]) else { die("draw needs X1 Y1 X2 Y2") }
    request.x = x; request.y = y; request.x2 = x2; request.y2 = y2
case "click", "hover", "bend":
    guard positional.count == 2, let x = Int(positional[0]), let y = Int(positional[1]) else { die("\(cmd) needs X Y") }
    request.x = x; request.y = y
case "text":
    guard positional.count >= 3, let x = Int(positional[0]), let y = Int(positional[1]) else { die("text needs X Y STRING") }
    request.x = x; request.y = y
    request.value = positional[2...].joined(separator: " ")
case "send", "sendrecent":
    request.value = positional.first
case "tool", "color", "width", "uitool":
    guard let v = positional.first else { die("\(cmd) needs a value") }
    request.value = v
case "set":
    guard positional.count == 2 else { die("set needs KEY VALUE") }
    request.key = positional[0]; request.value = positional[1]
case "export", "savefile":
    guard let p = positional.first else { die("\(cmd) needs a PATH") }
    request.path = URL(fileURLWithPath: p).standardizedFileURL.path
case "select", "injectwindow":
    guard positional.count == 4, let x = Int(positional[0]), let y = Int(positional[1]),
          let w = Int(positional[2]), let h = Int(positional[3]) else { die("\(cmd) needs X Y W H") }
    request.x = x; request.y = y; request.w = w; request.h = h
case "snapshot", "clipboard":
    guard let p = positional.first else { die("\(cmd) needs a PATH") }
    request.path = URL(fileURLWithPath: p).standardizedFileURL.path
default:
    break
}

let path = DebugSocket.path
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { die("socket() failed") }
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let fits = withUnsafeMutablePointer(to: &addr.sun_path) { ptr -> Bool in
    let capacity = MemoryLayout.size(ofValue: ptr.pointee)
    return path.withCString { src -> Bool in
        guard strlen(src) < capacity else { return false }
        ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strcpy($0, src) }
        return true
    }
}
guard fits else { die("socket path too long: \(path)") }
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard connected == 0 else { die("cannot connect to Tyto at \(path) (is Tyto running in debug mode?)") }

// Longer than a destination script's 60 s, so `send` reports a timeout instead of dying first.
var timeout = timeval(tv_sec: 90, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

let encoded = try! JSONEncoder().encode(request)
var payload = Array(encoded) + [0x0A]
var sent = 0
while sent < payload.count {
    let n = payload[sent...].withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    guard n > 0 else { die("write failed") }
    sent += n
}

// Read until the terminating newline. Only the freshly appended bytes are scanned: rescanning
// the whole buffer each time is quadratic and crawls on multi-megabyte image payloads.
var response = Data()
var chunk = [UInt8](repeating: 0, count: 1 << 20)
var searchFrom = 0
var newlineIndex: Int?
while newlineIndex == nil {
    let n = read(fd, &chunk, chunk.count)
    guard n > 0 else { die("connection closed before a response arrived (timeout 90s)") }
    response.append(contentsOf: chunk[0..<n])
    if let idx = response[searchFrom...].firstIndex(of: 0x0A) { newlineIndex = idx }
    else { searchFrom = response.count }
}
close(fd)

let line = response.prefix(upTo: newlineIndex!)
guard var decoded = try? JSONDecoder().decode(DebugResponse.self, from: Data(line)) else {
    die("unparseable response: \(String(decoding: line, as: UTF8.self))")
}

// Image-returning commands send the PNG as base64: the sandboxed app cannot write to
// caller-chosen paths, and its container is not readable by other processes. Write it here.
if decoded.ok, case .string(let b64)? = decoded.data["png"] {
    guard let outPath = request.path else { die("\(cmd) produced an image but no output PATH was given") }
    guard let bytes = Data(base64Encoded: b64) else { die("\(cmd): response PNG was not valid base64") }
    do {
        let dst = URL(fileURLWithPath: outPath)
        try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: dst, options: .atomic)
    } catch { die("\(cmd): could not write \(outPath): \(error)") }
    decoded.data["png"] = nil
    decoded.data["path"] = .string(outPath)
    decoded.data["bytes"] = JSONValue(bytes.count)
}

let pretty = JSONEncoder()
pretty.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(decoding: try! pretty.encode(decoded), as: UTF8.self))
exit(decoded.ok ? 0 : 1)
