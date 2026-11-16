import Foundation
import Testing

@testable import DevDevCore

/// The output a Command keeps across exits and restarts.
@Suite struct OutputTests {
    @Test func anExitAddsAClosingLineWithTheExitCode() async throws {
        try await withHarness("echo first; exit 4") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .crashed)
            #expect(try await h.plainOutput(h.first) == "first\n── exited with code 4 ──\n")
        }
    }

    @Test func aRestartKeepsTheOldOutputAndInsertsABannerLine() async throws {
        try await withHarness("echo run; \(Script.runsForever)") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")
            _ = try await h.engine.restart(h.first, origin: .user)
            try await waitUntil("the second run printed") {
                try await h.plainOutput(h.first).components(separatedBy: "ready").count == 3
            }
            let output = try await h.plainOutput(h.first)
            let pattern = /^run\nready\n── stopped ──\n── restarted \d\d:\d\d:\d\d ──\nrun\nready\n$/
            #expect(output.wholeMatch(of: pattern) != nil, "unexpected output: \(output)")
        }
    }

    @Test func aStartAfterACrashKeepsTheOldOutputAndInsertsABannerLine() async throws {
        try await withHarness("echo boom; exit 1") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .crashed)
            _ = try await h.engine.start(h.first, origin: .user)
            try await waitUntil("the second run ended") {
                try await h.plainOutput(h.first).components(separatedBy: "exited with code 1").count == 3
            }
            let output = try await h.plainOutput(h.first)
            let pattern =
                /^boom\n── exited with code 1 ──\n── started \d\d:\d\d:\d\d ──\nboom\n── exited with code 1 ──\n$/
            #expect(output.wholeMatch(of: pattern) != nil, "unexpected output: \(output)")
        }
    }

    @Test func theFirstStartHasNoBanner() async throws {
        try await withHarness("echo only") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .finished)
            #expect(try await h.plainOutput(h.first) == "only\n── exited with code 0 ──\n")
        }
    }

    @Test func anExitBySignalAddsAClosingLineNamingTheSignal() async throws {
        try await withHarness("kill -KILL $$") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .crashed)
            #expect(try await h.plainOutput(h.first).contains("── ended by signal 9 ──"))
        }
    }

    @Test func rawOutputKeepsEscapeSequencesAndPlainOutputRemovesThem() async throws {
        try await withHarness("printf '\\033[31mred\\033[0m\\n'") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForStatus(h.first, .finished)
            let raw = String(decoding: try await h.engine.output(h.first), as: UTF8.self)
            #expect(raw.contains("\u{1b}[31mred\u{1b}[0m"))
            #expect(try await h.plainOutput(h.first).hasPrefix("red\n"))
            #expect(try await h.engine.plainOutput(h.first, lastLines: 1) == "── exited with code 0 ──")
        }
    }

    @Test func anOutputSubscriberGetsTheStoredOutputFirstAndThenTheNewOutput() async throws {
        try await withHarness("echo old; \(Script.runsForever); ") { h in
            _ = try await h.engine.start(h.first, origin: .user)
            try await h.waitForOutput(h.first, containing: "ready")

            let subscription = await h.engine.subscribe()
            try await h.engine.subscribeOutput(h.first, subscriber: subscription.id)
            _ = try await h.engine.stop(h.first, origin: .user)

            var replay: String?
            var live = ""
            for await event in subscription.events {
                if case .outputReplay(let chunk) = event {
                    #expect(live.isEmpty, "the replay must come before any new output")
                    replay = PlainText.strip(chunk.data)
                } else if case .output(let chunk) = event {
                    live += PlainText.strip(chunk.data)
                    if live.contains("stopped") { break }
                }
            }
            #expect(replay == "old\nready\n")
            #expect(live == "── stopped ──\n")
        }
    }
}
