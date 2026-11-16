import AppKit
import DevDevCore
import SwiftTerm
import SwiftUI

/// Read-only output drawn by SwiftTerm: colours, scrollback, selection, copy and find.
/// Nothing typed here reaches the Process.
struct TerminalOutputView: NSViewRepresentable {
    let session: OutputSession
    let onResize: (_ columns: Int, _ rows: Int) -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onResize: onResize)
    }

    func makeNSView(context: Context) -> TerminalView {
        let options = TerminalOptions(scrollback: OutputBuffer.standardMaxLines)
        let view = TerminalView(frame: .zero, font: nil, options: options)
        view.terminalDelegate = context.coordinator
        // A program's mouse mode must not take over text selection.
        view.allowMouseReporting = false
        // No caret: there is nothing to type into.
        view.caretColor = .clear
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        Self.applyTheme(dark: colorScheme == .dark, to: view)
        context.coordinator.isDark = colorScheme == .dark
        session.attach { [weak view] data in
            view?.feed(byteArray: [UInt8](data)[...])
        }
        return view
    }

    func updateNSView(_ view: TerminalView, context: Context) {
        context.coordinator.onResize = onResize
        let isDark = colorScheme == .dark
        if context.coordinator.isDark != isDark {
            context.coordinator.isDark = isDark
            Self.applyTheme(dark: isDark, to: view)
        }
    }

    /// The Graphite terminal colours for the current appearance.
    private static func applyTheme(dark: Bool, to view: TerminalView) {
        let colors = Graphite.terminalColors(dark: dark)
        view.nativeBackgroundColor = colors.background
        view.nativeForegroundColor = colors.foreground
        view.selectedTextBackgroundColor = colors.selection
        view.layer?.backgroundColor = colors.background.cgColor
        view.installColors(colors.ansi.map(Self.terminalColor))
    }

    private static func terminalColor(_ color: NSColor) -> SwiftTerm.Color {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return SwiftTerm.Color(
            red8: UInt16(rgb.redComponent * 255), green8: UInt16(rgb.greenComponent * 255),
            blue8: UInt16(rgb.blueComponent * 255))
    }

    static func dismantleNSView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.session.detach()
    }

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        let session: OutputSession
        var onResize: (Int, Int) -> Void
        var isDark: Bool?

        init(session: OutputSession, onResize: @escaping (Int, Int) -> Void) {
            self.session = session
            self.onResize = onResize
        }

        /// The view's size in character cells goes to the Helper, which resizes the pseudo-terminal.
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onResize(newCols, newRows)
        }

        /// Keyboard input and terminal replies end here. Output is read-only.
        func send(source: TerminalView, data: ArraySlice<UInt8>) {}

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func bell(source: TerminalView) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        /// A Process may not write to the clipboard or read it.
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }

        func requestOpenLink(source: TerminalView, request: TerminalLinkRequest) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    }
}
