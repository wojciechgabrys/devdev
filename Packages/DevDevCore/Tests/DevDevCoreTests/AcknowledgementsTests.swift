import Foundation
import Testing

@testable import DevDevCore

/// The About window's list, checked against the repo: every pinned package is listed, and every
/// listed file is in `App/Acknowledgements/`, which the App target copies into its Resources.
@Suite struct AcknowledgementsTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private var folder: URL { root.appendingPathComponent("App/Acknowledgements") }

    private func pinnedIdentities() throws -> Set<String> {
        let url = root.appendingPathComponent(
            "devdev.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        struct Resolved: Decodable {
            struct Pin: Decodable { let identity: String }
            let pins: [Pin]
        }
        let resolved = try JSONDecoder().decode(Resolved.self, from: Data(contentsOf: url))
        return Set(resolved.pins.map(\.identity))
    }

    @Test func everyPinnedPackageIsListedAndNothingElse() throws {
        #expect(Set(Acknowledgements.packages.map(\.id)) == (try pinnedIdentities()))
    }

    @Test func theFolderHoldsExactlyTheListedFiles() throws {
        let present = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        let listed = Set(Acknowledgements.all.flatMap(\.files))
        #expect(present == listed)
    }

    @Test func devDevIsFirstAndItsBundledLicenseIsTheRepoLicense() throws {
        #expect(Acknowledgements.all.first == Acknowledgements.devDev)
        let repo = try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8)
        let bundled = try String(contentsOf: folder.appendingPathComponent("devdev-LICENSE.txt"), encoding: .utf8)
        #expect(repo.hasPrefix("MIT License"))
        #expect(bundled == repo)
    }

    @Test func textJoinsTheFilesAndNamesAMissingOne() throws {
        let bundle = try #require(Bundle(url: folder))
        let nio = try #require(Acknowledgements.packages.first { $0.id == "swift-nio" })
        let text = Acknowledgements.text(of: nio, in: bundle)
        #expect(text.contains("Apache License"))
        #expect(text.contains("The SwiftNIO Project"))

        let ghost = Acknowledgement(
            id: "ghost", name: "Ghost", url: URL(string: "https://example.com")!, license: "MIT",
            files: ["ghost-LICENSE.txt"])
        #expect(Acknowledgements.text(of: ghost, in: bundle) == "ghost-LICENSE.txt is missing from this build.")
    }
}
