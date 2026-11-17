import AppKit
import DevDevCore

/// The Helper: a background app with no Dock icon. Every rule lives in `DevDevCore`.
@main
enum HelperMain {
    @MainActor
    static func main() {
        let flavor = BuildFlavor.current()
        let paths = HelperPaths(flavor: flavor)
        // Launch at login: a LaunchAgent file, because the login-item API fails after a reinstall
        // (docs/spike-results.md item 3). Release always points at /Applications/devdev.app.
        let loginItem = LaunchAgentLoginItem.forHelper(
            flavor: flavor,
            runningHelperExecutable: Bundle.main.executableURL ?? HelperLocation(
                flavor: flavor, appBundle: HelperLocation.installedApp).helperExecutable)
        let opener = AppOpener(flavor: flavor, appBundle: HelperLocation.app(containingHelper: Bundle.main.bundleURL))
        let notifications = SystemNotifications(opener: opener)
        let host: HelperHost
        do {
            // The build is read once, at start: the app on disk may be replaced while this Helper runs.
            host = try HelperHost.start(
                paths: paths, helperVersion: HelperBuild.identifier(ofExecutableAt: Bundle.main.executableURL),
                loginItem: loginItem, notifications: notifications)
        } catch let error as HelperError where error.code == HelperError.alreadyRunning {
            // One Helper per data folder. The one that runs keeps its Processes.
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("DevDev Helper could not start: \(error)\n".utf8))
            exit(1)
        }

        // Stop All and Quit: every Process is stopped by now.
        Task {
            for await _ in host.engine.quitRequests {
                host.server.stop()
                exit(0)
            }
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        // Clicking a notification opens the App on that Command's output.
        notifications.start()

        // The menubar icon and panel stay for as long as the Helper runs, with or without the App.
        let model = MenubarModel(engine: host.engine)
        let statusItem = StatusItemController(model: model, opener: opener)
        Task { @MainActor in
            await model.start()
            statusItem.start()
        }

        withExtendedLifetime((host, statusItem, notifications)) {
            application.run()
        }
    }
}
