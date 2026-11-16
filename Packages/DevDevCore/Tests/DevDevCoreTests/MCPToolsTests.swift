import Foundation
import Testing

@testable import DevDevCore

/// The MCP tool handlers, run against a real Helper over its socket.
@Suite struct MCPToolsTests {
    private static let settle = Duration.milliseconds(800)

    /// A Helper on a socket with one Project named "Shop", and the tools connected to it as an agent.
    private func withTools(
        _ commands: [CommandSettings],
        workingDirectory: ((Harness) -> String)? = nil,
        _ body: (Harness, MCPTools) async throws -> Void
    ) async throws {
        try await withHarness(commands) { h in
            _ = try await h.engine.renameProject(h.projectID, name: "Shop")
            let socketPath = h.folder.appendingPathComponent("h.sock").path
            let server = HelperServer(engine: h.engine, socketPath: socketPath)
            try server.start()
            let client: HelperClient
            do {
                client = try await HelperClient.connect(socketPath: socketPath, clientName: "mcp-test")
            } catch {
                server.stop()
                throw error
            }
            let tools = MCPTools(
                helper: client, workingDirectory: workingDirectory?(h) ?? h.projectFolder.path, settle: Self.settle)
            do {
                try await body(h, tools)
            } catch {
                client.close()
                server.stop()
                throw error
            }
            client.close()
            server.stop()
        }
    }

    private let shop = [
        CommandSettings(name: "Vite", commandLine: Script.runsForever),
        CommandSettings(name: "Queue Worker", commandLine: Script.runsForever),
        CommandSettings(name: "Scheduler", commandLine: Script.runsForever, includedInStartAll: false),
    ]

