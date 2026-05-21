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
        Task { await loadLayers() }
    }

    @MainActor
    private func loadLayers() async {
        cantons = loadGeoJSON(filename: "cantons")
        municipalities = loadMunicipalitiesGeoJSON()
        print("🗺️ Loaded \(cantons.count) cantons, \(municipalities.count) municipalities")
    }

    // MARK: - Generic canton loader (geometry + id/name only)

    private func loadGeoJSON(filename: String) -> [GeoRegion] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let features = try? MKGeoJSONDecoder().decode(data) as? [MKGeoJSONFeature]
        else { return [] }

        return features.compactMap { feature in
            guard let props = feature.properties,
                  let dict = try? JSONSerialization.jsonObject(with: props) as? [String: Any]
            else { return nil }

            let id   = dict["id"].map { "\($0)" } ?? UUID().uuidString
            let name = dict["name"] as? String ?? "Unknown"

            return GeoRegion(id: id, name: name, polygons: extractPolygons(from: feature))
        }
    }

    // MARK: - Municipality loader — single pass for both geometry and metadata

    /// Parses municipalities.geojson once, populating:
    ///   • self.municipalities  — GeoRegion array for map rendering
    ///   • RegionMetadataManager.shared.municipalities — id→(name,cantonID) for app-wide lookups
    private func loadMunicipalitiesGeoJSON() -> [GeoRegion] {
        guard let url = Bundle.main.url(forResource: "municipalities", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let features = try? MKGeoJSONDecoder().decode(data) as? [MKGeoJSONFeature]
        else { return [] }

        var regions: [GeoRegion] = []
        var metadata: [String: (name: String, cantonID: String)] = [:]

        for feature in features {
            guard let props = feature.properties,
                  let dict = try? JSONSerialization.jsonObject(with: props) as? [String: Any],
                  let idVal = dict["id"],
                  let name = dict["name"] as? String
            else { continue }

            let id       = "\(idVal)"
            let cantonID = "\(dict["KTNR"] ?? "Unknown")"

            metadata[id] = (name: name, cantonID: cantonID)
            regions.append(GeoRegion(id: id, name: name, polygons: extractPolygons(from: feature)))
        }

        RegionMetadataManager.shared.municipalities = metadata
        print("✅ Municipality metadata: \(metadata.count) entries")

        return regions
    }

    // MARK: - Geometry helpers

    private func extractPolygons(from feature: MKGeoJSONFeature) -> [[CLLocationCoordinate2D]] {
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
        return polys
    }

    private func extractCoords(from polygon: MKPolygon) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                              count: polygon.pointCount)
        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
        return coords
    }
}
