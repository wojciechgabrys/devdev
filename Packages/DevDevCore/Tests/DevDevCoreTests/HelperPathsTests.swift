import Foundation
import Testing

@testable import DevDevCore

@Suite struct HelperPathsTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    @Test func releaseUsesTheDevdevDataFolderAndASocketInsideIt() {
        let paths = HelperPaths(flavor: .release, homeFolder: home)
        #expect(paths.dataFolder.path == "/Users/someone/Library/Application Support/devdev")
        #expect(paths.socketPath == "/Users/someone/Library/Application Support/devdev/helper.sock")
        #expect(paths.configurationFile.path == "/Users/someone/Library/Application Support/devdev/configuration.json")
    }

    @Test func debugUsesTheDevdevDebugDataFolderAndItsOwnSocket() {
        let paths = HelperPaths(flavor: .debug, homeFolder: home)
        #expect(paths.dataFolder.path == "/Users/someone/Library/Application Support/devdev-debug")
        #expect(paths.socketPath == "/Users/someone/Library/Application Support/devdev-debug/helper.sock")
        #expect(paths.socketPath != HelperPaths(flavor: .release, homeFolder: home).socketPath)
    }

    @Test func debugAndReleaseHaveDistinctBundleIdentifiers() {
        #expect(BuildFlavor.release.appBundleIdentifier == "dev.devdev.app")
        #expect(BuildFlavor.release.helperBundleIdentifier == "dev.devdev.helper")
        #expect(BuildFlavor.debug.appBundleIdentifier == "dev.devdev.app.debug")
        #expect(BuildFlavor.debug.helperBundleIdentifier == "dev.devdev.helper.debug")
    }

    @Test func flavorFollowsTheBundleIdentifierOfTheRunningProgram() {
        #expect(BuildFlavor.current(bundleIdentifier: "dev.devdev.app") == .release)
        #expect(BuildFlavor.current(bundleIdentifier: "dev.devdev.helper") == .release)
        #expect(BuildFlavor.current(bundleIdentifier: "dev.devdev.app.debug") == .debug)
        #expect(BuildFlavor.current(bundleIdentifier: "dev.devdev.helper.debug") == .debug)
        #expect(BuildFlavor.current(bundleIdentifier: nil) == BuildFlavor.compiled)
    }

    @Test func onlyAReleaseBuildHasAnUpdater() {
        #expect(BuildFlavor.release.hasUpdater)
        #expect(!BuildFlavor.debug.hasUpdater)
    }
}
