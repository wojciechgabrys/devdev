import AppKit
import DevDevCore
import SwiftUI

/// The App: a thin client of the Helper. Every rule lives in `DevDevCore`.
@main
struct DevDevApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = HelperLauncher.makeModel()

    var body: some Scene {
        // One window. Closing it quits the App; the Helper and its Processes carry on.
        Window("devdev", id: "main") {
            MainWindow(model: model)
                .frame(minWidth: 900, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit devdev") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
                Button("Stop All and Quit") {
                    Task {
                        if await model.stopAllAndQuit() { NSApp.terminate(nil) }
                    }
                }
            }
            // Find in the output: SwiftTerm answers the standard Find menu items.
            TextEditingCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
