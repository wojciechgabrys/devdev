---
type: decision
title: "MCP tools match names case-insensitively and wait before answering starts"
description: "MCP finds Projects and Commands by name without regard to case, defaults to the Project holding the working directory, and waits about 1 s after start or restart."
timestamp: "2026-11-16T16:45:32+00:00"
---

# MCP tools match names case-insensitively and wait before answering starts

Rules for `MCPTools.swift`:

- Names match without regard to letter case. A miss returns a sentence listing the available names.
- A call without `project` uses the Project whose folder holds the working directory.
- After a start or restart, the tool waits about 1 s before answering, so an immediate crash reads as Crashed. The wait is injectable for tests.
- A single Restart on a Command that is not Running starts it (also for the App button). Only Restart All skips Stopped, Finished and Crashed Commands.
- The CLI starts the Helper of its own flavor with `open -g` when none runs.
