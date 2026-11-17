import Foundation
import Observation

/// The output of one Command on its way to the output view: the replay first, then the live stream.
///
/// A new session is made for every replay, so the view starts from an empty terminal each time.
@MainActor
public final class OutputSession: Identifiable {
    public nonisolated let id = UUID()
    public nonisolated let commandID: UUID
    private var pending: [Data] = []
    private var sink: ((Data) -> Void)?

    init(commandID: UUID) {
        self.commandID = commandID
    }

    /// Hands over everything that arrived so far, then every new chunk.
    public func attach(_ sink: @escaping (Data) -> Void) {
        self.sink = sink
        let waiting = pending
        pending = []
        waiting.forEach(sink)
    }

    public func detach() {
        sink = nil
    }

    func deliver(_ data: Data) {
        guard !data.isEmpty else { return }
        if let sink { sink(data) } else { pending.append(data) }
    }
}

/// The model behind the main window. It asks the Helper for everything and decides nothing about
/// Processes itself. Every request it sends carries the origin `user`.
@MainActor @Observable
public final class WindowModel {
    public private(set) var state = WindowState()
    /// The output of the selected Command. Nil until its replay arrives.
    public private(set) var output: OutputSession?
    /// A sentence to show when a request failed. The view clears it.
    public var errorMessage: String?
    /// The Settings the Helper stores. Nil until the Helper answers, or when it is too old to know them.
    public private(set) var settings: HelperSettings?
    /// The Discovery checklist waiting for the user. Nil when none is shown.
    public private(set) var discoveryChecklist: DiscoveryChecklist?
    /// The Project Discovery is reading right now.
    public private(set) var discoveringProjectID: UUID?

    private let socketPath: String
    private let expectedHelperBuild: String
    private let clientName: String
    private let launchWait: Duration
    private let launchHelper: @Sendable () async throws -> Void

    private var client: HelperClient?
    private var isConnecting = false
    /// True while the App itself asked the Helper to quit, so the closed connection is not a death.
    private var expectsTheHelperToQuit = false
    private var watchedCommandID: UUID?
    private var outputViewSize: TerminalSize?

    /// - Parameters:
    ///   - expectedHelperBuild: The build of the Helper this App would start. See `HelperBuild`.
    ///   - launchWait: How long to wait for a started Helper to listen.
    ///   - launchHelper: Starts the Helper program.
    public init(
        socketPath: String,
        expectedHelperBuild: String,
        clientName: String = "app",
        launchWait: Duration = .seconds(10),
        launchHelper: @escaping @Sendable () async throws -> Void
    ) {
        self.socketPath = socketPath
        self.expectedHelperBuild = expectedHelperBuild
        self.clientName = clientName
        self.launchWait = launchWait
        self.launchHelper = launchHelper
    }

    // MARK: - The Helper

