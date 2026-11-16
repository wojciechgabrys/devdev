import AppKit
import DevDevCore
import Observation
import SwiftUI

/// The menubar icon and its panel. What they show comes from `MenubarModel`; this only draws it.
@MainActor
final class StatusItemController {
    private let model: MenubarModel
    private let opener: AppOpener
    private var item: NSStatusItem?
    private var popover = NSPopover()

    init(model: MenubarModel, opener: AppOpener) {
        self.model = model
        self.opener = opener
        popover = MenubarPopover.make(
            MenubarPanelView(model: model, opener: opener, close: { [weak self] in self?.closePanel() }))
    }

    /// Shows or hides the icon now, then follows the model.
    func start() {
        update()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = model.showsIcon
            _ = model.panel.showsCrashBadge
        } onChange: {
            Task { @MainActor [weak self] in
                self?.update()
                self?.observe()
            }
        }
    }

    private func update() {
        guard model.showsIcon else {
            closePanel()
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        let item = self.item ?? makeItem()
        self.item = item
        item.button?.image = MenubarIcon.image(badge: model.panel.showsCrashBadge)
        item.button?.toolTip = model.panel.showsCrashBadge ? "devdev: a Command crashed" : "devdev"
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        return item
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePanel()
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func closePanel() {
        if popover.isShown { popover.performClose(nil) }
    }
}

/// The menubar icon, with a red dot while any Command is Crashed.
///
/// A server rack drawn on the pixel grid rather than the `server.rack` symbol. The symbol is 15pt
/// tall with its lines on half points, so on a 1x screen every edge fell between two pixels and the
/// icon looked blurred. Here every size and position is a whole point, and each 1pt stroke sits on a
/// half point, so it covers exactly one pixel at 1x and two at 2x.
enum MenubarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func image(badge: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            // Drawn at display time, so a badged icon follows the menu bar's light or dark look.
            (badge ? NSColor.labelColor : .black).set()
            drawRack()
            if badge {
                // Clear a 1pt ring first, so the dot stands apart from the top rack unit.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 11, y: 11, width: 8, height: 8)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12, y: 12, width: 6, height: 6)).fill()
            }
            return true
        }
        // A template lets the menu bar tint the icon. The badged one keeps its red.
        image.isTemplate = !badge
        image.accessibilityDescription = badge ? "devdev, a Command crashed" : "devdev"
        return image
    }

    /// Three rack units, 4pt tall with 1pt between them, each with a status light on the right.
    private static func drawRack() {
        for unit in 0..<3 {
            let bottom = CGFloat(2 + unit * 5)
            let outline = NSBezierPath(
                roundedRect: NSRect(x: 2.5, y: bottom + 0.5, width: 13, height: 3), xRadius: 1, yRadius: 1)
            outline.lineWidth = 1
            outline.stroke()
            NSRect(x: 12, y: bottom + 1, width: 2, height: 2).fill()
        }
    }
}

/// Opens the App this Helper belongs to: plain, or on one Command's output.
struct AppOpener {
    let flavor: BuildFlavor
    let appBundle: URL

    @MainActor
    func openApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appBundle, configuration: configuration) { _, _ in }
    }

    @MainActor
    func open(_ link: OpenLink) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [link.url(flavor: flavor)], withApplicationAt: appBundle, configuration: configuration
        ) { _, _ in }
    }
}
