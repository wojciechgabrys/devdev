import Foundation
import Testing

@testable import DevDevCore

/// The outdated-Helper decision, and where the App finds the Helper it starts.
@Suite struct HelperCompatibilityTests {
    @Test func aHelperOfTheSameProtocolAndBuildIsCurrentAndShowsNoBanner() {
        let verdict = HelperCompatibility.evaluate(
            appProtocol: 1, appBuild: "0.1.0+aaa", helperProtocol: 1, helperBuild: "0.1.0+aaa")
        #expect(verdict == .current)
        #expect(verdict.allowsRequests)
        #expect(WindowState.connected(compatibility: verdict).notice == nil)
    }

    @Test func aHelperOfAnotherBuildButTheSameProtocolIsOutdatedAndKeepsWorking() {
        let verdict = HelperCompatibility.evaluate(
            appProtocol: 1, appBuild: "0.1.0+bbb", helperProtocol: 1, helperBuild: "0.1.0+aaa")
        #expect(verdict == .outdated)
        #expect(verdict.allowsRequests)
    }

    @Test func aHelperOfAnotherProtocolVersionIsIncompatibleAndTakesNoRequests() {
        let older = HelperCompatibility.evaluate(
            appProtocol: 2, appBuild: "0.1.0+aaa", helperProtocol: 1, helperBuild: "0.1.0+aaa")
        #expect(older == .incompatible(helperProtocol: 1, appProtocol: 2))
        #expect(!older.allowsRequests)
    }

    @Test func theOutdatedBannerOffersARestartWhoseLabelSaysItStopsAllProcesses() throws {
        let notice = try #require(WindowState.connected(compatibility: .outdated).notice)
        #expect(notice.action == .restartHelper)
        #expect(notice.actionLabel == "Restart Helper (stops all Processes)")
        #expect(notice.message.contains("keeps working"))
    }

    @Test func theIncompatibleBannerSaysPlainlyThatTheAppCannotControlTheHelper() throws {
        let state = WindowState.connected(compatibility: .incompatible(helperProtocol: 1, appProtocol: 2))
        let notice = try #require(state.notice)
        #expect(notice.action == .restartHelper)
        #expect(notice.actionLabel == "Restart Helper (stops all Processes)")
        #expect(notice.message.contains("protocol version 1"))
        #expect(notice.message.contains("cannot control"))
        #expect(!state.canAct)
    }

    @Test func theBuildOfAHelperFollowsTheBytesOfItsExecutable() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = folder.appendingPathComponent("one")
        let same = folder.appendingPathComponent("same")
        let other = folder.appendingPathComponent("other")
        try Data("build one".utf8).write(to: one)
        try Data("build one".utf8).write(to: same)
        try Data("build two".utf8).write(to: other)

        #expect(HelperBuild.identifier(ofExecutableAt: one) == HelperBuild.identifier(ofExecutableAt: same))
        #expect(HelperBuild.identifier(ofExecutableAt: one) != HelperBuild.identifier(ofExecutableAt: other))
        #expect(HelperBuild.identifier(ofExecutableAt: one).hasPrefix(DevDevCore.version + "+"))
        #expect(HelperBuild.identifier(ofExecutableAt: folder.appendingPathComponent("missing")) == DevDevCore.version)
    }

    @Test func aReleaseAppStartsTheHelperInsideTheInstalledAppWhereverItRunsFrom() {
        let location = HelperLocation(
            flavor: .release, appBundle: URL(fileURLWithPath: "/Users/someone/DerivedData/Release/devdev.app"))
        #expect(location.helperBundle.path == "/Applications/devdev.app/Contents/Helpers/devdevHelper.app")
        #expect(
            location.helperExecutable.path
                == "/Applications/devdev.app/Contents/Helpers/devdevHelper.app/Contents/MacOS/devdevHelper")
    }

    @Test func aDebugAppStartsItsOwnHelperAndNeverTheInstalledOne() {
        let location = HelperLocation(
            flavor: .debug, appBundle: URL(fileURLWithPath: "/Users/someone/DerivedData/Debug/devdev.app"))
        #expect(
            location.helperBundle.path
                == "/Users/someone/DerivedData/Debug/devdev.app/Contents/Helpers/devdevHelper.app")
        #expect(!location.helperBundle.path.hasPrefix("/Applications"))
    }

    @Test func aMissingHelperBundleIsReportedWithTheInstallScript() throws {
        let location = HelperLocation(flavor: .release, appBundle: URL(fileURLWithPath: "/tmp/devdev.app"))
        #expect(throws: HelperError.self) {
            _ = try location.existingHelperBundle(fileExists: { _ in false })
        }
        do {
            _ = try location.existingHelperBundle(fileExists: { _ in false })
        } catch let error as HelperError {
            #expect(error.message.contains("scripts/install.sh"))
        }
        #expect(try location.existingHelperBundle(fileExists: { _ in true }) == location.helperBundle)
    }
}
