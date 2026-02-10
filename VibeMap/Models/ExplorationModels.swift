//
//  ExplorationModels.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 07.02.2026.
//


import Foundation
import SwiftData

@Model
class ExploredHex {
    @Attribute(.unique) var h3Index: String
    var visitCount: Int = 1
    var firstVisited: Date = Date()
    var lastVisited: Date = Date()
    
    // NEW: Track if this is a high-density area
    // Default to false (Rural)
    var isUrban: Bool = false
    
    init(h3Index: String, isUrban: Bool = false) { // Updated Init
        self.h3Index = h3Index
        self.isUrban = isUrban
    }
    
    init(h3Index: String, firstVisited: Date = Date()) {
        self.h3Index = h3Index
        self.firstVisited = firstVisited
        self.lastVisited = firstVisited
        self.visitCount = 1
    }
    
    func recordVisit() {
        visitCount += 1
        lastVisited = Date()
    }
}
    
@Model
class LocationPoint {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var h3Index: String
    
    init(latitude: Double, longitude: Double, h3Index: String, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.h3Index = h3Index
        self.timestamp = timestamp
    }
}
