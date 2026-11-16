import Foundation
import Testing

@testable import DevDevCore

/// The `dev:list` parser, fed the unedited output the spike saved (see `docs/spike-results.md`).
@Suite struct DevListParserTests {
    private func run(_ fixture: String, exitCode: Int32 = 0) throws -> DevListRun {
        .finished(exitCode: exitCode, stdout: try DevListFixture.data(fixture))
    }

    @Test func theDefaultJSONGivesTheFourDefaultProcessesInOrder() throws {
        #expect(
            DevList.processes(from: try run("default.json")) == [
                DevListProcess(name: "server", command: "php artisan serve"),
                DevListProcess(name: "queue", command: "php artisan queue:listen --tries=1 --timeout=0"),
                DevListProcess(name: "logs", command: "php artisan pail --timeout=0"),
                DevListProcess(name: "vite", command: "npm run dev"),
            ])
    }

    @Test func theNoInteractionOutputParsesTheSameAsJSON() throws {
        #expect(
            DevList.processes(from: try run("default-no-interaction.json"))
                == DevList.processes(from: try run("default.json")))
    }

    @Test func processesTheAppRegistersAreListedWithEscapedSlashesUndone() throws {
        let listed = try #require(DevList.processes(from: try run("custom-registered.json")))
        #expect(listed.map(\.name) == [
            "stripe", "horizon", "scheduler", "watch:docs", "types", "server", "queue", "logs", "vite",
        ])
        #expect(listed[0].command == "stripe listen --forward-to localhost:8000/stripe/webhook")
        #expect(listed[4].command == "npx tsc --watch")
    }

    @Test func thePnpmVariantKeepsThePackageManagersCommandLines() throws {
        let listed = try #require(DevList.processes(from: try run("custom-registered-pnpm.json")))
        #expect(listed.first { $0.name == "vite" }?.command == "pnpm run dev")
        #expect(listed.first { $0.name == "types" }?.command == "pnpm dlx tsc --watch")
    }

    @Test func withoutDefaultCommandsOnlyTheRegisteredProcessesAreListed() throws {
        let listed = try #require(DevList.processes(from: try run("custom-without-defaults.json")))
        #expect(listed.map(\.name) == ["stripe", "horizon", "scheduler", "watch:docs"])
    }

    @Test func anEmptyListIsAnAnswerNotAFailure() throws {
        #expect(DevList.processes(from: try run("empty.json")) == [])
    }

    @Test func aNonZeroExitMeansFallBackEvenWhenJSONWasPrinted() throws {
        #expect(DevList.processes(from: try run("filter-no-match.json", exitCode: 1)) == nil)
    }

    @Test func anUndefinedCommandMeansFallBack() throws {
        #expect(DevList.processes(from: try run("command-not-defined.stdout.txt", exitCode: 1)) == nil)
        // Even if some shell reported success, the error text is not a list.
        #expect(DevList.processes(from: try run("command-not-defined.stdout.txt", exitCode: 0)) == nil)
    }

    @Test func theTextTableIsNeverParsed() throws {
        for fixture in ["default.txt", "default-ansi.txt", "default-agent-env.txt", "custom-registered.txt", "empty.txt"] {
            #expect(DevList.processes(from: try run(fixture)) == nil, "\(fixture) was parsed")
        }
    }

    @Test func linesALoginShellPrintsBeforeTheListAreSkipped() throws {
        var stdout = Data("Welcome back!\nnvm: using node 24\n".utf8)
        stdout.append(try DevListFixture.data("default.json"))
        #expect(DevList.processes(from: .finished(exitCode: 0, stdout: stdout))?.count == 4)
    }

    @Test func aTimeoutOrAFailedStartMeansFallBack() {
        #expect(DevList.processes(from: .timedOut) == nil)
        #expect(DevList.processes(from: .failedToStart("no shell")) == nil)
    }

    @Test func theCombinedDevProcessIsNeverListed() {
        let stdout = Data(#"[{"command":"php artisan dev","name":"dev"},{"command":"php artisan serve","name":"server"}]"#.utf8)
        #expect(
            DevList.processes(from: .finished(exitCode: 0, stdout: stdout)) == [
                DevListProcess(name: "server", command: "php artisan serve")
            ])
    }
}
