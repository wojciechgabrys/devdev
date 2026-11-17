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

    /// The package products a target names in `packageProductDependencies`.
    private func packageProducts(ofTarget name: String, in project: String) throws -> [String] {
        let start = try #require(project.range(of: "/* \(name) */ = {\n\t\t\tisa = PBXNativeTarget;"))
        let target = project[start.upperBound...]
        let list = try #require(target.range(of: "packageProductDependencies = ("))
        let end = try #require(target[list.upperBound...].range(of: ");"))
        return target[list.upperBound..<end.lowerBound].split(separator: "\n").compactMap { line in
            guard let open = line.range(of: "/* "), let close = line.range(of: " */") else { return nil }
            return String(line[open.upperBound..<close.lowerBound])
        }
    }

    @Test func onlyTheAppLinksSparkleAndTheProjectPinsIt() throws {
        let project = try read("devdev.xcodeproj/project.pbxproj")
        #expect(try packageProducts(ofTarget: "devdev", in: project).contains("Sparkle"))
        #expect(try packageProducts(ofTarget: "devdevHelper", in: project) == ["DevDevCore"])
        #expect(try packageProducts(ofTarget: "devdevCLI", in: project) == ["DevDevCore", "MCP"])
        #expect(project.contains("/* Sparkle in Frameworks */,"))

        let resolved = try read("devdev.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        #expect(resolved.contains("\"identity\" : \"sparkle\""))
    }

    @Test func devDevCoreDependsOnNoPackageSoNotOnSparkle() throws {
        let manifest = try read("Packages/DevDevCore/Package.swift")
        #expect(!manifest.contains(".package("))
        #expect(!manifest.localizedCaseInsensitiveContains("sparkle"))
        let sources = root.appendingPathComponent("Packages/DevDevCore/Sources/DevDevCore")
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            #expect(!text.contains("import Sparkle"), "\(file) imports Sparkle")
        }
    }
}
