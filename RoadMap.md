# VibeMap — Roadmap

> **How to use this file:**
> - Paste this file at the start of each Claude session for full context
> - Update `Status` as items are completed
> - Add notes in the `Notes` column as decisions are made

**Last updated:** 2026-05-28

---

## Status Legend
| Symbol | Meaning |
|--------|---------|
| ✅ | Complete |
| 🔄 | In Progress |
| ⏳ | Planned |
| ⏸️ | On Hold |
| ❌ | Cancelled |
| ❓ | Needs More Info |

---

## Session History

### 2026-05-28
- Colour fix: exploration-based opacity (municipality/canton fills); flat colour only on hex outlines
- HealthKit sync: `HealthKitImporter` for all GPS-capable apps (Komoot, Apple Fitness, Strava). Garmin Connect confirmed to not expose GPS routes via HealthKit — GPX export remains the only Garmin path
- Res-10 enforcement: all three recording paths (live GPS, GPX import, HealthKit) now always save `resolution: 10`
- Res-9 → Res-10 migration: `DataMigrationManager` runs once on first launch, converts all legacy res-9 records to their res-10 centre child atomically
- Map rendering refactor: removed the intermediate res-9 zoom tier — res-10 hex outlines now appear at span < 0.15 (was < 0.02)
- Performance: spatial grid index (`[GridKey: [String]]`, 0.1° buckets) replaces O(n) linear scan — viewport lookup is O(~36 buckets) regardless of total hex count
- Performance: full off-thread outline pipeline — main-thread cost per gesture event is now O(1) task launch + O(~36) integer additions
- Unexplored area prompt: when outside a session, entering a Swiss hex that has never been explored shows "New territory ahead!" overlay with option to start a session
- Known issue logged in ARCHITECTURE.md: hex rendering still laggy at hex zoom — needs profiling (likely MapKit polygon count; possible fix: custom MKOverlay / Metal renderer)

---

## Known Open Issues
| Issue | File | Status | Notes |
|-------|------|--------|-------|
| Confetti animation not confirmed working | `ConfettiView.swift` | ⏳ | Deferred, address after Phase 3 |
| Hex rendering laggy at span < 0.15 | `MapView.swift` | ⏳ | Root cause not isolated. Suspects: too many `MapPolygon` rings, SwiftUI diff cost, MapKit overlay threshold. Next step: profile with Instruments (Time Profiler + Metal System Trace). Long-term fix: custom `MKOverlay` / Metal renderer batching all rings into one draw call |

---

## Phase 1 — Stabilize the Foundation ✅
| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 1.1 | Batch hex existence check in `flushPendingData` | ✅ | Single SwiftData fetch before loop |
| 1.2 | Fix flush threshold | ✅ | Kept at >= 1 in foreground intentionally for live map feedback |
| 1.3 | O(1) contains check in `RegionExploration` | ✅ | Transient `Set<String>` backed by persisted `[String]` |
| 1.4 | Pre-compile SQLite statements | ✅ | Statements prepared once at `init()`, reused via `sqlite3_reset` |
| 1.5 | Dispatch `updateCenteredRegion` off main thread | ✅ | H3 + SQLite on detached tasks, `@State` updates on `MainActor` |
| 1.6 | Cache `visitedCantonIDs` in `MapView` | ✅ | Rebuilt only on `regions` change via `.onChange` |
| 1.7 | Dead code removal | ✅ | Deleted unused files, fields, and writes |

---

## Phase 2 — Complete What's Already Built ✅
| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 2.1 | Wire up Achievement system | ✅ | `checkAchievements()` triggered on `exploredHexes.count` change and on launch |
| 2.2 | Achievement banner UI | ✅ | Slide-down banner, 3 s auto-dismiss, queue for multiple unlocks |
| 2.3 | Stats screen consolidation | ✅ | Single `currentUnlockedAchievements` computed property as source of truth |
| 2.4 | Replace `GenevaDetector` with `LiveLocationDetector` | ✅ | Detects municipality from GPS in real time |
| 2.5 | HUD pill crosshair fix | ✅ | Pill always reflects map crosshair, not GPS position |

---

