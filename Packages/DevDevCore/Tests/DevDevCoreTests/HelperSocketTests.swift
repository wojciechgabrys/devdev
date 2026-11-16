import Foundation
import Testing

@testable import DevDevCore

/// The Helper socket protocol, exercised by a real client over a real Unix domain socket.
@Suite struct HelperSocketTests {
    /// Runs the body with a Helper listening on a socket in the harness folder.
    private func withServer(
        _ commands: [CommandSettings],
        _ body: (Harness, String) async throws -> Void
    ) async throws {
        try await withHarness(commands) { h in
            let socketPath = h.folder.appendingPathComponent("h.sock").path
            let server = HelperServer(engine: h.engine, socketPath: socketPath)
            try server.start()
            do {
                try await body(h, socketPath)
            } catch {
                server.stop()
                throw error
            }
            server.stop()
        }
    }

    private func settings(_ line: String) -> [CommandSettings] {
        [CommandSettings(name: "Main", commandLine: line)]
    }

    @Test func aTestClientStartsACommandThroughTheHelperSocketAndReceivesItsOutputAsPushedEvents() async throws {
        try await withServer(settings("echo hello from the socket; \(Script.runsForever)")) { h, socketPath in
            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            defer { client.close() }

            #expect(try await client.send(.subscribeOutput(commandID: h.first)) == .ok)
            let response = try await client.send(.start(commandID: h.first), origin: .user)
            guard case .command(let started) = response else {
                Issue.record("expected a Command, got \(response)")
                return
            }
            #expect(started.status == .running)

            var received = ""
            var sawRunning = false
            for await event in client.events {
                switch event {
                case .output(let chunk):
                    #expect(chunk.commandID == h.first)
                    received += PlainText.strip(chunk.data)
                case .status(let change):
                    sawRunning = sawRunning || (change.command.status == .running && change.origin == .user)
                default:
                    break
                }
                if sawRunning, received.contains("ready") { break }
            }
            #expect(received == "hello from the socket\nready\n")
        }
    }

    @Test func theHelloExchangeCarriesTheProtocolVersion() async throws {
        try await withServer([]) { _, socketPath in
            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            defer { client.close() }
            #expect(client.helperProtocolVersion == HelperProtocol.version)
            #expect(client.helperVersion == DevDevCore.version)
            #expect(HelperProtocol.version == 1)
        }
    }

    @Test func aClientThatSubscribesLaterGetsTheStoredOutputReplayedAndThenTheLiveStream() async throws {
        try await withServer(settings("echo early; \(Script.runsForever)")) { h, socketPath in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")

            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            defer { client.close() }
            _ = try await client.send(.subscribeOutput(commandID: h.first))
            _ = try await client.send(.stop(commandID: h.first), origin: .agent)

            var order: [String] = []
            for await event in client.events {
                if case .outputReplay(let chunk) = event {
                    order.append("replay:" + PlainText.strip(chunk.data))
                } else if case .output(let chunk) = event {
                    order.append("live:" + PlainText.strip(chunk.data))
                    break
                }
            }
            #expect(order == ["replay:early\nready\n", "live:── stopped ──\n"])
        }
    }

    @Test func statusAndConfigurationChangesArePushedToEveryClientWithoutPolling() async throws {
        try await withServer(settings("exit 3")) { h, socketPath in
            let watcher = try await HelperClient.connect(socketPath: socketPath, clientName: "watcher")
            let actor = try await HelperClient.connect(socketPath: socketPath, clientName: "actor")
            defer {
                watcher.close()
                actor.close()
            }

            _ = try await actor.send(.start(commandID: h.first), origin: .agent)
            let added = try await actor.send(
                .addCommand(projectID: h.projectID, settings: CommandSettings(name: "Vite", commandLine: "npm run dev")),
                origin: .user)
            guard case .command(let vite) = added else {
                Issue.record("expected a Command, got \(added)")
                return
            }

            var causes: [StatusCause] = []
            var sawConfiguration = false
            for await event in watcher.events {
                if case .status(let change) = event {
                    causes.append(change.cause)
                    if change.cause == .crashed {
                        #expect(change.command.lastExit == .exited(3))
                        #expect(change.projectStatus == .crashed)
                        #expect(change.origin == nil)
                    }
                } else if case .configuration(let snapshot) = event {
                    sawConfiguration = snapshot.command(vite.id) != nil
                }
                if causes.contains(.crashed), sawConfiguration { break }
            }
            #expect(causes == [.started, .crashed])
        }
    }

