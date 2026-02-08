import SwiftUI
import SwiftData
import CoreLocation

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var exploredHexes: [ExploredHex]
    @Query private var locationPoints: [LocationPoint]
    @Query(sort: \CityExploration.lastVisited, order: .reverse) private var cities: [CityExploration]
    
    // FIXED: Injection of LocationManager (as per our previous discussion)
    @Environment(LocationManager.self) var locationManager
    
    @State private var showStats = false
    @State private var isLoading = true
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            if isLoading {
                SplashView()
                    .transition(.opacity)
            } else {
                mapContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isLoading)
        .onAppear {
            locationManager.modelContext = modelContext
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                isLoading = false
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
    
    private var mapContent: some View {
        ZStack {
            // Map
            MapView(
                exploredHexes: exploredHexes,
                userLocation: locationManager.userLocation
            )
            .ignoresSafeArea()
            
            // Top HUD
            VStack {
                    // Top stats card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            // NEW: Settings Button
                            Button(action: { showSettings.toggle() }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("🔷 \(exploredHexes.count) hexes")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: { showStats.toggle() }) {                            // Badge notification if new achievements available?
                            Image(systemName: showStats ? "xmark.circle.fill" : "trophy.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .symbolEffect(.bounce, value: showStats)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(15)
                .padding(.horizontal)
                .padding(.top, 8)
                
                Spacer()
                
                // Permission Button logic...
                if locationManager.authorizationStatus == .notDetermined {
                    Button("Enable Location Tracking") {
                        locationManager.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 120)
                }
            }
            
            // EXPANDED STATS SHEET WITH ACHIEVEMENTS
            if showStats {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showStats = false }
                
                VStack(spacing: 20) {
                    Text("Exploration Profile")
                        .font(.title2)
                        .bold()
                    
                    Divider()
                    
                    // 1. Stats Grid
                    HStack(spacing: 30) {
                        VStack {
                            Text("🔷")
                            Text("\(exploredHexes.count)")
                                .bold()
                            Text("Hexes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        VStack {
                            Text("🏙️")
                            Text("\(cities.count)")
                                .bold()
                            Text("Cities")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        VStack {
                            Text("🏆")
                            // Calc total achievements
                            Text("\(AchievementLibrary.getUnlocked(hexCount: exploredHexes.count, cityCount: cities.count).count)")
                                .bold()
                            Text("Badges")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // 2. Tab Selection (Cities vs Achievements)
                    // Simple ScrollView for now showing both
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            
                            // ACHIEVEMENTS SECTION
                            Text("Recent Achievements")
                                .font(.headline)
                                .padding(.top, 5)
                            
                            let unlocked = AchievementLibrary.getUnlocked(hexCount: exploredHexes.count, cityCount: cities.count)
                            
                            if unlocked.isEmpty {
                                Text("Explore more to unlock badges!")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            } else {
                                ForEach(unlocked) { achievement in
                                    AchievementRow(achievement: achievement)
                                }
                            }
                            
                            Divider()
                                .padding(.vertical, 5)
                            
                            // CITIES SECTION
                            if !cities.isEmpty {
                                Text("Cities Visited")
                                    .font(.headline)
                                ForEach(cities, id: \.cityName) { city in
                                    CityRow(city: city)
                                }
                            }
                        }
                    }
                    
                    Button("Close") { showStats = false }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(24)
                .frame(maxWidth: 350, maxHeight: 600)
                .background(.ultraThickMaterial)
                .cornerRadius(20)
                .shadow(radius: 20)
            }
        }
    }
}

// Helper View for Achievements
struct AchievementRow: View {
    let achievement: Achievement
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(achievement.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: achievement.icon)
                    .foregroundStyle(achievement.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(.subheadline)
                    .bold()
                Text(achievement.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        }
        .padding(8)
        .background(Color.white.opacity(0.1)) // Subtle background
        .cornerRadius(10)
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
                    .foregroundStyle(.orange)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(.orange)
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
