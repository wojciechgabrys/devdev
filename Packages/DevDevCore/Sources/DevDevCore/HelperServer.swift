import Foundation

/// Serves the Helper socket protocol on a Unix domain socket.
public final class HelperServer: @unchecked Sendable {
    private let engine: HelperEngine
    private let socketPath: String
    private let queue = DispatchQueue(label: "dev.devdev.server")
    private let lock = NSLock()
    private var acceptSource: DispatchSourceRead?
    private var lockDescriptor: Int32 = -1
    private var connections: [ObjectIdentifier: LineConnection] = [:]

    public init(engine: HelperEngine, socketPath: String) {
        self.engine = engine
        self.socketPath = socketPath
    }

    /// Starts listening. Fails with `alreadyRunning` when another Helper holds this socket.
    public func start() throws {
        _ = try UnixSocket.address(for: socketPath)

        // The lock file decides who owns the socket, so a stale socket file can be replaced safely.
        let lockDescriptor = open(socketPath + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lockDescriptor >= 0 else {
            throw HelperError(
                code: HelperError.connectionFailed,
                message: "The Helper cannot create \(socketPath).lock: \(UnixSocket.errorText())")
        }
        // A Process being spawned holds a copy of every descriptor for an instant, which can keep a
        // lock that was just released looking taken. So try a few times before giving up.
        var locked = flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0
        for _ in 0..<10 where !locked {
            usleep(20_000)
            locked = flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0
        }
        guard locked else {
            close(lockDescriptor)
            throw HelperError(
                code: HelperError.alreadyRunning, message: "Another Helper already listens on \(socketPath).")
        }

        unlink(socketPath)
        let listening: Int32
        do {
            listening = try UnixSocket.listen(at: socketPath)
        } catch {
            close(lockDescriptor)
            throw error
        }
        _ = fcntl(listening, F_SETFL, fcntl(listening, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: listening, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAll(listening) }
        source.setCancelHandler { close(listening) }
        lock.withLock {
            self.lockDescriptor = lockDescriptor
            acceptSource = source
        }
        source.resume()
    }

    /// Stops listening and closes every connection. Processes are not touched.
    public func stop() {
        let (source, descriptor, open) = lock.withLock {
            let state = (acceptSource, lockDescriptor, Array(connections.values))
            acceptSource = nil
            lockDescriptor = -1
            connections = [:]
            return state
        }
        guard let source else { return }
        source.cancel()
        unlink(socketPath)
        open.forEach { $0.close() }
        if descriptor >= 0 { close(descriptor) }
    }

    private func acceptAll(_ listening: Int32) {
        while true {
            let fd = accept(listening, nil, nil)
            guard fd >= 0 else { return }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            serve(fd)
        }
    }

    private func serve(_ fd: Int32) {
        let (lines, input) = AsyncStream.makeStream(of: Data.self)
        let connection = LineConnection(
            fd: fd,
            onLine: { input.yield($0) },
            onClose: { input.finish() })
        let key = ObjectIdentifier(connection)
        let listening = lock.withLock {
            guard acceptSource != nil else { return false }
            connections[key] = connection
            return true
        }
        guard listening else {
            close(fd)
            return
        }

        let engine = engine
        Task { [weak self] in
            let subscription = await engine.subscribe()
            let pushing = Task {
                for await event in subscription.events {
                    if let line = Wire.encode(ServerEnvelope(event: event)) { connection.send(line) }
                }
            }
            connection.start()
            for await line in lines {
                guard let envelope = Wire.decode(RequestEnvelope.self, from: line) else {
                    Self.refuse(line, on: connection)
                    continue
                }
                let answer: @Sendable () async -> Void = {
                    let response = await engine.respond(
                        to: envelope.request, origin: envelope.origin, subscriber: subscription.id)
                    if let line = Wire.encode(ServerEnvelope(id: envelope.id, response: response)) {
                        connection.send(line)
                    }
                }
                if envelope.request.waitsForAProcess {
                    // A stop can take seconds. It must not hold up the client's other requests.
                    Task { await answer() }
                } else {
                    await answer()
                }
            }
            await engine.unsubscribe(subscription.id)
            pushing.cancel()
            self?.lock.withLock { _ = self?.connections.removeValue(forKey: key) }
        }
    }

    /// Answers a line that is not a request this Helper knows.
    private static func refuse(_ line: Data, on connection: LineConnection) {
        struct IDOnly: Decodable { var id: Int }
        guard let id = Wire.decode(IDOnly.self, from: line)?.id else { return }
        let failure = HelperResponse.failure(
            HelperError(
                code: HelperError.unknownRequest,
                message: "This Helper (protocol version \(HelperProtocol.version)) does not know that request."))
        if let line = Wire.encode(ServerEnvelope(id: id, response: failure)) { connection.send(line) }
    }
}
