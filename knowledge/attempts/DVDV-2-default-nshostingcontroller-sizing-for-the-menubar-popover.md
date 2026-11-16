---
type: attempt
title: "Default NSHostingController sizing for the menubar popover"
description: "Letting NSHostingController keep its default sizingOptions inside the menubar NSPopover was dropped because the popover opened about 217 pt below the icon."
timestamp: "2026-11-16T18:04:59+00:00"
---

# Default NSHostingController sizing for the menubar popover

DVDV-1 put `MenubarPanelView` in an `NSPopover` through a plain `NSHostingController` with default `sizingOptions`.

The hosting view then resized the popover's window directly. AppKit keeps the bottom edge when it resizes a window, so the top fell away from the status item. A standalone harness measured the popover top at 873 against an anchor bottom of 1090. The unit test saw 883 vs 1090.

Setting `sizingOptions = .preferredContentSize` closed the gap to 0. Do not go back to the default sizing for a popover that hosts SwiftUI.
