---
type: decision
title: "SwiftUI content in an NSPopover uses preferredContentSize sizing"
description: "Any NSHostingController placed in an NSPopover sets sizingOptions to .preferredContentSize, and the menubar popover is built only through MenubarPopover.make."
timestamp: "2026-11-16T18:04:59+00:00"
---

# SwiftUI content in an NSPopover uses preferredContentSize sizing

The menubar panel's `NSHostingController` sets `sizingOptions = .preferredContentSize`. The popover then sizes and anchors itself from the content's preferred size.

Left at the default, the hosting view resizes the popover's window directly. AppKit keeps the window's bottom edge on that resize, so the popover's top drops away from its anchor. For the menubar panel the gap was about 217 pt (DVDV-2).

Rules for later work:

- Build the menubar popover with `MenubarPopover.make(_:)` in DevDevCore, not inline in `Helper/StatusItemController.swift`. It holds the sizing setting and is the test seam.
- Any other popover hosting SwiftUI should set the same sizing option.
- `MenubarPopoverTests` guards the anchor: the popover window's top must sit within 2 pt of the anchor's bottom.
