import SwiftUI
import MapKit
import H3

struct MapView: View {
    @State private var position: MapCameraPosition = .automatic
    @State private var mapStyle: MapStyle = .standard
    @State private var hasInitiallyPositioned = false
    
    // NEW: Track zoom level to optimize rendering
    @State private var currentSpan: Double = 0.05
    
    var exploredHexes: [ExploredHex]
    var userLocation: CLLocationCoordinate2D?
    
    // Performance Threshold: Hide hexes if zoomed out further than this
    // 0.2 is roughly "Metropolitan Area" size. 1.0 is "State/Province" size.
    private let hexRenderThreshold = 0.5
    
    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            
            // FOG OF WAR: Cover world
            MapPolygon(coordinates: worldBoundary())
                .foregroundStyle(.black.opacity(0.6))
                .stroke(.clear, lineWidth: 0)
            
            // PERFORMANCE: Only render hexes if we are zoomed in enough
            if currentSpan < hexRenderThreshold {
                ForEach(exploredHexes, id: \.h3Index) { hex in
                    if let polygon = hexToPolygon(h3Index: hex.h3Index) {
                        MapPolygon(coordinates: polygon)
                             // NEW: Orange fill with transparency
                            .foregroundStyle(.orange.opacity(0.4))
                            // NEW: Thinner orange border
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
        .onAppear {
            if let userLocation, !hasInitiallyPositioned {
                position = .region(MKCoordinateRegion(
                    center: userLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                hasInitiallyPositioned = true
            }
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
        // ... (Keep existing overlay buttons for Style and Recenter) ...
        .overlay(alignment: .top) {
            // Optional: Visual indicator when hexes are hidden
            if currentSpan >= hexRenderThreshold {
                Text("Zoom in to see detailed exploration")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomLeading) {
             // ... (Keep your Recenter Button code here)
             // Copy from original file
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
             // ... (Keep your Menu/Style Button code here)
             // Copy from original file
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
    
    // ... (Keep existing private helper methods worldBoundary and hexToPolygon) ...
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
        // Reuse your existing H3 logic from previous file
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
