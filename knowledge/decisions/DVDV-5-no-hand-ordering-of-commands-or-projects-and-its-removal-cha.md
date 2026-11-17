---
type: decision
title: "No hand ordering of Commands or Projects, and its removal changed no version"
description: "Move Up, Move Down and the moveCommand request were removed with no replacement, no setting, and no bump of the protocol or configuration version."
timestamp: "2026-11-17T20:03:34+00:00"
---

# No hand ordering of Commands or Projects, and its removal changed no version

There is no way to order Commands or Projects by hand, and no setting or per-Project option to turn sorting off. `moveCommand`, `HelperEngine.moveCommand`, `WindowModel.moveCommand` and `CommandMove` are gone. A later feature that wants a custom order reverses an agreed choice and must be asked for, not slipped in.

Versions:

- `HelperProtocol.version` stays 1. Removing a request does not stop an older program from reading any message: a new App simply never sends `moveCommand`.
- `Configuration.currentVersion` stays 1. The file shape did not change; only the order inside it.

Upgrade behaviour:

- An old configuration is sorted when the Helper loads it. Hand-set orders are lost. This was accepted in shaping.
- The file on disk is rewritten sorted at the next change, not at load.
- An Outdated Helper keeps showing its own saved order until it restarts. This was accepted.

Tab order is not part of this decision. It belongs to the tab strip.
