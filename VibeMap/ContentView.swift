import SwiftUI
import SwiftData
import CoreLocation

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var exploredHexes: [ExploredHex]
    @Query private var locationPoints: [LocationPoint]
    @Query(sort: \CityExploration.lastVisited, order: .reverse) private var cities: [CityExploration]
    
    @State private var locationManager = LocationManager()
    @State private var showStats = false
    @State private var isLoading = true // NEW: Loading state
    
    var body: some View {
        ZStack {
            if isLoading {
                // Show splash screen
                SplashView()
                    .transition(.opacity)
            } else {
                // Show main map view
                mapContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isLoading)
        .onAppear {
            locationManager.modelContext = modelContext
            
            // Hide splash screen after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                isLoading = false
            }
        }
    }
    
    // Main map content (extracted for cleaner code)
    private var mapContent: some View {
        ZStack {
            // Map (full screen)
            MapView(
                exploredHexes: exploredHexes,
                userLocation: locationManager.userLocation
            )
            .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top stats card with current city
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("🔷 \(exploredHexes.count) hexes explored")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: { showStats.toggle() }) {
                            Image(systemName: showStats ? "xmark.circle.fill" : "info.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    // Show current city exploration
                    if let currentCity = cities.first {
                        HStack(spacing: 4) {
                            Text("🏙️ \(currentCity.cityName):")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.1f", currentCity.explorationPercentage))% explored")
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(15)
                .padding(.horizontal)
                .padding(.top, 8)
                
                Spacer()
                
                // Bottom permission button (only show if needed)
                if locationManager.authorizationStatus == .notDetermined {
                    Button("Enable Location Tracking") {
                        locationManager.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 120)
                }
            }
            
            // Stats overlay
            if showStats {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showStats = false
                    }
                
                VStack(spacing: 20) {
                    Text("Exploration Stats")
                        .font(.title2)
                        .bold()
                    
                    Divider()
                    
                    StatRow(icon: "🔷", label: "Total Hexes", value: "\(exploredHexes.count)")
                    StatRow(icon: "🏙️", label: "Cities Visited", value: "\(cities.count)")
                    
                    if !cities.isEmpty {
                        Divider()
                        Text("Cities")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ScrollView {
                            ForEach(cities, id: \.cityName) { city in
                                CityRow(city: city)
                            }
                        }
                        .frame(maxHeight: 250)
                    }
                    
                    Spacer()
                    
                    Button("Close") {
                        showStats = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(24)
                .frame(maxWidth: 350, maxHeight: 500)
                .background(.ultraThickMaterial)
                .cornerRadius(20)
                .shadow(radius: 20)
            }
        }
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(icon)
                .font(.title3)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
        .padding(.vertical, 4)
    }
}

struct CityRow: View {
    let city: CityExploration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(city.cityName)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text("\(String(format: "%.1f", city.explorationPercentage))%")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(.green)
                        .frame(width: geometry.size.width * (city.explorationPercentage / 100), height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
            
            Text("\(city.exploredHexes.count) / \(city.totalHexesInBoundary) hexes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ExploredHex.self, LocationPoint.self, CityExploration.self])
}
