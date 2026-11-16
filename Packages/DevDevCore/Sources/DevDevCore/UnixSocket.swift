import Foundation

/// Small helpers for Unix domain sockets.
enum UnixSocket {
    /// The socket address for a path. Paths are limited to 103 bytes.
    static func address(for path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !bytes.isEmpty, bytes.count < capacity else {
            throw HelperError(
                code: HelperError.invalid,
                message: "The socket path is \(bytes.count) bytes long. The limit is \(capacity - 1): \(path)")
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }

    private static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw HelperError(code: HelperError.connectionFailed, message: "No socket: \(errorText())")
        }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        return fd
    }

    /// Connects to a listening socket and returns the file descriptor.
    static func connect(to path: String) throws -> Int32 {
        var address = try address(for: path)
        let fd = try makeSocket()
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let text = errorText()
            close(fd)
            throw HelperError(
                code: HelperError.connectionFailed,
                message: "The Helper does not answer on \(path): \(text)")
        }
        return fd
    }

    /// Binds and listens at the path, readable and writable by the user only.
    static func listen(at path: String) throws -> Int32 {
        var address = try address(for: path)
        let fd = try makeSocket()
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 16) == 0 else {
            let text = errorText()
            close(fd)
            throw HelperError(
                code: HelperError.connectionFailed, message: "The Helper cannot listen on \(path): \(text)")
        }
        return fd
    }

    static func errorText() -> String { String(cString: strerror(errno)) }
}

/// One end of a connection that carries newline-delimited messages.
final class LineConnection: @unchecked Sendable {
    private let fd: Int32
    private let readQueue: DispatchQueue
    private let writeQueue: DispatchQueue
    private let lock = NSLock()
    private var closed = false
    private var source: DispatchSourceRead?
    private var pending = Data()
    private let onLine: @Sendable (Data) -> Void
    private let onClose: @Sendable () -> Void

    /// `onLine` and `onClose` run on a private queue. `onClose` runs once.
    init(fd: Int32, onLine: @escaping @Sendable (Data) -> Void, onClose: @escaping @Sendable () -> Void) {
        self.fd = fd
        self.onLine = onLine
        self.onClose = onClose
        readQueue = DispatchQueue(label: "dev.devdev.socket.read.\(fd)")
        writeQueue = DispatchQueue(label: "dev.devdev.socket.write.\(fd)")
    }

    func start() {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [fd, writeQueue] in
            // After the writes still queued, so the descriptor is not reused under them.
            writeQueue.async { Darwin.close(fd) }
        }
        lock.withLock { self.source = source }
        source.resume()
    }

    /// Queues one message. A newline is added.
    func send(_ message: Data) {
        let line = message + [0x0a]
        writeQueue.async { [self] in
            guard !isClosed else { return }
            if !writeAll(line) { close() }
        }
    }

    func close() {
        let first = lock.withLock {
            if closed { return false }
            closed = true
            return true
        }
        guard first else { return }
        shutdown(fd, SHUT_RDWR)
        lock.withLock { source }?.cancel()
        readQueue.async { [onClose] in onClose() }
    }

    private var isClosed: Bool { lock.withLock { closed } }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while !isClosed {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                pending.append(contentsOf: buffer[0..<count])
                while let end = pending.firstIndex(of: 0x0a) {
                    let line = Data(pending[pending.startIndex..<end])
                    pending = Data(pending[pending.index(after: end)...])
                    if !line.isEmpty { onLine(line) }
                }
            } else if count == -1, errno == EINTR {
                continue
            } else if count == -1, errno == EAGAIN {
                return
            } else {
                close()
                return
            }
        }
    }

    private func writeAll(_ data: Data) -> Bool {
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Bool in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress! + offset, bytes.count - offset)
                if count > 0 {
                    offset += count
                } else if count == -1, errno == EINTR {
                    continue
                } else if count == -1, errno == EAGAIN {
                    var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&descriptor, 1, 500)
                    if isClosed { return false }
                } else {
                    return false
                }
            }
            return true
        }
    }
}
