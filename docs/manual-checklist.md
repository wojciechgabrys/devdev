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

## Phase 2: main window

SwiftTerm's build plug-in must be trusted once per Mac in Xcode before any build works (see item 2 in `docs/spike-results.md`).

- [ ] **`scripts/install.sh` installs the app and it opens.**
  1. Run `scripts/install.sh` from the repo root. It ends with `Installed /Applications/devdev.app`.
  2. `ls /Applications/devdev.app/Contents/Helpers` prints `devdevHelper.app`.
  3. Open `/Applications/devdev.app`. The main window shows three columns and no banner.
  4. Activity Monitor shows one `devdevHelper`. `ls ~/Library/Application\ Support/devdev/` shows `helper.sock`.
- [ ] **A real Laravel + Vite project can be added, started, read, restarted and stopped.**
  1. Click + under Projects and pick a Laravel project that has `npm run dev`. It appears in the sidebar, selected, with a grey dot.
  2. Click + in the toolbar. Add a Command named `Vite` with the command line `npm run dev`. Add a second one named `Server` with `php artisan serve`.
  3. Click Start All. Both rows read Running and the Project dot turns green.
  4. Select `Vite`. The Output column shows Vite's coloured start-up text, and new lines appear as they are printed.
  5. Scroll up, select text with the mouse, press <kbd>Cmd</kbd> + <kbd>C</kbd> and paste it elsewhere. Press <kbd>Cmd</kbd> + <kbd>F</kbd> and find a word. Type some letters into the output: nothing happens.
  6. Widen the window, then click Restart on `Vite`. A `── restarted HH:MM:SS ──` line appears below the old output, and the new output is laid out for the wider view.
  7. Click Stop on `Vite`. The row reads Stopped and the output ends with `── stopped ──`.
  8. Click Stop All. Every row reads Stopped and the Project dot turns grey.
- [ ] **Quitting and reopening the App keeps the same Processes and their earlier output.**
  1. Click Start All. Note the first lines of `Vite`'s output.
  2. Press <kbd>Cmd</kbd> + <kbd>Q</kbd>. Activity Monitor still shows `devdevHelper`, and `pgrep -fl vite` still prints a process.
  3. Open `/Applications/devdev.app` again. Both Commands read Running. `Vite`'s output starts with the lines you noted, and new lines still arrive.
  4. Close the window with the red button instead. The App quits and `pgrep -fl vite` still prints a process.
- [ ] **Adding and removing Projects by hand.**
  1. Drag a folder from Finder onto the window. It becomes a Project and is selected.
  2. Drag the same folder again. No second Project appears and the existing one is selected.
  3. Drag a file, not a folder. An alert says there is no folder at that path.
  4. Select a Project with a Running Command and click −. The question names the Project and says its Running Commands are stopped first. Confirm. The Project is gone and `pgrep` shows its Processes ended.
- [ ] **Editing, deleting and reordering Commands.**
  1. Start a Command. Right-click it, choose Edit…, change the command line and save. The row still reads Running and shows "restart to apply".
  2. Click Restart. The hint is gone and the new command line runs.
  3. Edit it again and fill every field: subfolder, one environment variable, both switches, one glob pattern. Save, reopen the form: every field kept its value.
  4. Add a Command with a name the Project already uses. The form stays open and an alert names the clash.
  5. Right-click a Running Command and choose Delete…. The question says it is stopped first. Confirm. The row is gone and its Process ended.
  6. Drag a Command to another place in the list. Quit and reopen the App: the order is kept.
- [ ] **Stop All and Quit ends everything.**
  1. Start two Commands. Choose devdev > Stop All and Quit.
  2. The App quits. Activity Monitor shows no `devdevHelper`, and `pgrep` shows no Process of either Command.
- [ ] **The outdated-Helper banner appears after a reinstall and never restarts by itself.**
  1. With the App open and one Command Running, change any line of Swift in `Helper/` and run `scripts/install.sh`. The Command keeps running while the script runs and after it.
  2. Quit the App with <kbd>Cmd</kbd> + <kbd>Q</kbd> and open `/Applications/devdev.app`. A banner says the Helper is outdated. The Command still reads Running, and Start and Stop still work.
  3. The button reads "Restart Helper (stops all Processes)". Click it. Every Command reads Stopped, the banner is gone, and Activity Monitor shows a `devdevHelper` with a new process ID.
- [ ] **A Helper that dies is shown, and can be started again.**
  1. Start a Command. In Activity Monitor, force quit `devdevHelper`.
  2. The window shows a banner that the Helper stopped. Every Command reads Stopped and the buttons are dimmed.
  3. Click Start Helper. The banner is gone and Start works again.
- [ ] **A Debug build keeps away from the installed app.**
  1. With `/Applications/devdev.app` open and a Command Running, run the `devdev` scheme from Xcode.
  2. The Debug window shows none of the installed app's Projects. Activity Monitor shows two `devdevHelper` processes.
  3. Choose Stop All and Quit in the Debug app. The installed app's Command still reads Running.
- [ ] **The Settings window opens.**
  1. Press <kbd>Cmd</kbd> + <kbd>,</kbd>. A Settings window opens. It is empty until later phases.
