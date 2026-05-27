# VibeMap — Architecture & Codebase Reference

## What the app does

VibeMap is an iOS exploration-tracking app for Switzerland. It divides the country into a hexagonal grid using Uber's H3 system and records which cells you physically visit. As you walk, hexes light up on the map. Stats accumulate at municipality, canton, and country level. GPX files from past tracks can be imported to backfill history.

---

## Features

| Feature | Description |
|---|---|
| Hex recording | Every GPS fix is converted to an H3 resolution-10 cell (~15 m² area). New cells are written to SwiftData. |
| Session model | GPS only runs during an explicit "Explore" session. Outside sessions, significant-change monitoring keeps location roughly current at minimal battery cost. |
| Zoom-level map overlays | Street zoom → individual hex outlines. Mid-zoom → coarser res-9 cells. Municipality zoom → filled municipality polygons. Canton zoom → canton polygons. |
| Offline region lookup | An SQLite database (`swiss_index.sqlite`) maps every H3 cell to its Swiss municipality — no network required. |
| Live HUD pill | Shows the municipality/canton/country name and exploration % at the current map crosshair. Updates on pan and on walking. |
| Location Details | Tap the HUD pill for a three-level drill-down: municipality hex progress, canton town count, Switzerland canton count. |
| Canton Passport | Per-canton breakdown of visited vs total municipalities. |
| Explorer Profile | Total hexes, area (km²), national discovery progress, and unlocked achievements. |
| Achievements | 7 unlockable badges based on hex count and municipality count. Banners appear with confetti on unlock; multiple unlocks queue. |
| GPX import | Parses GPX files from Garmin, Strava, AllTrails, etc. Preview before committing. Batch-inserts only new hexes. |
| Backup / restore | Exports all data as a JSON file. Restore reads the file and merges records. Auto-backup on app background. |
| Map styles | Standard, Hybrid, Imagery — switched via the layer panel. |
| Data repair | Regions with `totalHexes = 0` (startup race condition) are silently fixed on launch. |

---

## Architecture overview

```
┌─────────────────────────────────────────────────────┐
│  SwiftUI Views                                       │
│  ContentView → MapView, SettingsView, PassportView  │
└───────────────────┬─────────────────────────────────┘
                    │ @Query / @Environment
┌───────────────────▼─────────────────────────────────┐
│  State & Managers                                    │
│  LocationManager   MapLayerManager                  │
│  LiveLocationDetector   BackupManager   GPXImporter │
└──────┬──────────────────────┬───────────────────────┘
       │ SwiftData             │ SQLite (read-only)
┌──────▼──────┐        ┌──────▼───────────────┐
│ ExploredHex │        │  swiss_index.sqlite   │
│ LocationPoint        │  Hex_Map table        │
│ RegionExploration    │  h3_index → region_id │
└─────────────┘        └──────────────────────┘
       │
┌──────▼──────────────────────────────────────────────┐
│  Helpers                                             │
│  H3Wrapper (C bridge)   HexMerger (polygon math)    │
└─────────────────────────────────────────────────────┘
```

**Data flows in one sentence each:**

- **Recording**: GPS fix → H3 cell (C API) → SQLite lookup → SwiftData insert → map outline rebuild.
- **Map rendering**: `@Query exploredHexes` → HexMerger (off main thread) → `MapPolygon` overlays.
- **HUD pill**: map pan end or walking location update → H3 + SQLite (off main thread, 250 ms debounce) → centred region name + %.
- **GPX import**: file picker → SAX XML parse → coordinate→H3 batch conversion (detached) → batch SwiftData insert.

---

## File reference

### App

| File | Role |
|---|---|
| `VibeMapApp.swift` | `@main` entry point. Creates the SwiftData `ModelContainer` (ExploredHex, LocationPoint, RegionExploration). Injects `LocationManager` as an environment object. Forwards scene lifecycle events to LocationManager. |

### Views

