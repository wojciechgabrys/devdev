import AppKit
import DevDevCore

/// Starts the Helper program. Which Helper, and whether one is needed, is decided in `DevDevCore`.
enum HelperLauncher {
    @MainActor
    static func makeModel() -> WindowModel {
        let flavor = BuildFlavor.current()
        let location = HelperLocation(flavor: flavor, appBundle: Bundle.main.bundleURL)
        return WindowModel(
            socketPath: HelperPaths(flavor: flavor).socketPath,
            expectedHelperBuild: HelperBuild.identifier(ofExecutableAt: location.helperExecutable),
            launchHelper: { try await launch(location) })
    }

    @MainActor
    private static func launch(_ location: HelperLocation) async throws {
        let bundle = try location.existingHelperBundle()
        // A Helper that was just told to quit may still be on its way out. Opening it now would
        // only bring that one forward, so give it a moment to go.
        let deadline = ContinuousClock.now + .seconds(3)
        while isRunning(bundle), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { _, error in
                if let error { done.resume(throwing: error) } else { done.resume() }
            }
        }
    }

    @MainActor
    private static func isRunning(_ bundle: URL) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL.path == bundle.standardizedFileURL.path && !$0.isTerminated
        }
    }
}