## Phase 3 — Map Experience
| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 3.1 | Hex polygon merging | ✅ | 🔴 High | `HexMerger` half-edge algorithm: merges N individual hexes into a handful of cluster outline rings. Runs off main thread via `Task.detached` |
| 3.2 | Fog of War | ⏸️ | 🟡 Medium | On hold — revisit later |
| 3.3 | Smooth zoom layer transitions | ⏳ | 🟠 Medium-High | Crossfade between hex / municipality / canton layers at zoom thresholds |
| 3.4 | HUD progress ring | ❓ | 🟡 Medium | Circular arc showing current municipality % — needs design decision |
| 3.5 | Map style improvements | ⏳ | 🟡 Medium | Reduce POI clutter, dark mode hex colours |
| 3.6 | Hex detail on tap | ⏳ | 🟡 Medium | Popover on hex tap: first visited, municipality name |
| 3.7 | Viewport culling | ✅ | 🔴 High | Spatial grid index (0.1° buckets, ~7 km each). Viewport lookup at span 0.15 touches ~36 buckets regardless of total hex count (~30× faster than linear scan at 50k hexes). Full outline pipeline runs in `Task.detached` — main-thread cost per gesture is O(1) |
| 3.8 | Cache building off main thread | ✅ | 🟡 Medium | Spatial grid rebuild runs in `Task.detached`. `rebuildRegionCaches` remains on main thread (reads ~26 regions, negligible cost) |
| 3.9 | Zoom threshold tuning | ✅ | 🟡 Medium | Hex outlines: span < 0.15 (was < 0.02 for res-10, 0.02–0.2 for res-9). Municipality fills: 0.15–2.0. Canton fills: 2.0–10.0 |
| 3.10 | Fix hex rendering performance (ongoing) | ⏳ | 🔴 High | Still laggy at hex zoom despite spatial grid. See Known Open Issues |

---

## Phase 4 — Social & Motivation Layer
| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 4.1 | Exploration streaks | ⏳ | 🟠 Medium-High | Consecutive days with new hexes — derivable from existing `lastVisited` data |
| 4.2 | Personal records | ⏳ | 🟡 Medium | "Best day" stats — derivable from `firstVisited` timestamps |
| 4.3 | Passport / Profile view | ✅ | 🟠 Medium-High | `PassportView` — per-canton card with visited/total municipalities |
| 4.4 | Challenges | ⏳ | 🟡 Medium | Time-boxed auto-generated goals — builds on existing achievement engine |

---

## Phase 5 — Data & Reliability
| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 5.1 | Merge GeoJSON parsing | ⏳ | 🟠 Medium-High | `municipalities.geojson` parsed twice at startup — merge into single pass |
| 5.2 | Backup system overhaul | ⏳ | 🔴 High | Current backup not confirmed working — needs investigation + iCloud auto-backup + restore preview |
| 5.3 | Expand beyond Switzerland | ⏳ | 🔴 High | Architecture is country-agnostic — main work is generating SQLite databases for other countries |
| 5.4 | Simplify GeoJSON geometries | ⏳ | 🟠 Medium-High | Use Mapshaper to simplify canton/municipality polygons 70–80%. Do this when adding each new country |
| 5.5 | UIViewRepresentable + CoreGraphics renderer | ⏳ | 🟡 Low | Replace `Map` with `MKMapView` + single CoreGraphics canvas. Last resort if MapKit polygon count remains the bottleneck after profiling |
| 5.6 | Res-9 → Res-10 database migration | ✅ | 🔴 High | `DataMigrationManager.migrateRes9ToRes10` — runs once on first launch, converts all legacy res-9 `ExploredHex` records to their res-10 centre child. Gated by `UserDefaults` flag. `RegionExploration.replaceHex(old:new:)` keeps region hex lists in sync |

---

## Phase 6 — Tracking Intelligence
| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 6.1 | Exploration Session Mode | ✅ | 🔴 High | User explicitly starts an "Explore" session. GPS only runs during active sessions. Launch prompt: "Exploring somewhere new today?" |
| 6.2 | Smart session suggestions | ⏳ | 🟠 Medium-High | Learn routine locations (home, work) and skip tracking in known territory |
| 6.3 | Already-explored suppression | ✅ | 🟠 Medium-High | `exploredHexSet` built at session start — O(1) check per GPS fix, no SwiftData lookup for known hexes |
| 6.4 | Session summary | ⏳ | 🟡 Medium | After ending a session: new hexes, new municipalities, distance, time |
| 6.5 | Battery & accuracy profiles | ✅ | 🟡 Medium | Foreground: best accuracy, 15 m filter. Background: 10 m accuracy, 50 m filter. Outside session: significant-change monitoring only |
| 6.6 | Unexplored area prompt | ✅ | 🟠 Medium-High | When outside a session, entering a Swiss hex never before explored shows "New territory ahead!" overlay prompting the user to start a session. Gated by `lastCheckedHex` to avoid repeated prompts for the same cell |

