import AppKit
import DevDevCore
import SwiftUI

/// The App: a thin client of the Helper. Every rule lives in `DevDevCore`.
@main
struct DevDevApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = HelperLauncher.makeModel()
    /// Started here, at launch, in a Release build. A Debug build has none.
    private let updater = AppUpdater.forThisBuild

    var body: some Scene {
        // One window. Closing it quits the App; the Helper and its Processes carry on.
        Window("DevDev", id: "main") {
            MainWindow(model: model)
                .frame(minWidth: 900, minHeight: 520)
                // A Command's name in the menubar panel, or a notification: show its output.
                .onOpenURL { url in
                    guard let link = OpenLink(url: url, flavor: BuildFlavor.current()) else { return }
                    Task { await model.open(link) }
                }
        }
        // Graphite draws its own title strip under the window buttons.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .handlesExternalEvents(matching: [BuildFlavor.current().urlScheme])
        .commands {
            AboutCommands()
            UpdateCommands(updater: updater)
            CommandGroup(replacing: .appTermination) {
                Button("Quit DevDev") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
                Button("Stop All and Quit") {
                    Task {
                        if await model.stopAllAndQuit() { NSApp.terminate(nil) }
                    }
                }
            }
            TabCommands()
            // Find in the output: SwiftTerm answers the standard Find menu items.
            TextEditingCommands()
        }

        Window("About DevDev", id: AboutWindow.id) {
            AboutWindow()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