| File | Lines | Role |
|---|---|---|
| `ContentView.swift` | 923 | Central orchestrator. Owns all top-level state: map camera, HUD pill data, achievement queue, session prompt, layer settings. Hosts the splash/map transition and all overlay sheets. Contains the crosshair region lookup pipeline (`updateCenteredRegion`) and the canton count cache. |
| `MapView.swift` | 210 | Renders the `Map`. Owns the zoom-level rendering ladder and a single viewport-culled outline rebuild pipeline (`rebuildHexOutlines`). Individual hex outlines (res-10 only) use a flat `orange.opacity(0.4)`; aggregated municipality and canton polygons scale opacity with exploration % (floor 0.15, ceiling 0.6). Also owns region colour caches. |
| `SettingsView.swift` | 600 | Backup export/import UI, GPX import UI, Garmin Connect sync UI, achievement list, data clear. Manages async preview → confirm workflows for all import types. |
| `PassportView.swift` | 210 | Canton-by-canton progress. Computes visited/total municipalities per canton. Maps Swiss federal canton IDs (KTNR) to ISO abbreviations. |
| `SplashView.swift` | 122 | 2.5 s launch animation. Rotating hex ring + spinning globe. Dismissed by ContentView with a fade. |
| `AchievementBannerView.swift` | 87 | Toast-style slide-down banner for achievement unlocks. Dismiss callback drives the queue in ContentView. |
| `LayerPanelView.swift` | 49 | Compact panel for base map style (3 options) and the Explored Hexes toggle. |
| `ConfettiView.swift` | 73 | 50-particle confetti animation shown alongside achievement banners. Non-interactive (`allowsHitTesting(false)`). |

### Managers

| File | Lines | Role |
|---|---|---|
| `LocationManager.swift` | 315 | Core location engine. Manages the session lifecycle (start/stop), two GPS accuracy profiles (foreground / background), and the two-layer deduplication system (`lastSavedHex` for same-hex skips, `exploredHexSet` for full-history suppression). Batches new hexes in `pendingHexes` and flushes to SwiftData. Handles background task lifecycle so flushes complete even after the user backgrounds the app. |
| `MapLayerManager.swift` | 103 | Async-loads `cantons.geojson` and `municipalities.geojson` from the bundle. Parses them into `[GeoRegion]` polygon arrays. Populates `RegionMetadataManager` as a side effect during municipality parse. |
| `OfflineDatabase.swift` | 90 | Singleton wrapping `swiss_index.sqlite`. Opens the file once, pre-compiles two SQLite statements (region lookup by hex index, hex count per region), and reuses them on every call. Used on every GPS fix — must be fast. |
| `BackupManager.swift` | 129 | Serialises all `ExploredHex` and `RegionExploration` records to JSON (`BackupData` v2). Restores by decoding and merging (skips duplicates). Auto-backup runs on scene background. |
| `GPXImporter.swift` | 300 | Two-phase import: `parse()` (no DB writes, builds preview summary) and `importFiles()` (batch write). The coordinate→H3 conversion runs on a detached task. Only genuinely new hexes reach SwiftData. |
| `HealthKitImporter.swift` | 230 | Two-phase sync from any app that writes `HKWorkoutRoute` GPS data (Komoot, Apple Fitness, Strava, etc.). `buildPreview()` fetches workout metadata and groups by source app. `importWorkouts()` fetches GPS routes via `HKWorkoutRouteQuery`, converts to H3 off-thread (same pipeline as GPXImporter), and batch-inserts new hexes. Tracks hexes per source app for the result summary. Stores a sync watermark in UserDefaults (`healthKitLastSyncDate`) for incremental syncs. Apps that only sync summaries (e.g. Garmin Connect) produce `workoutsWithRoutes = 0` in the result and are called out in the UI. |
| `DataMigrationManager.swift` | 130 | One-time data migrations run from `ContentView.task` on each launch. Each migration is gated by a UserDefaults flag. **Migration 1 (`hasCompletedRes9ToRes10Migration_v1`)**: converts every res-9 `ExploredHex` to its res-10 centre child via `H3Wrapper.cellToCenterChild`. If a res-10 counterpart already exists the res-9 record is removed without creating a duplicate. `RegionExploration.exploredHexes` is updated in the same atomic `context.save()`. |
| `LiveLocationDetector.swift` | 74 | Real-time municipality/canton detection from current GPS coordinate. Uses `OfflineDatabase` for the lookup. Kept for future use; currently does not drive the HUD pill directly. |
| `RegionMetadataManager.swift` | 11 | Singleton cache of `[regionID: (name, cantonID)]`. Populated once by `MapLayerManager` during GeoJSON parse. Read-only after that. |

### Models

| File | Lines | Role |
|---|---|---|
| `ExplorationModels.swift` | 52 | Two SwiftData models. `ExploredHex`: one record per H3 cell visited (`@Attribute(.unique)` on h3Index); each hex is written exactly once, never updated. `visitCount` is always 1 and kept only to avoid a SwiftData schema migration. `LocationPoint`: raw GPS coordinates — currently unused, reserved for a future breadcrumb feature. |
| `RegionExploration.swift` | 55 | SwiftData model for per-municipality stats. Stores `exploredHexes: [String]` (persistable) plus a `@Transient Set<String>` for O(1) membership checks. The set is lazily rebuilt from the array on first access after a fetch. **All mutations must go through `addExploredHex` to keep array and set in sync.** Inline SQLite repair in `explorationPercentage` self-heals records where `totalHexes` was saved as 0. |
| `Achievement.swift` | 111 | 7 achievements defined as structs with `(hexCount, cityCount) -> Bool` closure criteria. Persistence uses title strings (not UUIDs, which regenerate each launch). `AchievementRow` is the list cell used in SettingsView and the stats overlay. |
| `BackupModels.swift` | 47 | Codable DTOs for JSON serialisation: `BackupData`, `HexBackupDTO`, `RegionBackupDTO`, `BackupPreview`. |
| `MapLayerSettings.swift` | 37 | `@Observable` class holding `baseStyle` (Standard / Hybrid / Imagery) and `showExploredHexes`. Shared between ContentView and MapView. |

