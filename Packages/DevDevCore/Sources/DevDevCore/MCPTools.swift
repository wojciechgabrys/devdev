import Foundation

/// What the MCP tools need from the Helper: one request at a time, with an origin.
public protocol HelperConnection: Sendable {
    func send(_ request: HelperRequest, origin: Origin?) async throws -> HelperResponse
}

extension HelperClient: HelperConnection {}

/// One argument value of a tool call.
public enum MCPArgument: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
}

/// What a tool call answers: plain text, and whether it is an error an agent should act on.
public struct MCPToolResult: Sendable, Equatable {
    public var text: String
    public var isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }
}

/// A tool as the MCP server lists it. Every property is a string or an integer.
public struct MCPToolDefinition: Sendable, Equatable {
    public struct Property: Sendable, Equatable {
        public enum Kind: String, Sendable { case string, integer }
        public var name: String
        public var kind: Kind
        public var description: String
    }

    public var name: String
    public var description: String
    public var properties: [Property]
    public var required: [String]
}

/// The tools of `devdev mcp`. Agents can control and read; they cannot create, edit or delete anything.
/// Every request carries the origin `agent`.
public struct MCPTools: Sendable {
    public static let origin = Origin.agent
    public static let defaultOutputLines = 100
    public static let defaultContextLines = 2

    private let helper: any HelperConnection
    private let workingDirectory: String
    private let settle: Duration
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - workingDirectory: The server's working directory. It picks the Project when a call names none.
    ///   - settle: The wait after a start or restart, so a Command that crashes at once reads as Crashed.
    public init(
        helper: any HelperConnection,
        workingDirectory: String,
        settle: Duration = Timings.standard.mcpWait,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.helper = helper
        self.workingDirectory = workingDirectory
        self.settle = settle
        self.now = now
    }

    // MARK: - Definitions

    private static let project = MCPToolDefinition.Property(
        name: "project", kind: .string,
        description:
            "Project name, any letter case. When left out, the Project whose folder holds the working directory.")
    private static let command = MCPToolDefinition.Property(
        name: "command", kind: .string, description: "Command name, any letter case.")

