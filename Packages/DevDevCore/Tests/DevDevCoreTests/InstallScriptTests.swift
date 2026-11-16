import Foundation
import Testing

/// `scripts/install.sh`, read as text. Running it is on the manual checklist.
@Suite struct InstallScriptTests {
    private func script() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("scripts/install.sh"), encoding: .utf8)
    }

    /// The lines that run, without comments.
    private func commands() throws -> [String] {
        try script().split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    @Test func theInstallScriptBuildsReleaseAndCopiesTheAppToApplications() throws {
        let lines = try commands().joined(separator: "\n")
        #expect(lines.contains("xcodebuild -project devdev.xcodeproj -scheme devdev -configuration Release"))
        #expect(lines.contains("destination_folder=${1:-/Applications}"))
        #expect(lines.contains("destination=\"$destination_folder/devdev.app\""))
        #expect(lines.contains("ditto \"$built\""))
        #expect(lines.contains("mv \"$staging\" \"$destination\""))
    }

    @Test func theInstallScriptContainsNothingThatStopsARunningHelper() throws {
        let stoppers = [
            "kill", "pkill", "killall", "launchctl", "osascript", "stopAllAndQuit", "helper.sock", "open ", "nc ",
        ]
        for line in try commands() {
            for stopper in stoppers {
                #expect(!line.contains(stopper), "install.sh must not run: \(line)")
            }
        }
        // It deletes only its own staging copy and the app it replaces.
        let removals = try commands().filter { $0.hasPrefix("rm ") }
        #expect(removals == ["rm -rf \"$staging\"", "rm -rf \"$destination\""])
    }
}
