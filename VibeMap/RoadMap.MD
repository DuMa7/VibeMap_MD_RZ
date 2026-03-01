# VibeMap — Project Roadmap

> **How to use this file:**
> - Update `Status` as you work through items
> - Paste this file at the start of each Claude session for full context
> - Add notes in the `Notes` column as decisions are made

**Last updated:** 2026-02-22
**Current session:** Phase 3 in progress

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

## Known Open Issues
| Issue | File | Status | Notes |
|-------|------|--------|-------|
| Confetti animation not confirmed working | `ConfettiView.swift` | ⏳ | Deferred, address after Phase 3 |

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
| 1.7 | Dead code removal | ✅ | Deleted `VibeMapGuide.md`, `GeoDataModels.swift`, `PopulationManager.swift`, unused `ExploredHex` fields, `LocationPoint` writes, `HexagonShape` |

---

## Phase 2 — Complete What's Already Built ✅
| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 2.1 | Wire up Achievement system | ✅ | `checkAchievements()` triggered on `exploredHexes.count` change and on launch |
| 2.2 | Achievement banner UI | ✅ | Slide-down banner, 3s auto-dismiss, queue system for multiple unlocks |
| 2.3 | Stats screen consolidation | ✅ | Single `currentUnlockedAchievements` computed property as source of truth |
| 2.4 | Replace `GenevaDetector` with `LiveLocationDetector` | ✅ | Detects municipality from GPS in real time, feeds `updateCenteredRegion` |
| 2.5 | HUD pill crosshair fix | ✅ | Pill always reflects map crosshair, not GPS position |

---

## Phase 3 — Map Experience
| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 3.1 | Hex polygon caching | ✅ | 🔴 High | Cache `[String: [CLLocationCoordinate2D]]`, invalidate on new hexes only |
| 3.2 | Fog of War | ⏸️ | 🟡 Medium | On hold — revisit later |
| 3.3 | Smooth zoom layer transitions | ⏳ | 🟠 Medium-High | Crossfade between hex / municipality / canton layers at zoom thresholds |
| 3.4 | HUD progress ring | ❓ | 🟡 Medium | Circular arc showing current municipality % — needs design decision (option A/B/C) |
| 3.5 | Map style improvements | ⏳ | 🟡 Medium | Reduce POI clutter, visit-count tinting, dark mode hex colors |
| 3.6 | Hex detail on tap | ⏳ | 🟡 Medium | Popover on hex tap: first visited, visit count, municipality name |
| 3.7 | H3 Compaction — merge contiguous hexes | ⏳ | 🔴 High | Use `cellsToLinkedMultiPolygon` to merge adjacent hexes into outline shapes. Reduces SwiftUI polygon views from N individual hexes to a handful of merged boundaries. Complex C memory management — implement when hex count approaches 500+ |
| 3.8 | Cache building off main thread | ⏳ | 🟡 Medium | Move `rebuildPolygonCache()` and `buildCantonIDs()` to background task. Low urgency now, implement when stutters are felt at high hex counts |

---

## Phase 4 — Social & Motivation Layer
| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 4.1 | Exploration streaks | ⏳ | 🟠 Medium-High | Consecutive days with new hexes — derivable from existing `lastVisited` data |
| 4.2 | Personal records | ⏳ | 🟡 Medium | "Best day" stats — derivable from `firstVisited` timestamps in SwiftData |
| 4.3 | Passport / Profile view | ⏳ | 🟠 Medium-High | Per-canton card: name, abbreviation, municipalities visited, %, first visited date |
| 4.4 | Challenges | ⏳ | 🟡 Medium | Time-boxed auto-generated goals — builds on existing achievement engine |

---

## Phase 5 — Data & Reliability
| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 5.1 | Merge GeoJSON parsing | ⏳ | 🟠 Medium-High | `municipalities.geojson` parsed twice at startup — merge into single pass |
| 5.2 | Backup system overhaul | ⏳ | 🔴 High | Current backup not confirmed working — needs investigation + iCloud auto-backup + restore preview |
| 5.3 | Expand beyond Switzerland | ⏳ | 🔴 High | Architecture is country-agnostic — main work is generating SQLite databases for other countries |
| 5.4 | Simplify GeoJSON geometries | ⏳ | 🟠 Medium-High | Use Mapshaper (mapshaper.org) to simplify canton and municipality polygons by 70-80%. Zero visual difference at map zoom levels but significant GPU savings. **Do this when adding each new country database** — process all country GeoJSON files before adding to the app |
| 5.5 | UIViewRepresentable + CoreGraphics renderer | ⏳ | 🟡 Low | Replace SwiftUI `Map` with `MKMapView` wrapped in `UIViewRepresentable`. Draw all hex paths onto a single CoreGraphics canvas layer instead of managing thousands of individual `MapPolygon` views. **Last resort — only if H3 compaction (3.7) is insufficient at very high hex counts** |

---

## Phase 6 — Tracking Intelligence
*Fundamental rethink of when and why tracking runs*

