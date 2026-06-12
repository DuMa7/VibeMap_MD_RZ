import Foundation
import SQLite3

// swiss_index.sqlite is a read-only lookup table bundled in the app bundle.
// It maps H3 hex indices (resolutions 9 and 10) to Swiss municipality IDs,
// allowing fully offline region identification with no network dependency.
//
// Hex_Map schema: h3_index TEXT, region_id TEXT, resolution INTEGER
//
// Statements are pre-compiled once at init and reused across every GPS fix,
// which is critical because getRegionData is called on every location update.
//
// Thread safety: callers run on the main actor (live GPS fixes) and inside
// detached tasks (HUD pill lookups, GPX/Health import pipelines). A single
// SQLite connection and its prepared statements must never be used from two
// threads at once, so every statement use is serialized on a private dispatch
// queue. @unchecked Sendable is sound because all mutable state is written
// only during init and accessed only through that queue afterwards.
nonisolated final class OfflineDatabase: @unchecked Sendable {
    static let shared = OfflineDatabase()
    private var db: OpaquePointer?

    /// Serializes all use of the connection and prepared statements.
    private let queue = DispatchQueue(label: "vibemap.offline-database")

    // Prepared once, reset and rebound on each call — avoids repeated SQL compilation overhead.
    private var regionStatement: OpaquePointer?
    private var countStatement: OpaquePointer?

    private init() {
        openDatabase()
        prepareStatements()
    }

    private func openDatabase() {
        guard let dbPath = Bundle.main.path(forResource: "swiss_index", ofType: "sqlite") else {
            print("❌ SQLite database not found in bundle.")
            return
        }

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Error opening offline database")
        } else {
            print("✅ Successfully opened offline SQLite database")
        }
    }

    private func prepareStatements() {
        // The OR query accepts both res-10 (primary) and res-9 (fallback) hex strings.
        // LIMIT 1 is safe because a given coordinate maps to exactly one res-10 and one
        // res-9 cell — both share the same region_id, so whichever row is returned first
        // yields the correct municipality regardless of resolution.
        let regionQuery = "SELECT h3_index, region_id, resolution FROM Hex_Map WHERE h3_index = ? OR h3_index = ? LIMIT 1;"
        if sqlite3_prepare_v2(db, regionQuery, -1, &regionStatement, nil) != SQLITE_OK {
            print("❌ Failed to prepare region statement")
        }

        // Statement 2: hex count per region
        let countQuery = "SELECT COUNT(*) FROM Hex_Map WHERE region_id = ?;"
        if sqlite3_prepare_v2(db, countQuery, -1, &countStatement, nil) != SQLITE_OK {
            print("❌ Failed to prepare count statement")
        }

        print("✅ SQLite statements pre-compiled")
    }

    func getRegionData(res10: String, res9: String) -> (matchedHex: String, regionID: String, resolution: Int)? {
        queue.sync { () -> (matchedHex: String, regionID: String, resolution: Int)? in
            guard let statement = regionStatement else { return nil }

            // Reset the statement for reuse, then bind new values
            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, (res10 as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (res9 as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

            let matchedHex = String(cString: sqlite3_column_text(statement, 0))
            let regionId   = String(cString: sqlite3_column_text(statement, 1))
            let resolution = Int(sqlite3_column_int(statement, 2))

            return (matchedHex, regionId, resolution)
        }
    }

    func getTotalHexes(for regionID: String) -> Int {
        queue.sync { () -> Int in
            guard let statement = countStatement else { return 0 }

            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, (regionID as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }

            return Int(sqlite3_column_int(statement, 0))
        }
    }

    deinit {
        // Finalize compiled statements before closing the database
        sqlite3_finalize(regionStatement)
        sqlite3_finalize(countStatement)
        sqlite3_close(db)
    }
}
