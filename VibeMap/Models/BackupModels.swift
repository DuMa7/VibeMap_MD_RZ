import Foundation

// A container for all our app data
struct BackupData: Codable {
    let version: Int
    let timestamp: Date
    let hexes: [HexBackupDTO]
    let regions: [RegionBackupDTO] // Changed from cities
}

struct HexBackupDTO: Codable {
    let h3Index: String
    let resolution: Int // NEW
    let regionID: String? // NEW
    let visitCount: Int
    let firstVisited: Date
    let lastVisited: Date
}

struct RegionBackupDTO: Codable {
    let regionID: String
    let name: String
    let type: String
    let totalHexes: Int
    let exploredHexes: [String]
    let firstVisited: Date
    let lastVisited: Date
}
