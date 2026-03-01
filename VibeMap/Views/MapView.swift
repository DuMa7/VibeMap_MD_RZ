import SwiftUI
import MapKit

struct MapView: View {
    @Binding var position: MapCameraPosition
    @Binding var currentSpan: Double
    @Binding var centerCoordinate: CLLocationCoordinate2D?
    
    @State private var mapStyle: MapStyle = .standard
    
    /// Cache of pre-computed hex boundary polygons — keyed by h3Index.
    /// Computed once per hex via the H3 C library, reused on every subsequent redraw.
    /// Invalidated and rebuilt only when exploredHexes changes.
    @State private var polygonCache: [String: [CLLocationCoordinate2D]] = [:]
    
    /// Canton IDs of all visited regions — cached to avoid recomputing on every render pass
    @State private var cachedCantonIDs: Set<String> = []
    
    var exploredHexes: [ExploredHex]
    var regions: [RegionExploration]
    var layerManager: MapLayerManager
    var userLocation: CLLocationCoordinate2D?
    
    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            
            if currentSpan >= 10.0 {
                // World level — no overlays
            } else if currentSpan >= 2.0 {
                ForEach(layerManager.cantons.filter { cachedCantonIDs.contains($0.id) }) { canton in
                    ForEach(0..<canton.polygons.count, id: \.self) { i in
                        MapPolygon(coordinates: canton.polygons[i])
                            .foregroundStyle(.orange.opacity(0.5))
                            .stroke(.white, lineWidth: 1.5)
                    }
                }
            } else if currentSpan >= 0.2 {
                ForEach(layerManager.municipalities.filter { muni in
                    regions.contains(where: { $0.regionID == muni.id })
                }) { muni in
                    ForEach(0..<muni.polygons.count, id: \.self) { i in
                        MapPolygon(coordinates: muni.polygons[i])
                            .foregroundStyle(colorForRegion(muni.id))
                            .stroke(.white.opacity(0.3), lineWidth: 0.5)
                    }
                }
            } else if currentSpan >= 0.02 {
                // Res 9 hexes only (rural/lake level)
                ForEach(exploredHexes.filter { $0.resolution == 9 }, id: \.h3Index) { hex in
                    if let polygon = polygonCache[hex.h3Index] {
                        MapPolygon(coordinates: polygon)
                            .foregroundStyle(.orange.opacity(0.4))
                            .stroke(.orange, lineWidth: 1)
                    }
                }
            } else {
                // All hexes (street level)
                ForEach(exploredHexes, id: \.h3Index) { hex in
                    if let polygon = polygonCache[hex.h3Index] {
                        MapPolygon(coordinates: polygon)
                            .foregroundStyle(.orange.opacity(0.4))
                            .stroke(.orange, lineWidth: 1)
                    }
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControlVisibility(.hidden)
        .animation(.easeInOut(duration: 0.5), value: currentSpan)
        .onMapCameraChange(frequency: .onEnd) { context in
            currentSpan = context.region.span.latitudeDelta
            centerCoordinate = context.region.center
        }
        // Seed both caches on first appear
        .onAppear {
            cachedCantonIDs = buildCantonIDs()
            rebuildPolygonCache()
        }
        // Rebuild polygon cache only when the hex list changes
        .onChange(of: exploredHexes) { _, _ in
            rebuildPolygonCache()
            cachedCantonIDs = buildCantonIDs()
        }
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button { mapStyle = .standard } label: { Label("Standard", systemImage: "map") }
                Button { mapStyle = .hybrid }  label: { Label("Satellite", systemImage: "globe.americas.fill") }
                Button { mapStyle = .imagery } label: { Label("Imagery", systemImage: "photo") }
            } label: {
                Image(systemName: "map.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.gray.opacity(0.8))
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Cache Builders
    
    /// Builds the polygon cache for all explored hexes.
    /// Only hexes not already in the cache are computed — existing entries are preserved.
    /// This means adding 1 new hex only computes 1 new polygon, not all of them.
    private func rebuildPolygonCache() {
        let newHexes = exploredHexes.filter { polygonCache[$0.h3Index] == nil }
        guard !newHexes.isEmpty else { return }
        
        for hex in newHexes {
            if let polygon = computePolygon(h3Index: hex.h3Index) {
                polygonCache[hex.h3Index] = polygon
            }
        }
        
        print("📐 Polygon cache: added \(newHexes.count) new entries, total \(polygonCache.count)")
    }
    
    /// Builds the canton ID set from visited regions.
    /// Only recalculated when the regions array changes.
    private func buildCantonIDs() -> Set<String> {
        let ids = regions.compactMap { region in
            RegionMetadataManager.shared.municipalities[region.regionID]?.cantonID
        }
        return Set(ids)
    }
    
    // MARK: - Helpers
    
    /// Computes the boundary polygon for a single hex index via the H3 C library.
    /// This is the only place the C library is called — result is cached immediately after.
    private func computePolygon(h3Index: String) -> [CLLocationCoordinate2D]? {
        guard let index = UInt64(h3Index, radix: 16) else { return nil }
        var cellBoundary = CellBoundary()
        let error = cellToBoundary(index, &cellBoundary)
        guard error == 0 else { return nil }
        
        var coordinates: [CLLocationCoordinate2D] = []
        withUnsafeBytes(of: cellBoundary.verts) { rawBuffer in
            let vertsBuffer = rawBuffer.bindMemory(to: LatLng.self)
            for i in 0..<Int(cellBoundary.numVerts) {
                let vertex = vertsBuffer[i]
                coordinates.append(CLLocationCoordinate2D(
                    latitude:  vertex.lat * 180.0 / .pi,
                    longitude: vertex.lng * 180.0 / .pi
                ))
            }
        }
        return coordinates
    }
    
    /// Returns an opacity-scaled orange style for a region based on its exploration percentage.
    /// Regions with 0 totalHexes return clear to avoid division by zero.
    private func colorForRegion(_ id: String) -> AnyShapeStyle {
        guard let region = regions.first(where: { $0.regionID == id }), region.totalHexes > 0 else {
            return AnyShapeStyle(.clear)
        }
        let percentage = Double(region.exploredHexes.count) / Double(region.totalHexes)
        return AnyShapeStyle(.orange.opacity(max(0.15, percentage)))
    }
}

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
