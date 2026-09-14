import Darwin
import Foundation
import OwlCore

let usage = """
usage: owlctl <command> [options]

  ping                                  liveness + permission state
  displays                              list displays (id, name, main, size, scale)
  capture [--display SPEC] [--test]     freeze + show overlay; --test confines to SPEC, no focus change
  select X Y W H [--display SPEC]       set the selection in display pixels
  state                                 current session state
  copy                                  crop + copy to clipboard, end session
  cancel                                end session without copying
  snapshot PATH [--display SPEC]        PNG of a display as it looks now (incl. Owl's overlay)
  clipboard PATH                        write the clipboard image to PATH as PNG
  timings                               last session's latency numbers
  quit                                  terminate Owl

SPEC: all | main | secondary | <CGDirectDisplayID>     (default: all for capture, main otherwise)
Socket: $OWL_DEBUG_SOCKET or ~/Library/Application Support/Owl/debug.sock
"""

func die(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { die(usage) }
if cmd == "--help" || cmd == "-h" { print(usage); exit(0) }
args.removeFirst()

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
    default:
        positional.append(args[i])
        i += 1
    }
}

switch cmd {
case "select":
    guard positional.count == 4, let x = Int(positional[0]), let y = Int(positional[1]),
          let w = Int(positional[2]), let h = Int(positional[3]) else { die("select needs X Y W H") }
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
guard connected == 0 else { die("cannot connect to Owl at \(path) (is Owl running in debug mode?)") }

var timeout = timeval(tv_sec: 60, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

let encoded = try! JSONEncoder().encode(request)
var payload = Array(encoded) + [0x0A]
var sent = 0
while sent < payload.count {
    let n = payload[sent...].withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    guard n > 0 else { die("write failed") }
    sent += n
}

var response = Data()
var chunk = [UInt8](repeating: 0, count: 65536)
while !response.contains(0x0A) {
    let n = read(fd, &chunk, chunk.count)
    guard n > 0 else { die("connection closed before a response arrived (timeout 60s)") }
    response.append(contentsOf: chunk[0..<n])
}
close(fd)

let line = response.prefix { $0 != 0x0A }
guard let decoded = try? JSONDecoder().decode(DebugResponse.self, from: Data(line)) else {
    die("unparseable response: \(String(decoding: line, as: UTF8.self))")
}
let pretty = JSONEncoder()
pretty.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(decoding: try! pretty.encode(decoded), as: UTF8.self))
exit(decoded.ok ? 0 : 1)
