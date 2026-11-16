---
type: decision
title: "Every Helper request carries an origin that drives notifications"
description: "Requests that change Processes carry an origin (user, agent, autoRestart, fileChange), and NotificationRule decides banners from it."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Every Helper request carries an origin that drives notifications

`Origin` in `Model.swift` has four cases. `user` and `agent` come from clients. `autoRestart` and `fileChange` are internal and only the Helper may use them. The MCP server always sends `agent`. The menubar and App send `user`.

`NotificationRule` (`Notifications.swift`) uses the origin:

- A user's own click sends no banner, except crashes, which always notify.
- Start All, Restart All and Stop All send one grouped notification per Project, which opens the first affected Command.
- Auto-restart sends one banner per crash ("Queue crashed (exit 1), auto-restarting"), no Started or Restarted banner, and one more when it pauses after 5 crashes in 60 s.
- Stop on a Crashed or Finished Command sets it to Stopped silently.

Notifications are posted by the Helper, so they work with the App closed. The poster is behind the `NotificationPoster` seam for tests.
