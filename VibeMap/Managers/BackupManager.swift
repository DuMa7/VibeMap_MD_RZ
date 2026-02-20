import Foundation
import SwiftData
import SwiftUI

@MainActor
class BackupManager {
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Export
    
    func createBackupJSON() -> String? {
        do {
            // 1. Fetch all data
            let hexDescriptor = FetchDescriptor<ExploredHex>()
            let regionDescriptor = FetchDescriptor<RegionExploration>()
            
            let hexes = try modelContext.fetch(hexDescriptor)
            let regions = try modelContext.fetch(regionDescriptor)
            
            // 2. Convert to DTOs
            let hexDTOs = hexes.map { hex in
                HexBackupDTO(
                    h3Index: hex.h3Index,
                    resolution: hex.resolution,
                    regionID: hex.regionID,
                    visitCount: hex.visitCount,
                    firstVisited: hex.firstVisited,
                    lastVisited: hex.lastVisited
                )
            }
            
            let regionDTOs = regions.map { region in
                RegionBackupDTO(
                    regionID: region.regionID,
                    name: region.name,
                    type: region.type,
                    totalHexes: region.totalHexes,
                    exploredHexes: region.exploredHexes,
                    firstVisited: region.firstVisited,
                    lastVisited: region.lastVisited
                )
            }
            
            // 3. Encode
            let backup = BackupData(
                version: 2, // Bumped version for new schema
                timestamp: Date(),
                hexes: hexDTOs,
                regions: regionDTOs
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            
            let data = try encoder.encode(backup)
            return String(data: data, encoding: .utf8)
            
        } catch {
            print("❌ Backup failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Import
    
    func restoreFromJSON(url: URL) async throws {
        // 1. Read & Decode
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let backup = try decoder.decode(BackupData.self, from: data)
        
        // 2. Clear existing data
        try clearDatabase()
        
        // 3. Insert new data
        for hexDTO in backup.hexes {
            let hex = ExploredHex(h3Index: hexDTO.h3Index, resolution: hexDTO.resolution, regionID: hexDTO.regionID)
            hex.firstVisited = hexDTO.firstVisited
            hex.lastVisited = hexDTO.lastVisited
            hex.visitCount = hexDTO.visitCount
            modelContext.insert(hex)
        }
        
        for regionDTO in backup.regions {
            let region = RegionExploration(
                regionID: regionDTO.regionID,
                name: regionDTO.name,
                type: regionDTO.type,
                totalHexes: regionDTO.totalHexes
            )
            region.exploredHexes = regionDTO.exploredHexes
            region.firstVisited = regionDTO.firstVisited
            region.lastVisited = regionDTO.lastVisited
            modelContext.insert(region)
        }
        
        try modelContext.save()
        print("✅ Restore complete: \(backup.hexes.count) hexes restored.")
    }
    
    private func clearDatabase() throws {
        try modelContext.delete(model: ExploredHex.self)
        try modelContext.delete(model: RegionExploration.self)
        try modelContext.delete(model: LocationPoint.self)
    }
}