    private func expectSuccess(_ result: MCPToolResult, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!result.isError, "unexpected error: \(result.text)", sourceLocation: sourceLocation)
    }

    // MARK: - The ten tools

    @Test func theServerOffersExactlyTheTenTools() {
        #expect(
            MCPTools.definitions.map(\.name) == [
                "list_projects", "get_project", "start_command", "stop_command", "restart_command", "start_all",
                "stop_all", "restart_all", "get_output", "search_output",
            ])
        for definition in MCPTools.definitions {
            #expect(definition.properties.contains { $0.name == "project" }, "\(definition.name) takes a project")
            #expect(!definition.required.contains("project"))
        }
    }

    @Test func listProjectsGivesEveryProjectWithItsFolderAndStatus() async throws {
        try await withTools(shop) { h, tools in
            let result = await tools.call("list_projects", arguments: [:])
            expectSuccess(result)
            #expect(result.text == "Shop: Stopped, folder \(h.projectFolder.path)")
        }
    }

    @Test func listProjectsWithAProjectGivesOnlyThatOne() async throws {
        try await withTools(shop, workingDirectory: { _ in "/" }) { h, tools in
            let result = await tools.call("list_projects", arguments: ["project": .string("shop")])
            expectSuccess(result)
            #expect(result.text == "Shop: Stopped, folder \(h.projectFolder.path)")
        }
    }

    @Test func getProjectGivesEachCommandWithStatusExitCodeAndTimeSinceStart() async throws {
        try await withTools(
            [
                CommandSettings(name: "Vite", commandLine: Script.runsForever),
                CommandSettings(name: "Queue", commandLine: "exit 3"),
                CommandSettings(name: "Scheduler", commandLine: Script.runsForever),
            ]
        ) { h, tools in
            _ = try await h.engine.start(h.commandIDs[0], origin: .user)
            _ = try await h.engine.start(h.commandIDs[1], origin: .user)
            try await h.waitForStatus(h.commandIDs[1], .crashed)

            let result = await tools.call("get_project", arguments: [:])
            expectSuccess(result)
            let lines = result.text.split(separator: "\n").map(String.init)
            #expect(lines.first == "Shop: Crashed, folder \(h.projectFolder.path)")
            #expect(lines.contains { $0.hasPrefix("- Vite: Running, started ") && $0.hasSuffix(" ago") })
            #expect(lines.contains { $0.hasPrefix("- Queue: Crashed (exit code 3), last started ") })
            #expect(lines.contains("- Scheduler: Stopped, never started"))
        }
    }

    @Test func startCommandStartsItAsAnAgentAndReturnsItsStatus() async throws {
        try await withTools(shop) { h, tools in
            let log = await EventLog.listening(to: h.engine)
            let result = await tools.call("start_command", arguments: ["command": .string("Vite")])
            expectSuccess(result)
            #expect(result.text == "Vite in Shop: Running")
            let status = try await h.status(h.commandIDs[0])
            #expect(status == .running)
            #expect(await log.statusChanges.first?.origin == .agent)
        }
    }

    @Test func stopCommandStopsItAndReturnsStopped() async throws {
        try await withTools(shop) { h, tools in
            _ = try await h.engine.start(h.commandIDs[0], origin: .user)
            let result = await tools.call("stop_command", arguments: ["command": .string("Vite")])
            expectSuccess(result)
            #expect(result.text == "Vite in Shop: Stopped")
        }
    }

    @Test func restartCommandRestartsARunningCommand() async throws {
        try await withTools(shop) { h, tools in
            let first = try await h.engine.start(h.commandIDs[0], origin: .user)
            let result = await tools.call("restart_command", arguments: ["command": .string("Vite")])
            expectSuccess(result)
            #expect(result.text == "Vite in Shop: Running")
            let restarted = try await h.command(h.commandIDs[0])
            #expect(restarted.processID != first.processID)
        }
    }

    @Test func restartCommandStartsACommandThatIsNotRunning() async throws {
        try await withTools(shop) { h, tools in
            let result = await tools.call("restart_command", arguments: ["command": .string("Vite")])
            expectSuccess(result)
            #expect(result.text == "Vite in Shop: Running")
        }
    }

    @Test func startAllStartsTheProjectAndReturnsTheStatusOfEachCommand() async throws {
        try await withTools(shop) { h, tools in
            let result = await tools.call("start_all", arguments: [:])
            expectSuccess(result)
            #expect(
                result.text == """
                    Shop: Running
                    - Vite: Running
                    - Queue Worker: Running
                    - Scheduler: Stopped
                    """)
        }
    }

    @Test func stopAllStopsTheProjectAndReturnsTheStatusOfEachCommand() async throws {
        try await withTools(shop) { h, tools in
            _ = try await h.engine.startAll(h.projectID, origin: .user)
            let result = await tools.call("stop_all", arguments: ["project": .string("Shop")])
            expectSuccess(result)
            #expect(
                result.text == """
                    Shop: Stopped
                    - Vite: Stopped
                    - Queue Worker: Stopped
                    - Scheduler: Stopped
                    """)
        }
    }

    @Test func restartAllRestartsOnlyTheRunningCommands() async throws {
        try await withTools(shop) { h, tools in
            _ = try await h.engine.start(h.commandIDs[0], origin: .user)
            let result = await tools.call("restart_all", arguments: [:])
            expectSuccess(result)
            #expect(
                result.text == """
                    Shop: Partly Running
                    - Vite: Running
                    - Queue Worker: Stopped
                    - Scheduler: Stopped
                    """)
        }
    }

    @Test func getOutputGivesTheLastHundredLinesAsPlainTextByDefault() async throws {
        let script = #"i=1; while [ $i -le 150 ]; do printf '\033[32mline %d\033[0m\n' $i; i=$((i+1)); done; "#
        try await withTools([CommandSettings(name: "Log", commandLine: script + Script.runsForever)]) { h, tools in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")

            let result = await tools.call("get_output", arguments: ["command": .string("Log")])
            expectSuccess(result)
            let lines = result.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            #expect(lines.count == 100)
            #expect(lines.first == "line 52")
            #expect(lines.last == "ready")
            #expect(!result.text.contains("\u{1b}"))
        }
    }

    @Test func getOutputTakesTheNumberOfLines() async throws {
        let script = #"printf '\033[1mbold\033[0m\nsecond\n'; "#
        try await withTools([CommandSettings(name: "Log", commandLine: script + Script.runsForever)]) { h, tools in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            let result = await tools.call("get_output", arguments: ["command": .string("log"), "lines": .number(2)])
            expectSuccess(result)
            #expect(result.text == "second\nready")
        }
    }

    @Test func searchOutputGivesMatchingLinesWithALittleContextAndNoEscapeSequences() async throws {
        let script = #"printf 'one\ntwo\n\033[31mERROR: disk full\033[0m\nthree\nfour\nfive\nsix\nseven\nerror again\n'; "#
        try await withTools([CommandSettings(name: "Log", commandLine: script + Script.runsForever)]) { h, tools in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")

            let result = await tools.call(
                "search_output", arguments: ["command": .string("Log"), "pattern": .string("error")])
            expectSuccess(result)
            #expect(
                result.text == """
                    1- one
                    2- two
                    3: ERROR: disk full
                    4- three
                    5- four
                    --
                    7- six
                    8- seven
                    9: error again
                    10- ready
                    """)
            #expect(!result.text.contains("\u{1b}"))
        }
    }

    @Test func searchOutputSaysSoWhenNothingMatches() async throws {
        try await withTools([CommandSettings(name: "Log", commandLine: Script.runsForever)]) { h, tools in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            let result = await tools.call(
                "search_output", arguments: ["command": .string("Log"), "pattern": .string("nope")])
            expectSuccess(result)
            #expect(result.text == "No line of the output of Log in Shop matches 'nope'.")
        }
    }

    // MARK: - Names

    @Test func aProjectAndACommandAreFoundByNameWithoutRegardToLetterCase() async throws {
        try await withTools(shop, workingDirectory: { _ in "/" }) { h, tools in
            let result = await tools.call(
                "start_command", arguments: ["project": .string("sHOP"), "command": .string("queue WORKER")])
            expectSuccess(result)
            #expect(result.text == "Queue Worker in Shop: Running")
            let status = try await h.status(h.commandIDs[1])
            #expect(status == .running)
        }
    }

    @Test func aMissedCommandNameReturnsASentenceListingTheCommands() async throws {
        try await withTools(shop) { _, tools in
            let result = await tools.call("stop_command", arguments: ["command": .string("queue")])
            #expect(result.isError)
            #expect(result.text == "No Command named 'queue' in Project 'Shop'. Commands: Vite, Queue Worker, Scheduler.")
        }
    }

    @Test func aMissedProjectNameReturnsASentenceListingTheProjects() async throws {
        try await withTools(shop) { _, tools in
            let result = await tools.call("get_project", arguments: ["project": .string("blog")])
            #expect(result.isError)
            #expect(result.text == "No Project named 'blog'. Projects: Shop.")
        }
    }

    @Test func aMissingCommandArgumentReturnsASentenceListingTheCommands() async throws {
        try await withTools(shop) { _, tools in
            let result = await tools.call("start_command", arguments: [:])
            #expect(result.isError)
            #expect(result.text == "Name a Command with the 'command' argument. Commands in Shop: Vite, Queue Worker, Scheduler.")
        }
    }

    // MARK: - The working directory

    @Test func withoutAProjectArgumentTheProjectContainingTheWorkingDirectoryIsUsed() async throws {
        try await withTools(shop, workingDirectory: { h in h.projectFolder.appendingPathComponent("app/Models").path }) {
            _, tools in
            let result = await tools.call("get_project", arguments: [:])
            expectSuccess(result)
            #expect(result.text.hasPrefix("Shop: Stopped"))
        }
    }

    @Test func aWorkingDirectoryOutsideEveryProjectReturnsASentenceListingTheProjects() async throws {
        try await withTools(shop, workingDirectory: { h in h.folder.path }) { _, tools in
            let result = await tools.call("get_project", arguments: [:])
            #expect(result.isError)
            #expect(
                result.text
                    == "No Project contains the working directory. Name one with the 'project' argument. Projects: Shop.")
        }
    }

    @Test func aFolderThatOnlySharesAPrefixWithAProjectDoesNotMatch() async throws {
        try await withTools(shop, workingDirectory: { h in h.projectFolder.path + "-other" }) { _, tools in
            let result = await tools.call("get_project", arguments: [:])
            #expect(result.isError)
        }
    }

    // MARK: - An immediate crash

    @Test func aStartOfACommandThatCrashesAtOnceReturnsCrashed() async throws {
        try await withTools([CommandSettings(name: "Queue", commandLine: "echo boom; exit 1")]) { _, tools in
            let result = await tools.call("start_command", arguments: ["command": .string("Queue")])
            expectSuccess(result)
            #expect(result.text == "Queue in Shop: Crashed (exit code 1)")
        }
    }

    @Test func aRestartOfACommandThatCrashesAtOnceReturnsCrashed() async throws {
        let line = "if [ -f marker ]; then exit 2; fi; touch marker; \(Script.runsForever)"
        try await withTools([CommandSettings(name: "Queue", commandLine: line)]) { h, tools in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            let result = await tools.call("restart_command", arguments: ["command": .string("Queue")])
            expectSuccess(result)
            #expect(result.text == "Queue in Shop: Crashed (exit code 2)")
        }
    }

    @Test func anUnknownToolReturnsAnError() async throws {
        try await withTools(shop) { _, tools in
            let result = await tools.call("delete_project", arguments: [:])
            #expect(result.isError)
            #expect(result.text.hasPrefix("There is no tool named 'delete_project'."))
        }
    }
}
