import Foundation
import Testing

/// The Sparkle spike's entry in `docs/spike-results.md`, read as text, and the order the run
/// was done in, read from git. The spike itself was run once by hand; this keeps its record
/// whole and keeps the rule "spike first, stop when it fails" checkable.
@Suite struct SpikeResultsTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static let heading = "## Sparkle updater with an ad hoc signed update"

    /// What the rest of the feature added. None of it may exist when the spike failed.
    private static let builtAfterTheSpike = [
        "App/AppUpdater.swift",
        "Packages/DevDevCore/Sources/DevDevCore/UpdatesSection.swift",
        "scripts/make-appcast.sh",
        "scripts/setup-update-key.sh",
        "scripts/verify-update-signature.swift",
    ]

    /// The spike's entry: from its heading to the next `## ` heading, or the end of the file.
    private func entry() throws -> [String] {
        let text = try String(contentsOf: root.appendingPathComponent("docs/spike-results.md"), encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex(of: Self.heading), "docs/spike-results.md has no Sparkle entry")
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("## ") } ?? rest.endIndex
        return Array(rest[..<end])
    }

    /// The lines under the `### ` heading that starts with `prefix`, up to the next `### `.
    private func part(_ prefix: String) throws -> String {
        let lines = try entry()
        let start = try #require(lines.firstIndex { $0.hasPrefix("### \(prefix)") }, "no part \"\(prefix)\"")
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("### ") } ?? rest.endIndex
        return rest[..<end].joined(separator: "\n")
    }

    /// The Result cell of the three rows of the summary table, in order.
    private func answers() throws -> [String] {
        try entry().compactMap { line in
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 5, ["1", "2", "3"].contains(cells[1]) else { return nil }
            return cells[3]
        }
    }

    private func git(_ arguments: String...) throws -> (status: Int32, output: String) {
        try git(arguments)
    }

    /// The oldest commit a `git log` with these arguments lists.
    private func oldestCommit(_ arguments: String...) throws -> String {
        let log = try git(["log", "--format=%H"] + arguments)
        return try #require(log.output.split(separator: "\n").last.map(String.init), "git log \(arguments) found no commit")
    }

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

    // MARK: - AC-1

    @Test func theSparkleSpikeEntryAnswersItsThreeQuestionsEachWithEvidence() throws {
        let answers = try answers()
        try #require(answers.count == 3, "the summary table needs one row per question")
        for answer in answers {
            #expect(answer.hasPrefix("**Yes.**") || answer.hasPrefix("**No.**"), "not a plain answer: \(answer)")
        }

        // 1. Did Sparkle install an ad hoc signed update, verified by EdDSA alone?
        let setUp = try part("The set-up")
        #expect(setUp.contains("Signature=adhoc"))
        #expect(setUp.contains("0 valid identities found"))
        let install = try part("1. Install of an ad hoc signed update, verified by EdDSA alone")
        #expect(install.contains("**Result: "))
        #expect(install.contains("> v=1.0.0 delegate: will install 1.0.1"))
        #expect(install.contains("> v=1.0.1 launched"))
        #expect(install.contains("CDHash"))
        // The control: a wrong EdDSA signature was refused, so EdDSA is what decided.
        #expect(install.contains("SUSparkleErrorDomain Code=4005"))

        // 2. What did Gatekeeper do on the next launch?
        let gatekeeper = try part("2. Gatekeeper on the next launch")
        #expect(gatekeeper.contains("**Result: "))
        #expect(gatekeeper.contains("com.apple.quarantine"))
        #expect(gatekeeper.contains("`open` exited 0"))
        #expect(gatekeeper.contains("spctl"))

        // 3. What happened to a Helper running from inside the replaced app?
        let helper = try part("3. A Helper running from inside the replaced app")
        #expect(helper.contains("**Result: "))
        #expect(helper.contains("pid 31290"))
        #expect(helper.contains("SIGTERM"))
        #expect(helper.contains("Contents/Helpers/SpikeHelper.app"))

        // What a script could not see is said, not passed over.
        #expect(try part("Not verified").contains("Gatekeeper"))
    }

    // MARK: - AC-2

    @Test func theRestOfTheFeatureExistsOnlyBecauseEveryStopQuestionOfTheSpikePassed() throws {
        let answers = try answers()
        try #require(answers.count == 3)
        let passed = answers.allSatisfy { $0.hasPrefix("**Yes.**") }
        let built = Self.builtAfterTheSpike.filter {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        let resolved = try String(
            contentsOf: root.appendingPathComponent(
                "devdev.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"),
            encoding: .utf8)

        if passed {
            #expect(try entry().contains("**Result: all three questions pass. The feature is not stopped.**"))
        } else {
            // A failed spike stops the run: its record is all there may be.
            #expect(built.isEmpty, "the spike failed, but these were built: \(built)")
            #expect(!resolved.contains("\"identity\" : \"sparkle\""), "the spike failed, but Sparkle is pinned")
        }
    }

    @Test func theSpikeResultWasRecordedBeforeAnythingElseOfTheFeatureWasBuilt() throws {
        #expect(try entry().contains { $0.contains("before any other slice of the updater feature") })

        // Without history, as in an exported copy of the sources, the entry's own word is all there is.
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else { return }
        let spike = try oldestCommit("-S\(Self.heading)", "--", "docs/spike-results.md")
        for path in Self.builtAfterTheSpike {
            let added = try oldestCommit("--diff-filter=A", "--", path)
            // The same commit passes too: a squash merge puts the whole feature in one commit.
            #expect(
                try git("merge-base", "--is-ancestor", spike, added).status == 0,
                "\(path) was added before the spike result was recorded")
        }
    }
}
