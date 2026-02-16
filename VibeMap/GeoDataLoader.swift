//
//  GeoDataLoader.swift
//  VibeMap
//
//  Created by Claude on 15.02.2026.
//

import Foundation
import CoreLocation

/// Loads and parses Swiss geographic data from TopoJSON
class GeoDataLoader {
    
    static let shared = GeoDataLoader()
    
    // Cache the loaded data
    private var switzerlandData: Country?
    
    private init() {}
    
    // MARK: - Main Loading Function
    
    /// Load Switzerland geographic data from bundled TopoJSON
    func loadSwitzerlandData() async throws -> Country {
        // Return cached if available
        if let cached = switzerlandData {
            return cached
        }
        
        // Load from bundle
        guard let url = Bundle.main.url(forResource: "SwissRegions", withExtension: "json") else {
            throw GeoDataError.fileNotFound
        }
        
        let data = try Data(contentsOf: url)
        let topoJSON = try JSONDecoder().decode(TopoJSONRoot.self, from: data)
        
        // Parse TopoJSON into Swift models
        let switzerland = try parseTopoJSON(topoJSON)
        
        // Cache result
        switzerlandData = switzerland
        
        print("🇨🇭 Loaded Switzerland with \(switzerland.cantons.count) cantons")
        return switzerland
    }
    
    // MARK: - TopoJSON Parsing
    
    private func parseTopoJSON(_ topo: TopoJSONRoot) throws -> Country {
        // The swiss-maps file contains: country, cantons, municipalities
        // We need to extract these and build the hierarchy
        
        // For now, create a simple structure
        // In the next step, we'll properly decode the TopoJSON arcs
        
        // Placeholder for demonstration
        let switzerland = Country(
            id: "CH",
            name: "Switzerland",
            boundary: [],  // Will be populated from TopoJSON
            areaSquareMeters: 41_285_000_000 // ~41,285 km²
        )
        
        print("⚠️ TopoJSON parsing not yet fully implemented")
        print("   This is a placeholder - full parsing coming next")
        
        return switzerland
    }
    
    // MARK: - Helper Functions
    
    /// Calculate area of a polygon using Shoelace formula
    private func calculateArea(coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 3 else { return 0 }
        
        var area: Double = 0
        let earthRadiusMeters: Double = 6_371_000
        
        for i in 0..<coordinates.count {
            let j = (i + 1) % coordinates.count
            let lat1 = coordinates[i].latitude * .pi / 180
            let lat2 = coordinates[j].latitude * .pi / 180
            let lon1 = coordinates[i].longitude * .pi / 180
            let lon2 = coordinates[j].longitude * .pi / 180
            
            area += (lon2 - lon1) * (2 + sin(lat1) + sin(lat2))
        }
        
        area = abs(area) * earthRadiusMeters * earthRadiusMeters / 2
        return area
    }
}

// MARK: - TopoJSON Data Structures

/// Root structure of TopoJSON file
struct TopoJSONRoot: Codable {
    let type: String
    let arcs: [[[ Double]]]  // Array of arc arrays
    let transform: TopoJSONTransform?
    let objects: [String: TopoJSONObject]
    
    struct TopoJSONTransform: Codable {
        let scale: [Double]
        let translate: [Double]
    }
}

/// TopoJSON geometry object
struct TopoJSONObject: Codable {
    let type: String
    let geometries: [TopoJSONGeometry]?
}

/// Individual geometry within TopoJSON
struct TopoJSONGeometry: Codable {
    let type: String
    let id: String?
    let properties: [String: AnyCodable]?
    let arcs: AnyCodableArcs?
    
    // Custom decoding for flexible arc structures
    struct AnyCodableArcs: Codable {
        let value: Any
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            
            // Try different possible structures
            if let intArray = try? container.decode([[Int]].self) {
                value = intArray
            } else if let intArrayArray = try? container.decode([[[Int]]].self) {
                value = intArrayArray
            } else {
                value = []
            }
        }
        
        func encode(to encoder: Encoder) throws {
            // Not needed for our use case
        }
    }
}

/// Helper for dynamic JSON values
struct AnyCodable: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Errors

enum GeoDataError: LocalizedError {
    case fileNotFound
    case parsingFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "SwissRegions.json not found in bundle"
        case .parsingFailed:
            return "Failed to parse TopoJSON data"
        case .invalidData:
            return "Invalid geographic data structure"
        }
    }
}