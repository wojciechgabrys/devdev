---
type: decision
title: "Tab order is App state only, changes live during a drag, and is not saved"
description: "The order of output tabs lives only in WindowState.tabs in memory, is changed on every new place during a drag, and is never sent to the Helper or saved."
timestamp: "2026-11-17T20:12:24+00:00"
---

# Tab order is App state only, changes live during a drag, and is not saved

The tab order is `WindowState.tabs`. The only way to change it is `WindowState.moveTab(_:to:)`, called through `WindowModel.moveTab(_:to:)`.

- **No Helper message.** Tab order is window state. The Helper, the socket protocol, the CLI and the MCP tools know nothing about it.
- **No persistence.** The order lasts until the App quits, like the tabs themselves. Saving tabs across launches was put out of scope by the user.
- **Live change.** The state order changes each time the dragged tab takes a new place, not at the drop. So the strip, the shortcuts and the Window menu always agree, also in the middle of a drag.
- **Esc uses the same mutation.** Cancel moves the tab back to its starting place with `moveTab`. If tabs were closed during the drag, the model clamps the place.
- **Only `tabs` changes.** A move never touches the selected Command or Project.

New tabs still open at the right end. Closing the selected tab still selects its neighbour by the current order.

A later feature that wants saved tab order must add persistence on purpose. It should not assume the order survives a launch.
