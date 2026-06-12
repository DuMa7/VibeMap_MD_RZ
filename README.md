# VibeMap

An iOS app that gamifies exploring Switzerland on foot. As you walk, H3 hexagonal cells light up on the map. Stats accumulate at municipality, canton, and national level. Past tracks can be imported from GPX files.

**Platform:** iOS 26+ · **Language:** Swift · **UI:** SwiftUI · **Persistence:** SwiftData + SQLite

---

## Features

- **Hex recording** — GPS fixes are converted to H3 resolution-10 cells (~15,000 m², ≈66 m edge) and stored locally. New cells are deduplicated in O(1) using an in-memory set.
- **Session-based GPS** — tracking only runs during an active "Explore" session; significant-change monitoring handles the rest at minimal battery cost.
- **Zoom-adaptive overlays** — street zoom shows individual hex outlines; municipality zoom fills visited towns; canton zoom fills visited cantons.
- **Offline region detection** — a bundled SQLite database maps every Swiss H3 cell to its municipality. No network required.
- **Live HUD** — the top pill shows the place name and exploration % at the map crosshair, updating on pan and while walking.
- **Location Details** — tap the pill for municipality hex progress, canton town count, and Swiss canton count.
- **Canton Passport** — per-canton breakdown of visited municipalities.
- **Achievements** — 7 badges based on hex count and municipality count, shown as banners with confetti.
- **GPX import** — parse tracks from Garmin, Strava, AllTrails; preview before committing to the database.
- **Backup / restore** — full JSON export and import; auto-backup on app background.

---

## Requirements

- iOS 26+
- Xcode 26+
- "Always" location permission (required for background hex recording)

---

## Setup

```bash
git clone https://github.com/DuMa7/VibeMap.git
open VibeMap.xcodeproj
```

1. **Set your signing team** — select the `VibeMap` target → Signing & Capabilities → choose your team.
2. **Resolve packages** — Xcode fetches `swift-h3` automatically. If it doesn't: **File → Packages → Resolve Package Versions**.
3. **Run on a real device** — background location doesn't work in the simulator. Select your iPhone and press Run (⌘R).
4. **Grant location access** — choose **Always Allow** when prompted so exploring keeps recording in the background.

---

## Tech stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Persistence | SwiftData (hexes, regions) + SQLite (offline region index) |
| Location | CoreLocation — `CLLocationManager`, significant-change monitoring |
| Hex grid | [Uber H3](https://h3geo.org/) via Swift package (resolution 10; res 9 only as a lookup fallback) |
| Mapping | MapKit (`Map`, `MapPolygon`) |
| Concurrency | Swift Concurrency (`async/await`, `Task.detached`) |
| State | `@Observable`, `@Query` |

---

## Codebase documentation

See **[ARCHITECTURE.md](./ARCHITECTURE.md)** for:
- Full file-by-file reference
- Session recording and flush pipeline
- Map rendering pipeline and zoom-level logic
- GPX import pipeline
- Database schema
- Known constraints and tech debt
