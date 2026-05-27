import Foundation
import SwiftData

/// One-time data migrations executed on each app launch.
/// Every migration is gated by a UserDefaults flag so it runs exactly once.
/// New migrations are added as private static functions and called from `runPendingMigrations`.
@MainActor
enum DataMigrationManager {

    // MARK: - Entry Point

    /// Called from `ContentView.task` on launch. Runs any migration that has not yet completed.
    static func runPendingMigrations(context: ModelContext) async {
        await migrateRes9ToRes10(context: context)
    }

    // MARK: - Migration 1: res-9 → res-10

    /// Flag set in UserDefaults once this migration has completed successfully.
    private static let migrationKey = "hasCompletedRes9ToRes10Migration_v1"

    /// Replaces every `ExploredHex` stored at resolution 9 with its resolution-10 centre child.
    ///
    /// **Background**: All recording paths now always save at res-10. Legacy records from
    /// older app versions were saved at res-9 for two reasons: (1) the original code used
    /// res-9 as the canonical cell for boundary areas, and (2) some code paths saved at res-9
    /// unconditionally. This migration normalises the database so every hex is resolution 10.
    ///
    /// **Centre-child strategy**: The original GPS coordinates are not retained — only the
    /// res-9 cell index was stored. `cellToCenterChild` returns the unique res-10 child whose
    /// centroid is closest to the res-9 centroid. This is the most conservative, deterministic
    /// choice: it marks exactly one 15 m cell per legacy record rather than all seven children.
    ///
    /// **Deduplication**: If a res-10 centre child already exists in SwiftData (because the
    /// user revisited the area after the recording fix), the res-9 record is deleted and the
    /// `RegionExploration.exploredHexes` list is cleaned up without adding a duplicate.
    ///
    /// **Atomicity**: All inserts, deletes, and region updates are committed in a single
    /// `context.save()`. If the save fails the database is unchanged and the migration flag
    /// is NOT set, so the migration will retry on the next launch.
    private static func migrateRes9ToRes10(context: ModelContext) async {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        // 1. Fetch all res-9 ExploredHex records
        let descriptor = FetchDescriptor<ExploredHex>(
            predicate: #Predicate { $0.resolution == 9 }
        )
        guard let res9Hexes = try? context.fetch(descriptor) else {
            print("❌ Res-9 migration: fetch failed — will retry on next launch")
            return
        }
        guard !res9Hexes.isEmpty else {
            print("✅ Res-9 migration: no res-9 hexes found — nothing to do")
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        print("🔄 Res-9 → Res-10 migration: \(res9Hexes.count) hexes to process")

        // 2. Snapshot immutable data before crossing actor boundary
        struct HexSnap {
            let h3Index: String
            let regionID: String?
            let firstVisited: Date
            let lastVisited: Date
        }
        let snaps = res9Hexes.map {
            HexSnap(h3Index: $0.h3Index, regionID: $0.regionID,
                    firstVisited: $0.firstVisited, lastVisited: $0.lastVisited)
        }

        // 3. Compute centre children off the main thread (CPU-bound H3 calls)
        struct Mapping {
            let oldIndex: String
            let newIndex: String
            let regionID: String?
            let firstVisited: Date
            let lastVisited: Date
        }
        let mappings: [Mapping] = await Task.detached(priority: .userInitiated) {
            snaps.compactMap { snap in
                guard let child = H3Wrapper.cellToCenterChild(h3Index: snap.h3Index, childRes: 10)
                else { return nil }
                return Mapping(oldIndex: snap.h3Index, newIndex: child,
                               regionID: snap.regionID,
                               firstVisited: snap.firstVisited, lastVisited: snap.lastVisited)
            }
        }.value

        guard !mappings.isEmpty else {
            // Shouldn't happen — every valid H3 cell has a centre child
            print("⚠️ Res-9 migration: cellToCenterChild returned nil for all hexes — aborting")
            return
        }

        // 4. Batch-fetch res-10 indices that already exist (recorded after the fix was applied)
        let newIndices = mappings.map { $0.newIndex }
        let existDesc = FetchDescriptor<ExploredHex>(
            predicate: #Predicate { newIndices.contains($0.h3Index) }
        )
        let alreadyAtRes10 = Set((try? context.fetch(existDesc))?.map { $0.h3Index } ?? [])

        // 5. Batch-fetch all affected RegionExploration records
        let regionIDs = Array(Set(mappings.compactMap { $0.regionID }))
        let regionDesc = FetchDescriptor<RegionExploration>(
            predicate: #Predicate { regionIDs.contains($0.regionID) }
        )
        var regionCache: [String: RegionExploration] = Dictionary(
            uniqueKeysWithValues: ((try? context.fetch(regionDesc)) ?? []).map { ($0.regionID, $0) }
        )

        // Index old records for O(1) deletion lookup
        let oldHexByIndex = Dictionary(uniqueKeysWithValues: res9Hexes.map { ($0.h3Index, $0) })

        var migrated = 0
        var deduplicated = 0

        // 6. Apply mappings: replace region list entry, insert/deduplicate, delete old
        for m in mappings {
            // Update the region's hex index list regardless of dedup
            if let rid = m.regionID {
                regionCache[rid]?.replaceHex(old: m.oldIndex, new: m.newIndex)
            }

            if alreadyAtRes10.contains(m.newIndex) {
                // The res-10 centre child was already recorded — just remove the stale res-9 entry
                deduplicated += 1
            } else {
                // Create the replacement res-10 hex, preserving the original visit timestamps
                let newHex = ExploredHex(h3Index: m.newIndex, resolution: 10, regionID: m.regionID)
                newHex.firstVisited = m.firstVisited
                newHex.lastVisited  = m.lastVisited
                context.insert(newHex)
                migrated += 1
            }

            // Delete the original res-9 record
            if let old = oldHexByIndex[m.oldIndex] { context.delete(old) }
        }

        // 7. Commit everything atomically
        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
            let skipped = res9Hexes.count - mappings.count
            print("""
                ✅ Res-9 → Res-10 migration complete: \
                \(migrated) converted, \(deduplicated) deduplicated, \(skipped) skipped
                """)
        } catch {
            // Flag is NOT set — migration will retry on next launch
            print("❌ Res-9 migration save failed: \(error) — will retry on next launch")
        }
    }
}
