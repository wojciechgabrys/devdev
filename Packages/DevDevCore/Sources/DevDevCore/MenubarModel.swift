import Foundation
import Observation

/// The model behind the menubar icon and panel. It lives inside the Helper and talks to the engine
/// directly. Every click it forwards carries the origin `user`.
@MainActor @Observable
public final class MenubarModel {
    public private(set) var panel = MenubarPanel(snapshot: HelperSnapshot(projects: []))
    /// False when Settings turned the menubar icon off. The Helper keeps running.
    public private(set) var showsIcon = HelperSettings().showMenubarIcon

    private let engine: HelperEngine
    private var snapshot = HelperSnapshot(projects: [])
    private var subscription: UUID?
    private var listening: Task<Void, Never>?

    public init(engine: HelperEngine) {
        self.engine = engine
    }

    /// Loads the Helper's state and follows every change.
    public func start() async {
        guard subscription == nil else { return }
        // Subscribe first, so no change made in between is missed.
        let (id, events) = await engine.subscribe()
        subscription = id
        snapshot = await engine.snapshot()
        showsIcon = await engine.settings().showMenubarIcon
        panel = MenubarPanel(snapshot: snapshot)
        listening = Task { [weak self] in
            for await event in events {
                self?.receive(event)
            }
        }
    }

    public func stopListening() async {
        listening?.cancel()
        listening = nil
        if let subscription { await engine.unsubscribe(subscription) }
        subscription = nil
    }

    private func receive(_ event: HelperEvent) {
        switch event {
        case .configuration(let new):
            snapshot = new
        case .status(let change):
            snapshot.apply(change)
        case .settings(let settings):
            showsIcon = settings.showMenubarIcon
            return
        case .output, .outputReplay:
            return
        }
        panel = MenubarPanel(snapshot: snapshot)
    }

    // MARK: - Clicks

    public func start(_ commandID: UUID) async { _ = try? await engine.start(commandID, origin: .user) }
    public func stop(_ commandID: UUID) async { _ = try? await engine.stop(commandID, origin: .user) }
    public func restart(_ commandID: UUID) async { _ = try? await engine.restart(commandID, origin: .user) }
    public func startAll(_ projectID: UUID) async { _ = try? await engine.startAll(projectID, origin: .user) }
    public func stopAll(_ projectID: UUID) async { _ = try? await engine.stopAll(projectID, origin: .user) }
    public func restartAll(_ projectID: UUID) async { _ = try? await engine.restartAll(projectID, origin: .user) }

    /// Stops every Process of every Project, then the Helper exits.
    public func stopAllAndQuit() async { await engine.stopAllAndQuit(origin: .user) }
}

extension HelperSnapshot {
    /// Puts a pushed status change in place: the Command and its Project's status.
    mutating func apply(_ change: StatusChange) {
        guard
            let projectIndex = projects.firstIndex(where: { $0.id == change.command.projectID }),
            let commandIndex = projects[projectIndex].commands.firstIndex(where: { $0.id == change.command.id })
        else { return }
        projects[projectIndex].commands[commandIndex] = change.command
        projects[projectIndex].status = change.projectStatus
    }
}
