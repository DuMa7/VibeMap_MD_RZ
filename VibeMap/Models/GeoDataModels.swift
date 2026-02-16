//
//  for.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 15.02.2026.
//


//
//  GeoDataModels.swift
//  VibeMap
//
//  Created by Claude on 15.02.2026.
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Geographic Hierarchy

/// Base protocol for all geographic entities
protocol GeographicEntity {
    var name: String { get }
    var boundary: [CLLocationCoordinate2D] { get }
    var exploredHexes: Set<String> { get set }
    var areaSquareMeters: Double { get }
    
    func explorationPercentage(hexAreaM2: Double) -> Double
}

extension GeographicEntity {
    /// Calculate exploration percentage based on hex coverage
    func explorationPercentage(hexAreaM2: Double) -> Double {
        guard areaSquareMeters > 0 else { return 0 }
        let exploredArea = Double(exploredHexes.count) * hexAreaM2
        return (exploredArea / areaSquareMeters) * 100
    }
}

// MARK: - Country

struct Country: GeographicEntity, Identifiable, Codable {
    let id: String
    let name: String
    let boundary: [CLLocationCoordinate2D]
    let areaSquareMeters: Double
    var exploredHexes: Set<String> = []
    var cantons: [Canton] = []
    
    init(id: String, name: String, boundary: [CLLocationCoordinate2D], areaSquareMeters: Double) {
        self.id = id
        self.name = name
        self.boundary = boundary
        self.areaSquareMeters = areaSquareMeters
    }
    
    // Codable conformance for CLLocationCoordinate2D
    enum CodingKeys: String, CodingKey {
        case id, name, areaSquareMeters, exploredHexes, cantons
        case boundaryLats, boundaryLons
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        areaSquareMeters = try container.decode(Double.self, forKey: .areaSquareMeters)
        exploredHexes = try container.decode(Set<String>.self, forKey: .exploredHexes)
        cantons = try container.decode([Canton].self, forKey: .cantons)
        
        let lats = try container.decode([Double].self, forKey: .boundaryLats)
        let lons = try container.decode([Double].self, forKey: .boundaryLons)
        boundary = zip(lats, lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(areaSquareMeters, forKey: .areaSquareMeters)
        try container.encode(exploredHexes, forKey: .exploredHexes)
        try container.encode(cantons, forKey: .cantons)
        
        let lats = boundary.map { $0.latitude }
        let lons = boundary.map { $0.longitude }
        try container.encode(lats, forKey: .boundaryLats)
        try container.encode(lons, forKey: .boundaryLons)
    }
}

// MARK: - Canton (Region)

struct Canton: GeographicEntity, Identifiable, Codable {
    let id: String
    let name: String
    let abbreviation: String
    let boundary: [CLLocationCoordinate2D]
    let areaSquareMeters: Double
    var exploredHexes: Set<String> = []
    var communes: [Commune] = []
    
    var exploredCommuneCount: Int {
        communes.filter { !$0.exploredHexes.isEmpty }.count
    }
    
    var totalCommunes: Int {
        communes.count
    }
    
    /// Alternative percentage: % of communes that have been explored
    var communeExplorationPercentage: Double {
        guard totalCommunes > 0 else { return 0 }
        return (Double(exploredCommuneCount) / Double(totalCommunes)) * 100
    }
    
    init(id: String, name: String, abbreviation: String, boundary: [CLLocationCoordinate2D], areaSquareMeters: Double) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.boundary = boundary
        self.areaSquareMeters = areaSquareMeters
    }
    
    // Codable conformance
    enum CodingKeys: String, CodingKey {
        case id, name, abbreviation, areaSquareMeters, exploredHexes, communes
        case boundaryLats, boundaryLons
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        abbreviation = try container.decode(String.self, forKey: .abbreviation)
        areaSquareMeters = try container.decode(Double.self, forKey: .areaSquareMeters)
        exploredHexes = try container.decode(Set<String>.self, forKey: .exploredHexes)
        communes = try container.decode([Commune].self, forKey: .communes)
        
        let lats = try container.decode([Double].self, forKey: .boundaryLats)
        let lons = try container.decode([Double].self, forKey: .boundaryLons)
        boundary = zip(lats, lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(abbreviation, forKey: .abbreviation)
        try container.encode(areaSquareMeters, forKey: .areaSquareMeters)
        try container.encode(exploredHexes, forKey: .exploredHexes)
        try container.encode(communes, forKey: .communes)
        
        let lats = boundary.map { $0.latitude }
        let lons = boundary.map { $0.longitude }
        try container.encode(lats, forKey: .boundaryLats)
        try container.encode(lons, forKey: .boundaryLons)
    }
}

// MARK: - Commune (Municipality/City)

struct Commune: GeographicEntity, Identifiable, Codable {
    let id: String
    let name: String
    let cantonId: String
    let boundary: [CLLocationCoordinate2D]
    let areaSquareMeters: Double
    var exploredHexes: Set<String> = []
    
    init(id: String, name: String, cantonId: String, boundary: [CLLocationCoordinate2D], areaSquareMeters: Double) {
        self.id = id
        self.name = name
        self.cantonId = cantonId
        self.boundary = boundary
        self.areaSquareMeters = areaSquareMeters
    }
    
    // Codable conformance
    enum CodingKeys: String, CodingKey {
        case id, name, cantonId, areaSquareMeters, exploredHexes
        case boundaryLats, boundaryLons
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cantonId = try container.decode(String.self, forKey: .cantonId)
        areaSquareMeters = try container.decode(Double.self, forKey: .areaSquareMeters)
        exploredHexes = try container.decode(Set<String>.self, forKey: .exploredHexes)
        
        let lats = try container.decode([Double].self, forKey: .boundaryLats)
        let lons = try container.decode([Double].self, forKey: .boundaryLons)
        boundary = zip(lats, lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(cantonId, forKey: .cantonId)
        try container.encode(areaSquareMeters, forKey: .areaSquareMeters)
        try container.encode(exploredHexes, forKey: .exploredHexes)
        
        let lats = boundary.map { $0.latitude }
        let lons = boundary.map { $0.longitude }
        try container.encode(lats, forKey: .boundaryLats)
        try container.encode(lons, forKey: .boundaryLons)
    }
}

// MARK: - Geographic Level Enum

enum GeographicLevel {
    case world
    case country
    case region  // Canton
    case city    // Commune
}