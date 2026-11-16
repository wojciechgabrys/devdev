import Foundation
import Testing

@testable import DevDevCore

/// A `dev:list` runner that answers with saved output and counts how often it ran.
final class FakeDevListRunner: DevListRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var answer: DevListRun
    private var folders: [URL] = []

    init(_ answer: DevListRun) {
        self.answer = answer
    }

    /// Answers with an unedited spike fixture.
    convenience init(fixture: String, exitCode: Int32 = 0) throws {
        self.init(.finished(exitCode: exitCode, stdout: try DevListFixture.data(fixture)))
    }

    var runs: [URL] { lock.withLock { folders } }

    /// What later runs answer, as if the Project changed.
    func answer(withFixture fixture: String) throws {
        let data = try DevListFixture.data(fixture)
        lock.withLock { answer = .finished(exitCode: 0, stdout: data) }
    }

    func run(in folder: URL) async -> DevListRun {
        lock.withLock { folders.append(folder) }
        return answer
    }
}

/// A Project folder saved under `Fixtures/projects`.
func projectFixture(_ name: String) throws -> URL {
    try #require(
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/projects"),
        "missing project fixture \(name)")
}

/// Name, command line and whether the checklist ticks it, for compact expectations.
private struct Row: Equatable, CustomStringConvertible {
    var name: String
    var line: String
    var checked = true

    var description: String { "\(name): \(line)\(checked ? "" : " (unchecked)")" }
}

private func rows(_ proposals: [DiscoveryProposal]) -> [Row] {
    proposals.map { Row(name: $0.settings.name, line: $0.settings.commandLine, checked: $0.checked) }
}

private let fixedListWithPail = [
    Row(name: "server", line: "php artisan serve"),
    Row(name: "queue", line: "php artisan queue:listen --tries=1 --timeout=0"),
    Row(name: "schedule", line: "php artisan schedule:work"),
    Row(name: "logs", line: "php artisan pail --timeout=0"),
]

@Suite struct DiscoveryTests {
    // MARK: - The five fixture folders of Phase 6

