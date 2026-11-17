import Foundation
import Testing

/// The four commands the README gives for building and testing, and what makes them one check:
/// `xcodebuild … test` runs this same test target through the scheme's test plan.
///
/// A test cannot run the test run it is part of. So this suite keeps the commands and their
/// wiring in place, and proves the resolve step by building against the package it fetched.
/// That all four pass is shown by running them.
@Suite struct BuildCommandsTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The lines of the fenced `bash` blocks under the README's "Build and test" heading.
    private func commands() throws -> [String] {
        let lines = try read("README.md").components(separatedBy: "\n")
        let start = try #require(lines.firstIndex(of: "## Build and test"))
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("## ") } ?? rest.endIndex
        var found: [String] = []
        var inBlock = false
        for line in rest[..<end] {
            if line.hasPrefix("```") {
                inBlock = line == "```bash"
            } else if inBlock {
                found.append(line)
            }
        }
        return found
    }

    @Test func theReadmeGivesTheThreeXcodebuildCommandsAndSwiftTest() throws {
        #expect(
            try commands() == [
                "xcodebuild -project devdev.xcodeproj -scheme devdev -resolvePackageDependencies",
                "xcodebuild -project devdev.xcodeproj -scheme devdev -destination platform=macOS build",
                "xcodebuild -project devdev.xcodeproj -scheme devdev -destination platform=macOS test",
                "cd Packages/DevDevCore && swift test",
            ])
    }

    @Test func xcodebuildTestAndSwiftTestRunTheSameTestsSoOneRedTestFailsBoth() throws {
        // The shared scheme tests through the test plan, and the plan holds this package's test target.
        let scheme = try read("devdev.xcodeproj/xcshareddata/xcschemes/devdev.xcscheme")
        #expect(scheme.contains("reference = \"container:devdev.xctestplan\""))
        let data = try Data(contentsOf: root.appendingPathComponent("devdev.xctestplan"))
        let plan = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let targets = try #require(plan["testTargets"] as? [[String: Any]])
        let named = targets.compactMap { $0["target"] as? [String: String] }
        #expect(named.count == 1)
        #expect(named.first?["containerPath"] == "container:Packages/DevDevCore")
        #expect(named.first?["name"] == "DevDevCoreTests")
        // No test of the plan is switched off.
        #expect(targets.allSatisfy { $0["skippedTests"] == nil && $0["selectedTests"] == nil && $0["enabled"] == nil })

        // This file is in that target's folder, so it runs under both commands.
        let package = try read("Packages/DevDevCore/Package.swift")
        #expect(package.contains("name: \"DevDevCoreTests\""))
        #expect(#filePath.contains("/Packages/DevDevCore/Tests/DevDevCoreTests/"))
    }

    @Test func theSchemeBuildsEveryTargetTheBuildCommandMustBuildAndPinsEveryPackageItResolves() throws {
        let scheme = try read("devdev.xcodeproj/xcshareddata/xcschemes/devdev.xcscheme")
        for name in ["devdev", "devdevHelper", "devdevCLI"] {
            #expect(scheme.contains("BlueprintName = \"\(name)\""), "the scheme builds \(name)")
        }
        // Every remote package the project names has a pin, so the resolve command fetches fixed versions.
        let project = try read("devdev.xcodeproj/project.pbxproj")
        let resolved = try read("devdev.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").lowercased()
        let urls = project.components(separatedBy: "\n").compactMap { line -> String? in
            guard let range = line.range(of: "repositoryURL = \"") else { return nil }
            return String(line[range.upperBound...].prefix { $0 != "\"" })
        }
        #expect(!urls.isEmpty)
        for url in urls {
            let identity = URL(string: url)?.deletingPathExtension().lastPathComponent.lowercased() ?? url
            #expect(resolved.contains("\"identity\" : \"\(identity)\""), "\(url) is not pinned")
        }
    }
}
