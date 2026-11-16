# Manual checklist

Checks that need a person at the Mac. None of them is verified until someone ticks it. Grouped by phase.

## Phase 1: core and Helper

- [ ] **The Debug Helper starts with no Dock icon and keeps to its own data folder.**
  1. Run `xcodebuild -project devdev.xcodeproj -scheme devdev -destination platform=macOS build`.
  2. Note the time. In Finder, open the built `devdev.app` (Show Package Contents), then `Contents/Helpers`, and double-click `devdevHelper.app`.
  3. No Dock icon appears. `ls -la ~/Library/Application\ Support/devdev-debug/` shows `helper.sock` and `helper.sock.lock`.
  4. `ls -la ~/Library/Application\ Support/devdev/` shows nothing changed after the time you noted, or the folder does not exist.
  5. Double-click `devdevHelper.app` again. Activity Monitor still shows one `devdevHelper`.
  6. Quit it from Activity Monitor.
- [ ] **A Command sees the same `PATH` as Terminal when the Helper was not started from a terminal.** Needs the main window (Phase 2).
  1. Start the Helper from Finder or by opening the App, not from a shell.
  2. Add a Project and a Command with the command line `which node php composer; node -v; php -v`.
  3. Start it. The output shows the same paths and versions as the same line typed in Terminal.
- [ ] **Stopping a real dev server leaves nothing behind.** Needs the main window (Phase 2).
  1. Start a Command with `npm run dev` in a Vite project.
  2. Run `pgrep -fl vite` and note the process.
  3. Stop the Command. Within 5 seconds `pgrep -fl vite` prints nothing, and the port is free.
- [ ] **A command line with two parts stops fully.** Needs the main window (Phase 2).
  1. Start a Command with `sleep 600; sleep 600`.
  2. Stop it. The status reads Stopped within about 5 seconds and `pgrep -fl "sleep 600"` prints nothing.