    @Test func laravelWithDevListProposesOneCommandPerListedProcessNamedAfterIt() async throws {
        let folder = try projectFixture("laravel-dev-list")
        let runner = try FakeDevListRunner(fixture: "default.json")

        let proposals = await Discovery.propose(folder: folder, devList: runner)

        #expect(rows(proposals) == [
            Row(name: "server", line: "php artisan serve"),
            Row(name: "queue", line: "php artisan queue:listen --tries=1 --timeout=0"),
            Row(name: "logs", line: "php artisan pail --timeout=0"),
            Row(name: "vite", line: "npm run dev"),
        ])
        #expect(runner.runs == [folder])
        let combined = proposals.filter { DevList.isCombinedDev($0.settings.commandLine) }
        #expect(combined.isEmpty)
    }

    @Test func laravelWithAppRegisteredProcessesProposesThemAll() async throws {
        let proposals = await Discovery.propose(
            folder: try projectFixture("laravel-dev-list"), devList: try FakeDevListRunner(fixture: "custom-registered.json"))

        #expect(proposals.map(\.settings.name) == [
            "stripe", "horizon", "scheduler", "watch:docs", "types", "server", "queue", "logs", "vite",
        ])
        #expect(proposals.filter { !$0.checked }.isEmpty)
    }

    @Test func laravelWithoutDevListFallsBackToTheFixedList() async throws {
        let runner = try FakeDevListRunner(fixture: "command-not-defined.stdout.txt", exitCode: 1)

        let proposals = await Discovery.propose(folder: try projectFixture("laravel-no-dev-list"), devList: runner)

        #expect(rows(proposals) == fixedListWithPail)
        #expect(runner.runs.count == 1)
    }

    @Test func laravelWithHorizonProposesHorizonAndReverbAndLeavesTheQueueUnchecked() async throws {
        let runner = FakeDevListRunner(.failedToStart("php: command not found"))

        let proposals = await Discovery.propose(folder: try projectFixture("laravel-horizon"), devList: runner)

        #expect(rows(proposals) == [
            Row(name: "server", line: "php artisan serve"),
            Row(name: "queue", line: "php artisan queue:listen --tries=1 --timeout=0", checked: false),
            Row(name: "schedule", line: "php artisan schedule:work"),
            Row(name: "horizon", line: "php artisan horizon"),
            Row(name: "reverb", line: "php artisan reverb:start"),
        ])
    }

    @Test func nodeOnlyWithPnpmProposesTheDevScriptWithPnpmAndNeverRunsArtisan() async throws {
        let runner = try FakeDevListRunner(fixture: "default.json")

        let proposals = await Discovery.propose(folder: try projectFixture("node-pnpm"), devList: runner)

        #expect(rows(proposals) == [Row(name: "dev", line: "pnpm run dev")])
        #expect(runner.runs.isEmpty)
    }

    @Test func laravelPlusNodeWithDevListProposesNpmRunDevOnlyOnce() async throws {
        let proposals = await Discovery.propose(
            folder: try projectFixture("laravel-node"), devList: try FakeDevListRunner(fixture: "default.json"))

        #expect(proposals.filter { $0.settings.commandLine == "npm run dev" }.count == 1)
        #expect(proposals.map(\.settings.name) == ["server", "queue", "logs", "vite"])
    }

    @Test func laravelPlusNodeWithoutDevListAddsTheDevScriptToTheFixedList() async throws {
        let proposals = await Discovery.propose(
            folder: try projectFixture("laravel-node"), devList: FakeDevListRunner(.timedOut))

        #expect(rows(proposals) == fixedListWithPail + [Row(name: "dev", line: "npm run dev")])
    }

    @Test func aDevListThatListsNothingProposesNoLaravelCommands() async throws {
        let proposals = await Discovery.propose(
            folder: try projectFixture("laravel-dev-list"), devList: try FakeDevListRunner(fixture: "empty.json"))

        #expect(proposals.isEmpty)
    }

    @Test func aFolderWithNeitherStackProposesNothing() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let runner = try FakeDevListRunner(fixture: "default.json")

        #expect(await Discovery.propose(folder: folder, devList: runner).isEmpty)
        #expect(runner.runs.isEmpty)
    }

    // MARK: - Detection

    @Test func aComposerJSONWithoutLaravelFrameworkIsNotLaravel() async throws {
        try await withFolder([
            "composer.json": #"{"require": {"symfony/console": "^7.0"}, "require-dev": {"laravel/pail": "^1.0"}}"#
        ]) { folder in
            let runner = try FakeDevListRunner(fixture: "default.json")
            #expect(await Discovery.propose(folder: folder, devList: runner).isEmpty)
            #expect(runner.runs.isEmpty)
        }
    }

    @Test func aPackageJSONWithoutADevScriptProposesNothing() async throws {
        try await withFolder(["package.json": #"{"scripts": {"build": "vite build"}}"#]) { folder in
            #expect(await Discovery.propose(folder: folder, devList: FakeDevListRunner(.timedOut)).isEmpty)
        }
    }

    // MARK: - Package manager choice

    @Test func thePackageManagerFieldWinsOverTheLockfile() async throws {
        try await withFolder([
            "package.json": #"{"packageManager": "yarn@4.5.0", "scripts": {"dev": "vite"}}"#,
            "pnpm-lock.yaml": "", "package-lock.json": "{}",
        ]) { folder in
            #expect(await devLine(folder) == "yarn run dev")
        }
    }

    @Test func withoutThePackageManagerFieldTheLockfileDecides() async throws {
        let cases = [
            "pnpm-lock.yaml": "pnpm run dev", "yarn.lock": "yarn run dev", "bun.lock": "bun run dev",
            "bun.lockb": "bun run dev", "package-lock.json": "npm run dev",
        ]
        for (lockfile, line) in cases {
            try await withFolder(["package.json": #"{"scripts": {"dev": "vite"}}"#, lockfile: ""]) { folder in
                #expect(await devLine(folder) == line, "with \(lockfile)")
            }
        }
    }

    @Test func withNeitherTheFieldNorALockfileItIsNpm() async throws {
        try await withFolder(["package.json": #"{"scripts": {"dev": "vite"}}"#]) { folder in
            #expect(await devLine(folder) == "npm run dev")
        }
    }

    @Test func anUnknownPackageManagerFieldFallsThroughToTheLockfile() async throws {
        try await withFolder([
            "package.json": #"{"packageManager": "something@1.0.0", "scripts": {"dev": "vite"}}"#, "yarn.lock": "",
        ]) { folder in
            #expect(await devLine(folder) == "yarn run dev")
        }
    }

    // MARK: - Failure and timeout of dev:list

    @Test func aDevListThatTimesOutFallsBackToTheFixedList() async throws {
        let folder = try projectFixture("laravel-no-dev-list")
        let runner = ShellDevListRunner(shell: .plain, commandLine: "sleep 30", timeout: .milliseconds(300))
        let began = ContinuousClock.now

        let proposals = await Discovery.propose(folder: folder, devList: runner)

        #expect(ContinuousClock.now - began < .seconds(10))
        #expect(rows(proposals) == fixedListWithPail)
    }

    @Test func aDevListThatFailsFallsBackToTheFixedList() async throws {
        let fixture = try DevListFixture.url("command-not-defined.stdout.txt")
        let runner = ShellDevListRunner(shell: .plain, commandLine: "cat '\(fixture.path)'; exit 1")

        let proposals = await Discovery.propose(folder: try projectFixture("laravel-no-dev-list"), devList: runner)

        #expect(rows(proposals) == fixedListWithPail)
    }

    // MARK: - Helpers

    private func devLine(_ folder: URL) async -> String? {
        await Discovery.propose(folder: folder, devList: FakeDevListRunner(.timedOut)).first?.settings.commandLine
    }

    private func withFolder(_ files: [String: String], _ body: (URL) async throws -> Void) async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, text) in files {
            try Data(text.utf8).write(to: folder.appendingPathComponent(name))
        }
        try await body(folder)
    }
}

