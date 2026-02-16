import SwiftUI
import SwiftData
import CoreLocation

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) var locationManager
    
    @Query private var exploredHexes: [ExploredHex]
    @Query private var locationPoints: [LocationPoint]
    @Query(sort: \CityExploration.lastVisited, order: .reverse) private var cities: [CityExploration]
    
    // UI State
    @State private var showStats = false
    @State private var showSettings = false
    @State private var isLoading = true
    @State private var genevaDetector = GenevaDetector.shared

    
    // Celebration State
    @State private var showConfetti = false
    @State private var lastAchievementCount = 0
    @State private var newAchievementTitle: String? = nil
    
    var body: some View {
        ZStack {
            if isLoading {
                SplashView().transition(.opacity)
            } else {
                mapContent.transition(.opacity)
            }
            
            // Celebration Overlay
            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false) // Let touches pass through
                    .ignoresSafeArea()
                
                // Achievement Banner
                if let title = newAchievementTitle {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow)
                                .font(.title)
                            VStack(alignment: .leading) {
                                Text("Achievement Unlocked!")
                                    .font(.caption)
                                    .bold()
                                    .foregroundStyle(.white.opacity(0.8))
                                Text(title)
                                    .font(.headline)
                                    .bold()
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .shadow(radius: 10)
                        .padding(.bottom, 60)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        // Hide banner after 4 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation { newAchievementTitle = nil }
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isLoading)
        .onAppear {
            locationManager.modelContext = modelContext
            // Initialize achievement count so we don't celebrate on first load
            lastAchievementCount = AchievementLibrary.getUnlocked(hexCount: exploredHexes.count, cityCount: cities.count).count
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { isLoading = false }
        }
        // WATCH FOR NEW ACHIEVEMENTS
        .onChange(of: exploredHexes.count) { oldValue, newValue in
            checkForAchievements()
        }
        .onChange(of: cities.count) { oldValue, newValue in
            checkForAchievements()
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
    
    private func checkForAchievements() {
        let currentUnlocked = AchievementLibrary.getUnlocked(hexCount: exploredHexes.count, cityCount: cities.count)
        let count = currentUnlocked.count
        
        if count > lastAchievementCount {
            // New Unlock detected!
            let newBadges = currentUnlocked.suffix(count - lastAchievementCount)
            if let latest = newBadges.last {
                triggerCelebration(title: latest.title)
            }
            lastAchievementCount = count
        }
    }
    
    private func triggerCelebration(title: String) {
        newAchievementTitle = title
        showConfetti = true
        
        // Haptic Feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Stop confetti after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation { showConfetti = false }
        }
    }
    
    // REDESIGNED MAP INTERFACE
    private var mapContent: some View {
        ZStack(alignment: .top) {
            // Map Layer
            MapView(
                exploredHexes: exploredHexes,
                userLocation: locationManager.userLocation
            )
            .ignoresSafeArea()
            
            // Top HUD (Redesigned)
            HStack {
                // Settings Button (Glass Effect)
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.primary)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                
                Spacer()
                
                // Central Stats Pill
                Button(action: { // TODO: Add City Details View later
                }) {
                    HStack(spacing: 12) {
                        // Left: City Name
                        if let city = cities.first {
                            Text(genevaDetector.getDisplayName())
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(.primary)
                        } else {
                            Text("World")
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(.primary)
                        }
                        
                        Divider()
                            .frame(height: 20)
                        
                        // Right: Percentage (instead of hex count)
                        if let city = cities.first {
                            Text("\(String(format: "%.1f", city.explorationPercentage))%")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                        } else {
                            Text("0%")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 5)
                }
                
                Spacer()
                
                // Profile/Stats Button
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
            .padding(.top, 10) // Safe area spacing
            
            // Bottom Elements
            VStack {
                Spacer()
                if locationManager.authorizationStatus == .notDetermined {
                    Button("Enable Tracking") { locationManager.requestPermission() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.bottom, 40)
                }
            }
            
            // Stats Sheet (Keep your existing one or use the one below)
            if showStats {
                statsOverlay
            }
        }
    }
    
    // Extracted Stats Overlay to keep body clean
    private var statsOverlay: some View {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .onTapGesture { withAnimation { showStats = false } }
            .overlay {
                VStack(spacing: 20) {
                    Text("Exploration Profile")
                        .font(.title2)
                        .bold()
                    
                    Divider()
                    
                    // Stats Grid
                    HStack(spacing: 30) {
                        statItem(icon: "hexagon.fill", value: "\(exploredHexes.count)", label: "Hexes")
                        statItem(icon: "building.2.fill", value: "\(cities.count)", label: "Cities")
                        statItem(icon: "trophy.fill", value: "\(lastAchievementCount)", label: "Badges")
                    }
                    
                    Divider()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Recent Badges").font(.headline)
                            let unlocked = AchievementLibrary.getUnlocked(hexCount: exploredHexes.count, cityCount: cities.count)
                            if unlocked.isEmpty {
                                Text("Explore to unlock badges!").font(.caption).foregroundStyle(.secondary)
                            } else {
                                ForEach(unlocked.reversed()) { AchievementRow(achievement: $0) }
                            }
                            
                            Divider().padding(.vertical)
                            
                            Text("Cities").font(.headline)
                            ForEach(cities, id: \.cityName) { CityRow(city: $0) }
                        }
                    }
                    
                    Button("Close") { withAnimation { showStats = false } }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.orange)
                }
                .padding(24)
                .frame(maxWidth: 350, maxHeight: 600)
                .background(.ultraThickMaterial)
                .cornerRadius(25)
                .shadow(radius: 20)
                .transition(.scale.combined(with: .opacity))
            }
    }
    
    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack {
            Image(systemName: icon).font(.title2).foregroundStyle(.orange)
            Text(value).bold().font(.title3)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
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
                .foregroundStyle(.green) // Kept green for "Success/Done" meaning
                .font(.caption)
        }
        .padding(8)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }
}
