---
type: feature
title: "Fix menubar menu rendering too low"
description: "Fixed the menubar panel opening about 217 points below the Helper's menubar icon, so it now hangs right under the icon."
timestamp: "2026-11-16T18:04:59+00:00"
---

# Fix menubar menu rendering too low

The Helper's menubar panel (an `NSPopover` holding the SwiftUI `MenubarPanelView`) opened more than 200 points below its status item icon.

## Cause

`NSHostingController`'s default `sizingOptions` let the SwiftUI hosting view resize the popover's window directly. AppKit keeps a window's bottom edge when it resizes it, so as the panel grew to its content height its top edge dropped away from the icon. A standalone harness measured the popover top at 873 against an anchor bottom of 1090, a 217 pt gap.

## Fix

- `Packages/DevDevCore/Sources/DevDevCore/MenubarPopover.swift`: new `MenubarPopover.make(_:)` builds the popover (`.transient`, no animation) and sets `host.sizingOptions = .preferredContentSize`, so NSPopover sizes and anchors itself from the content's preferred size.
- `Helper/StatusItemController.swift`: builds its popover through `MenubarPopover.make` instead of inline. Popover construction moved into DevDevCore to give it a test seam.
- `Packages/DevDevCore/Tests/DevDevCoreTests/MenubarPopoverTests.swift`: shows the popover under a borderless anchor window near the top of the screen with a panel-shaped view (capped scroll area plus two rows), waits 500 ms for layout, and checks that the popover window's top is within 2 pt of the anchor's bottom. It failed before the fix (883 vs 1090) and passes after.

## Side fix

`BuildRecordTests.gitHistoryHasOneCommitPerPhaseInSpecOrderAfterAtMostOneSpikeCommit` failed on any branch cut from main, because the DVDV-1 phase commits were squash-merged (e0fa409). It now reads the build's commit subjects from the squash commit's `* subject` body lines when the branch does not hold the Phase 1 commit, dropping the pre-build skeleton commit. The assertions are unchanged.

Branch: `factory/DVDV-2-menubars-menu-is-rendered-over-200px-too`

## Related

### Decisions

- [SwiftUI content in an NSPopover uses preferredContentSize sizing](../decisions/DVDV-2-swiftui-content-in-an-nspopover-uses-preferredcontentsize-si.md)
- [Build-history tests read squash-merged builds from the squash commit body](../decisions/DVDV-2-build-history-tests-read-squash-merged-builds-from-the-squas.md)

### Attempts dropped

- [Default NSHostingController sizing for the menubar popover](../attempts/DVDV-2-default-nshostingcontroller-sizing-for-the-menubar-popover.md)
