import AppKit
import SwiftUI

/// The popover that holds the menubar panel.
public enum MenubarPopover {
    /// A popover showing `content`, closed when the user clicks elsewhere.
    @MainActor
    public static func make<Content: View>(_ content: Content) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        let host = NSHostingController(rootView: content)
        // The popover must size itself from the content. Left at the default, the hosting
        // view resizes the popover's window directly, which keeps the window's bottom edge
        // and drops its top more than 200 points below the icon (DVDV-2).
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        return popover
    }
}