/// The real runner, with real child processes through `/bin/sh`.
@Suite struct ShellDevListRunnerTests {
    @Test func itGivesTheExitCodeAndStdoutOfTheLineRunInTheFolder() async throws {
        let fixture = try DevListFixture.url("default.json")
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let runner = ShellDevListRunner(shell: .plain, commandLine: "pwd >&2; cat '\(fixture.path)'")

        let run = await runner.run(in: folder)

        #expect(run == .finished(exitCode: 0, stdout: try DevListFixture.data("default.json")))
    }

    @Test func itRunsInTheProjectFolder() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let run = await ShellDevListRunner(shell: .plain, commandLine: "pwd -P; exit 4").run(in: folder)

        let real = try #require(realpath(folder.path, nil).map { path in defer { free(path) }; return String(cString: path) })
        #expect(run == .finished(exitCode: 4, stdout: Data("\(real)\n".utf8)))
    }

    @Test func aRunThatOutlastsTheTimeoutIsKilledWithItsChildren() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pidFile = folder.appendingPathComponent("child.pid")
        let runner = ShellDevListRunner(
            shell: .plain, commandLine: "sleep 60 & echo $! > '\(pidFile.path)'; wait", timeout: .milliseconds(300))

        let run = await runner.run(in: folder)

        #expect(run == .timedOut)
        let child = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        try await waitUntil("the child of the shell is gone") { !processIsAlive(child) }
    }

    @Test func aShellThatCannotStartIsReported() async throws {
        let runner = ShellDevListRunner(shell: Shell(executable: "/no/such/shell", arguments: ["-c"]))
        guard case .failedToStart = await runner.run(in: URL(fileURLWithPath: "/tmp")) else {
            Issue.record("expected failedToStart")
            return
        }
    }
}
