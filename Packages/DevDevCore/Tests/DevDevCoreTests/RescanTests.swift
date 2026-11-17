import Foundation
import Testing

@testable import DevDevCore

/// Rescan: what to offer for adding and for removal (`docs/spec.md` section 6).
@Suite struct RescanTests {
    private func command(_ name: String, _ line: String, discovery: Bool) -> Command {
        Command(settings: CommandSettings(name: name, commandLine: line), madeByDiscovery: discovery)
    }

    private func proposal(_ name: String, _ line: String) -> DiscoveryProposal {
        DiscoveryProposal(settings: CommandSettings(name: name, commandLine: line))
    }

    @Test func rescanOffersMissingProposalsToAddAndOnlyStaleDiscoveryMadeCommandsToRemove() {
        let kept = command("server", "php artisan serve", discovery: true)
        let stale = command("queue", "php artisan queue:listen --tries=1 --timeout=0", discovery: true)
        let handWritten = command("stripe", "stripe listen", discovery: false)
        let project = Project(name: "shop", folder: "/tmp/shop", commands: [kept, stale, handWritten])

        let plan = DiscoveryPlan.make(
            project: project,
            proposals: [
                proposal("server", "php artisan serve"),
                proposal("horizon", "php artisan horizon"),
                proposal("vite", "npm run dev"),
            ])

        #expect(plan.projectID == project.id)
        #expect(plan.add.map(\.settings.commandLine) == ["php artisan horizon", "npm run dev"])
        #expect(plan.remove == [DiscoveryRemoval(commandID: stale.id, name: "queue", commandLine: stale.settings.commandLine)])
    }

    @Test func aCommandEditedByHandIsNeverOfferedForRemoval() async throws {
        try await withHarness([]) { h in
            let added = try await h.engine.addCommand(
                to: h.projectID, settings: CommandSettings(name: "queue", commandLine: "php artisan queue:work"),
                madeByDiscovery: true)
            var edited = added.settings
            edited.commandLine = "php artisan queue:work --tries=3"
            _ = try await h.engine.updateCommand(added.id, settings: edited)

            let project = try #require(try h.store.load().projects.first)
            let plan = DiscoveryPlan.make(project: project, proposals: [proposal("server", "php artisan serve")])

            #expect(plan.remove.isEmpty)
            #expect(plan.add.map(\.settings.name) == ["server"])
        }
    }

    @Test func matchingIsOnTheCommandLineNotTheName() {
        let renamedByNothing = command("web", "php artisan  serve", discovery: false)
        let project = Project(name: "shop", folder: "/tmp/shop", commands: [renamedByNothing])

        let plan = DiscoveryPlan.make(project: project, proposals: [proposal("server", "php artisan serve")])

        #expect(plan.add.isEmpty)
        #expect(plan.remove.isEmpty)
    }

    @Test func aProposalWhoseNameIsTakenGetsAFreeName() {
        let project = Project(name: "shop", folder: "/tmp/shop", commands: [command("Server", "valet share", discovery: false)])

        let plan = DiscoveryPlan.make(project: project, proposals: [proposal("server", "php artisan serve")])

        #expect(plan.add.map(\.settings.name) == ["server 2"])
    }

    @Test func theChecklistStartsWithProposalsAsDiscoveryTicksThemAndRemovalsUnticked() {
        let stale = command("worker", "php artisan queue:listen", discovery: true)
        let project = Project(name: "shop", folder: "/tmp/shop", commands: [stale])
        var unchecked = proposal("queue", "php artisan queue:listen --tries=1 --timeout=0")
        unchecked.checked = false
        let plan = DiscoveryPlan.make(project: project, proposals: [proposal("server", "php artisan serve"), unchecked])

        var checklist = DiscoveryChecklist(plan: plan, reason: .rescan)

        #expect(checklist.addChecked == [true, false])
        #expect(checklist.removeChecked == [false])
        #expect(checklist.commandsToAdd.map(\.name) == ["server"])
        #expect(checklist.commandsToRemove.isEmpty)

        checklist.addChecked = [false, true]
        checklist.removeChecked = [true]
        #expect(checklist.commandsToAdd.map(\.name) == ["queue"])
        #expect(checklist.commandsToRemove == [stale.id])
    }

