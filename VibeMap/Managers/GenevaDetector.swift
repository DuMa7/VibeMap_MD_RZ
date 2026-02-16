//
//  GenevaDetector.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 16.02.2026.
//


//
//  GenevaDetector.swift
//  VibeMap
//
//  Created by Claude on 15.02.2026.
//

import Foundation
import CoreLocation
import Observation

/// Simple location detector for Geneva canton
@Observable
class GenevaDetector {
    
    static let shared = GenevaDetector()
    
    // Current detected location
    private(set) var currentLocation: DetectedLocation = .unknown
    
    private init() {}
    
    enum DetectedLocation {
        case geneva
        case unknown
        
        var displayName: String {
            switch self {
            case .geneva: return "Geneva"
            case .unknown: return "Exploring"
            }
        }
    }
    
    /// Check if user is in Geneva and update current location
    func detect(coordinate: CLLocationCoordinate2D) {
        if GenevaData.shared.contains(coordinate) {
            if currentLocation != .geneva {
                currentLocation = .geneva
                print("🏙️ Entered Geneva!")
            }
        } else {
            if currentLocation != .unknown {
                currentLocation = .unknown
                print("🌍 Left Geneva / Unknown location")
            }
        }
    }
    
    /// Get display name for Central Stats Pill
    func getDisplayName() -> String {
        return currentLocation.displayName
    }
}