    @Test func aStateChangingRequestWithoutAnOriginIsRefused() async throws {
        try await withServer(settings(Script.runsForever)) { h, socketPath in
            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            defer { client.close() }
            let requests: [HelperRequest] = [
                .start(commandID: h.first), .stop(commandID: h.first), .restart(commandID: h.first),
                .startAll(projectID: h.projectID), .stopAll(projectID: h.projectID),
                .restartAll(projectID: h.projectID),
                .renameProject(projectID: h.projectID, name: "New"),
                .deleteCommand(commandID: h.first),
            ]
            for request in requests {
                let response = try await client.send(request)
                guard case .failure(let error) = response else {
                    Issue.record("\(request) was accepted without an origin")
                    continue
                }
                #expect(error.code == HelperError.originRequired)
            }
            #expect(try await h.status(h.first) == .stopped)
            #expect(try await h.project().name == "project")
        }
    }

    @Test(arguments: [Origin.autoRestart, Origin.fileChange])
    func aClientMayNotUseAnOriginThatBelongsToTheHelper(origin: Origin) async throws {
        try await withServer(settings(Script.runsForever)) { h, socketPath in
            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            defer { client.close() }
            let response = try await client.send(.start(commandID: h.first), origin: origin)
            guard case .failure(let error) = response else {
                Issue.record("a client used the origin \(origin)")
                return
            }
            #expect(error.code == HelperError.originNotAllowed)
            #expect(try await h.status(h.first) == .stopped)
        }
    }