    /// Connects to the Helper, starting it when it is not running. Used on launch and by "Start Helper".
    public func connect() async {
        guard client == nil, !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        state.connecting()

        if let client = await tryConnect() {
            await adopt(client)
            return
        }
        do {
            try await launchHelper()
        } catch {
            state.helperUnavailable(Self.sentence(error))
            return
        }
        let deadline = ContinuousClock.now + launchWait
        while ContinuousClock.now < deadline {
            if let client = await tryConnect() {
                await adopt(client)
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        state.helperUnavailable("The Helper was started but did not answer on \(socketPath).")
    }

    /// Stop All and Quit: stops every Process and quits the Helper. True when the App may quit now.
    public func stopAllAndQuit() async -> Bool {
        guard let client else { return true }
        expectsTheHelperToQuit = true
        do {
            let response = try await client.send(.stopAllAndQuit, origin: .user)
            if case .failure(let error) = response {
                expectsTheHelperToQuit = false
                errorMessage = error.message
                return false
            }
        } catch {
            // The connection closed before the answer: the Helper is already gone.
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while self.client != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    /// Restart Helper: stops every Process, quits the Helper and starts the one this App expects.
    public func restartHelper() async {
        guard await stopAllAndQuit() else { return }
        client?.close()
        client = nil
        await connect()
    }

    private func tryConnect() async -> HelperClient? {
        try? await HelperClient.connect(socketPath: socketPath, clientName: clientName)
    }

    private func adopt(_ client: HelperClient) async {
        self.client = client
        expectsTheHelperToQuit = false
        let compatibility = HelperCompatibility.evaluate(
            appProtocol: HelperProtocol.version, appBuild: expectedHelperBuild,
            helperProtocol: client.helperProtocolVersion, helperBuild: client.helperVersion)
        var snapshot = HelperSnapshot(projects: [])
        if compatibility.allowsRequests,
            case .snapshot(let loaded)? = try? await client.send(.snapshot, origin: .user)
        {
            snapshot = loaded
        }
        if compatibility.allowsRequests,
            case .settings(let loaded)? = try? await client.send(.settings, origin: .user)
        {
            settings = loaded
        }
        state.connected(snapshot: snapshot, compatibility: compatibility)
        Task { [weak self] in
            for await event in client.events {
                self?.receive(event)
            }
            self?.connectionEnded(client)
        }
        watchedCommandID = nil
        await watchSelectedCommand()
    }

    private func receive(_ event: HelperEvent) {
        switch event {
        case .outputReplay(let chunk):
            guard chunk.commandID == watchedCommandID else { return }
            let session = OutputSession(commandID: chunk.commandID)
            session.deliver(chunk.data)
            output = session
        case .output(let chunk):
            guard chunk.commandID == watchedCommandID, output?.commandID == chunk.commandID else { return }
            output?.deliver(chunk.data)
        case .settings(let changed):
            settings = changed
        case .status, .configuration:
            state.apply(event)
            if state.selectedCommandID != watchedCommandID {
                Task { await watchSelectedCommand() }
            }
        }
    }

    private func connectionEnded(_ ended: HelperClient) {
        guard client === ended else { return }
        client = nil
        if !expectsTheHelperToQuit {
            state.helperDied()
        }
    }

    // MARK: - Selection and output

    public func select(project id: UUID?) async {
        state.select(project: id)
        await watchSelectedCommand()
    }

    public func select(command id: UUID?) async {
        state.select(command: id)
        await watchSelectedCommand()
    }

    /// Shows a Command's output in its tab, from whichever Project it belongs to.
    /// Used by the project tree, the tabs and Go to Command.
    public func show(command id: UUID) async {
        state.select(tab: id)
        await watchSelectedCommand()
    }

    public func closeTab(_ id: UUID) async {
        state.closeTab(id)
        await watchSelectedCommand()
    }

    /// A link from the menubar panel or a notification: shows that Command's output.
    public func open(_ link: OpenLink) async {
        state.open(link)
        await watchSelectedCommand()
    }

    /// The output view reports its size in character cells. The Helper resizes the pseudo-terminal.
    public func outputViewResized(columns: Int, rows: Int) async {
        guard columns > 0, rows > 0, columns <= Int(UInt16.max), rows <= Int(UInt16.max) else { return }
        let size = TerminalSize(columns: UInt16(columns), rows: UInt16(rows))
        guard size != outputViewSize else { return }
        outputViewSize = size
        await sendSize(for: watchedCommandID)
    }

    private func sendSize(for commandID: UUID?) async {
        guard let commandID, let size = outputViewSize, let client, state.canAct else { return }
        _ = try? await client.send(
            .resize(commandID: commandID, columns: size.columns, rows: size.rows), origin: .user)
    }

    /// Follows the selection: asks the Helper for the replay and the live stream of the selected Command.
    private func watchSelectedCommand() async {
        let wanted = state.selectedCommandID
        guard wanted != watchedCommandID else { return }
        let previous = watchedCommandID
        watchedCommandID = wanted
        output = nil
        guard let client, state.canAct else { return }
        if let previous {
            _ = try? await client.send(.unsubscribeOutput(commandID: previous), origin: .user)
        }
        if let wanted {
            await sendSize(for: wanted)
            _ = try? await client.send(.subscribeOutput(commandID: wanted), origin: .user)
        }
    }

    // MARK: - Commands and Projects

    public func start(_ commandID: UUID) async { await perform(.start(commandID: commandID)) }
    public func stop(_ commandID: UUID) async { await perform(.stop(commandID: commandID)) }
    public func restart(_ commandID: UUID) async { await perform(.restart(commandID: commandID)) }
    public func startAll(_ projectID: UUID) async { await perform(.startAll(projectID: projectID)) }
    public func stopAll(_ projectID: UUID) async { await perform(.stopAll(projectID: projectID)) }
    public func restartAll(_ projectID: UUID) async { await perform(.restartAll(projectID: projectID)) }

    /// Adds the folder as a Project and selects it. A folder that already is a Project is just selected.
    /// A new Project then gets the Discovery checklist when Discovery proposes anything.
    public func addProject(folder: URL) async {
        // Taken before asking: the Helper's configuration event may arrive before its answer.
        let known = Set(state.projects.map(\.id))
        guard case .project(let project)? = await perform(.addProject(folder: folder.path, name: nil)) else {
            return
        }
        let isNew = !known.contains(project.id)
        state.include(project)
        await select(project: project.id)
        if isNew {
            await discover(project.id, reason: .projectAdded)
        }
    }

    // MARK: - Discovery

    /// Asks the Helper what Discovery proposes now and shows the checklist, even when it is empty.
    public func rescan(_ projectID: UUID) async {
        await discover(projectID, reason: .rescan)
    }

    private func discover(_ projectID: UUID, reason: DiscoveryChecklist.Reason) async {
        guard discoveringProjectID == nil else { return }
        discoveringProjectID = projectID
        defer { discoveringProjectID = nil }
        guard case .discovery(let plan)? = await perform(.discover(projectID: projectID)) else { return }
        if reason == .projectAdded, plan.add.isEmpty { return }
        let folder = state.projects.first { $0.id == projectID }.map { URL(fileURLWithPath: $0.folder) }
        discoveryChecklist = DiscoveryChecklist(
            plan: plan, reason: reason, dockerFiles: folder.map(Discovery.dockerFiles(in:)) ?? [])
    }

    /// Adds the checked proposals as Discovery-made Commands and deletes the checked removals.
    public func applyDiscovery(_ checklist: DiscoveryChecklist) async {
        discoveryChecklist = nil
        let projectID = checklist.plan.projectID
        for settings in checklist.commandsToAdd {
            await perform(.addCommand(projectID: projectID, settings: settings, madeByDiscovery: true))
        }
        for commandID in checklist.commandsToRemove {
            await perform(.deleteCommand(commandID: commandID))
        }
    }

    /// The user closed the checklist without confirming. No Command is added or removed.
    /// Closing it right after adding a Project takes the Project back out, so no empty Project is left behind.
    public func dismissDiscovery() async {
        guard let checklist = discoveryChecklist else { return }
        discoveryChecklist = nil
        if checklist.reason == .projectAdded {
            await removeProject(checklist.plan.projectID)
        }
    }

    /// The Helper stops the Project's Processes, then removes it.
    public func removeProject(_ projectID: UUID) async {
        await perform(.removeProject(projectID: projectID))
    }

    /// True when the Helper saved the Command, so the form can close.
    public func addCommand(to projectID: UUID, draft: CommandDraft) async -> Bool {
        guard case .command(let command)? = await perform(.addCommand(projectID: projectID, settings: draft.settings))
        else { return false }
        if state.selectedProjectID == projectID {
            state.select(command: command.id)
            await watchSelectedCommand()
        }
        return true
    }

    /// True when the Helper saved the edit, so the form can close. Nothing restarts by itself.
    public func updateCommand(_ commandID: UUID, draft: CommandDraft) async -> Bool {
        await perform(.updateCommand(commandID: commandID, settings: draft.settings)) != nil
    }

    /// The Helper stops the Command if it is Running, then deletes it.
    public func deleteCommand(_ commandID: UUID) async {
        await perform(.deleteCommand(commandID: commandID))
    }

    /// A drag in the Commands list. `toOffset` is the row the Command was dropped before.
    public func moveCommand(_ commandID: UUID, from: Int, toOffset: Int) async {
        await perform(.moveCommand(commandID: commandID, toIndex: CommandMove.targetIndex(from: from, toOffset: toOffset)))
    }

    // MARK: - Settings

    public func setShowMenubarIcon(_ on: Bool) async {
        guard var changed = settings else { return }
        changed.showMenubarIcon = on
        await save(changed)
    }

    public func setLaunchAtLogin(_ on: Bool) async {
        guard var changed = settings else { return }
        changed.launchAtLogin = on
        await save(changed)
    }

    /// One notification switch.
    public func setNotification(_ kind: NotificationKind, on: Bool) async {
        guard var changed = settings else { return }
        changed.notifications[kind] = on
        await save(changed)
    }

    private func save(_ changed: HelperSettings) async {
        if case .settings(let saved)? = await perform(.updateSettings(changed)) {
            settings = saved
        }
    }

    /// Sends one request with the origin `user`. Nil when it failed; the reason is in `errorMessage`.
    @discardableResult
    private func perform(_ request: HelperRequest) async -> HelperResponse? {
        guard let client, state.canAct else {
            // Not connected: the banner already says why and offers the way out.
            return nil
        }
        do {
            let response = try await client.send(request, origin: .user)
            if case .failure(let error) = response {
                errorMessage = error.message
                return nil
            }
            return response
        } catch {
            if self.client != nil { errorMessage = Self.sentence(error) }
            return nil
        }
    }

    private static func sentence(_ error: Error) -> String {
        (error as? HelperError)?.message ?? error.localizedDescription
    }
}
