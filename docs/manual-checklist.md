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
  1. Press <kbd>Cmd</kbd> + <kbd>,</kbd>. A Settings window opens. Phase 3 adds its first two switches.

## Phase 3: menubar panel

Run every check here with the App closed, unless a step says to open it. Install first with `scripts/install.sh`, and use a Project with two Commands: `Vite` (`npm run dev`) and `Fails` (`sleep 2; exit 3`).

- [ ] **The menubar icon appears with the Helper and stays after the App quits.**
  1. Open `/Applications/devdev.app`, then press <kbd>Cmd</kbd> + <kbd>Q</kbd>.
  2. The devdev icon is still in the menu bar. Activity Monitor shows `devdevHelper` and no `devdev`.
- [ ] **The panel lists each Project with its status and Start All, Restart All, Stop All.**
  1. Click the menubar icon. A panel opens with one row per Project: name, coloured dot, status word and three buttons.
  2. Click Start All on the Project. The dot turns green and the status reads Running.
  3. Click Restart All. The row reads Running again. In the App later, `Vite`'s output shows a `── restarted HH:MM:SS ──` line.
  4. Click Stop All. The dot turns grey and the status reads Stopped. `pgrep -fl vite` prints nothing.
- [ ] **Expanding a Project shows its Commands with status and Start, Restart, Stop.**
  1. Click the Project's name or its arrow. Its Commands appear below it, in the App's order, each with a dot and a status.
  2. Click Start on `Vite`. It reads Running, and the Project reads Partly Running if `Fails` is included in Start All.
  3. Click Restart on `Vite`, then Stop. It reads Running, then Stopped.
  4. Click the Project's name again. The Commands are hidden.
- [ ] **The panel shows no output.**
  1. With `Vite` Running, open the panel. No output text appears anywhere in it.
- [ ] **Clicking a Command's name opens the App on that Command's output.**
  1. With the App closed, open the panel and click `Vite`'s name.
  2. The App opens with `Vite` selected and its output showing.
  3. In the App select the other Command. Open the panel and click `Vite` again. The App comes forward and `Vite` is selected again.
- [ ] **Open devdev launches or focuses the App.**
  1. With the App closed, click Open devdev at the bottom of the panel. The App opens.
  2. Click on another app's window, then click Open devdev again. The same devdev window comes forward and no second one opens.
- [ ] **A crash puts a badge on the icon, and Stop All clears it.**
  1. Click Start on `Fails`. After about 2 seconds it reads Crashed (exit code 3) and the icon shows a red dot.
  2. Check the icon in both the light and the dark menu bar (System Settings > Appearance). The icon itself stays readable.
  3. Click Stop All on the Project. The red dot is gone.
- [ ] **Stop All and Quit in the panel ends everything.**
  1. Start both Commands from the panel. Click Stop All and Quit.
  2. The icon is gone. Activity Monitor shows no `devdevHelper`, and `pgrep -fl vite` prints nothing.
- [ ] **Show menubar icon off keeps the Helper running without an icon.**
  1. Open the App, press <kbd>Cmd</kbd> + <kbd>,</kbd>. Show menubar icon is on and Launch at login is off.
  2. Start `Vite`. Turn Show menubar icon off. The icon disappears at once.
  3. Quit the App with <kbd>Cmd</kbd> + <kbd>Q</kbd>. Activity Monitor still shows `devdevHelper`, and `pgrep -fl vite` still prints a process.
  4. Open the App and turn the switch back on. The icon comes back. Quit the App and open it again: the switch kept its value.
- [ ] **Launch at login starts the Helper only, after a real logout and login.**
  1. In Settings turn Launch at login on. `cat ~/Library/LaunchAgents/dev.devdev.helper.plist` shows `RunAtLoad` and the path `/Applications/devdev.app/Contents/Helpers/devdevHelper.app/Contents/MacOS/devdevHelper`, and no `KeepAlive`.
  2. Turning it on did not start a second Helper: Activity Monitor shows one `devdevHelper`.
  3. Start `Vite`, then choose Stop All and Quit in the panel.
  4. Log out of macOS and log back in. Do not open the App.
  5. The devdev icon is in the menu bar and Activity Monitor shows one `devdevHelper`. The panel shows every Command as Stopped, and `pgrep -fl vite` prints nothing.
  6. Note whether macOS showed a "Background Items Added" notice, and whether devdev is listed under System Settings > General > Login Items.
  7. Turn Launch at login off. The file is gone and the running Helper keeps running. Log out and in again: no `devdevHelper` starts.
- [ ] **The login item survives a reinstall.**
  1. Turn Launch at login on. Change any line of Swift in `Helper/` and run `scripts/install.sh`.
  2. Choose Stop All and Quit in the panel. Log out and log back in.
  3. The new Helper starts: the icon is there, and opening the App shows no outdated-Helper banner.


## Phase 4: notifications

