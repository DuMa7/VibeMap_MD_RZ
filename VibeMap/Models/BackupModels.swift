import Foundation

// The Codable DTOs are nonisolated so encoding can run inside detached tasks
// (the project's default actor isolation is MainActor).
nonisolated struct BackupData: Codable {
    let version: Int
    let timestamp: Date
    let hexes: [HexBackupDTO]
    let regions: [RegionBackupDTO]
}

nonisolated struct HexBackupDTO: Codable {
    let h3Index: String
    let resolution: Int
    let regionID: String?
    let visitCount: Int
    let firstVisited: Date
    let lastVisited: Date
}

nonisolated struct RegionBackupDTO: Codable {
    let regionID: String
    let name: String
    let type: String
    let totalHexes: Int
    let exploredHexes: [String]
    let firstVisited: Date
    let lastVisited: Date
}

/// Summary of a backup file — shown in the restore preview before committing.
struct BackupPreview {
    let hexCount: Int
    let regionCount: Int
    let timestamp: Date
    let version: Int
}

enum BackupError: LocalizedError {
    case noData

    var errorDescription: String? {
        switch self {
        case .noData: return "No data to back up."
        }
    }
}
