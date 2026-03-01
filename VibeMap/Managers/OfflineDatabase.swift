import Foundation
import SQLite3

class OfflineDatabase {
    static let shared = OfflineDatabase()
    private var db: OpaquePointer?
    
    // Pre-compiled statements — prepared once, reused forever
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
        // Statement 1: region lookup by hex index
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
    
    func getTotalHexes(for regionID: String) -> Int {
        guard let statement = countStatement else { return 0 }
        
        sqlite3_reset(statement)
        sqlite3_bind_text(statement, 1, (regionID as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        
        return Int(sqlite3_column_int(statement, 0))
    }
    
    deinit {
        // Finalize compiled statements before closing the database
        sqlite3_finalize(regionStatement)
        sqlite3_finalize(countStatement)
        sqlite3_close(db)
    }
}
