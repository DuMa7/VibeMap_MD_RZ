import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import H3

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) var locationManager
    
    @Query private var exploredHexes: [ExploredHex]
    @Query private var locationPoints: [LocationPoint]
    @Query(sort: \RegionExploration.lastVisited, order: .reverse) private var regions: [RegionExploration]
    
    @State private var layerManager = MapLayerManager()
    
    // Map State
    @State private var currentSpan: Double = 0.05
    @State private var position: MapCameraPosition = .automatic
    @State private var hasInitiallyPositioned = false
    @State private var centerCoordinate: CLLocationCoordinate2D? = nil
    
    // Dynamic Center State
    @State private var centeredRegionID: String? = nil
    @State private var centeredMunicipalityName: String = "Locating..."
    @State private var centeredCantonName: String = "Locating..."
    
    // UI State
    @State private var showStats = false
    @State private var showSettings = false
    @State private var isLoading = true
    
    var body: some View {
        ZStack(alignment: .top) {
            if isLoading {
                SplashView().transition(.opacity)
            } else {
                mapContent.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isLoading)
        .onAppear {
            locationManager.modelContext = modelContext
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { isLoading = false }
        }
        .onChange(of: locationManager.userLocation) { oldValue, newValue in
            if let newValue, !hasInitiallyPositioned {
                position = .region(MKCoordinateRegion(
                    center: newValue,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                hasInitiallyPositioned = true
            }
        }
        .onChange(of: centerCoordinate) { oldValue, newValue in
            if let newValue {
                updateCenteredRegion(coordinate: newValue)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
    
    private var mapContent: some View {
        ZStack(alignment: .top) {
            MapView(
                position: $position,
                currentSpan: $currentSpan,
                centerCoordinate: $centerCoordinate,
                exploredHexes: exploredHexes,
                regions: regions,
                layerManager: layerManager,
                userLocation: locationManager.userLocation
            )
            .ignoresSafeArea()
            
            // Dynamic Top HUD
            HStack {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.primary)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                
                Spacer()
                
                // Dynamic Central Pill
                Button(action: { }) {
                    HStack(spacing: 12) {
                        Text(currentZoomLabel)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.primary)
                            // NEW: Smooth transition when the text changes due to zooming
                            .contentTransition(.interpolate)
                        
                        Divider().frame(height: 20)
                        
                        Text(currentZoomPercentage)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 5)
                    // NEW: Animates the pill resizing slightly when names change
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentZoomLabel)
                }
                
                Spacer()
                
                Button(action: { showStats.toggle() }) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(.primary)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            
            // Recenter Button
            VStack {
                Spacer()
                HStack {
                    Button {
                        if let userLocation = locationManager.userLocation {
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
                    .disabled(locationManager.userLocation == nil)
                    .opacity(locationManager.userLocation == nil ? 0.5 : 1.0)
                    .padding(.leading, 16)
                    .padding(.bottom, 40)
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Dynamic Zoom & Center Logic
    
    // NEW: Helper function to strip out secondary names (e.g. "Biel/Bienne" -> "Biel")
    private func getPrimaryName(from fullName: String) -> String {
        let separators = CharacterSet(charactersIn: "/,(")
        let parts = fullName.components(separatedBy: separators)
        return parts.first?.trimmingCharacters(in: .whitespaces) ?? fullName
    }
    
    private func updateCenteredRegion(coordinate: CLLocationCoordinate2D) {
        let latRads = coordinate.latitude * .pi / 180.0
        let lonRads = coordinate.longitude * .pi / 180.0
        var coord = LatLng(lat: latRads, lng: lonRads)
        
        var h3Index10: H3Index = 0
        var h3Index9: H3Index = 0
        latLngToCell(&coord, Int32(10), &h3Index10)
        latLngToCell(&coord, Int32(9), &h3Index9)
        
        let hex10 = String(h3Index10, radix: 16)
        let hex9 = String(h3Index9, radix: 16)
        
        if let regionData = OfflineDatabase.shared.getRegionData(res10: hex10, res9: hex9) {
            centeredRegionID = regionData.regionID
            
            if let metadata = RegionMetadataManager.shared.municipalities[regionData.regionID] {
                // Apply the single-name filter to the Municipality
                centeredMunicipalityName = getPrimaryName(from: metadata.name)
                
                if let canton = layerManager.cantons.first(where: { $0.id == metadata.cantonID }) {
                    // Apply the single-name filter to the Canton
                    centeredCantonName = getPrimaryName(from: canton.name)
                } else {
                    centeredCantonName = "Canton \(metadata.cantonID)"
                }
            }
        } else {
            centeredRegionID = nil
            centeredMunicipalityName = "Unknown Area"
            centeredCantonName = "Unknown Canton"
        }
    }
    
    private var currentZoomLabel: String {
        if currentSpan >= 10.0 { return "World" }
        if currentSpan >= 1.8 { return "Switzerland" }
        if currentSpan >= 0.18 { return centeredCantonName }
        return centeredMunicipalityName
    }
    
    private var currentZoomPercentage: String {
        if currentSpan >= 10.0 {
            return "1 Country"
        }
        if currentSpan >= 2.0 {
            return "\(regions.count) Towns"
        }
        if currentSpan >= 0.2 {
            let cantonID = layerManager.cantons.first(where: { getPrimaryName(from: $0.name) == centeredCantonName })?.id
            let visitedInCanton = regions.filter { RegionMetadataManager.shared.municipalities[$0.regionID]?.cantonID == cantonID }.count
            return "\(visitedInCanton) Munis"
        }
        
        guard let regionID = centeredRegionID,
              let region = regions.first(where: { $0.regionID == regionID }) else {
            return "0%"
        }
        return "\(String(format: "%.1f", region.explorationPercentage))%"
    }
}