    public static let definitions: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "list_projects", description: "Every devdev Project with its folder and status.",
            properties: [
                .init(
                    name: "project", kind: .string,
                    description: "Only this Project, any letter case. When left out, every Project.")
            ], required: []),
        MCPToolDefinition(
            name: "get_project",
            description: "One Project: its Commands with status, exit code and time since the last start.",
            properties: [project], required: []),
        MCPToolDefinition(
            name: "start_command", description: "Start one Command. Returns its status about a second later.",
            properties: [project, command], required: ["command"]),
        MCPToolDefinition(
            name: "stop_command", description: "Stop one Command. Returns its status.",
            properties: [project, command], required: ["command"]),
        MCPToolDefinition(
            name: "restart_command",
            description: "Restart one Command, or start it when it is not Running. Returns its status about a second later.",
            properties: [project, command], required: ["command"]),
        MCPToolDefinition(
            name: "start_all",
            description: "Start every Command of the Project that is included in Start All. Returns each Command's status.",
            properties: [project], required: []),
        MCPToolDefinition(
            name: "stop_all",
            description: "Stop every Running Command of the Project and clear Crashed and Finished ones. Returns each Command's status.",
            properties: [project], required: []),
        MCPToolDefinition(
            name: "restart_all",
            description: "Restart the Running Commands of the Project. Others are left alone. Returns each Command's status.",
            properties: [project], required: []),
        MCPToolDefinition(
            name: "get_output", description: "The last lines of a Command's output, as plain text.",
            properties: [
                project, command,
                .init(name: "lines", kind: .integer, description: "How many lines. Default \(defaultOutputLines)."),
            ], required: ["command"]),
        MCPToolDefinition(
            name: "search_output",
            description:
                "Lines of a Command's output that match a pattern, with a little context. Matching lines are marked `N:`, context lines `N-`.",
            properties: [
                project, command,
                .init(
                    name: "pattern", kind: .string,
                    description: "A regular expression, or plain text when it is not one. Letter case is ignored."),
                .init(
                    name: "context", kind: .integer,
                    description: "Lines shown before and after each match. Default \(defaultContextLines)."),
            ], required: ["command", "pattern"]),
    ]

    // MARK: - Calls

    /// Runs one tool. Every failure comes back as a sentence with `isError` set.
    public func call(_ name: String, arguments: [String: MCPArgument]) async -> MCPToolResult {
        do {
            let text: String
            switch name {
            case "list_projects": text = try await listProjects(arguments)
            case "get_project": text = try await getProject(arguments)
            case "start_command": text = try await act(on: arguments, waits: true) { .start(commandID: $0) }
            case "stop_command": text = try await act(on: arguments, waits: false) { .stop(commandID: $0) }
            case "restart_command": text = try await act(on: arguments, waits: true) { .restart(commandID: $0) }
            case "start_all": text = try await actOnProject(arguments, waits: true) { .startAll(projectID: $0) }
            case "stop_all": text = try await actOnProject(arguments, waits: false) { .stopAll(projectID: $0) }
            case "restart_all": text = try await actOnProject(arguments, waits: true) { .restartAll(projectID: $0) }
            case "get_output": text = try await getOutput(arguments)
            case "search_output": text = try await searchOutput(arguments)
            default:
                let names = Self.definitions.map(\.name).joined(separator: ", ")
                throw ToolError("There is no tool named '\(name)'. Tools: \(names).")
            }
            return MCPToolResult(text: text, isError: false)
        } catch let error as ToolError {
            return MCPToolResult(text: error.message, isError: true)
        } catch let error as HelperError {
            return MCPToolResult(text: error.message, isError: true)
        } catch {
            return MCPToolResult(text: "devdev could not reach its Helper: \(error)", isError: true)
        }
    }

    private struct ToolError: Error {
        var message: String
        init(_ message: String) { self.message = message }
    }

    // MARK: - The tools

    /// Every Project, or only the one named by `project`.
    private func listProjects(_ arguments: [String: MCPArgument]) async throws -> String {
        if case .string(let name)? = arguments["project"], !name.isEmpty {
            return Self.headline(try await resolveProject(arguments))
        }
        let projects = try await snapshot().projects
        guard !projects.isEmpty else { return Self.noProjects }
        return projects.map(Self.headline).joined(separator: "\n")
    }

    private func getProject(_ arguments: [String: MCPArgument]) async throws -> String {
        let project = try await resolveProject(arguments)
        let lines = project.commands.map { "- \($0.settings.name): \(detail($0))" }
        return ([Self.headline(project)] + (lines.isEmpty ? ["No Commands yet."] : lines)).joined(separator: "\n")
    }

    private func act(
        on arguments: [String: MCPArgument], waits: Bool, _ request: (UUID) -> HelperRequest
    ) async throws -> String {
        let (project, command) = try await resolveCommand(arguments)
        var result = try commandResult(try await send(request(command.id)))
        if waits {
            try? await Task.sleep(for: settle)
            result = try await snapshot().command(command.id) ?? result
        }
        return "\(result.settings.name) in \(project.name): \(result.statusText)"
    }

    private func actOnProject(
        _ arguments: [String: MCPArgument], waits: Bool, _ request: (UUID) -> HelperRequest
    ) async throws -> String {
        let project = try await resolveProject(arguments)
        var result = try projectResult(try await send(request(project.id)))
        if waits {
            try? await Task.sleep(for: settle)
            result = try await snapshot().project(project.id) ?? result
        }
        let lines = result.commands.map { "- \($0.settings.name): \($0.statusText)" }
        return (["\(result.name): \(result.status.label)"] + lines).joined(separator: "\n")
    }

    private func getOutput(_ arguments: [String: MCPArgument]) async throws -> String {
        let (project, command) = try await resolveCommand(arguments)
        let count = try integer("lines", in: arguments) ?? Self.defaultOutputLines
        let text = try await plainOutput(command.id, lastLines: max(0, count))
        return text.isEmpty ? "\(command.settings.name) in \(project.name) has no output yet." : text
    }

    private func searchOutput(_ arguments: [String: MCPArgument]) async throws -> String {
        let (project, command) = try await resolveCommand(arguments)
        guard case .string(let pattern)? = arguments["pattern"], !pattern.isEmpty else {
            throw ToolError("Give the text to look for in the 'pattern' argument.")
        }
        let context = max(0, try integer("context", in: arguments) ?? Self.defaultContextLines)
        let text = try await plainOutput(command.id, lastLines: nil)
        let found = OutputSearch.search(text, for: pattern, context: context)
        return found.isEmpty
            ? "No line of the output of \(command.settings.name) in \(project.name) matches '\(pattern)'." : found
    }

    // MARK: - Finding Projects and Commands

    private func resolveProject(_ arguments: [String: MCPArgument]) async throws -> ProjectSnapshot {
        let projects = try await snapshot().projects
        guard !projects.isEmpty else { throw ToolError(Self.noProjects) }
        let names = projects.map(\.name).joined(separator: ", ")
        if case .string(let name)? = arguments["project"], !name.isEmpty {
            guard let project = projects.first(where: { Self.sameName($0.name, name) }) else {
                throw ToolError("No Project named '\(name)'. Projects: \(names).")
            }
            return project
        }
        guard let project = ProjectFolders.project(containing: workingDirectory, in: projects) else {
            throw ToolError(
                "No Project contains the working directory. Name one with the 'project' argument. Projects: \(names).")
        }
        return project
    }

    private func resolveCommand(_ arguments: [String: MCPArgument]) async throws -> (ProjectSnapshot, CommandSnapshot) {
        let project = try await resolveProject(arguments)
        let names = project.commands.map(\.settings.name).joined(separator: ", ")
        guard !project.commands.isEmpty else {
            throw ToolError("Project '\(project.name)' has no Commands yet. Add them in the devdev App.")
        }
        guard case .string(let name)? = arguments["command"], !name.isEmpty else {
            throw ToolError("Name a Command with the 'command' argument. Commands in \(project.name): \(names).")
        }
        guard let command = project.commands.first(where: { Self.sameName($0.settings.name, name) }) else {
            throw ToolError("No Command named '\(name)' in Project '\(project.name)'. Commands: \(names).")
        }
        return (project, command)
    }

    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces))
            == .orderedSame
    }

    private static let noProjects = "There are no Projects in devdev yet. Add one in the devdev App."

    // MARK: - Talking to the Helper

    private func send(_ request: HelperRequest) async throws -> HelperResponse {
        let response = try await helper.send(request, origin: request.changesState ? Self.origin : nil)
        if case .failure(let error) = response { throw error }
        return response
    }

    private func snapshot() async throws -> HelperSnapshot {
        guard case .snapshot(let snapshot) = try await send(.snapshot) else { throw Self.unexpected }
        return snapshot
    }

    private func plainOutput(_ commandID: UUID, lastLines: Int?) async throws -> String {
        guard case .plainOutput(let text) = try await send(.plainOutput(commandID: commandID, lastLines: lastLines))
        else { throw Self.unexpected }
        return text
    }

    private func commandResult(_ response: HelperResponse) throws -> CommandSnapshot {
        guard case .command(let command) = response else { throw Self.unexpected }
        return command
    }

    private func projectResult(_ response: HelperResponse) throws -> ProjectSnapshot {
        guard case .project(let project) = response else { throw Self.unexpected }
        return project
    }

    private static let unexpected = ToolError("The devdev Helper gave an answer this devdev CLI does not understand.")

    private func integer(_ name: String, in arguments: [String: MCPArgument]) throws -> Int? {
        switch arguments[name] {
        case nil: return nil
        case .number(let value)? where value.rounded() == value && abs(value) < 1e9: return Int(value)
        case .string(let text)?: if let value = Int(text) { return value }
        default: break
        }
        throw ToolError("The '\(name)' argument must be a whole number.")
    }

    // MARK: - Text

    private static func headline(_ project: ProjectSnapshot) -> String {
        "\(project.name): \(project.status.label), folder \(project.folder)"
    }

    private func detail(_ command: CommandSnapshot) -> String {
        guard let startedAt = command.startedAt else { return "\(command.statusText), never started" }
        let ago = Self.elapsed(now().timeIntervalSince(startedAt))
        let started = command.status == .running ? "started" : "last started"
        return "\(command.statusText), \(started) \(ago) ago"
    }

    /// "12s", "4m 5s", "2h 3m".
    static func elapsed(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}

