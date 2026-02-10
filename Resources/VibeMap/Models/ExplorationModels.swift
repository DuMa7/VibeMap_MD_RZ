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
    @Attribute(.unique) var h3Index: String  // Hex index as string
    var firstVisited: Date
    var lastVisited: Date
    var visitCount: Int
    
    init(h3Index: String, firstVisited: Date = Date()) {
        self.h3Index = h3Index
        self.firstVisited = firstVisited
        self.lastVisited = firstVisited
        self.visitCount = 1
    }
    
    func recordVisit() {
        self.lastVisited = Date()
        self.visitCount += 1
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