    @Test func readingRequestsNeedNoOrigin() async throws {
        try await withServer(settings("echo one; echo two")) { h, socketPath in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .finished)
            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            defer { client.close() }

            guard case .snapshot(let snapshot) = try await client.send(.snapshot) else {
                Issue.record("expected a snapshot")
                return
            }
            #expect(snapshot.command(h.first)?.status == .finished)
            #expect(try await client.send(.plainOutput(commandID: h.first, lastLines: 2))
                == .plainOutput("two\n── exited with code 0 ──"))
            #expect(try await client.send(.resize(commandID: h.first, columns: 90, rows: 20)) == .ok)
        }
    }

    @Test func theAllActionsAndEditsWorkThroughTheSocket() async throws {
        try await withServer(settings(Script.runsForever)) { h, socketPath in
            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            defer { client.close() }

            guard case .project(let started) = try await client.send(.startAll(projectID: h.projectID), origin: .agent)
            else {
                Issue.record("expected a Project")
                return
            }
            #expect(started.status == .running)

            var edited = started.commands[0].settings
            edited.commandLine = "echo changed; \(Script.runsForever)"
            guard
                case .command(let after) = try await client.send(
                    .updateCommand(commandID: h.first, settings: edited), origin: .user)
            else {
                Issue.record("expected a Command")
                return
            }
            #expect(after.restartToApply)
            #expect(after.processID == started.commands[0].processID)

            guard
                case .project(let restarted) = try await client.send(
                    .restartAll(projectID: h.projectID), origin: .user)
            else {
                Issue.record("expected a Project")
                return
            }
            #expect(restarted.commands[0].status == .running)
            #expect(!restarted.commands[0].restartToApply)

            guard case .project(let stopped) = try await client.send(.stopAll(projectID: h.projectID), origin: .user)
            else {
                Issue.record("expected a Project")
                return
            }
            #expect(stopped.status == .stopped)
        }
    }

    @Test func anErrorComesBackAsASentence() async throws {
        try await withServer([]) { _, socketPath in
            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            defer { client.close() }
            let response = try await client.send(.start(commandID: UUID()), origin: .user)
            #expect(response == .failure(HelperError(
                code: HelperError.unknownCommand, message: "There is no Command with that ID.")))
        }
    }

    @Test func aRequestTheHelperDoesNotKnowGetsAFailureAndTheConnectionStaysUsable() async throws {
        try await withServer([]) { _, socketPath in
            let raw = try RawSocket(path: socketPath)
            defer { raw.close() }
            try raw.write(#"{"id":7,"request":{"somethingFromTheFuture":{}}}"# + "\n")
            let failure = try raw.readLine()
            #expect(failure.contains(#""id":7"#))
            #expect(failure.contains("unknownRequest"))
            try raw.write(#"{"id":8,"request":{"hello":{"protocolVersion":99,"client":"future"}}}"# + "\n")
            let hello = try raw.readLine()
            #expect(hello.contains(#""id":8"#))
            #expect(hello.contains(#""protocolVersion":1"#))
        }
    }

    @Test func everyMessageOnTheWireIsOneLineOfJSON() async throws {
        try await withServer([]) { _, socketPath in
            let raw = try RawSocket(path: socketPath)
            defer { raw.close() }
            try raw.write(#"{"id":1,"request":{"snapshot":{}}}"# + "\n")
            let line = try raw.readLine()
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            #expect(object?["id"] as? Int == 1)
            #expect(object?["response"] != nil)
        }
    }

    @Test func aSecondHelperOnTheSameSocketRefusesToStartAndLeavesTheFirstRunning() async throws {
        try await withServer([]) { h, socketPath in
            let second = HelperServer(engine: h.engine, socketPath: socketPath)
            let error = #expect(throws: HelperError.self) { try second.start() }
            #expect(error?.code == HelperError.alreadyRunning)
            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            defer { client.close() }
            #expect(try await client.send(.snapshot) != .ok)
        }
    }

    @Test func aSocketFileLeftByADeadHelperIsReplaced() async throws {
        try await withHarness([]) { h in
            let socketPath = h.folder.appendingPathComponent("h.sock").path
            let dead = HelperServer(engine: h.engine, socketPath: socketPath)
            try dead.start()
            dead.stop()
            FileManager.default.createFile(atPath: socketPath, contents: nil)

            let server = HelperServer(engine: h.engine, socketPath: socketPath)
            try server.start()
            defer { server.stop() }
            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            client.close()
        }
    }

    @Test func connectingWhenNoHelperListensIsAnError() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        await #expect(throws: HelperError.self) {
            _ = try await HelperClient.connect(
                socketPath: folder.appendingPathComponent("none.sock").path, clientName: "test")
        }
    }

    @Test func whenTheHelperGoesAwayTheClientsEventStreamEndsAndRequestsFail() async throws {
        try await withHarness([]) { h in
            let socketPath = h.folder.appendingPathComponent("h.sock").path
            let server = HelperServer(engine: h.engine, socketPath: socketPath)
            try server.start()
            let client = try await HelperClient.connect(socketPath: socketPath, clientName: "test")
            defer { client.close() }

            server.stop()

            for await _ in client.events {}
            await #expect(throws: HelperError.self) {
                _ = try await client.send(.snapshot)
            }
        }
    }

    @Test func aSocketPathThatIsTooLongIsRefusedWithAClearError() throws {
        let long = "/tmp/" + String(repeating: "x", count: 120) + "/h.sock"
        #expect(throws: HelperError.self) {
            _ = try UnixSocket.address(for: long)
        }
    }
}

/// A bare socket for tests that must see the bytes on the wire.
final class RawSocket {
    private let fd: Int32
    private var pending = Data()

    init(path: String) throws {
        fd = try UnixSocket.connect(to: path)
    }

    func write(_ text: String) throws {
        let bytes = Array(text.utf8)
        #expect(Darwin.write(fd, bytes, bytes.count) == bytes.count)
    }

    func readLine() throws -> String {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            if let end = pending.firstIndex(of: 0x0a) {
                let line = pending[pending.startIndex..<end]
                pending = Data(pending[pending.index(after: end)...])
                return String(decoding: line, as: UTF8.self)
            }
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { throw TimedOut(description: "the socket closed before a full line arrived") }
            pending.append(contentsOf: buffer[0..<count])
        }
    }

    func close() {
        Darwin.close(fd)
    }
}