/// Which Project a folder belongs to.
enum ProjectFolders {
    /// The Project whose folder is the path or holds it. The deepest folder wins.
    static func project(containing path: String, in projects: [ProjectSnapshot]) -> ProjectSnapshot? {
        let candidates = forms(of: path)
        return
            projects
            .filter { project in
                forms(of: project.folder).contains { folder in candidates.contains { inside($0, folder) } }
            }
            .max { $0.folder.count < $1.folder.count }
    }

    private static func inside(_ path: String, _ folder: String) -> Bool {
        let folder = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return path == folder || path.hasPrefix(folder + "/") || folder.isEmpty
    }

    /// The path as written and with symbolic links resolved, such as `/tmp` and `/private/tmp`.
    private static func forms(of path: String) -> Set<String> {
        let standard = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        return [standard, resolved(standard)]
    }

    /// Resolves the longest part of the path that exists, then adds the rest back.
    private static func resolved(_ path: String) -> String {
        var head = path
        var tail: [String] = []
        while !head.isEmpty, head != "/" {
            if let real = realpath(head, nil) {
                defer { free(real) }
                let base = String(cString: real)
                return tail.isEmpty ? base : base + "/" + tail.reversed().joined(separator: "/")
            }
            tail.append((head as NSString).lastPathComponent)
            head = (head as NSString).deletingLastPathComponent
        }
        return path
    }
}

/// Lines of plain output that match a pattern, marked the way `grep -n -C` marks them.
enum OutputSearch {
    static func search(_ text: String, for pattern: String, context: Int) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        let matches = matcher(for: pattern)
        let hits = lines.indices.filter { matches(lines[$0]) }
        guard !hits.isEmpty else { return "" }

        var ranges: [ClosedRange<Int>] = []
        for hit in hits {
            let range = max(0, hit - context)...min(lines.count - 1, hit + context)
            if let last = ranges.last, range.lowerBound <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                ranges.append(range)
            }
        }
        let hitSet = Set(hits)
        return ranges.map { range in
            range.map { "\($0 + 1)\(hitSet.contains($0) ? ":" : "-") \(lines[$0])" }.joined(separator: "\n")
        }.joined(separator: "\n--\n")
    }

    private static func matcher(for pattern: String) -> (String) -> Bool {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            return { line in
                regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            }
        }
        return { $0.range(of: pattern, options: .caseInsensitive) != nil }
    }
}
