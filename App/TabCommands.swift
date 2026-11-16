import AppKit
import DevDevCore
import SwiftUI

extension FocusedValues {
    /// The model of the main window, while that window is in front. Nil when Settings is in front.
    @Entry var windowModel: WindowModel?
}

/// Cmd-W closes the selected output tab, or the window when no tab is open.
/// Cmd-1 to Cmd-9 show a tab by its place from the left. Cmd-0 shows the last one.
/// The rules come from `WindowState.closeTarget` and `WindowState.tab(number:)`.
struct TabCommands: Commands {
    @FocusedValue(\.windowModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button(closesTab ? "Close Tab" : "Close Window", action: close)
                .keyboardShortcut("w")
        }
        CommandGroup(before: .windowList) {
            ForEach(1..<10) { number in
                tabButton("Show Tab \(number)", number: number)
            }
            tabButton("Show Last Tab", number: 0)
            Divider()
        }
    }

    private var closesTab: Bool {
        if case .tab = model?.state.closeTarget { return true }
        return false
    }

    private func close() {
        guard let model, case .tab(let id) = model.state.closeTarget else {
            // Settings, or the main window with no tab open. Closing the main window quits the App.
            NSApp.keyWindow?.performClose(nil)
            return
        }
        Task { await model.closeTab(id) }
    }

    private func tabButton(_ title: String, number: Int) -> some View {
        Button(title) {
            guard let model, let id = model.state.tab(number: number) else { return }
            Task { await model.show(command: id) }
        }
        .keyboardShortcut(KeyEquivalent(Character(String(number))))
        .disabled(model?.state.tab(number: number) == nil)
    }
}
