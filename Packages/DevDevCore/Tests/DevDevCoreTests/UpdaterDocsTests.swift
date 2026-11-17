import Foundation
import Testing

/// The docs for the updater, read as text: `README.md`, `docs/spec.md` and the Updates group of
/// `docs/manual-checklist.md`. Doing the checklist is a person's job; this only keeps it in place.
@Suite struct UpdaterDocsTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The lines under a `## ` heading, up to the next one.
    private func section(_ heading: String, of path: String) throws -> String {
        let lines = try text(path).components(separatedBy: "\n")
        let start = try #require(lines.firstIndex(of: "## \(heading)"), "\(path) has no \"## \(heading)\"")
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("## ") } ?? rest.endIndex
        return rest[..<end].joined(separator: "\n")
    }

    /// One checklist item per element: its title line and its numbered steps.
    private func updateItems() throws -> [String] {
        var items: [String] = []
        for line in try section("Updates", of: "docs/manual-checklist.md").components(separatedBy: "\n") {
            if line.hasPrefix("- [") {
                items.append(line)
            } else if !items.isEmpty, line.hasPrefix("  ") {
                items[items.count - 1] += "\n" + line
            }
        }
        return items
    }

    private func item(_ words: String...) throws -> String {
        try #require(
            try updateItems().first { item in words.allSatisfy { item.localizedCaseInsensitiveContains($0) } },
            "No Updates item mentions \(words)")
    }

    @Test func theReadmeAndTheSpecNoLongerSayThereIsNoAutoUpdate() throws {
        let readme = try text("README.md")
        let spec = try text("docs/spec.md")
        #expect(!readme.contains("notarization or auto-update"))
        #expect(!spec.contains("no update mechanism"))
        #expect(!spec.contains("Signing, notarizing, auto-update"))
        // Developer ID signing and notarization stay out of scope.
        #expect(try section("2. Non-goals", of: "docs/spec.md").contains("notariz"))
    }

    @Test func theReadmeInstallSectionExplainsTheDMGTheUpdaterAndTheOneHandReplacement() throws {
        let install = try section("Install", of: "README.md")
        #expect(install.contains("devdev-<version>.dmg"))
        #expect(install.contains("Check for Updates…"))
        #expect(install.contains("0.2.1 and earlier"))
        #expect(install.contains("by hand"))
    }

    @Test func theReadmeNamesTheThreeValuesAVersionBumpChanges() throws {
        let readme = try text("README.md")
        let line = try #require(readme.components(separatedBy: "\n").first { $0.contains("version bump") })
        for name in ["DevDevCore.version", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION"] {
            #expect(line.contains(name))
        }
    }

    @Test func everyUpdatesItemIsUncheckedAndHasNumberedSteps() throws {
        let items = try updateItems()
        #expect(items.count >= 6)
        for item in items {
            #expect(item.hasPrefix("- [ ] **"), "Not unchecked: \(item.prefix(60))")
            #expect(item.contains("\n  1. "), "No steps: \(item.prefix(60))")
            #expect(item.contains("\n  2. "), "One step only: \(item.prefix(60))")
        }
    }

    @Test func theChecklistCoversARealUpdateTheSwitchPermissionsTheDailyCheckAndDebug() throws {
        let update = try item("tag", "Check for Updates…", "Install", "relaunch")
        #expect(update.contains("git tag"))
        let toggle = try item("Settings switch", "Check for updates automatically")
        #expect(toggle.contains("Quit"))
        #expect(try item("permission", "after an update").contains("Record"))
        #expect(try item("daily check").contains("24 hours"))
        #expect(try item("Debug").contains("Check for Updates…"))
    }

    @Test func theChecklistChecksTheHelperAndTheOutdatedHelperBannerAfterAnUpdate() throws {
        let helper = try item("after the update", "Helper", "banner")
        #expect(helper.contains("Running"))
        #expect(helper.contains("process ID"))
        #expect(helper.contains("outdated"))
        #expect(try section("Updates", of: "docs/manual-checklist.md").contains("not verified"))
    }
}
