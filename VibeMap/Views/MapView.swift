import SwiftUI
import MapKit

struct MapView: View {
    @Binding var position: MapCameraPosition
    @Binding var currentSpan: Double
    @Binding var centerCoordinate: CLLocationCoordinate2D? // NEW: Exposes the map's center
    
    @State private var mapStyle: MapStyle = .standard
    
    var exploredHexes: [ExploredHex]
    var regions: [RegionExploration]
    var layerManager: MapLayerManager
    var userLocation: CLLocationCoordinate2D?
    
    private var visitedCantonIDs: Set<String> {
        let ids = regions.compactMap { region in
            RegionMetadataManager.shared.municipalities[region.regionID]?.cantonID
        }
        return Set(ids)
    }
    
    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            
            if currentSpan >= 10.0 {
                // World level
            } else if currentSpan >= 2.0 {
                ForEach(layerManager.cantons.filter { visitedCantonIDs.contains($0.id) }) { canton in
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
                ForEach(exploredHexes.filter { $0.resolution == 9 }, id: \.h3Index) { hex in
                    if let polygon = hexToPolygon(h3Index: hex.h3Index) {
                        MapPolygon(coordinates: polygon)
                            .foregroundStyle(.orange.opacity(0.4))
                            .stroke(.orange, lineWidth: 1)
                    }
                }
            } else {
                ForEach(exploredHexes, id: \.h3Index) { hex in
                    if let polygon = hexToPolygon(h3Index: hex.h3Index) {
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
            centerCoordinate = context.region.center // NEW: Updates the center coordinate when panning stops
        }
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button { mapStyle = .standard } label: { Label("Standard", systemImage: "map") }
                Button { mapStyle = .hybrid } label: { Label("Satellite", systemImage: "globe.americas.fill") }
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
    
    private func colorForRegion(_ id: String) -> AnyShapeStyle {
        guard let region = regions.first(where: { $0.regionID == id }), region.totalHexes > 0 else {
            return AnyShapeStyle(.clear)
        }
        let percentage = Double(region.exploredHexes.count) / Double(region.totalHexes)
        return AnyShapeStyle(.orange.opacity(max(0.15, percentage)))
    }
    
    private func hexToPolygon(h3Index: String) -> [CLLocationCoordinate2D]? {
        guard let index = UInt64(h3Index, radix: 16) else { return nil }
        var cellBoundary = CellBoundary()
        let error = cellToBoundary(index, &cellBoundary)
        
        guard error == 0 else { return nil }
        
        var coordinates: [CLLocationCoordinate2D] = []
        withUnsafeBytes(of: cellBoundary.verts) { rawBuffer in
            let vertsBuffer = rawBuffer.bindMemory(to: LatLng.self)
            for i in 0..<Int(cellBoundary.numVerts) {
                let vertex = vertsBuffer[i]
                let lat = vertex.lat * 180.0 / .pi
                let lon = vertex.lng * 180.0 / .pi
                coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        return coordinates
    }
}

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
