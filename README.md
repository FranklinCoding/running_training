# Reach

An iOS app that records where you go in New York and paints it onto an
"explored" map, plus (later) a walk-and-transit range map ported from
`reference/reach.html`. Everything stays on the device: no accounts, servers
or analytics.

**Status: Phase 1:** background recording and a plain explored map.

## Getting it running

You need a Mac with Xcode 15.3 or later (iOS 17 SDK) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open Reach.xcodeproj
```

Then in Xcode:

1. Select the **Reach** target, open **Signing & Capabilities** and pick your Team.
   A free Apple ID works for running on your own iPhone (see below).
2. Change the bundle identifier from `com.example.reach.app` to something of your
   own (or edit `bundleIdPrefix` / `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`).
3. Run on a simulator or your iPhone.

`Reach.xcodeproj` is generated and git-ignored; edit `project.yml` instead and
re-run `xcodegen generate` after adding or removing files.

## Tests

The logic lives in `ReachCore`, a Swift package with no Apple-only imports, so
its tests run anywhere Swift does:

```bash
cd ReachCore && swift test
```

Or open `ReachCore/Package.swift` in Xcode and press ⌘U.

Covered so far: H3 cell maths, the fix filter, coverage tracing (including not
drawing across subway GPS gaps), the packed point format, GPX parsing, and the
tracking state machine, including a replay of a walk–stop–walk GPX file.

## Simulating walks

GPX files live in `Reach/Simulation` (copies used by the tests are in
`ReachCore/Tests/ReachCoreTests/Fixtures`). Regenerate both with:

```bash
python3 tools/gpx/make_gpx.py
```

The Reach scheme plays `WalkBarclaysToGrandArmyPlaza.gpx` by default. To use
another one, open **Debug › Simulate Location** while the app is running in the simulator.

The simulator plays back locations only. It has no Core Motion, no geofence
or visit wakeups, no real GPS dropouts and no battery, so it shows the map and
screens working, not the battery-saving logic. The unit tests cover that logic.

## What needs a real iPhone or a paid developer account

| Needs | Why |
| --- | --- |
| Real iPhone | Background recording, wakeups after iOS suspends or kills the app (geofence exit, visits, significant changes), Core Motion, GPS loss underground, battery measurement, and how the Always permission prompts actually behave. |
| Paid account ($99/yr) | TestFlight and the App Store. With a free Apple ID the app runs on your phone but stops launching after 7 days until you run it from Xcode again (your data survives reinstalling over the top). |
| Neither | Everything in `ReachCore` and its tests; the UI in the simulator. |

To test recording on a phone: install, finish onboarding with Always + Motion,
then carry it for a day. The **Recording** tab shows the state changes
(GPS on/off), with battery level at each one, and today's raw track.

## How recording works

`ReachCore/Sources/ReachCore/Recording/TrackingPolicy.swift` is the state machine:

- **Moving**: continuous GPS (best accuracy and a 5 m filter on foot; 10 m accuracy and a 20 m filter in a vehicle, per Core Motion).
- **Stationary**: after 3 minutes within ~40 m of one spot (and no movement from
  Core Motion in the last minute), GPS turns off and a 150 m geofence (CLMonitor)
  goes around the spot. Leaving it, a visit ending, a significant location
  change, or Core Motion seeing movement turns GPS back on. Those same events
  relaunch the app if iOS has terminated it.

Fixes pass through `PointFilter`, are stored in packed batches (`PointBatch`),
and are traced into H3 resolution-11 hexagons (~43 m across) by
`CoverageTracer`, which never bridges a gap of over 2 minutes or 500 m.

## Privacy

- Location history is stored in the app's SwiftData store, protected by iOS until
  first unlock after a restart (so background recording can write to it).
- It's included in the iPhone's iCloud or Finder backups like other app data.
  Standard iCloud Backup is encrypted, but Apple holds the keys unless the user
  turns on Advanced Data Protection.
- No network code exists in the app. Apple Maps tiles are fetched by MapKit
  as you pan the map, which tells Apple roughly which area you're viewing,
  but not your history.
- `Reach/Resources/PrivacyInfo.xcprivacy` declares no collected data and no tracking.

## Layout

```
project.yml              XcodeGen spec for the app
Reach/                   iOS app (SwiftUI, MapKit, Core Location, Core Motion, SwiftData)
  App/  Recording/  Map/  Onboarding/  Storage/  Resources/  Simulation/
ReachCore/               Swift package: platform-independent logic + tests
  Sources/CH3/           Uber H3 v4.1.0 C library (Apache-2.0), vendored
reference/reach.html     the Range web prototype (ported in Phase 4)
tools/gpx/               GPX fixture generator
```
