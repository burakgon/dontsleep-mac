import Foundation

/// The Unix socket the app listens on and the `dontsleep` command connects to.
///
/// A socket in the user's own Library is reachable from every shell of that user, including
/// ones over SSH, and from nobody else. An idle listener uses no CPU: the kernel wakes the
/// app only when a command connects.
public enum ControlSocket {
    /// The identifier of the app, which also names its preferences.
    public static let appIdentifier = "com.burakgon.DontSleep"

    public static let path: String = {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) } ?? NSHomeDirectory()
        let preferred = home + "/Library/Application Support/DontSleep/control.sock"
        // A socket address holds 103 bytes of path. A home folder deep enough to exceed
        // that gets a socket in /tmp instead, in a folder only this user can open.
        return preferred.utf8.count < maximumPathLength ? preferred : "/tmp/DontSleep-\(getuid())/control.sock"
    }()

    static let maximumPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

    static func address(_ path: String) -> sockaddr_un? {
        let bytes = Array(path.utf8)
        guard bytes.count < maximumPathLength else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    static func withSocketAddress<Result>(_ address: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Result) -> Result {
        var address = address
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    /// Gives up on a peer that stops reading or writing, and never raises SIGPIPE for one that left.
    static func configure(_ descriptor: Int32, timeout: TimeInterval) {
        var time = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    static func write(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress! + sent, buffer.count - sent)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { return false }
                sent += count
            }
            return true
        }
    }

    /// Reads one line, or everything up to the end of the stream.
    static func readLine(from descriptor: Int32, limit: Int = 64 * 1024) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < limit {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(contentsOf: buffer[..<count])
            if let newline = data.firstIndex(of: UInt8(ascii: "\n")) { return data[..<newline] }
        }
        return data.isEmpty ? nil : data
    }
}

/// The `dontsleep` command's side of the socket.
public enum ControlClient {
    public enum Failure: Error, Equatable {
        /// Nothing is listening: the app is not running.
        case notRunning
        case failed(String)

        public var reason: String {
            switch self {
            case .notRunning: "DontSleep is not running"
            case .failed(let reason): reason
            }
        }
    }

    /// Sends one request and waits for the answer.
    public static func send(_ request: Request, to path: String = ControlSocket.path, timeout: TimeInterval = 5) throws(Failure) -> Response {
        guard let address = ControlSocket.address(path) else { throw .failed("the socket path is too long: \(path)") }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw .failed(String(cString: strerror(errno))) }
        defer { close(descriptor) }
        ControlSocket.configure(descriptor, timeout: timeout)

        guard ControlSocket.withSocketAddress(address, { connect(descriptor, $0, $1) }) == 0 else {
            // No socket, or one that a copy of the app left behind when it was killed.
            if errno == ENOENT || errno == ECONNREFUSED || errno == ENOTDIR { throw .notRunning }
            throw .failed(String(cString: strerror(errno)))
        }
        guard var line = try? ControlCoding.encode(request) else { throw .failed("the request could not be encoded") }
        line.append(UInt8(ascii: "\n"))
        guard ControlSocket.write(line, to: descriptor) else { throw .failed("DontSleep did not take the request") }
        guard let answer = ControlSocket.readLine(from: descriptor) else { throw .failed("DontSleep did not answer") }
        guard let response = try? ControlCoding.decode(Response.self, from: answer) else {
            throw .failed("DontSleep gave an answer this command does not understand")
        }
        return response
    }
}

/// The app's side of the socket.
public final class ControlServer: @unchecked Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    private let path: String
    private let handler: @Sendable (Request) -> Response
    private let queue = DispatchQueue(label: "com.burakgon.DontSleep.control", qos: .userInitiated)
    private var source: DispatchSourceRead?

    /// - Parameter handler: Called on a background queue, one request at a time.
    public init(path: String = ControlSocket.path, handler: @escaping @Sendable (Request) -> Response) {
        self.path = path
        self.handler = handler
    }

    deinit {
        source?.cancel()
    }

    /// Starts listening. A socket left behind by an earlier run is replaced.
    public func start() throws {
        guard source == nil else { return }
        guard let address = ControlSocket.address(path) else { throw Failure(description: "the socket path is too long: \(path)") }
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(directory, 0o700)
        unlink(path)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure(description: String(cString: strerror(errno))) }
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        guard ControlSocket.withSocketAddress(address, { bind(descriptor, $0, $1) }) == 0,
              chmod(path, 0o600) == 0,
              listen(descriptor, 16) == 0,
              fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            let reason = String(cString: strerror(errno))
            close(descriptor)
            throw Failure(description: reason)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [handler] in
            while true {
                let client = accept(descriptor, nil, nil)
                guard client >= 0 else { break }
                Self.serve(client, handler: handler)
                close(client)
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    public func stop() {
        guard let source else { return }
        source.cancel()
        self.source = nil
        unlink(path)
    }

    private static func serve(_ client: Int32, handler: (Request) -> Response) {
        // Only this user. The folder's permissions say so already; this is the second lock.
        var user: uid_t = 0
        var group: gid_t = 0
        guard getpeereid(client, &user, &group) == 0, user == getuid() else { return }
        // An accepted socket inherits non-blocking mode; these reads are meant to wait.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        ControlSocket.configure(client, timeout: 2)

        var response: Response
        if let line = ControlSocket.readLine(from: client), let request = try? ControlCoding.decode(Request.self, from: line) {
            response = handler(request)
        } else {
            response = Response(error: "the request was not understood")
        }
        guard var answer = try? ControlCoding.encode(response) else { return }
        answer.append(UInt8(ascii: "\n"))
        _ = ControlSocket.write(answer, to: client)
    }
}
