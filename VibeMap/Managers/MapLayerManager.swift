import Foundation
import MapKit
import SwiftUI

struct GeoRegion: Identifiable {
    let id: String
    let name: String
    let polygons: [[CLLocationCoordinate2D]]
}

@Observable
class MapLayerManager {
    var cantons: [GeoRegion] = []
    var municipalities: [GeoRegion] = []
    
    init() {
        Task {
            await loadLayers()
        }
    }
    
    @MainActor
    private func loadLayers() async {
        self.cantons = loadGeoJSON(filename: "cantons")
        self.municipalities = loadGeoJSON(filename: "municipalities")
        print("🗺️ Loaded \(cantons.count) Cantons and \(municipalities.count) Municipalities")
    }
    
    private func loadGeoJSON(filename: String) -> [GeoRegion] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "geojson"),
              let data = try? Data(contentsOf: url) else { return [] }
        
        let decoder = MKGeoJSONDecoder()
        guard let features = try? decoder.decode(data) as? [MKGeoJSONFeature] else { return [] }
        
        var loadedRegions: [GeoRegion] = []
        
        for feature in features {
            var regionId = UUID().uuidString
            var regionName = "Unknown"
            
            if let props = feature.properties,
               let dict = try? JSONSerialization.jsonObject(with: props) as? [String: Any] {
                if let id = dict["id"] { regionId = "\(id)" }
                if let name = dict["name"] as? String { regionName = name }
            }
            
            var polys: [[CLLocationCoordinate2D]] = []
            for geo in feature.geometry {
                if let polygon = geo as? MKPolygon {
                    polys.append(extractCoords(from: polygon))
                } else if let multi = geo as? MKMultiPolygon {
                    for polygon in multi.polygons {
                        polys.append(extractCoords(from: polygon))
                    }
                }
            }
            
            loadedRegions.append(GeoRegion(id: regionId, name: regionName, polygons: polys))
        }
        return loadedRegions
    }
    
    private func extractCoords(from polygon: MKPolygon) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polygon.pointCount)
        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
        return coords
    }
}
