# Carry for iOS

The thin half of Carry. It captures the three things iCloud does not carry to your Mac (Health, Location, a share-sheet inbox) and holds the single control surface: which sources the Mac reader covers. **The iCloud container is the whole backend.** Every write goes to `iCloud.app.carry.ios/Documents/` exactly as [`docs/DATA-CONTRACT.md`](../docs/DATA-CONTRACT.md) says; the Mac CLI reads it from `~/Library/Mobile Documents/iCloud~app~carry~ios/Documents/`. There is no Carry server.

Visuals follow [`docs/DESIGN.md`](../docs/DESIGN.md): paper/ink, serif titles, mono status lines, moss `via iCloud`, tangerine `via Carry app`, no gradients, no spinners.

## Layout

```
project.yml            xcodegen spec. The .xcodeproj is generated; never hand-edit it.
Carry.storekit         StoreKit configuration: one subscription, app.carry.pro, $5.99 / month.
Carry/                 The app (SwiftUI, iOS 17+, no third-party code)
  CarryApp.swift         entry, scene phases, BGTask registration
  AppModel.swift         one object behind every screen: container, sources.json, sync, delete
  ProStore.swift         StoreKit 2: price, purchase, restore, license.json
  BackgroundSync.swift   BGAppRefreshTask app.carry.ios.sync (hourly)
  Demo.swift             DEBUG demo data for screenshots (never touches a real iCloud container)
  LaunchOptions.swift    DEBUG launch arguments
  Screens/               Welcome, Sources, Home, Pro, Settings
CarryKit/              Shared by app and extension (compiled into both targets, not a framework)
  Models.swift           every JSON shape in the contract (sources, manifest, license, health, location, inbox, heartbeat)
  ContainerStore.swift   the iCloud container: NSFileCoordinator, append-only JSONL, replace-whole JSON
  InboxWriter.swift      inbox/<id>.json + JPEG (<= 2000 px) or file sibling
  Capture/               app only: HealthExporter (HealthKit), LocationRecorder (CoreLocation)
  UI.swift               the design system as SwiftUI components
  Links.swift            every URL, command and path the app quotes
CarryShare/            Share extension: custom sheet, "Send to my agent", writes inbox/
```

## Open and build

```bash
brew install xcodegen          # once
cd ios
xcodegen generate              # writes Carry.xcodeproj
open Carry.xcodeproj           # scheme "Carry" is wired to Carry.storekit
```

Command line, simulator, no signing:

```bash
xcodebuild -project Carry.xcodeproj -scheme Carry \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

**Requires Xcode 26.2 with the iOS 26.2 platform installed** (Xcode › Settings › Components, or `xcodebuild -downloadPlatform iOS`, about 8 GB). Without it xcodebuild finds no eligible destination and `actool` refuses the asset catalog (`No simulator runtime version ... available to use with iphonesimulator SDK version 23C53`). On a Mac that has only an older simulator runtime, this equivalent builds everything except the asset catalog (app icon and launch color), which is enough to run and screenshot:

```bash
xcodebuild -project Carry.xcodeproj -target Carry -configuration Debug -sdk iphonesimulator -arch arm64 \
  CODE_SIGNING_ALLOWED=NO SYMROOT="$PWD/build/Build/Products" OBJROOT="$PWD/build/Build/Intermediates.noindex" \
  EXCLUDED_SOURCE_FILE_NAMES='*.xcassets' build
