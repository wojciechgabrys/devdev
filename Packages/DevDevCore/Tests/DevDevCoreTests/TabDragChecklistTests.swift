import Foundation
import Testing

/// The pointer checks of tab dragging that need a person at the Mac, read as text from
/// `docs/manual-checklist.md` and `docs/final-report.md`.
@Suite struct TabDragChecklistTests {
    private static let heading = "Reorder tabs by dragging"

    /// One title per check the feature asks for: the live slide, the click threshold, the x button,
    /// the edge scrolling, Esc, a release outside the window, and that the window does not move.
    private static let checks = [
        "A dragged tab follows the pointer and its neighbours slide aside live.",
        "A press below the threshold is a plain click.",
        "The x button closes and never starts a drag.",
        "Holding a dragged tab at an edge scrolls the strip.",
        "Esc during a drag puts the tab back.",
        "A release outside the window drops the tab.",
        "A tab drag never moves the window.",
    ]

    /// The lines of the feature's section in a document under `docs/`.
    private func section(of document: String) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("docs/\(document)"), encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("#") && $0.hasSuffix(Self.heading) })
        return Array(lines[(start + 1)...].prefix { !$0.hasPrefix("#") })
    }

    @Test func thePointerChecksThatNeedAPersonAreUncheckedItemsOnTheManualChecklist() throws {
        let items = try section(of: "manual-checklist.md").filter { $0.hasPrefix("- [") }
        for check in Self.checks {
            #expect(items.contains("- [ ] **\(check)**"), "missing or checked: \(check)")
        }
        // No item of the section is ticked: nobody has run them.
        #expect(items.allSatisfy { $0.hasPrefix("- [ ] ") })
    }

    @Test func theFinalReportCallsEveryPointerCheckNotVerified() throws {
        let checklist = try section(of: "manual-checklist.md").filter { $0.hasPrefix("- [") }
        let report = try section(of: "final-report.md").filter { $0.hasPrefix("- [") }
        for check in Self.checks {
            #expect(report.contains("- [ ] **Not verified.** \(check)"), "not reported: \(check)")
        }
        // Every item of the checklist's section is in the report, and each is called not verified.
        #expect(report.count == checklist.count)
        #expect(report.allSatisfy { $0.hasPrefix("- [ ] **Not verified.** ") })
    }
}
