// Packages/BrowserBridgeKit/Sources/BrowserBridgeKit/BridgeSocketServer.swift
import Darwin
import Foundation

/// The Capture (Snapzy) app side of the local IPC bridge: a Unix domain socket,
/// user-owned, parent directory user-only, socket permissions `0600`. The
/// native-messaging host (`native-host/`, a separate executable Chrome
/// launches) connects to this and relays validated messages from the
/// Chrome extension; this type never talks to Chrome directly.
///
/// Built on raw POSIX sockets (`Darwin.socket`/`bind`/`listen`/`accept`)
/// rather than `Network.framework`: `NWListener`'s public API only
/// supports binding to a TCP port, a launchd-activated socket, or a
/// Bonjour service — it has no supported way to listen on an arbitrary
/// Unix-domain-socket path, which is exactly what's needed here.
/// `DispatchSource` read sources drive accept/receive without blocking a
/// thread per connection.
///
/// Newline-delimited JSON framing is used over the socket (simplest robust
/// framing for a byte stream); each line is one `BridgeMessage` in, one
/// `BridgeResponse` out.
public final class BridgeSocketServer {
    public typealias Handler = (BridgeMessage) -> BridgeResponse

    public enum ServerError: Error, LocalizedError {
        case pathTooLong(String)
        case socketCreationFailed(String)
        case bindFailed(String)
        case listenFailed(String)

        public var errorDescription: String? {
            switch self {
            case .pathTooLong(let path):
                return "Socket path is too long for sockaddr_un: \(path)"
            case .socketCreationFailed(let msg): return "socket() failed: \(msg)"
            case .bindFailed(let msg): return "bind() failed: \(msg)"
            case .listenFailed(let msg): return "listen() failed: \(msg)"
            }
        }
    }

    /// A connected peer that never sends a newline within this many bytes
    /// is either malfunctioning or hostile — the connection is dropped
    /// rather than letting `buffer` grow without bound.
    public static let maxBufferedBytesPerConnection = 4 * 1024 * 1024

    private let socketURL: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.trongduong.snapzy.browser-bridge.socket")

    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: ConnectionState] = [:]

    private final class ConnectionState {
        var readSource: DispatchSourceRead?
        var buffer = Data()
    }

    public init(socketURL: URL = BridgeConfiguration.socketURL, handler: @escaping Handler) {
        self.socketURL = socketURL
        self.handler = handler
    }

    /// Binds and starts listening. Removes any stale socket file left over
    /// from a previous run first (a Unix socket path cannot be re-bound
    /// while the old inode still exists).
    public func start() throws {
        let fm = FileManager.default
        let parentDir = socketURL.deletingLastPathComponent()
        try fm.createDirectory(
            at: parentDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fm.removeItem(at: socketURL)

        let path = socketURL.path
        let pathBytes = Array(path.utf8)
        let maxLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1
        guard pathBytes.count <= maxLength else {
            throw ServerError.pathTooLong(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ServerError.socketCreationFailed(String(cString: strerror(errno)))
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let buffer = raw.bindMemory(to: UInt8.self)
            for (index, byte) in pathBytes.enumerated() {
                buffer[index] = byte
            }
            buffer[pathBytes.count] = 0
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw ServerError.bindFailed(message)
        }

        // Enforce 0600 permissions immediately after bind creates the inode.
        chmod(path, 0o600)

        guard listen(fd, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw ServerError.listenFailed(message)
        }

        listenerFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptNewConnection()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        acceptSource = source
    }

    public func stop() {
        for (fd, state) in connections {
            state.readSource?.cancel()
            close(fd)
        }
        connections.removeAll()
        acceptSource?.cancel()
        acceptSource = nil
        listenerFD = -1
        try? FileManager.default.removeItem(at: socketURL)
    }

    public var isRunning: Bool { listenerFD >= 0 }

    /// `getpeereid(3)` (a real BSD/Darwin libc API, not a custom credential
    /// scheme) returns the *effective* uid/gid of whatever process is on
    /// the other end of this specific Unix-domain-socket connection; a
    /// mismatch with our own uid means something other than the current
    /// user's own processes connected — the `0700`/`0600` filesystem
    /// permissions on the socket already make this the norm, not the
    /// exception, so this is defense in depth, not the primary control.
    public static func peerIsSameUser(_ fd: Int32) -> Bool {
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(fd, &peerUID, &peerGID) == 0 else { return false }
        return peerUID == getuid()
    }

    private func acceptNewConnection() {
        let clientFD = accept(listenerFD, nil, nil)
        guard clientFD >= 0 else { return }

        guard Self.peerIsSameUser(clientFD) else {
            close(clientFD)
            return
        }

        let state = ConnectionState()
        let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailableData(from: clientFD)
        }
        source.setCancelHandler { [weak self] in
            close(clientFD)
            self?.connections.removeValue(forKey: clientFD)
        }
        state.readSource = source
        connections[clientFD] = state
        source.resume()
    }

    private func readAvailableData(from fd: Int32) {
        guard let state = connections[fd] else { return }
        var chunk = [UInt8](repeating: 0, count: 65536)
        let bytesRead = chunk.withUnsafeMutableBytes { raw -> Int in
            read(fd, raw.baseAddress, raw.count)
        }

        if bytesRead <= 0 {
            state.readSource?.cancel()
            return
        }

        state.buffer.append(contentsOf: chunk[0..<bytesRead])

        if state.buffer.count > Self.maxBufferedBytesPerConnection, !state.buffer.contains(0x0A) {
            // No complete line within the size budget — drop the
            // connection rather than let an unbounded/hostile peer grow
            // this buffer forever.
            state.readSource?.cancel()
            return
        }

        while let newlineIndex = state.buffer.firstIndex(of: 0x0A) {
            let lineData = state.buffer[..<newlineIndex]
            state.buffer.removeSubrange(...newlineIndex)
            handle(lineData: Data(lineData), fd: fd)
        }
    }

    private func handle(lineData: Data, fd: Int32) {
        let response: BridgeResponse
        var requestID = "unknown"
        do {
            if lineData.count > BridgeMessageValidator.maxPayloadBytes {
                throw BridgeMessageValidator.ValidationError.messageTooLarge(lineData.count)
            }
            let message = try JSONDecoder().decode(BridgeMessage.self, from: lineData)
            requestID = message.id
            try BridgeMessageValidator.validate(message, encodedSize: lineData.count)
            response = handler(message)
        } catch let validationError as BridgeMessageValidator.ValidationError {
            response = .failure(id: requestID, code: BridgeErrorCode.invalidMessage, message: validationError.localizedDescription)
        } catch {
            response = .failure(id: requestID, code: BridgeErrorCode.malformedMessage, message: error.localizedDescription)
        }

        guard var payload = try? JSONEncoder().encode(response) else { return }
        payload.append(0x0A)
        payload.withUnsafeBytes { raw in
            _ = write(fd, raw.baseAddress, raw.count)
        }
    }
}
