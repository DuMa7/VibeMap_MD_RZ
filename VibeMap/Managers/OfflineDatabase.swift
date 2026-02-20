//
//  OfflineDatabase.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 19.02.2026.
//


import Foundation
import SQLite3

class OfflineDatabase {
    static let shared = OfflineDatabase()
    private var db: OpaquePointer?
    
    private init() {
        openDatabase()
    }
    
    private func openDatabase() {
        // Ensure you have added swiss_index.sqlite to your Xcode target!
        guard let dbPath = Bundle.main.path(forResource: "swiss_index", ofType: "sqlite") else {
            print("❌ SQLite database not found in bundle. Did you check 'Target Membership'?")
            return
        }
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Error opening offline database")
        } else {
            print("✅ Successfully opened offline SQLite database")
        }
    }
    
    /// Queries the database for both Res 10 and Res 9 indices simultaneously.
    /// Returns the matched H3 Index, Region ID, and Resolution.
    func getRegionData(res10: String, res9: String) -> (matchedHex: String, regionID: String, resolution: Int)? {
        let query = "SELECT h3_index, region_id, resolution FROM Hex_Map WHERE h3_index = ? OR h3_index = ? LIMIT 1;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("❌ Error preparing query")
            return nil
        }
        
        // Bind the two generated hex strings to the query
        sqlite3_bind_text(statement, 1, (res10 as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (res9 as NSString).utf8String, -1, nil)
        
        var result: (String, String, Int)? = nil
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let matchedHex = String(cString: sqlite3_column_text(statement, 0))
            let regionId = String(cString: sqlite3_column_text(statement, 1))
            let resolution = Int(sqlite3_column_int(statement, 2))
            
            result = (matchedHex, regionId, resolution)
        }
        
        sqlite3_finalize(statement)
        return result
    }
    
    /// Dynamically counts the total number of hexagons for a specific region
    func getTotalHexes(for regionID: String) -> Int {
        let query = "SELECT COUNT(*) FROM Hex_Map WHERE region_id = ?;"
        var statement: OpaquePointer?
        var count = 0
            
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (regionID as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count
    }
    
    deinit {
        sqlite3_close(db)
    }
}
