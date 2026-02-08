//
//  CityExploration.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 07.02.2026.
//


import Foundation
import SwiftData
import CoreLocation

@Model
class CityExploration {
    @Attribute(.unique) var cityName: String
    var country: String
    var centerLatitude: Double
    var centerLongitude: Double
    var radiusInMeters: Double // Approximate city size
    var totalHexesInBoundary: Int
    var exploredHexes: [String] // Array of h3Index strings
    var firstVisited: Date
    var lastVisited: Date
    
    init(cityName: String, country: String, centerLat: Double, centerLon: Double, radius: Double = 5000) {
        self.cityName = cityName
        self.country = country
        self.centerLatitude = centerLat
        self.centerLongitude = centerLon
        self.radiusInMeters = radius
        self.totalHexesInBoundary = 0
        self.exploredHexes = []
        self.firstVisited = Date()
        self.lastVisited = Date()
    }
    
    var explorationPercentage: Double {
        guard totalHexesInBoundary > 0 else { return 0 }
        return (Double(exploredHexes.count) / Double(totalHexesInBoundary)) * 100
    }
    
    func addExploredHex(_ h3Index: String) {
        if !exploredHexes.contains(h3Index) {
            exploredHexes.append(h3Index)
            lastVisited = Date()
        }
    }
}
    