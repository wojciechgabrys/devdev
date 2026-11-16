import Foundation

/// A connection to the Helper, for the App and the `devdev` CLI.
public final class HelperClient: @unchecked Sendable {
    /// Everything the Helper pushes. The stream ends when the connection closes.
    public let events: AsyncStream<HelperEvent>

    /// The protocol version the Helper speaks. Compare it with `HelperProtocol.version`.
    public var helperProtocolVersion: Int { lock.withLock { protocolVersion } }
    public var helperVersion: String { lock.withLock { version } }

    private let lock = NSLock()
    private let eventInput: AsyncStream<HelperEvent>.Continuation
    private var connection: LineConnection?
    private var waiting: [Int: CheckedContinuation<HelperResponse, Error>] = [:]
    private var nextID = 1
    private var closed = false
    private var protocolVersion = 0
    private var version = ""

    /// Connects to the Helper socket and exchanges hello messages.
    public static func connect(socketPath: String, clientName: String) async throws -> HelperClient {
        let fd = try UnixSocket.connect(to: socketPath)
        let client = HelperClient(fd: fd)
        let response = try await client.send(.hello(protocolVersion: HelperProtocol.version, client: clientName))
        guard case .hello(let protocolVersion, let helperVersion) = response else {
            client.close()
            throw HelperError(
                code: HelperError.connectionFailed, message: "The Helper did not answer the hello message.")
        }
        client.lock.withLock {
            client.protocolVersion = protocolVersion
            client.version = helperVersion
        }
        return client
    }

    private init(fd: Int32) {
        (events, eventInput) = AsyncStream.makeStream(of: HelperEvent.self)
        let connection = LineConnection(
            fd: fd,
            onLine: { [weak self] in self?.receive($0) },
            onClose: { [weak self] in self?.connectionClosed() })
        self.connection = connection
        connection.start()
    }

    deinit {
        connection?.close()
    }

    /// Sends one request and waits for its response. State-changing requests need an origin.
    public func send(_ request: HelperRequest, origin: Origin? = nil) async throws -> HelperResponse {
        try await withCheckedThrowingContinuation { continuation in
            let ready: (LineConnection, Data)? = lock.withLock {
                guard !closed, let connection else { return nil }
                let id = nextID
                nextID += 1
                guard let line = Wire.encode(RequestEnvelope(id: id, origin: origin, request: request)) else {
                    return nil
                }
                waiting[id] = continuation
                return (connection, line)
            }
            if let (connection, line) = ready {
                connection.send(line)
            } else {
                continuation.resume(throwing: Self.closedError)
            }
        }
    }

    public func close() {
        lock.withLock { connection }?.close()
    }

    private func receive(_ line: Data) {
        guard let envelope = Wire.decode(ServerEnvelope.self, from: line) else { return }
        if let id = envelope.id, let response = envelope.response {
            lock.withLock { waiting.removeValue(forKey: id) }?.resume(returning: response)
        } else if let event = envelope.event {
            eventInput.yield(event)
        }
    }

    private func connectionClosed() {
        let abandoned = lock.withLock {
            closed = true
            let all = Array(waiting.values)
            waiting = [:]
            return all
        }
        abandoned.forEach { $0.resume(throwing: Self.closedError) }
        eventInput.finish()
    }

    private static let closedError = HelperError(
        code: HelperError.connectionClosed, message: "The connection to the Helper is closed.")
}
