# Carry for Mac

The menu bar face of the `carry` CLI. A luggage tag in the menu bar, one window, no Dock icon. It exists for one reason: **Full Disk Access**.

macOS only lets the *user* grant Full Disk Access, in System Settings, and it attributes file access to the process that launchd or the user started. The CLI's own LaunchAgent runs a bare Python interpreter, so granting it means adding an ugly interpreter path to the FDA list, and it changes every time `uv` reinstalls the tool. With this app the user flips one switch for "Carry", once. Every `carry sync` the app spawns is a child of the app, and macOS attributes the child's reads to the app, so the grant is inherited. The app then replaces the LaunchAgent as the scheduler and shows what is going on.

The CLI stays the engine. The app never reads a database itself; it runs `carry` and renders the answers.

## What it does

- **Status**: `carry status --json` every minute and after every sync. Title, mono status line (`Last sync 00:42 · photos 252 · screenshots 95 · Pro`), the twelve sources with channel badges (`via iCloud` in moss, `via Carry app` in tangerine), item counts, per-source errors, the iPhone that last wrote to the iCloud container, Pro state and reason.
- **Sync**: `carry sync --quiet` at launch, after wake (`NSWorkspace.didWakeNotification`), every 5 / 15 / 30 / 60 minutes (default 15, stored in UserDefaults), and on "Sync now". Never two at once. While one runs the menu bar tag shows a dot and the status line reads `Syncing… since 00:41`. Each run's exit code and the last 20 lines of output go to `~/.carry/logs/app.log`.
- **Sources**: toggles call `carry sources <name> --on|--off`. When the iPhone app's `sources.json` is present (`decided_by == "phone"`) the toggles are disabled and the card says so; the phone wins, as the data contract says.
- **Run at login**: `SMAppService.mainApp.register()` / `unregister()`, reflecting `.status`; if macOS wants approval, the footer says so and links to Login Items.
- **Open context folder**: reveals `~/.carry/context/` in Finder.
- **Menu bar menu**: status line, Sync now, Open Carry, Open context folder, Quit.

Everything the user sees says what is read, where it goes, and who sees it. The window's first lines: *Read: the sources switched on below. Goes to: ~/.carry/context/ on this Mac. Seen by: the agents you point at it. Nobody else. There is no Carry server.*

## The Full Disk Access flow

Detection is a real read attempt: `open(2)` on `~/Library/Messages/chat.db`. `EPERM` means not granted; `ENOENT` (never used Messages) falls back to `~/Library/Safari/History.db`; if that does not exist either there is nothing to protect and it counts as granted. The CLI does the same check in its own process and reports it as `fda` in the status JSON.

"Grant in System Settings":

1. performs that read attempt first, which is what makes macOS list "Carry" in the Full Disk Access pane;
2. opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`;
3. polls every 2 seconds. macOS applies a new grant to processes started afterwards and may keep the running app's own verdict cached until relaunch, so the poll asks both: the in-process probe and a fresh `carry status --json` child. As soon as either says yes the card shows the moss check, a sync runs, and the CLI's LaunchAgent (if still installed) is removed with `carry agent uninstall`.

Why it must be a user action: TCC has no API to grant Full Disk Access. Any app that could flip the switch would defeat the switch. So the copy is honest: *One switch, once. macOS doesn't let any app flip it for you.* And it says what works without it: Photos, Screenshots, and everything from the iPhone.

## How the app and the CLI's LaunchAgent coexist

`~/.carry/app.json` is the handshake:

```json
{"pid": 123, "version": "0.1.0", "last_seen": "2026-09-08T00:40:00+08:00"}
```

- The app writes it at launch and every minute, and deletes it on quit. The CLI treats it as stale after 3 minutes or when the pid is gone.
- `carry init` sees it and does not install the LaunchAgent ("Carry for Mac is running and will schedule the sync itself"). `carry status` reports `app_running` and names the scheduler.
- When the app starts and finds `agent_installed: true`, it runs `carry agent uninstall` once and logs it. While the app runs, it is the scheduler. If the app is quit and Run at login is off, nothing syncs in the background; run `carry agent install` to go back to the LaunchAgent, or turn Run at login on.
- If the agent's plist carried the developer override `CARRY_PRO=1`, the app keeps it (`defaults write app.carry.mac CARRY_PRO 1`) and passes it to every `carry` it runs, so Pro processing does not silently stop. `defaults delete app.carry.mac CARRY_PRO` turns it off.

Children get `PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:~/.local/bin` and the inherited `HOME`; no shell is involved. The executable is looked up at `~/.local/bin/carry`, `/opt/homebrew/bin/carry`, `/usr/local/bin/carry`, then `PATH`. If it is missing, the window shows `uv tool install carry-context` with a Copy button and looks again every 5 seconds. If `carry status --json` is not understood, it shows the upgrade command instead.

## Build and run

Requirements: Xcode 26 (SwiftUI, macOS 14+), [xcodegen](https://github.com/yonaskolb/XcodeGen). No third-party dependencies.

```bash
cd mac
xcodegen generate
xcodebuild -project CarryMac.xcodeproj -scheme Carry -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/Carry.app
```

The window opens on the first launch ever and whenever something needs the user (no `carry`, no Full Disk Access); otherwise the app sits in the menu bar and "Open Carry" brings the window.

DEBUG-only launch arguments (see `project.yml`), used for screenshots: `-carryAppearance dark`, `-carryPreview 1` (renders the ungranted FDA card and a sample iPhone), `-carrySnapshot /path.png` (writes the window content 3 s after launch, or `-carrySnapshotDelay N`), `-carryScroll bottom`.

Files: `Carry/CarryApp.swift` (entry, MenuBarExtra, AppDelegate), `AppModel.swift` (state, scheduler, FDA flow, actions), `CarryCLI.swift` (finding and running `carry`), `Models.swift` (JSON shapes), `Support.swift` (presence file, log, FDA probe, heartbeat, LaunchAgent plist, links), `MainWindow.swift`, `MainView.swift` (the sections), `MenuContent.swift`, `MenuBarIcon.swift`, `Theme.swift` and `UI.swift` (the design system from `docs/DESIGN.md`, mirroring `ios/CarryKit/UI.swift`).

## Signing, notarization, distribution

The project leaves `DEVELOPMENT_TEAM` empty and hardened runtime off so it builds anywhere. Before handing the app to anyone:

1. **Developer ID**. Set `DEVELOPMENT_TEAM` in `project.yml`, sign with a Developer ID Application certificate. This matters beyond Gatekeeper: TCC keys the Full Disk Access grant to the app's code signature (designated requirement). A stable Developer ID identity keeps the grant across updates; ad-hoc or unsigned builds can lose it when the binary changes, and the user has to flip the switch again.
2. **Hardened runtime**. Set `ENABLE_HARDENED_RUNTIME: YES`. The app needs no entitlements beyond that: it is not sandboxed (it must read `~/.carry`, run `~/.local/bin/carry`, and probe `~/Library/Messages/chat.db`), and `SMAppService.mainApp` needs none.
3. **Notarize and staple**.
   ```bash
   xcodebuild -project CarryMac.xcodeproj -scheme Carry -configuration Release -derivedDataPath build build
   ditto -c -k --keepParent build/Build/Products/Release/Carry.app Carry.zip
   xcrun notarytool submit Carry.zip --keychain-profile "AC_PASSWORD" --wait
   xcrun stapler staple build/Build/Products/Release/Carry.app
   ```
4. Ship as a zip or a DMG. Keep `LSUIElement` true; the Dock stays empty on purpose.

No App Store: Full Disk Access and running a user-installed CLI are outside the sandbox.