### Helpers

| File | Lines | Role |
|---|---|---|
| `H3Wrapper.swift` | 87 | Static wrappers around the H3 Swift package. Key methods: `getRawIndex` (coordinate → UInt64 index), `getVertices` (index → boundary coordinates), `cellToParent` (promote to coarser resolution), `cellToCenterChild` (unique child closest to parent centroid — used by the res-9 migration), `cellCenter` (centroid by vertex average — used for viewport culling). |
| `HexMerger.swift` | 74 | Half-edge boundary algorithm. Collects all directed edges from a set of H3 hexes, filters to boundary edges (those with no reverse), then walks closed rings. Reduces N individual polygons to a handful of merged cluster outlines. `CoordKey` rounds coordinates to 7 decimal places (~1 cm) to safely compare vertices across independently-computed adjacent cells. |

---

## Key subsystems in detail

### Session and recording pipeline

```
startSession()
  └─ buildExploredSet()          ← loads all known h3Index into Set<String>
  └─ applySessionProfile()       ← sets GPS accuracy + distance filter

didUpdateLocations()
  ├─ reject stale fixes (>10 s old) or imprecise ones (>100 m accuracy)
  ├─ latLngToCell at res-10 and res-9 (C API, <1 ms)
  ├─ OfflineDatabase.getRegionData(res10:res9:)   ← SQLite, <1 ms
  ├─ lastSavedHex check          ← same hex as last fix? skip
  ├─ exploredHexSet check        ← ever recorded before? skip
  └─ pendingHexes[hex] = data

flushPendingData()              ← called on every new hex (foreground) or scene background
  ├─ batch-fetch existing ExploredHex for pending keys
  ├─ batch-fetch affected RegionExploration records
  ├─ insert new ExploredHex records
  ├─ update RegionExploration.addExploredHex (in-memory cache within flush)
  └─ context.save() → exploredHexSet updated → pendingHexes cleared

stopSession()
  └─ flushPendingData() → exploredHexSet.removeAll() → significant-change monitoring
```

### Map rendering pipeline

```
exploredHexes (@Query, SwiftData) or currentSpan/centerCoordinate changes
  └─ rebuildHexOutlines()    ← only if currentSpan < 0.2; single task handle
       └─ viewportFilteredIndices()  ← 2× buffer; H3Wrapper.cellCenter per hex
       └─ HexMerger.mergeHexOutlines(culledIndices) → hexOutlines
       └─ adaptive debounce: 300 ms if < 1 000 culled hexes, 800 ms otherwise

currentSpan < 0.2   → hexOutlines rendered as MapPolygon (res-10, flat orange.opacity(0.4))
currentSpan 0.2–2.0 → municipality GeoJSON polygons (opacity = max(0.15, explorationPct × 0.6))
currentSpan 2.0–10.0 → canton GeoJSON polygons (opacity = max(0.15, visitedMunis/totalMunis × 0.6))
currentSpan ≥ 10.0 → nothing
```

Viewport culling: `viewportFilteredIndices(from:center:span:)` filters hexes by centroid
bounding box using a 2× span buffer on each side. Only hexes whose centroid falls within
the enlarged viewport are passed to HexMerger. Hexes with no computable centroid are
included as a safe fallback.

Rebuild triggers:
- `onChange(of: exploredHexes)` — new hex recorded or imported
- `onChange(of: currentSpan)` — pinch-zoom (no centre change)
- `onChange(of: centerCoordinate)` — pan (no span change)

### Crosshair region lookup (HUD pill)

Every pan-end and every walking location update calls `updateCenteredRegion(coordinate:)`:

1. 250 ms debounce (cancels previous task)
2. Detached task: coordinate → H3 res-10 + res-9 strings
3. Detached task: `OfflineDatabase.getRegionData` → regionID
4. Main thread: update `centeredMunicipalityName`, `centeredCantonName`, `centeredRegionID`
5. HUD pill redraws with new values

### GPX import pipeline

