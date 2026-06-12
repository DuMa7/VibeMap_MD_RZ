import Foundation
import MapKit
import SwiftUI

/// nonisolated so instances can be constructed inside the detached GeoJSON parse
/// task (the project's default actor isolation is MainActor).
nonisolated struct GeoRegion: Identifiable {
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

    /// Parses both GeoJSON files (≈3.4 MB) in a detached task so the decode never
    /// blocks the main thread at startup, then publishes the results on the main
    /// actor — including the metadata side table consumed app-wide.
    private func loadLayers() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            let cantons = Self.loadGeoJSON(filename: "cantons")
            let munis   = Self.loadMunicipalitiesGeoJSON()
            return (cantons: cantons, municipalities: munis.regions, metadata: munis.metadata)
        }.value

        cantons = loaded.cantons
        municipalities = loaded.municipalities
        RegionMetadataManager.shared.municipalities = loaded.metadata
        print("🗺️ Loaded \(cantons.count) cantons, \(municipalities.count) municipalities")
        print("✅ Municipality metadata: \(loaded.metadata.count) entries")
    }

    // MARK: - Generic canton loader (geometry + id/name only)

    private nonisolated static func loadGeoJSON(filename: String) -> [GeoRegion] {
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

    /// Parses municipalities.geojson once, returning:
    ///   • regions  — GeoRegion array for map rendering
    ///   • metadata — id → (name, cantonID) for RegionMetadataManager
    /// Pure function: the caller publishes both results on the main actor.
    private nonisolated static func loadMunicipalitiesGeoJSON()
        -> (regions: [GeoRegion], metadata: [String: (name: String, cantonID: String)]) {
        guard let url = Bundle.main.url(forResource: "municipalities", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let features = try? MKGeoJSONDecoder().decode(data) as? [MKGeoJSONFeature]
        else { return ([], [:]) }

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

        return (regions, metadata)
    }

    // MARK: - Geometry helpers

    private nonisolated static func extractPolygons(from feature: MKGeoJSONFeature) -> [[CLLocationCoordinate2D]] {
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

    private nonisolated static func extractCoords(from polygon: MKPolygon) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                              count: polygon.pointCount)
        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
        return coords
    }
}