Install first with `scripts/install.sh`. Use a Project named `shop` with three Commands: `Vite` (`npm run dev`), `Queue` (`while :; do sleep 1; done`) and `Fails` (`sleep 2; exit 1`). Only `Vite` and `Queue` are included in Start All. Quit the App between checks unless a step says to open it.

- [ ] **The first start asks for notification permission, and Allow leads to banners.**
  1. Open `/Applications/devdev.app` on a Mac where devdev never ran. Note whether macOS asks whether `devdevHelper` may send notifications.
  2. Click Allow. System Settings > Notifications lists `devdevHelper` with Allow notifications on and the style Banners.
  3. If no prompt appeared, turn notifications on there by hand, and note that the prompt never showed.
- [ ] **A user click shows no banner.**
  1. In the App or the menubar panel, click Start, Restart and Stop on `Queue`, then Start All, Restart All and Stop All on `shop`.
  2. No banner appears for any of them, and Notification Centre lists nothing new from devdev.
- [ ] **A crash shows one banner, even after a user click.**
  1. Click Start on `Fails`. After about 2 seconds exactly one banner appears: title `shop`, text `Fails crashed (exit 1)`.
  2. Click Stop on `Fails`. It reads Stopped and no banner appears.
- [ ] **Start All from an agent shows exactly one banner.**
  1. With every Command Stopped, run this in Terminal. Press <kbd>Ctrl</kbd> + <kbd>C</kbd> once the answer is printed, and copy `shop`'s `id` from it:
     `echo '{"id":1,"request":{"snapshot":{}}}' | nc -U ~/Library/Application\ Support/devdev/helper.sock`
  2. Run the same way, with that ID: `echo '{"id":2,"origin":"agent","request":{"startAll":{"projectID":"<ID>"}}}' | nc -U ~/Library/Application\ Support/devdev/helper.sock`
  3. Exactly one banner appears: `Start All by an agent: Vite and Queue started`. Phase 7 replaces these steps with the MCP tool `start_all`.
  4. Run it again with `stopAll` in place of `startAll`. Exactly one banner appears: `Stop All by an agent: Vite and Queue stopped`.
- [ ] **Clicking a banner opens the App on that Command's output.**
  1. With the App closed, click Start on `Fails` in the menubar panel and wait for the crash banner.
  2. Click the banner. The App opens with `Fails` selected and its output showing, ending with the exit line.
  3. Select another Command in the App, crash `Fails` again and click the new banner. The App comes forward with `Fails` selected again.
  4. Repeat once with the banner clicked from Notification Centre after it went away.
- [ ] **Each notification switch turns its kind off.**
  1. Press <kbd>Cmd</kbd> + <kbd>,</kbd>. Under Notifications, Crashed, Started, Restarted and Stopped or Finished are all on.
  2. Turn Crashed off. Start `Fails`: no banner after it crashes. Turn Crashed back on.
  3. Quit the App and open it again. Every switch kept its value.
- [ ] **Notification permission survives a reinstall.**
  1. With notifications allowed, change any line of Swift in `Helper/` and run `scripts/install.sh`.
  2. Choose Stop All and Quit in the panel, then open `/Applications/devdev.app`.
  3. Start `Fails`. Note whether the crash banner appears without a new prompt, and whether System Settings > Notifications still shows `devdevHelper` allowed.

## Phase 5: auto-restart and restart when files change

- [ ] **A crashing Command with auto-restart on restarts after about 1 second, and pauses after 5 crashes.**
  1. Add a Command named `Flaky` with the command line `echo up; sleep 3; exit 1`. In its edit form turn Auto-restart on and save. Reopen the form: the switch is still on.
  2. Click Start. After about 3 seconds one banner appears: `Flaky crashed (exit 1), auto-restarting`. About 1 second later the row reads Running again, and the output shows `── restarted HH:MM:SS ──`. No Started or Restarted banner appears.
  3. Wait. After the fifth crash, two banners appear: `Flaky crashed (exit 1)` and `Flaky auto-restart paused after 5 crashes`. The row stays Crashed and the menubar icon shows the crash badge.
  4. Click Start. It runs and crashes again, and auto-restart works again for 5 more crashes.
  5. During one of the 1 second waits, click Stop. The row reads Stopped and nothing restarts.
- [ ] **A saved file restarts a Running dev server once.**
  1. In a Laravel project, edit the `Server` Command (`php artisan serve`). Under Restart when files change, type `app/**/*.php` and `routes/*.php` on two lines. Save, reopen the form: both lines are kept.
  2. Start `Server`. In your editor, save a file under `app/Models/`. About half a second later the output shows one `── restarted HH:MM:SS ──` line, and one banner says `Server restarted, files changed`.
  3. Save all open files at once in your editor. Exactly one more restart line appears.
  4. Save a file under `resources/`. Nothing restarts.
  5. Stop `Server`, then save a file under `app/`. It stays Stopped.