---

## Phase 7 — Data Import
| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 7.1 | GPX file import | ✅ | 🔴 High | `GPXImporter` — SAX parser, coordinate→H3 off main thread, preview before commit, batch SwiftData insert |
| 7.2 | Garmin Connect integration | ❌ | 🟠 Medium-High | Cancelled: Garmin Connect does not write `HKWorkoutRoute` GPS data to HealthKit — only workout summaries. GPX export from Garmin remains the only path. See 7.1 |
| 7.3 | Apple Health / Workouts import | ✅ | 🟠 Medium-High | `HealthKitImporter` — queries all sources (Komoot, Apple Fitness, Strava, etc.) via `HKWorkoutRouteQuery`. Preview sheet with per-source activity breakdown. Incremental sync watermark in UserDefaults. Apps without route data (Garmin) handled gracefully with actionable UI message |
| 7.4 | Strava integration | ⏳ | 🟡 Medium | OAuth connect to Strava, import historical activities |
| 7.5 | Import preview | ✅ | 🟡 Medium | Both GPX and HealthKit show a preview sheet before committing to the database |

---

## Phase 8 — Map Layers
| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 8.1 | Layer switcher architecture | ✅ | 🔴 High | `MapLayerSettings` + `LayerPanelView` — base map style (Standard / Hybrid / Imagery) + explored hexes toggle |
| 8.2 | Photo memories layer | ⏳ | 🟠 Medium-High | Geotagged photos from camera roll via `Photos` framework |
| 8.3 | Time lapse layer | ⏳ | 🟠 Medium-High | Scrubber to replay exploration history chronologically |
| 8.4 | Must-see / POI layer | ⏳ | 🟡 Medium | Curated landmark pins, gamified visit tracking |
| 8.5 | Activity routes layer | ⏳ | 🟡 Medium | Display imported GPX / Health routes as lines on the map |

---

## Architecture Notes
> Key decisions and constraints to carry across sessions

- **SQLite** (`swiss_index.sqlite`) — master hex-to-region lookup. Read-only. Covers Switzerland only.
- **GeoJSON** (`municipalities.geojson`, `cantons.geojson`) — boundary polygons for map overlays and metadata.
- **SwiftData** — user's personal exploration history (`ExploredHex`, `RegionExploration`).
- **H3 Resolution** — always res-10 (~15 m cells). Res-9 was used historically for boundary fallbacks; a one-time migration converts all legacy records on first launch. Never save at res-9 again.
- **Flush strategy** — foreground: flush every 1 hex (live map feedback). Background: flush immediately.
- **Thread safety** — all SQLite access via pre-compiled statements; all `@State` mutations on `MainActor`; CPU-heavy work (H3, HexMerger) in `Task.detached`.
- **Achievement IDs** — stored by `title` string in `@AppStorage` to survive app restarts.
- **`totalHexes` repair** — `repairRegionTotals()` in `ContentView.onAppear` self-heals any region with `totalHexes == 0`.
- **Tracking philosophy** — hexes are a scratch map; once scratched, no value in re-tracking. GPS only runs during explicit exploration sessions.
- **GeoJSON simplification** — run new country GeoJSON through Mapshaper at 70–80% before adding to the bundle.
- **Garmin limitation** — Garmin Connect does not write GPS routes to HealthKit. GPX export is the only integration path.
- **Map zoom thresholds** — hex outlines < 0.15, municipality fills 0.15–2.0, canton fills 2.0–10.0, nothing ≥ 10.0.

---

## Deferred / Future Ideas
| Idea | Notes |
|------|-------|
| Multiplayer / friend hex comparison | Requires backend — post v1.0 |
| Custom hex colours per user | Nice to have — post Phase 4 |
| Apple Watch companion app | Post v1.0 |
| Leaderboard | Requires backend — post v1.0 |
| Neighbourhood / district sub-layer | Below municipality granularity |
