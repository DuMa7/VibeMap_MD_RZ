//
//  LiveLocationDetector.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 22.02.2026.
//


import Foundation
import CoreLocation
import Observation
import H3

@Observable
class LiveLocationDetector {
    static let shared = LiveLocationDetector()
    
    private(set) var currentRegionID: String? = nil
    private(set) var currentMunicipalityName: String = "Locating..."
    private(set) var currentCantonName: String = ""
    
    private init() {}
    
    func detect(coordinate: CLLocationCoordinate2D, cantons: [GeoRegion]) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            // H3 lookup
            let latRads = coordinate.latitude * .pi / 180.0
            let lonRads = coordinate.longitude * .pi / 180.0
            var coord = LatLng(lat: latRads, lng: lonRads)
            
            var h3Index10: H3Index = 0
            var h3Index9: H3Index = 0
            latLngToCell(&coord, Int32(10), &h3Index10)
            latLngToCell(&coord, Int32(9), &h3Index9)
            
            let hex10 = String(h3Index10, radix: 16)
            let hex9 = String(h3Index9, radix: 16)
            
            // SQLite lookup
            guard let regionData = OfflineDatabase.shared.getRegionData(res10: hex10, res9: hex9) else {
                await MainActor.run {
                    self.currentRegionID = nil
                    self.currentMunicipalityName = "Unknown Area"
                    self.currentCantonName = ""
                }
                return
            }
            
            // Metadata lookup
            let regionID = regionData.regionID
            let metadata = RegionMetadataManager.shared.municipalities[regionID]
            let municipalityName = self.getPrimaryName(from: metadata?.name ?? "Unknown Area")
            
            var cantonName = ""
            if let cantonID = metadata?.cantonID,
               let canton = cantons.first(where: { $0.id == cantonID }) {
                cantonName = self.getPrimaryName(from: canton.name)
            }
            
            await MainActor.run {
                self.currentRegionID = regionID
                self.currentMunicipalityName = municipalityName
                self.currentCantonName = cantonName
            }
        }
    }
    
    private func getPrimaryName(from fullName: String) -> String {
        let separators = CharacterSet(charactersIn: "/,(")
        let parts = fullName.components(separatedBy: separators)
        return parts.first?.trimmingCharacters(in: .whitespaces) ?? fullName
    }
}