> **Core philosophy:** Hexes are a scratch map — once scratched, there is no value in tracking the same location again. The app should only track when the user is actively exploring somewhere new. Always-on GPS is wasteful and unnecessary for this use case.

| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 6.1 | Exploration Session Mode | ⏳ | 🔴 High | User explicitly starts an "Explore" session before going somewhere new. GPS only runs during active sessions. Prompt on launch: "Exploring somewhere new today?" |
| 6.2 | Smart session suggestions | ⏳ | 🟠 Medium-High | App learns your routine locations (home, work, gym) and automatically skips tracking when you're in known territory, activates when you deviate from routine |
| 6.3 | Already-explored suppression | ⏳ | 🟠 Medium-High | Even during an active session, skip processing hexes you've already scratched — no GPS writes, no SQLite lookups, no SwiftData updates for known hexes |
| 6.4 | Session summary | ⏳ | 🟡 Medium | After ending a session, show a recap: new hexes discovered, new municipalities entered, distance walked, time elapsed |
| 6.5 | Battery & accuracy profiles | ⏳ | 🟡 Medium | During sessions: high accuracy. Outside sessions: significant-change monitoring only. Replaces current motion-based profile system |

---

## Phase 7 — Data Import
*Scratch hexes from historical data, not just live GPS*

> **Core philosophy:** You've been places before VibeMap existed. GPX files, Garmin tracks, and other sources should retroactively scratch your map.

| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 7.1 | GPX file import | ⏳ | 🔴 High | Parse GPX track points, convert each to H3 index, batch-insert new hexes. Handles Garmin, Strava, Apple Fitness, AllTrails etc. |
| 7.2 | Garmin Connect integration | ⏳ | 🟠 Medium-High | Direct pull from Garmin Connect API — import all historical activities without manual GPX export |
| 7.3 | Apple Health / Workouts import | ⏳ | 🟠 Medium-High | Read workout routes from HealthKit — retroactively scratch every run, walk, hike already tracked by Apple |
| 7.4 | Strava integration | ⏳ | 🟡 Medium | OAuth connect to Strava, import historical activities as hex scratches |
| 7.5 | Import preview | ⏳ | 🟡 Medium | Before committing, show how many new hexes and municipalities an import would add — let user confirm before writing to SwiftData |

---

## Phase 8 — Map Layers
*Toggleable overlays that add context and memory to the map*

| # | Feature | Status | Priority | Notes |
|---|---------|--------|----------|-------|
| 8.1 | Layer switcher architecture | ⏳ | 🔴 High | Extend existing map style switcher into full layer system: base layers + toggleable data overlays. Prerequisite for all other layers |
| 8.2 | Photo memories layer | ⏳ | 🟠 Medium-High | Geotagged photos from camera roll via `Photos` framework. Pins where photos were taken, tap to view. Hexes with photos get subtle tint |
| 8.3 | Time lapse layer | ⏳ | 🟠 Medium-High | Scrubber at bottom of map — drag to replay exploration history chronologically. Hexes appear in order first scratched |
| 8.4 | Must-see / POI layer | ⏳ | 🟡 Medium | Curated landmark pins per city. Gamified: "3/12 landmarks visited in Geneva." Offline curated list or dynamic OpenStreetMap pull |
| 8.5 | Activity routes layer | ⏳ | 🟡 Medium | Display imported GPX/Garmin/Health routes as drawn lines on the map |

---

## Architecture Notes
> Key decisions and constraints to remember across sessions

- **SQLite** (`swiss_index.sqlite`) — master hex-to-region lookup. Read-only. Too large for the repo.
- **GeoJSON** (`municipalities.geojson`, `cantons.geojson`) — boundary polygons for map rendering and metadata.
- **SwiftData** — user's personal exploration history only (`ExploredHex`, `RegionExploration`).
- **H3 Resolution** — Res 10 for urban/street level, Res 9 for rural/lakes. Resolution stored per hex.
- **Flush strategy** — foreground: flush every 1 hex (live map feedback). Background: flush immediately.
- **Thread safety** — all SQLite access serialized via `DispatchQueue` in `OfflineDatabase`. All `@State` mutations on `MainActor`.
- **Achievement IDs** — stored by `title` string (not `UUID`) in `@AppStorage` to survive app restarts.
- **`totalHexes` repair** — `repairRegionTotals()` in `ContentView.onAppear` patches any region with `totalHexes == 0`. Self-eliminates once all records are healthy.
- **Tracking philosophy** — hexes are a scratch map. Once scratched, no value in re-tracking. GPS should only run during explicit exploration sessions.
- **GeoJSON simplification** — always run new country GeoJSON through Mapshaper at 70-80% simplification before adding to the app bundle.

---

## Deferred / Future Ideas
| Idea | Notes |
|------|-------|
| Multiplayer / friend hex comparison | Requires backend — post v1.0 |
| Custom hex colors per user | Nice to have — post Phase 4 |
| Apple Watch companion app | Post v1.0 |
| Leaderboard | Requires backend — post v1.0 |
| Neighborhood / district sub-layer | Below municipality granularity — nice to have |
