---
type: decision
title: "The Helper owns the one order of Projects and Commands; readers never sort"
description: "HelperEngine sorts the configuration on load and before every save, and every reader takes its order from the Helper's snapshot without sorting by itself."
timestamp: "2026-11-17T20:03:34+00:00"
---

# The Helper owns the one order of Projects and Commands; readers never sort

`HelperEngine` sorts the configuration in `init` and again in `commit`, with `Configuration.sortedByName()`. What is saved and what is served never differ in order.

No reader sorts or compares names for ordering: the Project tree, the menubar panel, Go to Command, the CLI and the MCP tools all show the snapshot's order. Start All and Restart All walk the same list, so they run in order of name.

Rules that follow:

- A new place that changes `configuration` must go through `commit`, or start from the already sorted configuration (as `updateSettings` does).
- After a `commit`, an index taken before it may point at another item. Read the item back by id. `renameProject` does this.
- A new reader must not sort. If it needs an order, it uses the snapshot's.
- Selection and tabs follow a Command by id, never by row position. Tab order is separate from this order.

## Why

One order everywhere was agreed in shaping. Sorting in one place means the App, the menubar panel, the CLI and agents cannot disagree, even when they are different builds. Sorting in each reader would repeat the rule in five places and let Start All differ from what the user sees.
