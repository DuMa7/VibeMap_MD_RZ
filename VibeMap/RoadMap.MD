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
| Confetti animation not confirmed working | `ConfettiView.swift` | ⏳ | Deferred, address after Phase 5 |

---

## Phase 1 — Stabilize the Foundation
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

## Phase 2 — Complete What's Already Built
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
| 3.1 | Hex polygon caching | ⏳ | 🔴 High | Cache `[String: [CLLocationCoordinate2D]]`, invalidate on new hexes only. Prerequisite for 3.2 |
| 3.2 | Fog of War | ⏸️ | 🟡 Medium | On hold — revisit after other Phase 3 items |
| 3.3 | Smooth zoom layer transitions | ⏳ | 🟠 Medium-High | Crossfade between hex / municipality / canton layers at zoom thresholds |
| 3.4 | HUD progress ring | ❓ | 🟡 Medium | Circular arc showing current municipality % — needs design decision (option A/B/C) |
| 3.5 | Map style improvements | ⏳ | 🟡 Medium | Reduce POI clutter, consider visit-count tinting, dark mode hex colors |
| 3.6 | Hex detail on tap | ⏳ | 🟡 Medium | Popover on hex tap: first visited, visit count, municipality name |

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
| 5.1 | Merge GeoJSON parsing | ⏳ | 🟠 Medium-High | `municipalities.geojson` currently parsed twice at startup (by `RegionMetadataManager` AND `MapLayerManager`) — merge into single pass |
| 5.2 | Backup system overhaul | ⏳ | 🔴 High | Current backup not confirmed working — needs investigation + iCloud auto-backup + restore preview |
| 5.3 | Expand beyond Switzerland | ⏳ | 🔴 High | Architecture is already country-agnostic (SQLite + H3) — main work is generating equivalent SQLite databases for other countries |

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
- **`totalHexes` repair** — `repairRegionTotals()` in `ContentView.onAppear` patches any region with `totalHexes == 0` caused by a past SQLite race condition. Self-eliminates once all records are healthy.

---

## Deferred / Future Ideas
| Idea | Notes |
|------|-------|
| Multiplayer / friend comparison | Out of scope for now |
| Custom hex colors per user | Nice to have — post Phase 4 |
| Apple Watch companion app | Post v1.0 |
| Offline tile caching | Depends on map provider constraints |