```

## What the owner must do (Apple account)

1. **Team.** Put your Team ID in `project.yml` (`DEVELOPMENT_TEAM`), then `xcodegen generate`. Do not set it in Xcode; the project is regenerated.
2. **App IDs** in the developer portal: `app.carry.ios` and `app.carry.ios.share`, both with **iCloud** (CloudKit not needed; iCloud Documents) and **App Groups**; the app also with **HealthKit** (plus *Background Delivery*).
3. **iCloud container** `iCloud.app.carry.ios`: create it under Identifiers › iCloud Containers and assign it to both App IDs. The identifier is fixed by the data contract; the Mac CLI reads that exact folder.
4. **App Group** `group.app.carry`: create it and assign it to both App IDs. Anchors and capture times live in its UserDefaults.
5. **Xcode › Signing & Capabilities** should then show iCloud (CloudDocuments, container ticked), App Groups, HealthKit, Background Modes (location, fetch, processing) for Carry; iCloud + App Groups for CarryShare. All of this is already in the two `.entitlements` files and `Info.plist`; automatic signing just needs the portal to agree.
6. **App Store Connect.** Create the app, then *Subscriptions*: group "Carry Pro", one auto-renewable product `app.carry.pro`, 1 month, price tier for $5.99 (the site quotes `$5.99 / month`; `Carry.storekit` matches). Add one localization and a review screenshot. Sign the **Paid Apps** agreement or the product never leaves "Missing Metadata". Add a **sandbox tester** for device testing.
7. **Privacy.** App Privacy labels: Health & Fitness and Location are collected and *not linked to you / not used for tracking* (the app writes them to the user's own iCloud only). Provide a privacy policy URL; HealthKit apps are rejected without one. `NSHealthShareUsageDescription` and the two location strings are in `Carry/Info.plist`.
8. **TestFlight.** Product › Archive (Release), Distribute › App Store Connect, then add internal testers. The share extension ships inside the app; nothing extra to upload.
9. **Links.** `CarryKit/Links.swift` holds every URL the app opens (site, install page, source, privacy, terms, support, manage subscriptions). Point privacy/terms at real pages before review.

## DEBUG launch arguments

Debug builds accept these (release builds ignore them). Each one is also listed, disabled, under Scheme › Run › Arguments.

| Argument | Effect |
|---|---|
| `-carryScreen welcome\|sources\|home\|pro\|settings` | open that screen with demo data (heartbeat, health, location, inbox, a placeholder Pro price) |
| `-carryDemo 1` | demo data without picking a screen |
| `-carryICloudOff 1` | preview the "iCloud Drive is off for Carry" state |
| `-carryScroll bottom` | scroll the screen to its end after 0.8 s (lower-half screenshots) |
| `-carryE2E 1` | drive the REAL writers (sources.json with Messages on, two inbox items through InboxWriter, manifest, Sync now) so `scripts/e2e-sim.sh` can test the Mac CLI against this container. Verified 2026-09-08: CLI read it, OCR'd the inbox image, wrote the heartbeat, and Home showed "Mac read just now". |

```bash
xcrun simctl launch booted app.carry.ios -carryScreen home
xcrun simctl launch booted app.carry.ios -carryScreen sources -carryScroll bottom
xcrun simctl io booted screenshot home.png
xcrun simctl ui booted appearance dark
```

Demo data is written only into the DEBUG fallback folder (an iCloud container is never touched) and is reset on every demo launch. Screenshots from the last pass live in `~/Claude_Code/tmp/carry/ios-shots/` (`<screen>.png`, plus `home-dark.png`, `sources-dark.png`, `<screen>-bottom.png`).

## Simulator: what works and what does not

- **iCloud.** The simulator has no ubiquity container, so `ContainerStore.resolve()` returns nil. DEBUG builds fall back to `CarryContainer/Documents/` inside the app group container (so the app and the share extension see the same files); the Home screen labels it `simulator`. Release builds show the "iCloud Drive is off for Carry" screen instead of crashing. Find the fallback with `xcrun simctl get_app_container booted app.carry.ios groups`.
- **HealthKit.** Needs a signed build (Xcode run) for the entitlement; the `CODE_SIGNING_ALLOWED=NO` build reports `Missing com.apple.developer.healthkit entitlement` on Sync now, honestly, in the mono line. With a signed build, add samples in the simulator's Health app to see them exported. Background delivery and the hourly `BGAppRefreshTask` do not run in the simulator; trigger the task from the debugger: `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"app.carry.ios.sync"]`.
- **Location.** Features › Location simulates points (a point is written at most every 10 minutes); `CLVisit` never fires in the simulator, so visits need a real phone. Grant permission without the dialog: `xcrun simctl privacy booted grant location-always app.carry.ios`.
- **StoreKit.** The price loads only when Xcode injects `Carry.storekit` (run from Xcode). `xcrun simctl launch` has no such hook, so demo runs show a placeholder `$5.99 / month` and say so when tapped. Real purchases: sandbox tester on a device.
- **Share extension.** Works in the simulator (Safari › share › Carry). It writes into the same fallback folder, so the Home inbox row updates.

## Notes on the data contract

- Steps and active energy hourly buckets carry `src: "Health"` (HealthKit merges sources for sums; a per-source split would double count iPhone + Watch). Raw samples, sleep and workouts carry the real source name.
- The last two completed hours of buckets are re-read on every export because the Watch delivers late; the Mac dedupes by `(type, start, end, src)`, so a bucket can appear twice in a JSONL file with the newer line winning.
- A visit still in progress is written with `depart: null` and written again when it ends (same `arrive`/`lat`/`lon`, so the Mac upserts).
- `license.json` is written whenever the entitlement changes and on every launch while active; it is never deleted on lapse. The Mac applies the 3-day grace from the JWS itself.
- "Delete everything Carry wrote" removes every file, then re-creates the layout plus `sources.json` and `manifest.json` (no personal data), so the Mac keeps obeying the switches.
- `from_app` in inbox items is `null`: iOS does not tell share extensions which app invoked them.
