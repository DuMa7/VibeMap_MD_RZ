import Foundation
import SwiftData
import SwiftUI

@MainActor
class BackupManager {
    let modelContext: ModelContext

    private static let autoBackupFilename = "vibemap_backup.json"
    private static let previousBackupFilename = "vibemap_backup_previous.json"

    /// Keeps the auto-backup write alive when the app is heading to the background.
    private var backupTaskID: UIBackgroundTaskIdentifier = .invalid

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Encode

    private func buildBackupData() throws -> BackupData {
        let hexes = try modelContext.fetch(FetchDescriptor<ExploredHex>())
        let regions = try modelContext.fetch(FetchDescriptor<RegionExploration>())

        guard !hexes.isEmpty || !regions.isEmpty else { throw BackupError.noData }

        let hexDTOs = hexes.map {
            HexBackupDTO(h3Index: $0.h3Index, resolution: $0.resolution, regionID: $0.regionID,
                         visitCount: $0.visitCount, firstVisited: $0.firstVisited, lastVisited: $0.lastVisited)
        }
        let regionDTOs = regions.map {
            RegionBackupDTO(regionID: $0.regionID, name: $0.name, type: $0.type,
                            totalHexes: $0.totalHexes, exploredHexes: $0.exploredHexes,
                            firstVisited: $0.firstVisited, lastVisited: $0.lastVisited)
        }
        return BackupData(version: 2, timestamp: Date(), hexes: hexDTOs, regions: regionDTOs)
    }

    /// Compact JSON — no pretty-printing, which roughly halved the file size.
    /// nonisolated static so encoding can run inside detached tasks.
    private nonisolated static func encode(_ backup: BackupData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    // MARK: - Export (share sheet)

    /// Writes the backup to a temp file and returns the URL for sharing.
    /// The SwiftData fetch runs on the main actor; encoding and writing run detached.
    func createBackupFile() async throws -> URL {
        let backup = try buildBackupData()
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibemap_backup_\(dateStr).json")
        try await Task.detached(priority: .userInitiated) {
            let data = try Self.encode(backup)
            try data.write(to: url, options: .atomic)
        }.value
        return url
    }

    // MARK: - Auto-backup (app Documents, included in iCloud device backup)

    /// Builds the snapshot on the main actor (SwiftData), then encodes and writes it
    /// off-main, wrapped in a UIKit background task so the write completes even when
    /// triggered by the app moving to the background.
    func saveAutoBackup() async throws {
        let backup = try buildBackupData()

        beginBackgroundTask()
        defer { endBackgroundTask() }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let current = docs.appendingPathComponent(Self.autoBackupFilename)
        let previous = docs.appendingPathComponent(Self.previousBackupFilename)

        try await Task.detached(priority: .utility) {
            let data = try Self.encode(backup)

            // Rotate: current → previous before overwriting
            if FileManager.default.fileExists(atPath: current.path) {
                try? FileManager.default.removeItem(at: previous)
                try? FileManager.default.moveItem(at: current, to: previous)
            }

            try data.write(to: current, options: .atomic)
            print("💾 Auto-backup saved (\(data.count / 1024) KB)")
        }.value
    }

    private func beginBackgroundTask() {
        backupTaskID = UIApplication.shared.beginBackgroundTask(withName: "AutoBackup") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backupTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backupTaskID)
            backupTaskID = .invalid
        }
    }

    /// Date of the most recent auto-backup, or nil if none exists.
    func lastAutoBackupDate() -> Date? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent(Self.autoBackupFilename)
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    // MARK: - Restore Preview

    /// Parses just the metadata from backup data without touching the database.
    func previewBackup(data: Data) throws -> BackupPreview {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)
        return BackupPreview(hexCount: backup.hexes.count, regionCount: backup.regions.count,
                             timestamp: backup.timestamp, version: backup.version)
    }

    // MARK: - Restore

    /// Replaces all local data with the contents of the supplied backup data.
    func restoreFromData(_ data: Data) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)

        try clearDatabase()

        for dto in backup.hexes {
            let hex = ExploredHex(h3Index: dto.h3Index, resolution: dto.resolution, regionID: dto.regionID)
            hex.firstVisited = dto.firstVisited
            hex.lastVisited = dto.lastVisited
            hex.visitCount = dto.visitCount
            modelContext.insert(hex)
        }

        for dto in backup.regions {
            let region = RegionExploration(regionID: dto.regionID, name: dto.name,
                                           type: dto.type, totalHexes: dto.totalHexes)
            region.exploredHexes = dto.exploredHexes
            region.firstVisited = dto.firstVisited
            region.lastVisited = dto.lastVisited
            modelContext.insert(region)
        }

        try modelContext.save()
        print("✅ Restore complete: \(backup.hexes.count) hexes, \(backup.regions.count) regions.")
    }

    // MARK: - Internal

    private func clearDatabase() throws {
        try modelContext.delete(model: ExploredHex.self)
        try modelContext.delete(model: RegionExploration.self)
    }
}
