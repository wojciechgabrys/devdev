import Foundation

/// One Command Discovery proposes. `checked` is how the checklist starts out.
public struct DiscoveryProposal: Codable, Sendable, Equatable {
    public var settings: CommandSettings
    public var checked: Bool

    public init(settings: CommandSettings, checked: Bool = true) {
        self.settings = settings
        self.checked = checked
    }

    init(name: String, commandLine: String, checked: Bool = true) {
        self.init(settings: CommandSettings(name: name, commandLine: commandLine), checked: checked)
    }
}

/// Reads a Project's folder and proposes Commands (`docs/spec.md` section 6). It only proposes:
/// creating or removing a Command is up to the user's checklist.
public enum Discovery {
    public static func propose(folder: URL, devList: any DevListRunner) async -> [DiscoveryProposal] {
        var proposals: [DiscoveryProposal] = []
        if let composer = readJSON(folder.appendingPathComponent("composer.json")),
            requires(composer, "laravel/framework")
        {
            if let listed = DevList.processes(from: await devList.run(in: folder)) {
                proposals = listed.map { DiscoveryProposal(name: $0.name, commandLine: $0.command) }
            } else {
                proposals = fixedLaravelList(composer)
            }
        }
        if let package = readJSON(folder.appendingPathComponent("package.json")),
            let scripts = package["scripts"] as? [String: Any], scripts["dev"] is String
        {
            let line = "\(packageManager(folder: folder, package: package)) run dev"
            if !proposals.contains(where: { sameCommandLine($0.settings.commandLine, line) }) {
                proposals.append(DiscoveryProposal(name: "dev", commandLine: line))
            }
        }
        return uniquelyNamed(proposals, taken: [])
    }

    /// The fallback when `dev:list` is missing or fails.
    static func fixedLaravelList(_ composer: [String: Any]) -> [DiscoveryProposal] {
        let horizon = requires(composer, "laravel/horizon")
        var list = [
            DiscoveryProposal(name: "server", commandLine: "php artisan serve"),
            DiscoveryProposal(name: "queue", commandLine: "php artisan queue:listen --tries=1 --timeout=0", checked: !horizon),
            DiscoveryProposal(name: "schedule", commandLine: "php artisan schedule:work"),
        ]
        if requires(composer, "laravel/pail") {
            list.append(DiscoveryProposal(name: "logs", commandLine: "php artisan pail --timeout=0"))
        }
        if horizon {
            list.append(DiscoveryProposal(name: "horizon", commandLine: "php artisan horizon"))
        }
        if requires(composer, "laravel/reverb") {
            list.append(DiscoveryProposal(name: "reverb", commandLine: "php artisan reverb:start"))
        }
        return list
    }

    /// The `packageManager` field, then the lockfile present, then `npm`.
    static func packageManager(folder: URL, package: [String: Any]) -> String {
        let known = ["npm", "pnpm", "yarn", "bun"]
        if let field = package["packageManager"] as? String,
            let name = field.split(separator: "@").first.map(String.init), known.contains(name)
        {
            return name
        }
        let lockfiles = [
            ("pnpm-lock.yaml", "pnpm"), ("yarn.lock", "yarn"), ("bun.lock", "bun"), ("bun.lockb", "bun"),
            ("package-lock.json", "npm"),
        ]
        for (file, manager) in lockfiles
        where FileManager.default.fileExists(atPath: folder.appendingPathComponent(file).path) {
            return manager
        }
        return "npm"
    }

    /// Command lines match when they differ only in spacing.
    public static func sameCommandLine(_ a: String, _ b: String) -> Bool {
        normalized(a) == normalized(b)
    }

    static func normalized(_ line: String) -> String {
        line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Gives each proposal a name no Command in `taken` and no earlier proposal has, by adding " 2", " 3", …
    static func uniquelyNamed(_ proposals: [DiscoveryProposal], taken: [String]) -> [DiscoveryProposal] {
        var used = Set(taken.map { $0.lowercased() })
        return proposals.map { proposal in
            var renamed = proposal
            let base = proposal.settings.name
            var number = 2
            while used.contains(renamed.settings.name.lowercased()) {
                renamed.settings.name = "\(base) \(number)"
                number += 1
            }
            used.insert(renamed.settings.name.lowercased())
            return renamed
        }
    }

    private static func requires(_ composer: [String: Any], _ package: String) -> Bool {
        ["require", "require-dev"].contains { (composer[$0] as? [String: Any])?[package] != nil }
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// A Command the Project has that came from Discovery and is no longer proposed.
public struct DiscoveryRemoval: Codable, Sendable, Equatable {
    public var commandID: UUID
    public var name: String
    public var commandLine: String

    public init(commandID: UUID, name: String, commandLine: String) {
        self.commandID = commandID
        self.name = name
        self.commandLine = commandLine
    }
}

/// What a Discovery checklist offers for one Project: proposals the Project lacks, and
/// Discovery-made Commands no longer proposed. Matched on the command line.
public struct DiscoveryPlan: Codable, Sendable, Equatable {
    public var projectID: UUID
    public var add: [DiscoveryProposal]
    public var remove: [DiscoveryRemoval]

    public init(projectID: UUID, add: [DiscoveryProposal], remove: [DiscoveryRemoval]) {
        self.projectID = projectID
        self.add = add
        self.remove = remove
    }

    public var isEmpty: Bool { add.isEmpty && remove.isEmpty }

    /// A hand-written or hand-edited Command is never offered for removal.
    public static func make(project: Project, proposals: [DiscoveryProposal]) -> DiscoveryPlan {
        let lines = project.commands.map(\.settings.commandLine)
        let missing = proposals.filter { proposal in
            !lines.contains { Discovery.sameCommandLine($0, proposal.settings.commandLine) }
        }
        let stale = project.commands.filter { command in
            command.madeByDiscovery
                && !proposals.contains { Discovery.sameCommandLine($0.settings.commandLine, command.settings.commandLine) }
        }
        return DiscoveryPlan(
            projectID: project.id,
            add: Discovery.uniquelyNamed(missing, taken: project.commands.map(\.settings.name)),
            remove: stale.map {
                DiscoveryRemoval(commandID: $0.id, name: $0.settings.name, commandLine: $0.settings.commandLine)
            })
    }
}

/// The checklist the user confirms. Proposals start as Discovery ticks them; removals start unticked.
public struct DiscoveryChecklist: Sendable, Equatable, Identifiable {
    public enum Reason: Sendable, Equatable {
        /// Shown right after a Project was added.
        case projectAdded
        /// Shown after the user pressed Rescan.
        case rescan
    }

    public let id = UUID()
    public var plan: DiscoveryPlan
    public var reason: Reason
    /// One per `plan.add`: checked = add.
    public var addChecked: [Bool]
    /// One per `plan.remove`: checked = remove.
    public var removeChecked: [Bool]

    public init(plan: DiscoveryPlan, reason: Reason) {
        self.plan = plan
        self.reason = reason
        addChecked = plan.add.map(\.checked)
        removeChecked = plan.remove.map { _ in false }
    }

    public var commandsToAdd: [CommandSettings] {
        zip(plan.add, addChecked).filter(\.1).map(\.0.settings)
    }

    public var commandsToRemove: [UUID] {
        zip(plan.remove, removeChecked).filter(\.1).map(\.0.commandID)
    }

    public var title: String {
        switch reason {
        case .projectAdded: "Commands found in this Project"
        case .rescan: "Rescan"
        }
    }
}
