//
//  RegionExploration.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 19.02.2026.
//


import Foundation
import SwiftData

@Model
class RegionExploration {
    @Attribute(.unique) var regionID: String // Matches the ID in SQLite
    var name: String // e.g., "Zurich" or "Vaud"
    var type: String // "Municipality" or "Canton"
    var totalHexes: Int // Pre-calculated, read from SQLite
    var exploredHexes: [String] // Array of h3Index strings
    var firstVisited: Date
    var lastVisited: Date
    
    init(regionID: String, name: String, type: String, totalHexes: Int) {
        self.regionID = regionID
        self.name = name
        self.type = type
        self.totalHexes = totalHexes
        self.exploredHexes = []
        self.firstVisited = Date()
        self.lastVisited = Date()
    }
    
    var explorationPercentage: Double {
        guard totalHexes > 0 else { return 0 }
        return (Double(exploredHexes.count) / Double(totalHexes)) * 100
    }
    
    func addExploredHex(_ h3Index: String) {
        if !exploredHexes.contains(h3Index) {
            exploredHexes.append(h3Index)
            lastVisited = Date()
        }
    }
}