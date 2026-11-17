---
type: term
title: "Name order"
description: "The one order of Projects and Commands: by name, compared the way Finder compares file names."
timestamp: "2026-11-17T20:03:34+00:00"
---

# Name order

The order every list of Projects and Commands is in. Names compare with `NameOrder` (`localizedStandardCompare`): case is ignored and numbers compare by value, so `worker 2` comes before `worker 10`. Projects with equal names keep their relative order.

The Helper keeps the saved lists in name order. Readers show the order they are given. Start All and Restart All follow it.

It replaces the older "the user's order" for Commands. It is not the tab order, which is separate.

_Avoid_: the user's order, Command order, alphabetical order (plain alphabetical would put `worker 10` before `worker 2`)
