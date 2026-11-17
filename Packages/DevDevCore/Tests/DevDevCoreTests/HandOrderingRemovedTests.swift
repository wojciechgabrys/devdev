import Foundation
import Testing

/// Ordering Commands by hand is gone: from the Command menu, from the code, and from the docs.
/// The sources and docs are read as text, because the App target has no tests of its own.
@Suite struct HandOrderingRemovedTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every Swift file below these folders, as paths relative to the repository root. Build folders are left out.
    private func swiftFiles(in folders: [String]) throws -> [String] {
        var found: [String] = []
        for folder in folders {
            let url = root.appendingPathComponent(folder, isDirectory: true)
            let files = try #require(FileManager.default.enumerator(atPath: url.path), "no folder \(folder)")
            for case let file as String in files where file.hasSuffix(".swift") {
                if file.hasPrefix(".build/") || file.contains("/.build/") { continue }
                found.append("\(folder)/\(file)")
            }
        }
        return found.sorted()
    }

    /// The titles of the buttons in a SwiftUI view's body, in source order.
    private func buttonTitles(in source: Substring) -> [String] {
        source.components(separatedBy: "Button(\"").dropFirst().compactMap { rest in
            rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
        }
    }

    /// The source of a type in a file, from its declaration to the closing brace in the first column.
    private func declaration(_ name: String, in source: String) throws -> Substring {
        let start = try #require(source.range(of: "struct \(name)"), "no \(name)")
        let rest = source[start.lowerBound...]
        let end = try #require(rest.range(of: "\n}\n"), "\(name) does not end")
        return rest[..<end.upperBound]
    }

    // MARK: - The Command menu

    @Test func theCommandContextMenuHasNoMoveUpAndNoMoveDownItem() throws {
        let tree = try read("App/ProjectTree.swift")

        // The Command row's context menu is `CommandActionsMenu` and nothing else.
        let leaf = try declaration("CommandLeaf", in: tree)
        let menu = try #require(leaf.range(of: ".contextMenu {"), "the Command row has no context menu")
        let menuBody = leaf[menu.upperBound...].prefix { $0 != "}" }
        #expect(menuBody.trimmingCharacters(in: .whitespacesAndNewlines)
            == "CommandActionsMenu(command: command, model: model, actions: actions)")

        let actions = try declaration("CommandActionsMenu", in: tree)
        #expect(buttonTitles(in: actions) == ["Start", "Restart", "Stop", "Edit Command…", "Delete Command…"])
        #expect(actions.components(separatedBy: "Divider()").count - 1 == 1, "the divider of the move items is gone too")

        for file in try swiftFiles(in: ["App"]) {
            let source = try read(file)
            #expect(!source.contains("Move Up"), "\(file) still has a Move Up item")
            #expect(!source.contains("Move Down"), "\(file) still has a Move Down item")
        }
    }

    // MARK: - The code

    @Test func theMoveCommandRequestItsEngineAndModelMethodsAndCommandMoveAreGoneWithTheirTests() throws {
        // Whole words only: `renamingACommandMovesIt…` is not `CommandMove`.
        let gone = try ["moveCommand", "CommandMove"].map { try Regex<Substring>("\\b\($0)\\b") }
        let own = URL(fileURLWithPath: #filePath).lastPathComponent

        let files = try swiftFiles(in: ["App", "Helper", "CLI", "Packages/DevDevCore/Sources", "Packages/DevDevCore/Tests"])
        // The scan saw the files that held the four names, so an empty result means they are gone.
        for held in ["HelperProtocol.swift", "HelperEngine.swift", "WindowModel.swift", "WindowState.swift"] {
            #expect(files.contains("Packages/DevDevCore/Sources/DevDevCore/\(held)"), "\(held) was not scanned")
        }
        for held in ["WindowStateTests.swift", "WindowModelTests.swift", "ConfigurationTests.swift"] {
            #expect(files.contains("Packages/DevDevCore/Tests/DevDevCoreTests/\(held)"), "\(held) was not scanned")
        }

        for file in files where !file.hasSuffix("/\(own)") {
            let source = try read(file)
            for name in gone {
                let match = source.firstMatch(of: name)
                #expect(match == nil, "\(file) still names \(match.map { String($0.output) } ?? "")")
            }
        }
    }

    // MARK: - The docs

    private let handOrderingWords = ["move up", "move down", "rearrang", "reorder", "user's order"]

    @Test func theSpecSaysCommandsAndProjectsAreSortedByNameAndNoLongerMentionsHandOrdering() throws {
        let spec = try read("docs/spec.md")
        #expect(spec.contains("Commands are always sorted by name"))
        #expect(spec.contains("Projects are always sorted by name"))
        #expect(spec.contains("Start All starts them in that order"))

        // Start All's order is stated right after the Commands' order, so "that order" is the sorted one.
        let lines = spec.components(separatedBy: "\n")
        let commands = try #require(lines.first { $0.hasPrefix("Commands are always sorted by name") })
        #expect(commands.contains("Start All starts them in that order"))

        for word in handOrderingWords {
            #expect(spec.range(of: word, options: .caseInsensitive) == nil, "docs/spec.md still says \"\(word)\"")
        }
    }

    @Test func theManualChecklistChecksTheSortedOrderInsteadOfAskingToReorderCommands() throws {
        let checklist = try read("docs/manual-checklist.md")
        for word in handOrderingWords {
            #expect(checklist.range(of: word, options: .caseInsensitive) == nil,
                    "docs/manual-checklist.md still says \"\(word)\"")
        }

        // The Commands check, with its numbered steps up to the next check.
        let lines = checklist.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("- [ ] **Editing and deleting Commands") },
                                 "no check for editing and deleting Commands")
        #expect(lines[start].contains("sorted order"))
        let steps = lines[(start + 1)...].prefix { !$0.hasPrefix("- [ ]") && !$0.hasPrefix("#") }
        let sorted = try #require(steps.first { $0.contains("sorted by name") }, "no step checks the sorted order")
        #expect(sorted.contains("add a Command"), "the step adds a Command out of order")
        #expect(sorted.contains("Rename it"), "the step renames a Command so its row moves")
        #expect(sorted.contains("not at the end"))
    }

    // MARK: - The build

    @Test func theSchemeTestsThroughTheTestPlanAndThePlanHoldsEveryTestTarget() throws {
        // The three commands are still the ones the spec names.
        let spec = try read("docs/spec.md")
        for arguments in ["-resolvePackageDependencies", "-destination platform=macOS build", "-destination platform=macOS test"] {
            #expect(spec.contains("`xcodebuild -project devdev.xcodeproj -scheme devdev \(arguments)`"))
        }

        // `xcodebuild … test` runs what the scheme's only test plan lists.
        let scheme = try read("devdev.xcodeproj/xcshareddata/xcschemes/devdev.xcscheme")
        #expect(scheme.components(separatedBy: "<TestPlanReference").count - 1 == 1)
        #expect(scheme.contains("reference = \"container:devdev.xctestplan\""))

        let data = try Data(contentsOf: root.appendingPathComponent("devdev.xctestplan"))
        let plan = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(plan["testTargets"] as? [[String: Any]])
        var planned: [String: Set<String>] = [:]
        for entry in entries {
            // A target is run whole: not switched off, and with no test skipped or picked out.
            #expect(entry["enabled"] as? Bool != false)
            #expect(entry["skippedTests"] == nil)
            #expect(entry["selectedTests"] == nil)
            let target = try #require(entry["target"] as? [String: String])
            let container = try #require(target["containerPath"])
            planned[container, default: []].insert(try #require(target["identifier"]))
        }

        // Every test target of every package in `Packages/` is in the plan.
        let packages = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Packages").path)
            .filter { FileManager.default.fileExists(atPath: root.appendingPathComponent("Packages/\($0)/Package.swift").path) }
        #expect(packages.contains("DevDevCore"))
        for package in packages {
            let manifest = try read("Packages/\(package)/Package.swift")
            let targets = manifest.components(separatedBy: ".testTarget(").dropFirst().compactMap { rest -> String? in
                guard let name = rest.range(of: "name: \""), let end = rest[name.upperBound...].firstIndex(of: "\"") else {
                    return nil
                }
                return String(rest[name.upperBound..<end])
            }
            #expect(!targets.isEmpty || package != "DevDevCore", "DevDevCore has a test target")
            for target in targets {
                #expect(planned["container:Packages/\(package)"]?.contains(target) == true,
                        "\(target) of \(package) is not in devdev.xctestplan")
            }
        }

        // The App, the Helper and the CLI have no test target of their own that the plan could miss.
        let project = try read("devdev.xcodeproj/project.pbxproj")
        #expect(!project.contains("com.apple.product-type.bundle.unit-test"))
        #expect(!project.contains("com.apple.product-type.bundle.ui-testing"))
    }
}
