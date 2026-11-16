import Foundation

/// The four kinds of notification, each with its own switch in Settings (`docs/spec.md` section 9).
public enum NotificationKind: String, Codable, Sendable, CaseIterable {
    case crashed
    case started
    case restarted
    /// Stopped, or Finished.
    case stoppedOrFinished
}

/// One switch per notification kind. All on by default.
public struct NotificationSettings: Codable, Sendable, Equatable {
    public var crashed: Bool
    public var started: Bool
    public var restarted: Bool
    public var stoppedOrFinished: Bool

    public init(crashed: Bool = true, started: Bool = true, restarted: Bool = true, stoppedOrFinished: Bool = true) {
        self.crashed = crashed
        self.started = started
        self.restarted = restarted
        self.stoppedOrFinished = stoppedOrFinished
    }

    public subscript(kind: NotificationKind) -> Bool {
        get {
            switch kind {
            case .crashed: crashed
            case .started: started
            case .restarted: restarted
            case .stoppedOrFinished: stoppedOrFinished
            }
        }
        set {
            switch kind {
            case .crashed: crashed = newValue
            case .started: started = newValue
            case .restarted: restarted = newValue
            case .stoppedOrFinished: stoppedOrFinished = newValue
            }
        }
    }

    // A switch missing from the file keeps its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        crashed = try container.decodeIfPresent(Bool.self, forKey: .crashed) ?? true
        started = try container.decodeIfPresent(Bool.self, forKey: .started) ?? true
        restarted = try container.decodeIfPresent(Bool.self, forKey: .restarted) ?? true
        stoppedOrFinished = try container.decodeIfPresent(Bool.self, forKey: .stoppedOrFinished) ?? true
    }
}

/// A notification to post. Clicking it opens the App on `commandID`'s output.
public struct SystemNotification: Sendable, Equatable {
    public var kind: NotificationKind
    /// The Project's name.
    public var title: String
    public var body: String
    public var projectID: UUID
    public var commandID: UUID

    public init(kind: NotificationKind, title: String, body: String, projectID: UUID, commandID: UUID) {
        self.kind = kind
        self.title = title
        self.body = body
        self.projectID = projectID
        self.commandID = commandID
    }
}

/// Posts system notifications. The Helper posts them with the notification centre; tests record them.
public protocol NotificationPoster: Sendable {
    func post(_ notification: SystemNotification)
}

/// What happened, as far as notifications care. A whole-Project action is one trigger for all its Commands.
public enum NotificationTrigger: Sendable, Equatable {
    public struct Target: Sendable, Equatable {
        public var id: UUID
        public var name: String

        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    case started([Target], origin: Origin, action: ProjectAction?)
    case restarted([Target], origin: Origin, action: ProjectAction?)
    /// A requested stop that ended a Process. Stop on a Crashed or Finished Command is not one.
    case stopped([Target], origin: Origin, action: ProjectAction?)
    case finished(Target)
    /// `exit` is nil when the Process could not start at all.
    case crashed(Target, exit: ProcessExit?, autoRestarting: Bool)
}

/// Decides which notification, if any, a trigger sends, and its text in GLOSSARY words.
public enum NotificationRule {
    public struct Subject: Sendable, Equatable {
        public var projectID: UUID
        public var projectName: String

        public init(projectID: UUID, projectName: String) {
            self.projectID = projectID
            self.projectName = projectName
        }
    }

    public static func notification(
        for trigger: NotificationTrigger, in subject: Subject, settings: NotificationSettings
    ) -> SystemNotification? {
        guard let (kind, target, body) = content(of: trigger), settings[kind] else { return nil }
        return SystemNotification(
            kind: kind, title: subject.projectName, body: body, projectID: subject.projectID, commandID: target.id)
    }

    private static func content(of trigger: NotificationTrigger)
        -> (NotificationKind, NotificationTrigger.Target, String)?
    {
        switch trigger {
        case .crashed(let target, let exit, let autoRestarting):
            let reason =
                if let code = exit?.exitCode { "exit \(code)" }
                else if let signal = exit?.signal { "signal \(signal)" }
                else { "could not start" }
            return (.crashed, target, "\(target.name) crashed (\(reason))" + (autoRestarting ? ", auto-restarting" : ""))
        case .finished(let target):
            return (.stoppedOrFinished, target, "\(target.name) finished")
        case .started(let targets, let origin, let action):
            return change(.started, "started", targets, origin, action)
        case .restarted(let targets, let origin, let action):
            return change(.restarted, "restarted", targets, origin, action)
        case .stopped(let targets, let origin, let action):
            return change(.stoppedOrFinished, "stopped", targets, origin, action)
        }
    }

    /// Started, Restarted and Stopped: never for `user`, and never on their own for `autoRestart`,
    /// whose crash notification already says it is auto-restarting.
    private static func change(
        _ kind: NotificationKind, _ verb: String, _ targets: [NotificationTrigger.Target], _ origin: Origin,
        _ action: ProjectAction?
    ) -> (NotificationKind, NotificationTrigger.Target, String)? {
        guard let first = targets.first else { return nil }
        let cause: String
        switch origin {
        case .user, .autoRestart: return nil
        case .agent: cause = " by an agent"
        case .fileChange: cause = ", files changed"
        }
        guard let action else {
            return (kind, first, "\(names(targets)) \(verb)\(cause)")
        }
        return (kind, first, "\(name(of: action))\(cause): \(names(targets)) \(verb)")
    }

    private static func name(of action: ProjectAction) -> String {
        switch action {
        case .startAll: "Start All"
        case .stopAll: "Stop All"
        case .restartAll: "Restart All"
        }
    }

    private static func names(_ targets: [NotificationTrigger.Target]) -> String {
        let names = targets.map(\.name)
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
}
