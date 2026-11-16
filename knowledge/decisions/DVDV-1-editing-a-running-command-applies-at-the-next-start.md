---
type: decision
title: "Editing a Running Command applies at the next start"
description: "Edits to a Running Command save at once and show a restart-to-apply hint; nothing restarts by itself."
timestamp: "2026-11-16T16:45:32+00:00"
---

# Editing a Running Command applies at the next start

When a Running Command is edited, the change is saved at once and applies at the next start. The row shows a small "restart to apply" hint until then. Nothing restarts automatically.

Deleting a Running Command asks for confirmation, then stops it, like deleting a Project.

Stop on a Crashed or Finished Command sets it to Stopped with no notification. Stop All does that for the whole Project and so clears the menubar crash badge.
