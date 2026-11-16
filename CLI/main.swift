import DevDevCore
import Foundation
import MCP

// The `devdev` CLI. `devdev mcp` is a stdio MCP server for agent hosts such as Claude Code.
// The tools live in `DevDevCore` (`MCPTools`). This file only wires them to the MCP SDK and the Helper.

let usage = """
    Usage: devdev mcp
      Runs the devdev MCP server on standard input and output, for agent hosts such as Claude Code.
      It connects to the devdev Helper and starts it when it is not running. The App may stay closed.

    """

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments == ["mcp"] else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] ? 0 : 2)
}

// A Debug build only ever talks to the Debug Helper: its own data folder and socket.
let flavor = BuildFlavor.compiled
let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
let helper = LazyHelper(
    socketPath: HelperPaths(flavor: flavor).socketPath,
    location: HelperLocation(flavor: flavor, appBundle: MCPSetup.app(containingCLI: executable)))
let tools = MCPTools(helper: helper, workingDirectory: FileManager.default.currentDirectoryPath)

let server = Server(
    name: "devdev", version: DevDevCore.version,
    instructions: "Control and read the dev processes devdev runs for your Projects.",
    capabilities: .init(tools: .init(listChanged: false)))

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: MCPTools.definitions.map(Tool.init(definition:)))
}
await server.withMethodHandler(CallTool.self) { call in
    var values: [String: MCPArgument] = [:]
    for (name, value) in call.arguments ?? [:] {
        if let argument = MCPArgument(value) { values[name] = argument }
    }
    let result = await tools.call(call.name, arguments: values)
    return CallTool.Result(content: [.text(text: result.text, annotations: nil, _meta: nil)], isError: result.isError)
}

do {
    try await server.start(transport: StdioTransport())
    await server.waitUntilCompleted()
} catch {
    FileHandle.standardError.write(Data("devdev mcp stopped: \(error)\n".utf8))
    exit(1)
}

// MARK: - The Helper connection

/// Connects to the Helper on the first call, starting it when needed, and again after it went away.
actor LazyHelper: HelperConnection {
    private let socketPath: String
    private let location: HelperLocation
    private var client: HelperClient?

    init(socketPath: String, location: HelperLocation) {
        self.socketPath = socketPath
        self.location = location
    }

    func send(_ request: HelperRequest, origin: Origin?) async throws -> HelperResponse {
        do {
            return try await connected().send(request, origin: origin)
        } catch let error as HelperError where error.code == HelperError.connectionClosed {
            // The Helper quit or was restarted since the last call. Try once more with a fresh connection.
            client = nil
            return try await connected().send(request, origin: origin)
        }
    }

    private func connected() async throws -> HelperClient {
        if let client { return client }
        let client: HelperClient
        if let running = try? await HelperClient.connect(socketPath: socketPath, clientName: "devdev mcp") {
            client = running
        } else {
            try launchHelper()
            client = try await waitForHelper()
        }
        guard client.helperProtocolVersion == HelperProtocol.version else {
            client.close()
            throw HelperError(
                code: HelperError.connectionFailed,
                message:
                    "The running devdev Helper speaks protocol version \(client.helperProtocolVersion), this devdev CLI speaks \(HelperProtocol.version). Ask the user to restart the Helper from the devdev App.")
        }
        self.client = client
        return client
    }

    private func launchHelper() throws {
        let bundle = try location.existingHelperBundle()
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", bundle.path]
        // Standard output carries JSON-RPC only.
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.nullDevice
        open.standardInput = FileHandle.nullDevice
        try open.run()
        open.waitUntilExit()
    }

    private func waitForHelper() async throws -> HelperClient {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if let client = try? await HelperClient.connect(socketPath: socketPath, clientName: "devdev mcp") {
                return client
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw HelperError(
            code: HelperError.connectionFailed,
            message: "The devdev Helper was started but did not answer on \(socketPath).")
    }
}

// MARK: - SDK types

extension Tool {
    init(definition: MCPToolDefinition) {
        var properties: [String: Value] = [:]
        for property in definition.properties {
            properties[property.name] = .object([
                "type": .string(property.kind.rawValue), "description": .string(property.description),
            ])
        }
        let readOnly = ["list_projects", "get_project", "get_output", "search_output"].contains(definition.name)
        self.init(
            name: definition.name,
            description: definition.description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(definition.required.map(Value.string)),
            ]),
            annotations: .init(readOnlyHint: readOnly, destructiveHint: false, openWorldHint: false))
    }
}

extension MCPArgument {
    init?(_ value: Value) {
        switch value {
        case .string(let text): self = .string(text)
        case .int(let number): self = .number(Double(number))
        case .double(let number): self = .number(number)
        case .bool(let flag): self = .bool(flag)
        default: return nil
        }
    }
}
