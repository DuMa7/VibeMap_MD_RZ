import SwiftUI
import MapKit

struct MapView: View {
    @State private var position: MapCameraPosition = .automatic
    @State private var mapStyle: MapStyle = .standard
    @State private var hasInitiallyPositioned = false
    @State private var currentSpan: Double = 0.05
    
    // NEW: Cache the heavy calculation here so we don't freeze the UI
    @State private var cachedRuralHexes: [String] = []
    
    var exploredHexes: [ExploredHex]
    var userLocation: CLLocationCoordinate2D?
    
    private let hexRenderThreshold = 0.5
    
    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            //DELETE ----(appear only here)-----------------------
            // FOG OF WAR
            MapPolygon(coordinates: worldBoundary())
                .foregroundStyle(.black.opacity(0.6))
                .stroke(.clear, lineWidth: 0)
            //Until Here --------------------------
            if currentSpan < hexRenderThreshold {
                // 1. Urban Hexes (Fast)
                ForEach(exploredHexes.filter { $0.isUrban }, id: \.h3Index) { hex in
                    if let polygon = hexToPolygon(h3Index: hex.h3Index) {
                        MapPolygon(coordinates: polygon)
                            .foregroundStyle(.orange.opacity(0.4))
                            .stroke(.orange, lineWidth: 1)
                    }
                }
                
                // 2. Rural Hexes (Read from CACHE, not calculated live)
                ForEach(cachedRuralHexes, id: \.self) { parentHexIndex in
                    if let polygon = hexToPolygon(h3Index: parentHexIndex) {
                        MapPolygon(coordinates: polygon)
                            .foregroundStyle(.orange.opacity(0.4))
                            .stroke(.orange, lineWidth: 1)
                    }
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControlVisibility(.hidden)
        .animation(.easeInOut(duration: 1.0), value: exploredHexes)
        .onMapCameraChange(frequency: .continuous) { context in
            currentSpan = context.region.span.latitudeDelta
        }
        // NEW: Recalculate only when data actually changes
        .onChange(of: exploredHexes) { oldValue, newValue in
            recalculateRuralHexes()
        }
        .onAppear {
            if let userLocation, !hasInitiallyPositioned {
                position = .region(MKCoordinateRegion(
                    center: userLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                hasInitiallyPositioned = true
            }
            // Trigger calculation on load
            recalculateRuralHexes()
        }
        .onChange(of: userLocation) { oldValue, newValue in
            if let newValue, !hasInitiallyPositioned {
                position = .region(MKCoordinateRegion(
                    center: newValue,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                hasInitiallyPositioned = true
            }
        }
        .overlay(alignment: .top) {
            if currentSpan >= hexRenderThreshold {
                Text("Zoom in to see detailed exploration")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.top, 100)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Button {
                if let userLocation {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        position = .region(MKCoordinateRegion(
                            center: userLocation,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.blue)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .disabled(userLocation == nil)
            .opacity(userLocation == nil ? 0.5 : 1.0)
            .padding(.leading, 16)
            .padding(.bottom, 40)
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
    
    // MARK: - Optimization Logic
    
    private func recalculateRuralHexes() {
        // Run this heavy work in the background!
        Task {
            let ruralHexes = exploredHexes.filter { !$0.isUrban }
            
            // Heavy math loop
            let parentIndices = ruralHexes.compactMap {
                cellToParentHex(h3Index: $0.h3Index, parentRes: 9)
            }
            
            let uniqueParents = Array(Set(parentIndices))
            
            // Update UI on main thread
            await MainActor.run {
                self.cachedRuralHexes = uniqueParents
            }
        }
    }
    
    // MARK: - Map Helpers
    
    private func worldBoundary() -> [CLLocationCoordinate2D] {
        return [
            CLLocationCoordinate2D(latitude: 85, longitude: -180),
            CLLocationCoordinate2D(latitude: 85, longitude: 180),
            CLLocationCoordinate2D(latitude: -85, longitude: 180),
            CLLocationCoordinate2D(latitude: -85, longitude: -180),
            CLLocationCoordinate2D(latitude: 85, longitude: -180)
        ]
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
    
    private func cellToParentHex(h3Index: String, parentRes: Int) -> String? {
        guard let index = UInt64(h3Index, radix: 16) else { return nil }
        var parent: UInt64 = 0
        // Call into the H3 C API to compute the parent cell at the requested resolution
        let error = cellToParent(index, Int32(parentRes), &parent)
        guard error == 0 else { return nil }
        // Return as lowercase hex string to match input format
        return String(parent, radix: 16)
    }
}

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
