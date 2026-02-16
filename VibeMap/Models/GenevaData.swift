//
//  GenevaData.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 16.02.2026.
//


//
//  GenevaData.swift
//  VibeMap
//
//  Created by Claude on 15.02.2026.
//

import Foundation
import CoreLocation

/// Simple structure for Geneva canton
struct GenevaData {
    static let shared = GenevaData()
    
    // Geneva canton center (approximate)
    let center = CLLocationCoordinate2D(latitude: 46.2044, longitude: 6.1432)
    
    // Simplified Geneva boundary (WGS84 coordinates)
    // This is a rough boundary for testing - we'll refine later
    let boundary: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 46.3596, longitude: 5.9563),
        CLLocationCoordinate2D(latitude: 46.3596, longitude: 6.3094),
        CLLocationCoordinate2D(latitude: 46.1400, longitude: 6.3094),
        CLLocationCoordinate2D(latitude: 46.1400, longitude: 5.9563),
        CLLocationCoordinate2D(latitude: 46.3596, longitude: 5.9563)
    ]
    
    let name = "Geneva"
    let abbreviation = "GE"
    let id = "25"
    
    // Geneva communes (major ones)
    let communes = [
        "Geneva",
        "Vernier",
        "Lancy",
        "Meyrin",
        "Carouge",
        "Onex",
        "Thônex",
        "Versoix",
        "Grand-Saconnex",
        "Chêne-Bougeries"
    ]
    
    private init() {}
    
    /// Check if a coordinate is inside Geneva canton
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return isPoint(coordinate, inPolygon: boundary)
    }
    
    /// Ray-casting algorithm for point-in-polygon test
    private func isPoint(_ point: CLLocationCoordinate2D, inPolygon polygon: [CLLocationCoordinate2D]) -> Bool {
        guard polygon.count > 2 else { return false }
        
        var inside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            let xi = polygon[i].latitude
            let yi = polygon[i].longitude
            let xj = polygon[j].latitude
            let yj = polygon[j].longitude
            
            let intersect = ((yi > point.longitude) != (yj > point.longitude)) &&
                           (point.latitude < (xj - xi) * (point.longitude - yi) / (yj - yi) + xi)
            
            if intersect {
                inside.toggle()
            }
            
            j = i
        }
        
        return inside
    }
}