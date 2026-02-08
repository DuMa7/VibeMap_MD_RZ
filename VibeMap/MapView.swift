import SwiftUI
import MapKit
import H3

struct MapView: View {
    @State private var position: MapCameraPosition = .automatic
    @State private var mapStyle: MapStyle = .standard
    @State private var hasInitiallyPositioned = false
    
    var exploredHexes: [ExploredHex]
    var userLocation: CLLocationCoordinate2D?
    
    var body: some View {
        Map(position: $position) {
            // Use MapKit's built-in user location (blue dot)
            UserAnnotation()
            
            // FOG OF WAR: Cover entire world with dark overlay
            MapPolygon(coordinates: worldBoundary())
                .foregroundStyle(.black.opacity(0.6))
                .stroke(.clear, lineWidth: 0)
            
            // Show explored hexagons
            ForEach(exploredHexes, id: \.h3Index) { hex in
                if let polygon = hexToPolygon(h3Index: hex.h3Index) {
                    MapPolygon(coordinates: polygon)
                        .foregroundStyle(.clear)
                        .stroke(.green, lineWidth: 2)
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControlVisibility(.hidden)
        .onAppear {
            // Initial positioning on first load
            if let userLocation, !hasInitiallyPositioned {
                position = .region(MKCoordinateRegion(
                    center: userLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                hasInitiallyPositioned = true
            }
        }
        .onChange(of: userLocation) { oldValue, newValue in
            // Also respond to location changes if not yet positioned
            if let newValue, !hasInitiallyPositioned {
                position = .region(MKCoordinateRegion(
                    center: newValue,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                hasInitiallyPositioned = true
            }
        }
        .overlay(alignment: .bottomLeading) {
            // Recenter button
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
            .disabled(userLocation == nil) // Disable if no location yet
            .opacity(userLocation == nil ? 0.5 : 1.0)
            .padding(.leading, 16)
            .padding(.bottom, 100)
        }
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button {
                    mapStyle = .standard
                } label: {
                    Label("Standard", systemImage: "map")
                }
                
                Button {
                    mapStyle = .hybrid
                } label: {
                    Label("Satellite", systemImage: "globe.americas.fill")
                }
                
                Button {
                    mapStyle = .imagery
                } label: {
                    Label("Imagery", systemImage: "photo")
                }
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
            .padding(.bottom, 100)
        }
    }
    
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
}

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
