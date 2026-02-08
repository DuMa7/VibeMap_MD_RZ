//
//  BackupManager.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 08.02.2026.
//


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
            let cityDescriptor = FetchDescriptor<CityExploration>()
            
            let hexes = try modelContext.fetch(hexDescriptor)
            let cities = try modelContext.fetch(cityDescriptor)
            
            // 2. Convert to DTOs
            let hexDTOs = hexes.map { hex in
                HexBackupDTO(
                    h3Index: hex.h3Index,
                    visitCount: hex.visitCount,
                    firstVisited: hex.firstVisited,
                    lastVisited: hex.lastVisited
                )
            }
            
            let cityDTOs = cities.map { city in
                CityBackupDTO(
                    cityName: city.cityName,
                    country: city.country,
                    centerLat: city.centerLatitude,
                    centerLon: city.centerLongitude,
                    radius: city.radiusInMeters,
                    totalHexes: city.totalHexesInBoundary,
                    exploredHexes: city.exploredHexes
                )
            }
            
            // 3. Encode
            let backup = BackupData(
                version: 1,
                timestamp: Date(),
                hexes: hexDTOs,
                cities: cityDTOs
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
        
        // 2. Clear existing data (Optional: You might want to merge instead)
        try clearDatabase()
        
        // 3. Insert new data
        for hexDTO in backup.hexes {
            let hex = ExploredHex(h3Index: hexDTO.h3Index, firstVisited: hexDTO.firstVisited)
            hex.lastVisited = hexDTO.lastVisited
            hex.visitCount = hexDTO.visitCount
            modelContext.insert(hex)
        }
        
        for cityDTO in backup.cities {
            let city = CityExploration(
                cityName: cityDTO.cityName,
                country: cityDTO.country,
                centerLat: cityDTO.centerLat,
                centerLon: cityDTO.centerLon,
                radius: cityDTO.radius
            )
            city.totalHexesInBoundary = cityDTO.totalHexes
            city.exploredHexes = cityDTO.exploredHexes
            modelContext.insert(city)
        }
        
        try modelContext.save()
        print("✅ Restore complete: \(backup.hexes.count) hexes restored.")
    }
    
    private func clearDatabase() throws {
        try modelContext.delete(model: ExploredHex.self)
        try modelContext.delete(model: CityExploration.self)
        try modelContext.delete(model: LocationPoint.self) // Also clear points to be safe
    }
}