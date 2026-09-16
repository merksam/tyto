#if DEBUG
import Darwin
import Foundation
import TytoCore

/// Main-actor bridge the server hands requests to.
final class DebugCommandRouter {
    private unowned let app: AppDelegate
    init(app: AppDelegate) { self.app = app }
    func handle(_ request: DebugRequest) async -> DebugResponse {
        await DebugCommands.handle(request, app: app)
    }
}

/// Newline-delimited JSON over a unix domain socket. Compiled into Debug builds only.
/// Runs entirely off the main actor; each request is dispatched to the router on the main actor.
nonisolated final class DebugServer: @unchecked Sendable {
    private let path: String
    private let router: DebugCommandRouter
    private let queue = DispatchQueue(label: "com.yevhenii.tyto.debug-socket")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]  // queue-confined

    init(path: String, router: DebugCommandRouter) {
        self.path = path
        self.router = router
    }

    func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

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
        guard fits else { close(fd); throw TytoError.badRequest("socket path too long") }

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            let e = errno
            close(fd)
            throw POSIXError(.init(rawValue: e) ?? .EIO)
        }
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        unlink(path)
    }

    private func acceptClient() {
        let cfd = accept(listenFD, nil, nil)
        guard cfd >= 0 else { return }
        let conn = Connection(fd: cfd, queue: queue,
                              onLine: { [weak self] line, reply in self?.dispatch(line: line, reply: reply) },
                              onClose: { [weak self] fd in self?.connections[fd] = nil })
        connections[cfd] = conn
        conn.start()
    }

    private func dispatch(line: String, reply: @escaping @Sendable (String) -> Void) {
        let request: DebugRequest
        do {
            request = try JSONDecoder().decode(DebugRequest.self, from: Data(line.utf8))
        } catch {
            reply(Self.encode(.failure("bad request: \(error)")))
            return
        }
        let router = self.router
        Task { @MainActor in
            let response = await router.handle(request)
            reply(Self.encode(response))
        }
    }

    static func encode(_ response: DebugResponse) -> String {
        if let data = try? JSONEncoder().encode(response), let s = String(data: data, encoding: .utf8) { return s }
        return #"{"ok":false,"error":"encode failed","data":{}}"#
    }
}

/// One client connection; all state is confined to the server queue.
nonisolated private final class Connection: @unchecked Sendable {
    let fd: Int32
    private let queue: DispatchQueue
    private var buffer = Data()
    private var source: DispatchSourceRead?
    private let onLine: (String, @escaping @Sendable (String) -> Void) -> Void
    private let onClose: (Int32) -> Void

    init(fd: Int32, queue: DispatchQueue,
         onLine: @escaping (String, @escaping @Sendable (String) -> Void) -> Void,
         onClose: @escaping (Int32) -> Void) {
        self.fd = fd
        self.queue = queue
        self.onLine = onLine
        self.onClose = onClose
    }

    func start() {
        let fd = self.fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let n = read(fd, &chunk, chunk.count)
        if n <= 0 {
            source?.cancel()
            onClose(fd)
            return
        }
        buffer.append(contentsOf: chunk[0..<n])
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let line = String(data: lineData, encoding: .utf8),
                  !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let fd = self.fd
            onLine(line) { response in Connection.write(fd: fd, response + "\n") }
        }
    }

    static func write(fd: Int32, _ s: String) {
        let bytes = Array(s.utf8)
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n <= 0 { return }
            offset += n
        }
    }
}
#endif
