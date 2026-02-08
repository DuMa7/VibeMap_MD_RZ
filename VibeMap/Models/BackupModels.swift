//
//  BackupModels.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 08.02.2026.
//

import Foundation

// A container for all our app data
struct BackupData: Codable {
    let version: Int
    let timestamp: Date
    let hexes: [HexBackupDTO]
    let cities: [CityBackupDTO]
}

struct HexBackupDTO: Codable {
    let h3Index: String
    let visitCount: Int
    let firstVisited: Date
    let lastVisited: Date
}

struct CityBackupDTO: Codable {
    let cityName: String
    let country: String
    let centerLat: Double
    let centerLon: Double
    let radius: Double
    let totalHexes: Int
    let exploredHexes: [String]
}
