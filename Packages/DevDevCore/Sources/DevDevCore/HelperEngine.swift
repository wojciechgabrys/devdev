import Foundation

/// The heart of the Helper: owns every Process, its output and the saved configuration.
public actor HelperEngine {
    private struct Runtime {
        var status: CommandStatus = .stopped
        var lastExit: ProcessExit?
        var buffer = OutputBuffer()
        var restartToApply = false
        var startedAt: Date?
        var size = TerminalSize.standard
        var process: PTYProcess?
        var run = 0
        var stopRequested = false
        var stopOrigin: Origin?
        var stopCause = StatusCause.stopped
        var stopAction: ProjectAction?
        /// Set by a restart while it waits for the old Process. A plain stop clears it.
        var startAfterStop = false
        var stopWaiters: [CheckedContinuation<Void, Never>] = []
        /// When the Command crashed with auto-restart on, since its last manual start.
        var crashTimes: [Date] = []
        /// The auto-restart waiting for its delay. Anything that starts or stops the Command clears it.
        var pendingAutoRestart: Int?
        /// The latest matching file change. A restart waits until no newer one came for the settle time.
        var pendingFileChange: Int?
    }

    private struct Watch {
        var folder: String
        var watch: any FolderWatch
    }

    /// Crashes within the crash window after which auto-restart pauses.
    static let crashesBeforePause = 5

    private struct Subscriber {
        var continuation: AsyncStream<HelperEvent>.Continuation
        var outputOf: Set<UUID> = []
    }

    private var configuration: Configuration
    private let store: ConfigurationStore
    private let shell: Shell
    private let timings: Timings
    private let environment: [String: String]
    private let now: @Sendable () -> Date
    private let loginItem: (any LoginItem)?
    private let poster: (any NotificationPoster)?
    private var runtimes: [UUID: Runtime] = [:]
    private var subscribers: [UUID: Subscriber] = [:]
    private var runCounter = 0
    private var waitCounter = 0
    private let folderWatcher: FolderWatcherFactory
    /// Runs `php artisan dev:list` for Discovery.
    private let devList: any DevListRunner
    /// One per Project with a Running Command that restarts when files change.
    private var watches: [UUID: Watch] = [:]

    /// What the Helper reports as its build in the hello answer.
    public nonisolated let helperVersion: String
    /// Yields once after Stop All and Quit has stopped every Process. The Helper program then exits.
    public nonisolated let quitRequests: AsyncStream<Void>
    private nonisolated let quitInput: AsyncStream<Void>.Continuation

    public init(
        configuration: Configuration,
        store: ConfigurationStore,
        shell: Shell = .userLogin(),
        timings: Timings = .standard,
        helperVersion: String = DevDevCore.version,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping @Sendable () -> Date = { Date() },
        loginItem: (any LoginItem)? = nil,
        notifications poster: (any NotificationPoster)? = nil,
        folderWatcher: @escaping FolderWatcherFactory = FSEventsFolderWatcher.factory,
        devList: (any DevListRunner)? = nil
    ) {
        self.devList = devList ?? ShellDevListRunner(shell: shell)
        self.folderWatcher = folderWatcher
        self.loginItem = loginItem
        self.poster = poster
        // A file saved before the lists were sorted is served sorted. It is rewritten at the next change.
        self.configuration = configuration.sortedByName()
        self.store = store
        self.shell = shell
        self.timings = timings
        self.environment = environment
        self.now = now
        self.helperVersion = helperVersion
        (quitRequests, quitInput) = AsyncStream.makeStream(of: Void.self)
    }

    // MARK: - Reading

    public func snapshot() -> HelperSnapshot {
        HelperSnapshot(projects: configuration.projects.map(projectSnapshot))
    }

    /// The stored output as the Process wrote it.
    public func output(_ commandID: UUID) throws -> Data {
        _ = try find(commandID)
        return runtimes[commandID]?.buffer.data ?? Data()
    }

    /// The stored output with escape sequences removed.
    public func plainOutput(_ commandID: UUID, lastLines: Int?) throws -> String {
        _ = try find(commandID)
        return runtimes[commandID]?.buffer.plainText(lastLines: lastLines) ?? ""
    }

    // MARK: - Events

    /// Every subscriber gets status and configuration events. Output is sent only after `subscribeOutput`.
    public func subscribe() -> (id: UUID, events: AsyncStream<HelperEvent>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: HelperEvent.self)
        subscribers[id] = Subscriber(continuation: continuation)
        return (id, stream)
    }

    public func unsubscribe(_ subscriber: UUID) {
        subscribers.removeValue(forKey: subscriber)?.continuation.finish()
    }

    /// Sends the stored output of the Command to the subscriber, then every new chunk.
    public func subscribeOutput(_ commandID: UUID, subscriber: UUID) throws {
        _ = try find(commandID)
        guard subscribers[subscriber] != nil else { return }
        let stored = runtimes[commandID]?.buffer.data ?? Data()
        subscribers[subscriber]?.continuation.yield(.outputReplay(OutputChunk(commandID: commandID, data: stored)))
        subscribers[subscriber]?.outputOf.insert(commandID)
    }

    public func unsubscribeOutput(_ commandID: UUID, subscriber: UUID) {
        subscribers[subscriber]?.outputOf.remove(commandID)
    }

    // MARK: - One Command

    /// Starts the Command. Starting a Running Command is a no-op that returns the current status.
    @discardableResult
    public func start(_ commandID: UUID, origin: Origin) throws -> CommandSnapshot {
        let wasRunning = isRunning(commandID)
        let snapshot = try launch(commandID, origin: origin, cause: .started, action: nil)
        if !wasRunning { notifyChange(.started, [commandID], origin: origin, action: nil) }
        return snapshot
    }

    /// Stops the Command: SIGTERM to the tree, then SIGKILL. A Crashed or Finished Command becomes Stopped.
    @discardableResult
    public func stop(_ commandID: UUID, origin: Origin) async throws -> CommandSnapshot {
        _ = try find(commandID)
        // Stop on a Crashed or Finished Command only clears it: no notification.
        let wasRunning = isRunning(commandID)
        await halt(commandID, origin: origin, cause: .stopped, action: nil)
        if wasRunning { notifyChange(.stopped, [commandID], origin: origin, action: nil) }
        return try commandSnapshot(commandID)
    }

    /// Stop, then start. On a Command that is not Running it is a start, and is reported as one.
    @discardableResult
    public func restart(_ commandID: UUID, origin: Origin) async throws -> CommandSnapshot {
        _ = try find(commandID)
        guard isRunning(commandID) else {
            return try start(commandID, origin: origin)
        }
        runtimes[commandID]?.startAfterStop = true
        await halt(commandID, origin: origin, cause: .stoppedForRestart, action: nil)
        if runtimes[commandID]?.startAfterStop == true {
            runtimes[commandID]?.startAfterStop = false
            let snapshot = try launch(commandID, origin: origin, cause: .restarted, action: nil)
            notifyChange(.restarted, [commandID], origin: origin, action: nil)
            return snapshot
        }
        return try commandSnapshot(commandID)
    }

    /// Resizes the pseudo-terminal of the Command. The size is kept for its next Process.
    public func resize(_ commandID: UUID, to size: TerminalSize) throws {
        _ = try find(commandID)
        guard size.columns > 0, size.rows > 0 else { return }
        runtimes[commandID, default: Runtime()].size = size
        runtimes[commandID]?.process?.resize(size)
    }

    // MARK: - A whole Project

    /// Starts every Command included in Start All that is not Running, in order of name.
    @discardableResult
    public func startAll(_ projectID: UUID, origin: Origin) throws -> ProjectSnapshot {
        let project = try findProject(projectID)
        var launched: [UUID] = []
        for command in project.commands
        where command.settings.includedInStartAll && runtimes[command.id]?.process == nil {
            try launch(command.id, origin: origin, cause: .started, action: .startAll)
            launched.append(command.id)
        }
        notifyChange(.started, launched, origin: origin, action: .startAll)
        return projectSnapshot(try findProject(projectID))
    }

    /// Stops every Running Command, and sets every Crashed or Finished Command to Stopped.
    @discardableResult
    public func stopAll(_ projectID: UUID, origin: Origin) async throws -> ProjectSnapshot {
        let project = try findProject(projectID)
        let running = project.commands.map(\.id).filter(isRunning)
        await haltAll(project.commands.map(\.id), origin: origin, cause: .stopped, action: .stopAll)
        notifyChange(.stopped, running, origin: origin, action: .stopAll)
        return projectSnapshot(try findProject(projectID))
    }

    /// Restarts only the Running Commands, in order of name. Never starts a Stopped, Finished or
    /// Crashed Command.
    @discardableResult
    public func restartAll(_ projectID: UUID, origin: Origin) async throws -> ProjectSnapshot {
        let project = try findProject(projectID)
        let running = project.commands.map(\.id).filter { runtimes[$0]?.process != nil }
        for id in running {
            runtimes[id]?.startAfterStop = true
        }
        await haltAll(running, origin: origin, cause: .stoppedForRestart, action: .restartAll)
        var restarted: [UUID] = []
        for id in running where runtimes[id]?.startAfterStop == true {
            runtimes[id]?.startAfterStop = false
            _ = try? launch(id, origin: origin, cause: .restarted, action: .restartAll)
            restarted.append(id)
        }
        notifyChange(.restarted, restarted, origin: origin, action: .restartAll)
        return projectSnapshot(try findProject(projectID))
    }

    /// Stops every Process of every Project.
    public func stopEverything(origin: Origin) async {
        let ids = configuration.projects.flatMap(\.commands).map(\.id)
        for id in ids { runtimes[id]?.pendingAutoRestart = nil }
        await haltAll(ids.filter { runtimes[$0]?.process != nil }, origin: origin, cause: .stopped, action: nil)
    }

    /// Stop All and Quit: stops every Process of every Project, then asks the Helper program to exit.
    public func stopAllAndQuit(origin: Origin) async {
        await stopEverything(origin: origin)
        let quitInput = quitInput
        // A moment for the answer to reach the client before the Helper exits.
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            quitInput.yield()
        }
    }

    // MARK: - Configuration

    /// Adds the folder as a Project. A folder that already is a Project gives that Project.
    @discardableResult
    public func addProject(folder: String, name: String? = nil) throws -> ProjectSnapshot {
        let path = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL.path
        if let existing = configuration.projects.first(where: { $0.folder == path }) {
            return projectSnapshot(existing)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HelperError(code: HelperError.invalid, message: "There is no folder at \(path).")
        }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let project = Project(
            name: trimmed.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : trimmed, folder: path)
        var changed = configuration
        changed.projects.append(project)
        try commit(changed)
        return projectSnapshot(project)
    }

    @discardableResult
    public func renameProject(_ projectID: UUID, name: String) throws -> ProjectSnapshot {
        let index = try projectIndex(projectID)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HelperError(code: HelperError.invalid, message: "A Project needs a name.")
        }
        var changed = configuration
        changed.projects[index].name = trimmed
        try commit(changed)
        // The rename may have moved the Project, so its old index can hold another one.
        return projectSnapshot(try findProject(projectID))
    }

    /// Stops the Project's Processes, then removes it.
    public func removeProject(_ projectID: UUID, origin: Origin) async throws {
        let project = try findProject(projectID)
        let ids = project.commands.map(\.id)
        await haltAll(ids.filter { runtimes[$0]?.process != nil }, origin: origin, cause: .stopped, action: nil)
        var changed = configuration
        changed.projects.removeAll { $0.id == projectID }
        try commit(changed)
        ids.forEach(forget)
    }

    @discardableResult
    public func addCommand(
        to projectID: UUID, settings: CommandSettings, madeByDiscovery: Bool = false
    ) throws -> CommandSnapshot {
        let index = try projectIndex(projectID)
        let command = Command(
            settings: try validated(settings, in: configuration.projects[index], except: nil),
            madeByDiscovery: madeByDiscovery)
        var changed = configuration
        changed.projects[index].commands.append(command)
        try commit(changed)
        return try commandSnapshot(command.id)
    }

    /// Saves the edit at once. A Running Command keeps running its old settings and is marked
    /// "restart to apply" until its next start.
    @discardableResult
    public func updateCommand(_ commandID: UUID, settings: CommandSettings) throws -> CommandSnapshot {
        let (projectIndex, commandIndex) = try indices(commandID)
        let old = configuration.projects[projectIndex].commands[commandIndex]
        let new = try validated(settings, in: configuration.projects[projectIndex], except: commandID)
        guard new != old.settings else { return try commandSnapshot(commandID) }

        var changed = configuration
        changed.projects[projectIndex].commands[commandIndex].settings = new
        changed.projects[projectIndex].commands[commandIndex].madeByDiscovery = false
        let needsRestart = runtimes[commandID]?.process != nil && new.runsDifferently(from: old.settings)
        if needsRestart {
            // Set before the configuration event goes out, so the event already carries the mark.
            let before = runtimes[commandID]?.restartToApply ?? false
            runtimes[commandID]?.restartToApply = true
            do {
                try commit(changed)
            } catch {
                runtimes[commandID]?.restartToApply = before
                throw error
            }
        } else {
            try commit(changed)
        }
        return try commandSnapshot(commandID)
    }

    /// Stops the Command if it is Running, then deletes it.
    public func deleteCommand(_ commandID: UUID, origin: Origin) async throws {
        _ = try find(commandID)
        runtimes[commandID]?.startAfterStop = false
        await halt(commandID, origin: origin, cause: .stopped, action: nil)
        guard let (projectIndex, commandIndex) = try? indices(commandID) else { return }
        var changed = configuration
        changed.projects[projectIndex].commands.remove(at: commandIndex)
        try commit(changed)
        forget(commandID)
    }

    // MARK: - Discovery

    /// Reads the Project's folder and says what a checklist should offer to add and to remove.
    /// It changes nothing: the user's confirmed choices come back as `addCommand` and `deleteCommand`.
    public func discover(_ projectID: UUID) async throws -> DiscoveryPlan {
        let folder = URL(fileURLWithPath: try findProject(projectID).folder, isDirectory: true)
        let proposals = await Discovery.propose(folder: folder, devList: devList)
        // The Project may have changed while `dev:list` ran.
        return DiscoveryPlan.make(project: try findProject(projectID), proposals: proposals)
    }

    // MARK: - Settings

    public func settings() -> HelperSettings {
        configuration.settings
    }

    /// Saves the Settings and tells every client. Launch at login is applied first: when that fails,
    /// nothing is saved. It only registers the Helper; it never starts or stops a Process.
    @discardableResult
    public func updateSettings(_ settings: HelperSettings) throws -> HelperSettings {
        let old = configuration.settings
        guard settings != old else { return old }
        if settings.launchAtLogin != old.launchAtLogin, let loginItem {
            do {
                try loginItem.apply(enabled: settings.launchAtLogin)
            } catch {
                throw HelperError(
                    code: HelperError.saveFailed,
                    message: "Launch at login could not be changed: \((error as? HelperError)?.message ?? error.localizedDescription)")
            }
        }
        var changed = configuration
        changed.settings = settings
        do {
            try store.save(changed)
        } catch {
            if settings.launchAtLogin != old.launchAtLogin {
                try? loginItem?.apply(enabled: old.launchAtLogin)
            }
            throw HelperError(
                code: HelperError.saveFailed,
                message: "The configuration could not be saved: \(error.localizedDescription)")
        }
        configuration = changed
        emit(.settings(settings))
        return settings
    }

    // MARK: - Starting and stopping

    @discardableResult
    private func launch(
        _ commandID: UUID, origin: Origin, cause: StatusCause, action: ProjectAction?
    ) throws -> CommandSnapshot {
        let (project, command) = try find(commandID)
        var runtime = runtimes[commandID] ?? Runtime()
        guard runtime.process == nil else { return try commandSnapshot(commandID) }

        let time = now()
        if !runtime.buffer.isEmpty {
            let text = cause == .restarted ? OutputBanner.restarted(at: time) : OutputBanner.started(at: time)
            runtimes[commandID] = runtime
            write(banner: text, to: commandID)
            runtime = runtimes[commandID] ?? runtime
        }

        var processEnvironment = environment
        processEnvironment["TERM"] = "xterm-256color"
        for variable in command.settings.environment where !variable.name.isEmpty {
            processEnvironment[variable.name] = variable.value
        }
        var folder = URL(fileURLWithPath: project.folder, isDirectory: true)
        if !command.settings.subfolder.isEmpty {
            folder.appendPathComponent(command.settings.subfolder, isDirectory: true)
        }
        let spec = ProcessSpec(
            executable: shell.executable,
            arguments: shell.arguments + [command.settings.effectiveCommandLine],
            environment: processEnvironment,
            workingDirectory: folder.path,
            size: runtime.size)

        runtime.restartToApply = false
        runtime.pendingAutoRestart = nil
        runtime.pendingFileChange = nil
        if !origin.isInternal { runtime.crashTimes = [] }
        runtime.stopRequested = false
        runtime.startAfterStop = false
        runtime.lastExit = nil
        do {
            let process = try PTYProcess.spawn(spec)
            runCounter += 1
            let run = runCounter
            runtime.process = process
            runtime.run = run
            runtime.status = .running
            runtime.startedAt = time
            runtimes[commandID] = runtime
            emitStatus(commandID, cause: cause, origin: origin, action: action)
            refreshWatches()
            Task { [weak self] in
                for await event in process.events {
                    await self?.handle(event, of: commandID, run: run)
                }
            }
        } catch {
            runtime.status = .crashed
            runtimes[commandID] = runtime
            write(banner: OutputBanner.couldNotStart("\(error)"), to: commandID)
            emitStatus(commandID, cause: .crashed, origin: origin, action: action)
            crashed(commandID, exit: nil)
        }
        return try commandSnapshot(commandID)
    }

    private func handle(_ event: ProcessEvent, of commandID: UUID, run: Int) {
        guard var runtime = runtimes[commandID], runtime.run == run else { return }
        switch event {
        case .output(let data):
            append(data, to: commandID)
        case .ended(let exit, _):
            let requested = runtime.stopRequested
            runtime.process = nil
            runtime.lastExit = exit
            runtime.stopRequested = false
            runtime.status = requested ? .stopped : exit.statusWhenEndedByItself
            let waiters = runtime.stopWaiters
            runtime.stopWaiters = []
            runtimes[commandID] = runtime
            write(banner: requested ? OutputBanner.stopped : OutputBanner.ended(exit), to: commandID)
            refreshWatches()
            if requested {
                emitStatus(
                    commandID, cause: runtime.stopCause, origin: runtime.stopOrigin, action: runtime.stopAction)
            } else {
                emitStatus(
                    commandID, cause: runtime.status == .finished ? .finished : .crashed, origin: nil, action: nil)
                if runtime.status == .finished {
                    notify(commandID) { .finished($0) }
                } else {
                    crashed(commandID, exit: exit)
                }
            }
            waiters.forEach { $0.resume() }
        }
    }

    /// Stops the Command's Process and waits until it is gone. Without a Process, a Crashed or Finished
    /// Command becomes Stopped.
    private func halt(_ commandID: UUID, origin: Origin, cause: StatusCause, action: ProjectAction?) async {
        guard var runtime = runtimes[commandID] else { return }
        if cause == .stopped { runtime.pendingAutoRestart = nil }
        if let process = runtime.process {
            if cause == .stopped { runtime.startAfterStop = false }
            if !runtime.stopRequested {
                runtime.stopRequested = true
                runtime.stopOrigin = origin
                runtime.stopCause = cause
                runtime.stopAction = action
                process.terminate(escalateAfter: timings.killEscalation)
            } else if cause == .stopped {
                // A plain stop that arrives during a restart's stop takes over.
                runtime.stopOrigin = origin
                runtime.stopCause = cause
                runtime.stopAction = action
            }
            runtimes[commandID] = runtime
            await withCheckedContinuation { continuation in
                runtimes[commandID]?.stopWaiters.append(continuation)
            }
        } else if cause == .stopped, runtime.status == .crashed || runtime.status == .finished {
            runtime.status = .stopped
            runtimes[commandID] = runtime
            emitStatus(commandID, cause: .cleared, origin: origin, action: action)
        } else {
            runtimes[commandID] = runtime
        }
    }

    private func haltAll(_ ids: [UUID], origin: Origin, cause: StatusCause, action: ProjectAction?) async {
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { await self.halt(id, origin: origin, cause: cause, action: action) }
            }
        }
    }

    private func forget(_ commandID: UUID) {
        runtimes[commandID] = nil
        refreshWatches()
        for key in subscribers.keys {
            subscribers[key]?.outputOf.remove(commandID)
        }
    }

    // MARK: - Auto-restart

    /// A crash notifies. With auto-restart on, it also restarts the Command after the delay, unless
    /// this is the fifth crash within the crash window: then auto-restart pauses until a manual start.
    private func crashed(_ commandID: UUID, exit: ProcessExit?) {
        guard let (_, command) = try? find(commandID), command.settings.autoRestart else {
            notify(commandID) { .crashed($0, exit: exit, autoRestarting: false) }
            return
        }
        let time = now()
        let window = timings.crashWindow.timeInterval
        var times = (runtimes[commandID]?.crashTimes ?? []).filter { time.timeIntervalSince($0) < window }
        times.append(time)
        runtimes[commandID]?.crashTimes = times
        guard times.count < Self.crashesBeforePause else {
            notify(commandID) { .crashed($0, exit: exit, autoRestarting: false) }
            notify(commandID) { .autoRestartPaused($0, crashes: times.count) }
            return
        }
        notify(commandID) { .crashed($0, exit: exit, autoRestarting: true) }

        waitCounter += 1
        let wait = waitCounter
        runtimes[commandID]?.pendingAutoRestart = wait
        let delay = timings.autoRestartDelay
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            await self?.autoRestart(commandID, wait: wait)
        }
    }

    /// Only a Command still Crashed, with its switch still on, and no start or stop since the crash.
    private func autoRestart(_ commandID: UUID, wait: Int) {
        guard let runtime = runtimes[commandID], runtime.pendingAutoRestart == wait,
            runtime.process == nil, runtime.status == .crashed,
            (try? find(commandID))?.command.settings.autoRestart == true
        else { return }
        runtimes[commandID]?.pendingAutoRestart = nil
        // The crash notification already said it is auto-restarting: no Restarted notification.
        _ = try? launch(commandID, origin: .autoRestart, cause: .restarted, action: nil)
    }

    // MARK: - Restart when files change

    /// Files changed at these absolute paths. Every Running Command with a matching glob restarts once
    /// the changes have been quiet for the settle time. A Command that is not Running is left alone.
    public func filesChanged(_ paths: [String]) {
        for project in configuration.projects {
            let folders = Set([project.folder, Self.realPath(project.folder)])
            let relative = paths.compactMap { path in
                folders.lazy.compactMap { Glob.relativePath(path, inFolder: $0) }.first
            }
            guard !relative.isEmpty else { continue }
            for command in project.commands
            where isRunning(command.id) && !command.settings.restartWhenFilesChange.isEmpty {
                let globs = command.settings.restartWhenFilesChange.map(Glob.init)
                if relative.contains(where: { path in globs.contains { $0.matches(path) } }) {
                    scheduleFileChangeRestart(command.id)
                }
            }
        }
    }

    private func scheduleFileChangeRestart(_ commandID: UUID) {
        waitCounter += 1
        let wait = waitCounter
        runtimes[commandID]?.pendingFileChange = wait
        let settle = timings.fileChangeSettle
        Task { [weak self] in
            try? await Task.sleep(for: settle)
            await self?.fileChangeSettled(commandID, wait: wait)
        }
    }

    private func fileChangeSettled(_ commandID: UUID, wait: Int) async {
        guard runtimes[commandID]?.pendingFileChange == wait, isRunning(commandID) else { return }
        runtimes[commandID]?.pendingFileChange = nil
        _ = try? await restart(commandID, origin: .fileChange)
    }

    /// Watches each Project folder while one of its Commands is Running with globs set.
    private func refreshWatches() {
        var wanted: [UUID: String] = [:]
        for project in configuration.projects
        where project.commands.contains(where: { isRunning($0.id) && !$0.settings.restartWhenFilesChange.isEmpty }) {
            wanted[project.id] = project.folder
        }
        for (id, watch) in watches where wanted[id] != watch.folder {
            watch.watch.stop()
            watches[id] = nil
        }
        for (id, folder) in wanted where watches[id] == nil {
            let watch = folderWatcher(folder) { [weak self] paths in
                Task { await self?.filesChanged(paths) }
            }
            if let watch { watches[id] = Watch(folder: folder, watch: watch) }
        }
    }

    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: - Output

    private func append(_ data: Data, to commandID: UUID) {
        runtimes[commandID]?.buffer.append(data)
        let event = HelperEvent.output(OutputChunk(commandID: commandID, data: data))
        for subscriber in subscribers.values where subscriber.outputOf.contains(commandID) {
            subscriber.continuation.yield(event)
        }
    }

    private func write(banner text: String, to commandID: UUID) {
        let midLine = runtimes[commandID]?.buffer.endsMidLine ?? false
        append(OutputBanner.line(text, afterPartialLine: midLine), to: commandID)
    }

    // MARK: - Notifications

    private enum Change {
        case started, restarted, stopped
    }

    private func isRunning(_ commandID: UUID) -> Bool {
        runtimes[commandID]?.process != nil
    }

    /// One notification for the Commands the change reached. Only those that ended up in the wanted
    /// status count: a start that could not launch already sent its crash.
    private func notifyChange(_ change: Change, _ ids: [UUID], origin: Origin, action: ProjectAction?) {
        let wanted: CommandStatus = change == .stopped ? .stopped : .running
        let reached = ids.filter { runtimes[$0]?.status == wanted }
        guard let first = reached.first, let (project, _) = try? find(first) else { return }
        let targets = reached.compactMap { id in
            (try? find(id)).map { NotificationTrigger.Target(id: id, name: $0.command.settings.name) }
        }
        let trigger: NotificationTrigger =
            switch change {
            case .started: .started(targets, origin: origin, action: action)
            case .restarted: .restarted(targets, origin: origin, action: action)
            case .stopped: .stopped(targets, origin: origin, action: action)
            }
        post(trigger, in: project)
    }

    private func notify(_ commandID: UUID, _ trigger: (NotificationTrigger.Target) -> NotificationTrigger) {
        guard let (project, command) = try? find(commandID) else { return }
        post(trigger(NotificationTrigger.Target(id: commandID, name: command.settings.name)), in: project)
    }

    private func post(_ trigger: NotificationTrigger, in project: Project) {
        guard let poster,
            let notification = NotificationRule.notification(
                for: trigger, in: NotificationRule.Subject(projectID: project.id, projectName: project.name),
                settings: configuration.settings.notifications)
        else { return }
        poster.post(notification)
    }

    // MARK: - Lookups and snapshots

    private func emit(_ event: HelperEvent) {
        for subscriber in subscribers.values {
            subscriber.continuation.yield(event)
        }
    }

    private func emitStatus(_ commandID: UUID, cause: StatusCause, origin: Origin?, action: ProjectAction?) {
        guard let (project, command) = try? find(commandID) else { return }
        emit(
            .status(
                StatusChange(
                    command: commandSnapshot(command, in: project),
                    projectStatus: status(of: project),
                    cause: cause,
                    origin: origin,
                    projectAction: action)))
    }

    /// Saves the change and tells every client. Projects and Commands are put in order of name
    /// first, so what is saved and what is served never differ in order.
    private func commit(_ changed: Configuration) throws {
        let changed = changed.sortedByName()
        do {
            try store.save(changed)
        } catch {
            throw HelperError(
                code: HelperError.saveFailed,
                message: "The configuration could not be saved: \(error.localizedDescription)")
        }
        configuration = changed
        emit(.configuration(snapshot()))
        refreshWatches()
    }

    private func validated(_ settings: CommandSettings, in project: Project, except: UUID?) throws -> CommandSettings {
        var settings = settings
        settings.name = settings.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !settings.name.isEmpty else {
            throw HelperError(code: HelperError.invalid, message: "A Command needs a name.")
        }
        guard !settings.commandLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HelperError(code: HelperError.invalid, message: "A Command needs a command line.")
        }
        settings.containerName = settings.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.runInContainer && settings.containerName.isEmpty {
            throw HelperError(code: HelperError.invalid, message: "A Command that runs in a container needs a container name.")
        }
        if let taken = project.commands.first(where: {
            $0.id != except && $0.settings.name.caseInsensitiveCompare(settings.name) == .orderedSame
        }) {
            throw HelperError(
                code: HelperError.invalid,
                message: "Project '\(project.name)' already has a Command named '\(taken.settings.name)'.")
        }
        return settings
    }

    private func findProject(_ projectID: UUID) throws -> Project {
        configuration.projects[try projectIndex(projectID)]
    }

    private func projectIndex(_ projectID: UUID) throws -> Int {
        guard let index = configuration.projects.firstIndex(where: { $0.id == projectID }) else {
            throw HelperError(code: HelperError.unknownProject, message: "There is no Project with that ID.")
        }
        return index
    }

    private func indices(_ commandID: UUID) throws -> (project: Int, command: Int) {
        for (projectIndex, project) in configuration.projects.enumerated() {
            if let commandIndex = project.commands.firstIndex(where: { $0.id == commandID }) {
                return (projectIndex, commandIndex)
            }
        }
        throw HelperError(code: HelperError.unknownCommand, message: "There is no Command with that ID.")
    }

    private func find(_ commandID: UUID) throws -> (project: Project, command: Command) {
        let (projectIndex, commandIndex) = try indices(commandID)
        let project = configuration.projects[projectIndex]
        return (project, project.commands[commandIndex])
    }

    private func commandSnapshot(_ commandID: UUID) throws -> CommandSnapshot {
        let (project, command) = try find(commandID)
        return commandSnapshot(command, in: project)
    }

    private func commandSnapshot(_ command: Command, in project: Project) -> CommandSnapshot {
        let runtime = runtimes[command.id] ?? Runtime()
        return CommandSnapshot(
            id: command.id,
            projectID: project.id,
            settings: command.settings,
            madeByDiscovery: command.madeByDiscovery,
            status: runtime.status,
            lastExit: runtime.lastExit,
            restartToApply: runtime.restartToApply,
            startedAt: runtime.startedAt,
            processID: runtime.process?.pid)
    }

    private func status(of project: Project) -> ProjectStatus {
        ProjectStatus.evaluate(
            project.commands.map {
                (status: runtimes[$0.id]?.status ?? .stopped, includedInStartAll: $0.settings.includedInStartAll)
            })
    }

    private func projectSnapshot(_ project: Project) -> ProjectSnapshot {
        ProjectSnapshot(
            id: project.id,
            name: project.name,
            folder: project.folder,
            status: status(of: project),
            commands: project.commands.map { commandSnapshot($0, in: project) })
    }
}