    @Test func withDockerFilesTheChecklistCanPutTheAddedCommandsInAContainer() {
        let project = Project(name: "shop", folder: "/tmp/shop")
        let plan = DiscoveryPlan.make(project: project, proposals: [proposal("server", "php artisan serve")])

        #expect(!DiscoveryChecklist(plan: plan, reason: .projectAdded).asksAboutContainer)
        var checklist = DiscoveryChecklist(plan: plan, reason: .projectAdded, dockerFiles: ["compose.yaml"])
        #expect(checklist.asksAboutContainer)
        #expect(checklist.commandsToAdd.map(\.runInContainer) == [false])

        checklist.runInContainer = true
        #expect(!checklist.canApply)
        checklist.containerName = " laravel "
        #expect(checklist.canApply)
        #expect(checklist.commandsToAdd.map(\.runInContainer) == [true])
        #expect(checklist.commandsToAdd.map(\.containerName) == ["laravel"])
    }

    @Test func dockerFilesAreFoundOnlyInTheProjectFolderItself() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("docker"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(Discovery.dockerFiles(in: folder).isEmpty)

        for file in ["Dockerfile", "docker-compose.yml", "docker/compose.yaml"] {
            try Data().write(to: folder.appendingPathComponent(file))
        }
        #expect(Discovery.dockerFiles(in: folder) == ["docker-compose.yml", "Dockerfile"])
    }

    // MARK: - Through the Helper

    @Test func discoveryRunsThroughTheHelperAndChangesNothingByItself() async throws {
        let runner = try FakeDevListRunner(fixture: "default.json")
        let folder = try projectFixture("laravel-node")
        try await withHarness([], devList: runner) { h in
            let project = try await h.engine.addProject(folder: folder.path)

            let response = await h.engine.respond(to: .discover(projectID: project.id), origin: nil, subscriber: UUID())

            guard case .discovery(let plan) = response else {
                Issue.record("expected a discovery answer, got \(response)")
                return
            }
            #expect(plan.add.map(\.settings.name) == ["server", "queue", "logs", "vite"])
            #expect(plan.remove.isEmpty)
            #expect(try #require(await h.engine.snapshot().project(project.id)).commands.isEmpty)
            #expect(runner.runs.map(\.standardizedFileURL.path) == [folder.standardizedFileURL.path])
        }
    }

    @Test func commandsAddedFromTheChecklistAreDiscoveryMadeAndARescanOffersTheStaleOneForRemoval() async throws {
        let folder = try projectFixture("laravel-dev-list")
        try await withHarness([], devList: try FakeDevListRunner(fixture: "default.json")) { h in
            let project = try await h.engine.addProject(folder: folder.path)
            let first = try await h.engine.discover(project.id)
            for proposal in first.add {
                _ = try await h.engine.addCommand(to: project.id, settings: proposal.settings, madeByDiscovery: true)
            }
            _ = try await h.engine.addCommand(
                to: project.id, settings: CommandSettings(name: "stripe", commandLine: "stripe listen"))
            #expect(try await h.engine.discover(project.id).add.isEmpty)
        }
        try await withHarness([], devList: try FakeDevListRunner(fixture: "empty.json")) { h in
            let project = try await h.engine.addProject(folder: folder.path)
            let server = try await h.engine.addCommand(
                to: project.id, settings: CommandSettings(name: "server", commandLine: "php artisan serve"),
                madeByDiscovery: true)
            _ = try await h.engine.addCommand(
                to: project.id, settings: CommandSettings(name: "stripe", commandLine: "stripe listen"))

            let plan = try await h.engine.discover(project.id)

            #expect(plan.add.isEmpty)
            #expect(plan.remove.map(\.commandID) == [server.id])
        }
    }
}
