//
//  RegionMetadataManager.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 19.02.2026.
//


import Foundation
import MapKit

class RegionMetadataManager {
    static let shared = RegionMetadataManager()
    
    // Maps Region ID -> (Name, Canton ID)
    var municipalities: [String: (name: String, cantonID: String)] = [:]
    
    private init() {
        loadMetadata()
    }
    
    private func loadMetadata() {
        // Find the GeoJSON in the Xcode bundle
        guard let url = Bundle.main.url(forResource: "municipalities", withExtension: "geojson"),
              let data = try? Data(contentsOf: url) else {
            print("❌ Could not find municipalities.geojson in bundle.")
            return
        }
        
        let decoder = MKGeoJSONDecoder()
        if let features = try? decoder.decode(data) as? [MKGeoJSONFeature] {
            for feature in features {
                // Extract properties from the GeoJSON
                if let props = feature.properties,
                   let dict = try? JSONSerialization.jsonObject(with: props) as? [String: Any],
                   let idVal = dict["id"],
                   let name = dict["name"] as? String {
                    
                    let idStr = "\(idVal)"
                    // KTNR is the Canton Number in Swiss datasets
                    let cantonID = "\(dict["KTNR"] ?? "Unknown")" 
                    
                    self.municipalities[idStr] = (name: name, cantonID: cantonID)
                }
            }
            print("✅ Loaded \(self.municipalities.count) municipality names into memory.")
        }
    }
}