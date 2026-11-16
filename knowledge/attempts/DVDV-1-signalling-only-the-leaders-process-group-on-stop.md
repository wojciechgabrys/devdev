---
type: attempt
title: "Signalling only the leader's process group on Stop"
description: "Stopping a Process by signalling only its leader's group was dropped because interactive zsh moves jobs into other groups and ignores SIGTERM."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Signalling only the leader's process group on Stop

The first Stop sent SIGTERM and SIGKILL to the child's own process group. Through an interactive login zsh, each job gets its own process group and zsh ignores SIGTERM, so nothing stopped.

Stop now signals every process group in the session the Process leads. Do not go back to a single `killpg` on the leader.
