import Testing

@testable import DevDevCore

@Suite struct ProjectStatusTests {
    private func status(_ commands: (CommandStatus, Bool)...) -> ProjectStatus {
        ProjectStatus.evaluate(commands.map { (status: $0.0, includedInStartAll: $0.1) })
    }

    @Test func projectIsCrashedWhenAnyCommandIsCrashedEvenIfOthersRun() {
        #expect(status((.crashed, true), (.running, true)) == .crashed)
        #expect(status((.running, true), (.crashed, false)) == .crashed)
        #expect(status((.crashed, true), (.stopped, true), (.finished, true)) == .crashed)
    }

    @Test func projectIsStoppedWhenNoCommandIsRunningAndNoneIsCrashed() {
        #expect(status() == .stopped)
        #expect(status((.stopped, true), (.stopped, false)) == .stopped)
        #expect(status((.finished, true), (.stopped, true)) == .stopped)
    }

    @Test func projectIsRunningWhenEveryCommandIncludedInStartAllIsRunning() {
        #expect(status((.running, true), (.running, true)) == .running)
        #expect(status((.running, true), (.stopped, false)) == .running)
        #expect(status((.running, true), (.finished, false)) == .running)
    }

    @Test func projectIsPartlyRunningOtherwise() {
        #expect(status((.running, true), (.stopped, true)) == .partlyRunning)
        #expect(status((.running, true), (.finished, true)) == .partlyRunning)
        #expect(status((.running, false), (.stopped, true)) == .partlyRunning)
    }

    @Test func crashedIsCheckedBeforeStoppedAndStoppedBeforeRunning() {
        // Crashed wins over "no Command is Running".
        #expect(status((.crashed, true), (.stopped, true)) == .crashed)
        // "No Command is Running" wins over "every included Command is Running" when none is included.
        #expect(status((.stopped, false)) == .stopped)
    }
}
