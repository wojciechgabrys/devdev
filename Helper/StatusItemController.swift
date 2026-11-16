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
enum MenubarIcon {
    static func image(badge: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let base =
            NSImage(systemSymbolName: "server.rack", accessibilityDescription: "devdev")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        guard badge else {
            base.isTemplate = true
            return base
        }
        let size = NSSize(width: max(base.size.width, 18), height: max(base.size.height, 18))
        let image = NSImage(size: size, flipped: false) { rect in
            // Drawn at display time, so the icon follows the menu bar's light or dark look.
            let iconRect = NSRect(
                x: (rect.width - base.size.width) / 2, y: (rect.height - base.size.height) / 2,
                width: base.size.width, height: base.size.height)
            base.draw(in: iconRect)
            NSColor.labelColor.set()
            iconRect.fill(using: .sourceAtop)
            let dot = NSRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 7, height: 7)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "devdev, a Command crashed"
        return image
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
