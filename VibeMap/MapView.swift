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
            // Show user location
            if let userLocation {
                Annotation("You", coordinate: userLocation) {
                    ZStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 20, height: 20)
                        Circle()
                            .stroke(.white, lineWidth: 3)
                            .frame(width: 20, height: 20)
                        Circle()
                            .stroke(.blue.opacity(0.3), lineWidth: 2)
                            .frame(width: 40, height: 40)
                    }
                }
            }
            
            // Show explored hexagons
            ForEach(exploredHexes, id: \.h3Index) { hex in
                if let polygon = hexToPolygon(h3Index: hex.h3Index) {
                    MapPolygon(coordinates: polygon)
                        .foregroundStyle(.green.opacity(0.3))
                        .stroke(.green, lineWidth: 1)
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControlVisibility(.hidden) // Hide default controls
        // Only center on user location ONCE when first loaded
        .onChange(of: userLocation) { oldValue, newValue in
            if let newValue, !hasInitiallyPositioned {
                position = .region(MKCoordinateRegion(
                    center: newValue,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                hasInitiallyPositioned = true
            }
        }
        .overlay(alignment: .bottomLeading) {
            // Custom location button (bottom left)
            Button {
                if let userLocation {
                    withAnimation {
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
            .padding(.leading, 16)
            .padding(.bottom, 100) // Above safe area
        }
        .overlay(alignment: .bottomTrailing) {
            // Map style picker (bottom right)
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
            .padding(.bottom, 100) // Above safe area
        }
    }
    
    // Convert H3 index to polygon coordinates
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

// MARK: - Extensions
extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
