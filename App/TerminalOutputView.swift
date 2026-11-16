import AppKit
import DevDevCore
import SwiftTerm
import SwiftUI

/// Read-only output drawn by SwiftTerm: colours, scrollback, selection, copy and find.
/// Nothing typed here reaches the Process.
struct TerminalOutputView: NSViewRepresentable {
    let session: OutputSession
    let onResize: (_ columns: Int, _ rows: Int) -> Void

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
        session.attach { [weak view] data in
            view?.feed(byteArray: [UInt8](data)[...])
        }
        return view
    }

    func updateNSView(_ view: TerminalView, context: Context) {
        context.coordinator.onResize = onResize
    }

    static func dismantleNSView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.session.detach()
    }

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        let session: OutputSession
        var onResize: (Int, Int) -> Void

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
