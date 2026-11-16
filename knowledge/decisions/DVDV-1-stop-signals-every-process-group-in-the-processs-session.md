---
type: decision
title: "Stop signals every process group in the Process's session"
description: "Stopping a Process sends SIGTERM then SIGKILL to every process group in the session the child leads, not just the leader's group."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Stop signals every process group in the Process's session

Each Process leads its own session on a pseudo-terminal. Stop sends SIGTERM to every process group found in that session, then SIGKILL after an injectable escalation time if anything still lives (`PTYProcess.swift`).

## Why

Commands run through the user's interactive login shell. An interactive zsh puts each job in its own process group and ignores SIGTERM. Signalling only the leader's group stopped nothing. A test covers a job in another process group.

Keep this when touching the process runner: a two-part command line (`a && b`, pipes) must stop fully.
