import AppKit
import SwiftUI
import Testing

@testable import DevDevCore

/// The menubar popover hangs right under the icon (DVDV-2).
@MainActor
@Suite struct MenubarPopoverTests {
    /// Shaped like the real panel: a capped scroll area, then the two menu rows.
    private struct PanelLike: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    Text("factory").padding(12)
                }
                .frame(maxHeight: 420)
                Divider()
                Text("Open DevDev").padding(10)
                Text("Stop All and Quit").padding(10)
            }
            .frame(width: 340)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @Test func thePopoverTopMeetsTheBottomOfItsAnchor() async throws {
        let screen = try #require(NSScreen.main).visibleFrame
        let window = NSWindow(
            contentRect: NSRect(x: screen.midX, y: screen.maxY - 40, width: 40, height: 22),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 22))
        window.contentView = anchor
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let popover = MenubarPopover.make(PanelLike())
        popover.behavior = .applicationDefined
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        defer { popover.close() }
        // Let SwiftUI lay the panel out and size its window.
        try await Task.sleep(for: .milliseconds(500))

        let anchorBottom = window.convertToScreen(anchor.convert(anchor.bounds, to: nil)).minY
        let popoverTop = try #require(popover.contentViewController?.view.window).frame.maxY
        // The arrow is part of the popover window, so its top sits at the anchor's bottom.
        #expect(abs(anchorBottom - popoverTop) < 2, "popover top \(popoverTop), anchor bottom \(anchorBottom)")
    }
}
