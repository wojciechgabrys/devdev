import Foundation
import Testing

@testable import DevDevCore

/// The Xcode project, read as text: the `devdev` CLI is built by the shared scheme and bundled where
/// `MCPSetup` says it is. That the built app holds it is checked by `scripts/install.sh`.
@Suite struct BundleLayoutTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theSharedSchemeBuildsTheAppTheHelperAndTheCLI() throws {
        let scheme = try read("devdev.xcodeproj/xcshareddata/xcschemes/devdev.xcscheme")
        for name in ["devdev", "devdevHelper", "devdevCLI"] {
            #expect(scheme.contains("BlueprintName = \"\(name)\""), "the scheme builds \(name)")
        }
    }

    @Test func theCLIIsATargetNamedDevdevCopiedIntoTheAppWhereTheSetupLinePointsAtIt() throws {
        let project = try read("devdev.xcodeproj/project.pbxproj")
        #expect(project.contains("productType = \"com.apple.product-type.tool\";"))
        #expect(project.contains("PRODUCT_NAME = devdev;"))
        #expect(project.contains("/* devdev in Embed CLI */ = {isa = PBXBuildFile;"))
        let embed = try #require(project.range(of: "/* Embed CLI */ = {"))
        let phase = project[embed.upperBound...].prefix(400)
        #expect(phase.contains("dstPath = Contents/Helpers;"))
        #expect(MCPSetup.cliPathInApp == "Contents/Helpers/devdev")
    }
}
