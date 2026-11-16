import Foundation
import Testing

@testable import DevDevCore

/// The line Settings shows for adding devdev to Claude Code, and where the `devdev` CLI sits.
@Suite struct MCPSetupTests {
    private let xcodeBuild = URL(fileURLWithPath: "/tmp/DerivedData/Build/Products/Release/devdev.app", isDirectory: true)

    @Test func aReleaseBuildPointsTheSetupLineAtTheCLIInsideTheInstalledApp() {
        let line = MCPSetup.line(flavor: .release, appBundle: xcodeBuild)
        #expect(line == #"claude mcp add devdev -- "/Applications/devdev.app/Contents/Helpers/devdev" mcp"#)
    }

    @Test func aDebugBuildPointsTheSetupLineAtTheCLIInsideTheRunningApp() {
        let app = URL(fileURLWithPath: "/tmp/Debug/devdev.app", isDirectory: true)
        #expect(MCPSetup.cliExecutable(flavor: .debug, appBundle: app).path == "/tmp/Debug/devdev.app/Contents/Helpers/devdev")
        #expect(
            MCPSetup.line(flavor: .debug, appBundle: app)
                == #"claude mcp add devdev-debug -- "/tmp/Debug/devdev.app/Contents/Helpers/devdev" mcp"#)
    }

    @Test func aPathWithQuotesOrDollarSignsIsEscapedInsideTheDoubleQuotes() {
        let app = URL(fileURLWithPath: #"/tmp/a "b" $c/devdev.app"#, isDirectory: true)
        #expect(
            MCPSetup.line(flavor: .debug, appBundle: app)
                == #"claude mcp add devdev-debug -- "/tmp/a \"b\" \$c/devdev.app/Contents/Helpers/devdev" mcp"#)
    }

    @Test func theCLIFindsTheAppItIsBundledIn() {
        let cli = URL(fileURLWithPath: "/tmp/Debug/devdev.app/Contents/Helpers/devdev")
        #expect(MCPSetup.app(containingCLI: cli).path == "/tmp/Debug/devdev.app")
    }

    @Test func aDebugCLIOutsideAnAppUsesTheAppBesideIt() {
        let cli = URL(fileURLWithPath: "/tmp/Build/Products/Debug/devdev")
        #expect(MCPSetup.app(containingCLI: cli).path == "/tmp/Build/Products/Debug/devdev.app")
    }
}
