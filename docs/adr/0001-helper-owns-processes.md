# A background Helper owns every Process

Processes must keep running when the app quits, including when the app is rebuilt from Xcode, and their output must not be lost in the gap. So a separate background program, the Helper, starts every Process, holds its terminal and keeps its output; the main window, the menubar icon and the MCP tool are all clients of it. We rejected running Processes inside the app (quitting kills them) and leaving them orphaned to be found again by ID (output during the gap is lost, and nothing can restart them or send notifications while the app is closed).

## Consequences

- The menubar icon and notifications belong to the Helper, not to the app, so they work while the app is closed.
- "Quit" leaves the Helper and all Processes running. "Stop All and Quit" stops every Process and the Helper.
- The app and the Helper can be different builds at the same moment, so they need a versioned protocol between them.
