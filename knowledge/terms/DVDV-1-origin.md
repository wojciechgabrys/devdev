---
type: term
title: "Origin"
description: "Who or what caused a change to a Process: user, agent, autoRestart or fileChange."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Origin

Every request that changes Processes or configuration carries an origin.

- **user**: a click in the App or menubar.
- **agent**: an MCP tool call through `devdev mcp`.
- **autoRestart**: the Helper restarting a Crashed Command.
- **fileChange**: the Helper restarting a Running Command after watched files changed.

The last two are internal; only the Helper uses them. Notifications are chosen from the origin.

_Avoid_: source, actor, trigger
