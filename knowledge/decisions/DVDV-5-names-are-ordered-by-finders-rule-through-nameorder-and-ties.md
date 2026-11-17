---
type: decision
title: "Names are ordered by Finder's rule through NameOrder, and ties keep their place"
description: "NameOrder in Model.swift, built on localizedStandardCompare, is the only comparison that orders Projects and Commands, and equal names keep their relative order."
timestamp: "2026-11-17T20:03:34+00:00"
---

# Names are ordered by Finder's rule through NameOrder, and ties keep their place

`NameOrder` in `Packages/DevDevCore/Sources/DevDevCore/Model.swift` is the one rule. It calls `localizedStandardCompare`: case is ignored and numbers compare by value, so `worker 2` comes before `worker 10`. Both Projects and Commands use it. Nothing else may compare names for ordering.

Ties:

- Command names are already unique per Project, ignoring case, so Commands never tie.
- Projects may share a name. They keep their existing relative order. `NameOrder.sorted` falls back to the original position on a tie, so this does not depend on Swift's sort being stable.

## Why

The user chose Finder's order in shaping, because numbered names like `worker 2` and `worker 10` read wrong in plain text order. One shared rule keeps Projects and Commands consistent.

## Know this

`localizedStandardCompare` follows the current locale, so the exact order of some names can differ between Macs. This feature did not pin a locale.