1. User picks files → `GPXImporter.parse()` → `GPXFile` array (no DB writes)
2. Preview sheet shown (`GPXImportSummary`)
3. User confirms → `GPXImporter.importFiles()`
   - Coordinate→H3 conversion on detached task (CPU-bound)
   - Consecutive duplicate suppression (`lastHex`) + batch duplicate suppression (`seenIndices`)
   - Single batch fetch of already-explored hexes
   - Insert only new hexes; update/create `RegionExploration` via in-memory cache
   - `context.save()`

### Apple Health sync pipeline (Komoot, Apple Fitness, Strava, …)

1. User taps "Sync GPS Activities" → `HealthKitImporter.requestAuthorization()` (no-op if already granted)
2. `buildPreview(since: lastSyncDate)` → `HKSampleQuery` for **all** workouts (no source filter) → `HealthSyncPreview` with source breakdown (metadata only, no GPS)
3. Preview sheet shown (activity count, date range, source app list)
4. User confirms → `importWorkouts(_ workouts:)`
   - `fetchLocations(for:)` per workout: `HKAnchoredObjectQuery` → `[HKWorkoutRoute]` → `HKWorkoutRouteQuery` (batched CLLocation stream). Workouts with no routes (e.g. Garmin Connect summaries) are silently skipped.
   - Coordinate→H3 on detached task — identical to GPXImporter pipeline
   - Batch fetch of existing hexes; insert only new ones
   - `context.save()`
   - UserDefaults watermark advanced to latest workout end date
   - Result carries `sourcesWithHexes` breakdown for the success alert

---

## External dependencies

| Dependency | Why |
|---|---|
| **H3 (Uber)** via Swift package | Hierarchical hex grid. Resolution 9/10 parent-child relationship drives the zoom-level ladder. Offline C computation, <1 ms per fix. |
| **swiss_index.sqlite** (bundled) | Pre-built map of every H3 cell in Switzerland → municipality ID. Eliminates network dependency for region detection. Schema: `Hex_Map(h3_index TEXT, region_id TEXT, resolution INTEGER)`. |
| **cantons.geojson / municipalities.geojson** (bundled) | GeoJSON polygon data for map overlays and metadata (names, canton IDs). Loaded once at startup. |
| **HealthKit** (system framework) | Read-only access to workout routes. Used exclusively by `HealthKitImporter` to pull Garmin Connect activities. Requires `com.apple.developer.healthkit` entitlement and `NSHealthShareUsageDescription` in Info.plist. |

---

## Persistence

| Store | Contents | Access pattern |
|---|---|---|
| SwiftData (on-device) | `ExploredHex`, `LocationPoint`, `RegionExploration` | `@Query` in views; `ModelContext` in managers |
| `swiss_index.sqlite` | H3 index → region mapping (read-only) | Pre-compiled SQLite statements, called per GPS fix |
| `UserDefaults` (`AppStorage`) | `unlockedAchievementTitles` (comma-separated) | Read/write on achievement check |
| JSON file (user's Files app) | Full data export for backup/restore | Written on demand and on scene background |

---

## Known constraints and technical debt

| Item | Detail |
|---|---|
| `visitCount` vestigial property | Always 1 on every `ExploredHex`. `recordVisit()` has been removed. The field is kept in the model to avoid a SwiftData schema migration; remove it with a `VersionedSchema` bump when the model is next versioned. |
| `LocationPoint` model unused | Defined and included in ModelContainer but never written to. Reserved for future breadcrumb feature. |
| Legacy res-9 hexes | All recording paths (live GPS, GPX import, HealthKit sync) now always save `resolution: 10`. On first launch after updating, `DataMigrationManager.migrateRes9ToRes10` converts every legacy res-9 record to its res-10 centre child in a single atomic `context.save()`. After migration the database contains only res-10 records and the rendering ladders work correctly at all zoom levels. |
| `currentZoomPercentage` does a linear scan | At canton zoom, finds the canton by a `.first(where:)` scan over `layerManager.cantons` on every render. Fine for 26 cantons, worth caching if canton list grows. |
| `LiveLocationDetector` not wired to HUD | Detects current municipality in real time but `ContentView` uses the crosshair-based `updateCenteredRegion` instead. Either wire it or remove it. |
| No tests on core logic | `HexMerger`, `LocationManager` session lifecycle, and `GPXImporter` batch pipeline have no unit tests. The algorithm-heavy paths are the highest risk. |
| SQLite OR + LIMIT 1 non-deterministic | `getRegionData` queries `WHERE h3_index = res10 OR h3_index = res9 LIMIT 1` without `ORDER BY`. If both rows exist for a coordinate the returned resolution is non-deterministic. Benign in practice (same `region_id` either way) but fragile. |
