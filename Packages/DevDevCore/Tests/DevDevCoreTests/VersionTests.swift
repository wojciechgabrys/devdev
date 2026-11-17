import Foundation
import Testing

@testable import DevDevCore

/// The build number equals the version, so Sparkle can compare versions. Checked against the
/// repo: the Xcode project, the release workflow's tag check, and the About window's label.
@Suite struct VersionTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private let projectPath = "devdev.xcodeproj/project.pbxproj"
    private let corePath = "Packages/DevDevCore/Sources/DevDevCore/DevDevCore.swift"

    private func project() throws -> String {
        try String(contentsOf: root.appendingPathComponent(projectPath), encoding: .utf8)
    }

    /// Every value a build setting takes in `project.pbxproj`, one per build configuration.
    private func values(of setting: String, in project: String) -> [String] {
        project.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " = ")
            guard parts.count == 2, parts[0] == setting, parts[1].hasSuffix(";") else { return nil }
            return String(parts[1].dropLast()).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
    }

    @Test(arguments: ["CURRENT_PROJECT_VERSION", "MARKETING_VERSION"])
    func everyBuildConfigurationCarriesTheCoreVersion(setting: String) throws {
        let found = values(of: setting, in: try project())
        // Two targets and the project, each with Debug and Release.
        #expect(found.count == 6)
        #expect(found.allSatisfy { $0 == DevDevCore.version }, "\(setting) is \(found), not \(DevDevCore.version)")
    }

    @Test func theAboutLabelShowsTheVersionOnce() {
        #expect(DevDevCore.versionLabel(short: "0.2.1", build: "0.2.1") == "Version 0.2.1")
    }

    @Test func theAboutLabelShowsABuildNumberThatDiffers() {
        #expect(DevDevCore.versionLabel(short: "0.2.1", build: "7") == "Version 0.2.1 (7)")
    }

    // MARK: - The release workflow's tag check

    /// The script of the step "Check the tag matches the app version", as the workflow holds it.
    private func tagCheckScript() throws -> String {
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)
        let lines = workflow.components(separatedBy: "\n")
        let name = try #require(lines.firstIndex { $0.contains("name: Check the tag matches the app version") })
        let run = try #require(lines[name...].firstIndex { $0.contains("run: |") })
        let body = lines[(run + 1)...].prefix { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return body.joined(separator: "\n")
    }

    /// Runs the tag check for `tag` in a copy of the repo's two version files, after `edit`
    /// has changed the copied `project.pbxproj`.
    private func runTagCheck(tag: String, edit: (String) -> String = { $0 }) throws -> (status: Int32, output: String) {
        let files = FileManager.default
        let copy = files.temporaryDirectory.appendingPathComponent("devdev-tag-check-\(UUID().uuidString)")
        defer { try? files.removeItem(at: copy) }
        for path in [projectPath, corePath] {
            let target = copy.appendingPathComponent(path)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            var text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            if path == projectPath { text = edit(text) }
            try text.write(to: target, atomically: true, encoding: .utf8)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-e", "-c", try tagCheckScript()]
        process.currentDirectoryURL = copy
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "GITHUB_REF_NAME": tag,
            "GITHUB_ENV": copy.appendingPathComponent("github-env").path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @Test func theTagCheckPassesWhenTheTagIsTheVersion() throws {
        let result = try runTagCheck(tag: "v\(DevDevCore.version)")
        #expect(result.status == 0, "\(result.output)")
    }

    @Test func theTagCheckFailsWhenTheTagDiffersFromEveryVersion() throws {
        let result = try runTagCheck(tag: "v99.0.0")
        #expect(result.status != 0)
    }

    @Test func theTagCheckFailsAndNamesTheBuildNumberThatDiffersFromTheTag() throws {
        let result = try runTagCheck(tag: "v\(DevDevCore.version)") {
            $0.replacingOccurrences(
                of: "CURRENT_PROJECT_VERSION = \(DevDevCore.version);", with: "CURRENT_PROJECT_VERSION = 1;")
        }
        #expect(result.status != 0)
        let error = result.output.split(separator: "\n").first { $0.hasPrefix("::error::") }
        #expect(error?.contains("CURRENT_PROJECT_VERSION (1)") == true, "\(result.output)")
    }

    @Test func theTagCheckFailsWhenOnlyOneBuildConfigurationDiffers() throws {
        let result = try runTagCheck(tag: "v\(DevDevCore.version)") {
            guard let first = $0.range(of: "CURRENT_PROJECT_VERSION = \(DevDevCore.version);") else { return $0 }
            return $0.replacingCharacters(in: first, with: "CURRENT_PROJECT_VERSION = 1;")
        }
        #expect(result.status != 0)
    }
}
