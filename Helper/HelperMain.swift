import AppKit
import DevDevCore

/// The Helper: a background app with no Dock icon. Every rule lives in `DevDevCore`.
@main
enum HelperMain {
    @MainActor
    static func main() {
        let paths = HelperPaths(flavor: .current())
        let host: HelperHost
        do {
            // The build is read once, at start: the app on disk may be replaced while this Helper runs.
            host = try HelperHost.start(
                paths: paths, helperVersion: HelperBuild.identifier(ofExecutableAt: Bundle.main.executableURL))
        } catch let error as HelperError where error.code == HelperError.alreadyRunning {
            // One Helper per data folder. The one that runs keeps its Processes.
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("devdev Helper could not start: \(error)\n".utf8))
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
        withExtendedLifetime(host) {
            application.run()
        }
    }
}
