import Foundation
import Testing

/// The build's own record: git history, `GLOSSARY.md`, `docs/manual-checklist.md` and `docs/final-report.md`.
@Suite struct BuildRecordTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func lines(_ path: String) throws -> [String] {
        try read(path).components(separatedBy: "\n")
    }

    /// The lines of a `## ` section, without its heading, up to the next `## ` heading.
    private func section(_ heading: String, in lines: [String]) throws -> [String] {
        let start = try #require(lines.firstIndex(of: "## \(heading)"), "no section \(heading)")
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("## ") } ?? lines.endIndex
        return Array(lines[(start + 1)..<end])
    }

    /// The cells of a Markdown table row, trimmed, without the outer pipes.
    private func cells(_ row: String) -> [String] {
        row.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The text between backticks in a table cell.
    private func backticked(_ cell: String) -> [String] {
        cell.split(separator: "`", omittingEmptySubsequences: false).enumerated()
            .filter { $0.offset % 2 == 1 }.map { String($0.element) }
    }

    // MARK: - Phases

    /// Phase numbers in `docs/spec.md` section 12, in spec order.
    private func specPhases() throws -> [Int] {
        try lines("docs/spec.md").compactMap { line -> Int? in
            guard line.hasPrefix("**Phase ") else { return nil }
            return Int(line.dropFirst("**Phase ".count).prefix { $0.isNumber })
        }
    }

    /// The final report's Phases table: phase number, outcome and commit subjects.
    private func reportPhases() throws -> [(phase: Int, outcome: String, commits: [String])] {
        try section("Phases", in: lines("docs/final-report.md")).compactMap { row in
            let c = cells(row)
            guard c.count == 3, let n = Int(c[0].prefix { $0.isNumber }) else { return nil }
            return (n, c[1], backticked(c[2]))
        }
    }

    // MARK: - Git

    private func git(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Commits on this branch since it left `main`, oldest first.
    private func branchCommits() throws -> [(subject: String, message: String)] {
        var base: String?
        for ref in ["main", "origin/main"] {
            let result = try git(["merge-base", "HEAD", ref])
            if result.status == 0 {
                base = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        let from = try #require(base, "neither main nor origin/main is known to git")
        let log = try git(["log", "--reverse", "--format=%s%x1f%B%x1e", "\(from)..HEAD"])
        #expect(log.status == 0)
        return log.output.components(separatedBy: "\u{1e}").compactMap { record in
            let parts = record.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1f}")
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        }
    }

    /// The subject of the skeleton commit that `docs/spec.md` says existed before the build began.
    /// It sits before the build's own commits, so it is not part of the build's history.
    private let skeletonSubject = "chore: add Xcode project skeleton with a tested core package"

    /// The build's commit subjects, oldest first.
    ///
    /// On the build branch these are the commits since `main`. Once the build was squash-merged,
    /// they live as `* subject` lines, oldest first, in the body of the squash commit on `HEAD`.
    private func buildSubjects(firstPhaseCommit: String) throws -> [String] {
        let branch = try branchCommits().map(\.subject)
        if branch.contains(firstPhaseCommit) { return branch }

        let log = try git(["log", "--first-parent", "--format=%B%x1e", "HEAD"])
        #expect(log.status == 0)
        let squash = log.output.components(separatedBy: "\u{1e}").lazy
            .map { $0.components(separatedBy: "\n").filter { $0.hasPrefix("* ") }.map { String($0.dropFirst(2)) } }
            .first { $0.contains(firstPhaseCommit) }
        let subjects = try #require(squash, "no branch commit or squash commit holds the Phase 1 commit")
        guard let skeleton = subjects.firstIndex(of: skeletonSubject) else { return subjects }
        return Array(subjects[(skeleton + 1)...])
    }

    /// Phases that knowingly have more than one commit, with the reason. Each one is named in the final report.
    /// Phase 2 was stopped at the output view and finished later. Squashing needs a history rewrite,
    /// which only the user may decide.
    private let phasesWithMoreThanOneCommit: [Int: Int] = [2: 2]

    @Test func gitHistoryHasOneCommitPerPhaseInSpecOrderAfterAtMostOneSpikeCommit() throws {
        let phases = try specPhases()
        #expect(phases == Array(1...7))

        let report = try reportPhases()
        #expect(report.map(\.phase) == phases, "the final report lists every phase in spec order")
        for row in report {
            let allowed = phasesWithMoreThanOneCommit[row.phase] ?? 1
            #expect(row.commits.count == allowed, "Phase \(row.phase) has \(row.commits.count) commits")
        }
        for phase in phasesWithMoreThanOneCommit.keys {
            let report = try read("docs/final-report.md")
            #expect(report.contains("Phase \(phase) has two commits"), "the deviation is named in the final report")
        }

        let expected = report.flatMap(\.commits)
        let subjects = try buildSubjects(firstPhaseCommit: expected[0])
        let first = try #require(subjects.firstIndex(of: expected[0]), "no Phase 1 commit")

        let beforePhaseOne = subjects[..<first]
        #expect(beforePhaseOne.count <= 1, "at most one spike commit before Phase 1")
        #expect(beforePhaseOne.allSatisfy { $0.hasPrefix("docs:") }, "the spike commit holds docs and fixtures")

        let phaseCommits = Array(subjects[first...].prefix(expected.count))
        #expect(phaseCommits == expected, "phase commits follow each other in spec order")

        let afterLastPhase = subjects[first...].dropFirst(expected.count)
        #expect(!afterLastPhase.contains { $0.hasPrefix("feat") }, "no feature commit after the last phase")
    }

    @Test func noCommitMessageOnTheBranchCreditsClaude() throws {
        let commits = try branchCommits()
        #expect(!commits.isEmpty)
        for commit in commits {
            for line in commit.message.lowercased().components(separatedBy: "\n") {
                let credits =
                    (line.hasPrefix("co-authored-by:") && (line.contains("claude") || line.contains("anthropic")))
                    || line.contains("noreply@anthropic.com")
                    || (line.contains("generated with") && line.contains("claude"))
                #expect(!credits, "\(commit.subject) credits Claude: \(line)")
            }
        }
    }

    // MARK: - Glossary

    @Test func theGlossaryDefinesCrashedAsANonZeroExitCodeOrASignal() throws {
        let glossary = try lines("GLOSSARY.md")
        let term = try #require(glossary.firstIndex(of: "**Crashed**:"), "GLOSSARY.md has no Crashed entry")
        let definition = glossary[term + 1]
        #expect(definition.contains("ended by itself with a non-zero exit code or a signal"))
    }

    // MARK: - Manual checklist

    /// Each checklist item: its line, its bold title, and the text up to the next item or heading.
    private func checklistItems() throws -> [(line: String, title: String, body: [String])] {
        let all = try lines("docs/manual-checklist.md")
        var items: [(String, String, [String])] = []
        for (index, line) in all.enumerated() where line.hasPrefix("- [") {
            let rest = all[(index + 1)...]
            let end = rest.firstIndex { $0.hasPrefix("- [") || $0.hasPrefix("#") } ?? all.endIndex
            let title = line.components(separatedBy: "**").dropFirst().first ?? ""
            items.append((line, title, Array(all[(index + 1)..<end])))
        }
        return items
    }

    @Test func everyManualCheckIsAnUncheckedItemWithNumberedSteps() throws {
        let items = try checklistItems()
        #expect(items.count >= 40)
        for item in items {
            #expect(item.line.hasPrefix("- [ ] **"), "not an unchecked item: \(item.line)")
            #expect(!item.title.isEmpty, "no title: \(item.line)")
            #expect(item.body.contains { $0.hasPrefix("  1. ") }, "no steps: \(item.title)")
        }
        let text = try read("docs/manual-checklist.md")
        #expect(!text.lowercased().contains("- [x]"))
        for phase in try specPhases() {
            #expect(text.contains("\n## Phase \(phase):"), "no section for Phase \(phase)")
        }
    }

    @Test func theManualChecklistCoversLaravelViteThePanelBannersLoginAndClaudeCode() throws {
        let checklist = try lines("docs/manual-checklist.md")
        let titles = try checklistItems().map(\.title)

        #expect(titles.contains("A real Laravel + Vite project can be added, started, read, restarted and stopped."))

        let panel = try section("Phase 3: menubar panel", in: checklist)
        #expect(panel.contains { $0.hasPrefix("Run every check here with the App closed") })
        #expect(panel.contains { $0.hasPrefix("- [ ] **The panel lists each Project") })

        #expect(titles.contains { $0.contains("Allow leads to banners") })
        #expect(titles.contains { $0.contains("Clicking a banner opens the App") })

        #expect(titles.contains { $0.hasPrefix("Launch at login starts the Helper only") })

        let claude = try #require(titles.first { $0.hasPrefix("Claude Code, set up with the line from Settings") })
        #expect(claude.contains("list a Project, restart its queue Command and read the output"))
    }

    // MARK: - Final report

    @Test func theFinalReportListsEveryManualCheckAsNotVerified() throws {
        let report = try read("docs/final-report.md")
        let reportLines = report.components(separatedBy: "\n")
        let titles = try checklistItems().map(\.title)
        for title in titles {
            #expect(reportLines.contains("- [ ] **Not verified.** \(title)"), "not in the final report: \(title)")
        }
        let listed = reportLines.filter { $0.hasPrefix("- [") }
        #expect(listed.count == titles.count)
        #expect(listed.allSatisfy { $0.hasPrefix("- [ ] **Not verified.** ") })
    }

    @Test func theFinalReportNamesEachSpikeResultFallbackAndStoppedPhase() throws {
        let report = try lines("docs/final-report.md")
        let spikeResults = try lines("docs/spike-results.md")

        // Each of the five spikes, with its result and the same fallback as in docs/spike-results.md.
        let reportSpikes = try section("Spikes", in: report).map(cells).filter { $0.count == 4 && Int($0[0]) != nil }
        let recordedSpikes = spikeResults.map(cells).filter { $0.count == 4 && Int($0[0]) != nil }
        #expect(reportSpikes.map { $0[0] } == ["1", "2", "3", "4", "5"])
        #expect(recordedSpikes.map { $0[0] } == ["1", "2", "3", "4", "5"])
        for (spike, recorded) in zip(reportSpikes, recordedSpikes) {
            #expect(!spike[2].isEmpty, "spike \(spike[0]) has no result")
            let fallback = recorded[3].replacingOccurrences(of: "**", with: "")
            if fallback.hasPrefix("None") {
                #expect(spike[3].hasPrefix("None"), "spike \(spike[0]) took no fallback")
            } else {
                #expect(spike[3] == fallback, "spike \(spike[0]) names its fallback")
            }
        }

        // One bullet per fallback taken.
        let taken = recordedSpikes.filter { !$0[3].replacingOccurrences(of: "**", with: "").hasPrefix("None") }
        let fallbacks = try section("Fallbacks taken", in: report).filter { $0.hasPrefix("- ") }
        #expect(fallbacks.count == taken.count)
        #expect(fallbacks.contains { $0.contains("LaunchAgent") })

        // Each phase that was stopped, even for a while, is named with its reason.
        let stopped = try section("Phases stopped", in: report).joined(separator: "\n")
        #expect(!stopped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        for row in try reportPhases() where row.outcome.lowercased().contains("stop") {
            #expect(stopped.contains("Phase \(row.phase) was stopped"), "Phase \(row.phase) is not named")
        }
    }
}
