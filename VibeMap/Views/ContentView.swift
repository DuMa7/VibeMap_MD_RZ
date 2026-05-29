import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import H3

struct ContentView: View {
    
    // MARK: - Environment & Queries
    
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) var locationManager
    
    /// All explored hexes — used for hex count, area calculation, and map rendering
    @Query private var exploredHexes: [ExploredHex]
    
    /// All visited regions sorted by most recent visit — drives municipality list and canton stats
    @Query(sort: \RegionExploration.lastVisited, order: .reverse) private var regions: [RegionExploration]
    
    // MARK: - Map State
    
    /// Loads canton and municipality GeoJSON polygons for map overlay rendering
    @State private var layerManager = MapLayerManager()
    
    /// Current map camera position — updated programmatically on first location fix and recenter
    @State private var position: MapCameraPosition = .automatic
    
    /// Latitude delta of the visible map region — drives zoom-level logic in the HUD pill
    @State private var currentSpan: Double = 0.05
    
    /// Prevents the map from re-centering on the user after they have manually panned
    @State private var hasInitiallyPositioned = false
    
    /// Center coordinate of the visible map region — updated on pan end and on location update
    @State private var centerCoordinate: CLLocationCoordinate2D? = nil
    
    // MARK: - Crosshair-Based Center State
    // Single source of truth for the HUD pill and Location Details overlay.
    // Updated both when the map stops panning AND when the user's location changes while walking.
    
    /// Region ID of the municipality at the map crosshair — used to fetch exploration % for the HUD
    @State private var centeredRegionID: String? = nil
    
    /// Display name of the municipality at the map crosshair
    @State private var centeredMunicipalityName: String = "Locating..."
    
    /// Total hexes in the municipality at the map crosshair — used for the Location Details progress bar
    @State private var centeredMuniTotalHexes: Int = 0
    
    /// Display name of the canton at the map crosshair
    @State private var centeredCantonName: String = "Locating..."
    
    // MARK: - UI State
    
    /// Controls visibility of the Explorer Profile stats overlay
    @State private var showStats = false

    /// Controls visibility of the Canton Passport sheet
    @State private var showPassport = false

    /// Controls visibility of the Settings sheet
    @State private var showSettings = false
    
    /// Controls visibility of the Location Details overlay (tapping the HUD pill)
    @State private var showRegionDetails = false
    
    /// Controls the splash screen — dismissed after 2.5s on first launch
    @State private var isLoading = true
    
    // MARK: - Achievement State
    
    /// Comma-separated titles of all previously unlocked achievements — persisted across launches via UserDefaults
    @AppStorage("unlockedAchievementTitles") private var unlockedAchievementTitles: String = ""
    
    /// The achievement currently being displayed in the banner (always 0 or 1 item)
    @State private var newlyUnlocked: [Achievement] = []
    
    /// Whether the achievement banner is currently visible
    @State private var showAchievementBanner = false
    
    /// Queue of achievements waiting to be shown — displayed one at a time after each banner dismisses
    @State private var bannerQueue: [Achievement] = []
    
    // MARK: - Session State

    /// Controls the "Exploring somewhere new today?" launch prompt
    @State private var showExplorationPrompt = false

    /// Controls the "New territory ahead!" prompt triggered by a location move into an unexplored hex
    @State private var showUnexploredAreaPrompt = false

    /// Controls the session summary sheet shown after stopping a session
    @State private var showSessionSummary = false

    /// Snapshot of the last completed session — drives the summary sheet
    @State private var lastSessionSummary: SessionSummary? = nil

    /// Drives the pulsing animation on the recording dot in the HUD pill
    @State private var recordingPulse: Bool = false

    // MARK: - Layer State

    /// Base map style + overlay toggle state — shared with MapView
    @State private var layerSettings = MapLayerSettings()

    /// Controls visibility of the layer switcher panel
    @State private var showLayerPanel = false

    // MARK: - Live Location

    /// Detects the user's current municipality in real time — kept for future use but not driving the pill directly
    private let liveDetector = LiveLocationDetector.shared

    /// Handle for the in-flight debounced centered-region lookup — cancelled when a newer coordinate arrives
    @State private var centeredRegionTask: Task<Void, Never>?

    // MARK: - Canton Count Cache

    /// cantonID → number of visited municipalities in that canton — O(1) HUD lookups
    @State private var visitedCountPerCanton: [String: Int] = [:]

    /// Total distinct cantons visited — cached to avoid O(N) compactMap on every render
    @State private var cachedVisitedCantonCount: Int = 0

    // MARK: - Streak Cache

    /// Current and best exploration streaks — recomputed when hex count changes
    @State private var streakResult = StreakCalculator.Result(current: 0, best: 0)
    
    // MARK: - Body

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .top) {
            if isLoading {
                SplashView().transition(.opacity)
            } else {
                mapContent.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isLoading)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                try? BackupManager(modelContext: modelContext).saveAutoBackup()
            }
        }
        .task {
            // Run data migrations before any view logic uses the database.
            // Each migration is gated by a UserDefaults flag — no-op after first completion.
            await DataMigrationManager.runPendingMigrations(context: modelContext)
        }
        .onAppear {
            // Inject the SwiftData context into LocationManager so it can persist hexes
            locationManager.modelContext = modelContext

            // Dismiss splash screen after 2.5s then seed initial achievement state
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { isLoading = false }
                repairRegionTotals()
                rebuildCantonCounts()
                rebuildStreak()
                checkAchievements()
                if !locationManager.isSessionActive {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showExplorationPrompt = true
                    }
                }
            }
        }
        // Center the map on the user's first location fix only.
        // Also update the crosshair state on every location update so the pill
        // tracks the user's position in real time while walking.
        .onChange(of: locationManager.userLocation) { _, newValue in
            if let newValue, !hasInitiallyPositioned {
                position = .region(MKCoordinateRegion(
                    center: newValue,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                hasInitiallyPositioned = true
            }
            if let newValue {
                liveDetector.detect(coordinate: newValue, cantons: layerManager.cantons)
                updateCenteredRegion(coordinate: newValue)
            }
        }
        // Re-check achievements and streak whenever the user enters a new hex
        .onChange(of: exploredHexes.count) { _, _ in
            checkAchievements()
            rebuildStreak()
        }
        // Rebuild canton caches when a new municipality is discovered
        .onChange(of: regions.count) { _, _ in
            rebuildCantonCounts()
        }
        // Update crosshair state when the map stops panning
        .onChange(of: centerCoordinate) { _, newValue in
            if let newValue {
                updateCenteredRegion(coordinate: newValue)
            }
        }
        // Session summary: presented as a sheet when LocationManager posts a completed summary.
        // Snapshot into local state so the sheet has a stable value even if LocationManager clears it.
        .onChange(of: locationManager.completedSessionSummary) { _, summary in
            if let summary {
                lastSessionSummary = summary
                showSessionSummary = true
            }
        }
        // Unexplored-area detection: LocationManager signals when a non-session location
        // update lands in a hex the user has never explored. Consume the flag immediately
        // so a second location event doesn't fire a second prompt.
        .onChange(of: locationManager.shouldPromptUnexploredArea) { _, detected in
            if detected {
                locationManager.shouldPromptUnexploredArea = false
                // Don't stack prompts — show only if neither prompt is already visible
                if !showExplorationPrompt && !locationManager.isSessionActive {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showUnexploredAreaPrompt = true
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPassport) {
            PassportView(regions: regions, cantons: layerManager.cantons)
        }
        .sheet(isPresented: $showSessionSummary) {
            if let summary = lastSessionSummary {
                SessionSummaryView(summary: summary) {
                    showSessionSummary = false
                }
            }
        }
    }
    
    // MARK: - Computed Achievement State
    
    /// Single source of truth for currently unlocked achievements — used by both the banner and stats overlay
    private var currentUnlockedAchievements: [Achievement] {
        AchievementLibrary.getUnlocked(
            hexCount: exploredHexes.count,
            cityCount: regions.count
        )
    }
    
    // MARK: - Map Content
    
    private var mapContent: some View {
        ZStack(alignment: .top) {
            MapView(
                position: $position,
                currentSpan: $currentSpan,
                centerCoordinate: $centerCoordinate,
                exploredHexes: exploredHexes,
                regions: regions,
                layerManager: layerManager,
                layerSettings: layerSettings,
                userLocation: locationManager.userLocation
            )
            .ignoresSafeArea()
            
            // MARK: Top HUD
            HStack {
                // Settings button
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.primary)
                        .padding(11)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                }
                
                Spacer()
                
                // Central pill — shows location name and exploration % at the active zoom level.
                // Always reflects the map crosshair: updates on pan and on walking location changes.
                // Tapping opens the Location Details overlay.
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation { showRegionDetails = true }
                }) {
                    HStack(spacing: 12) {
                        if locationManager.isSessionActive {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                                .opacity(recordingPulse ? 0.25 : 1.0)
                                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: recordingPulse)
                                .onAppear { recordingPulse = true }
                                .onDisappear { recordingPulse = false }
                        }

                        Text(currentZoomLabel)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.primary)
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
                    .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentZoomLabel)
                }
                
                Spacer()
                
                // Explorer Profile / Stats button
                Button(action: { withAnimation { showStats = true } }) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.primary)
                        .padding(11)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            
            // MARK: Bottom Controls — Floating Cards
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    // Left buttons: recenter + layers (separate floating circles)
                    VStack(spacing: 12) {
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
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 52, height: 52)
                                .background { Circle().fill(.ultraThinMaterial) }
                                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                        }
                        .disabled(locationManager.userLocation == nil)
                        .opacity(locationManager.userLocation == nil ? 0.4 : 1.0)

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                showLayerPanel.toggle()
                            }
                        } label: {
                            Image(systemName: "square.3.layers.3d")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(showLayerPanel ? .white : .primary)
                                .frame(width: 52, height: 52)
                                .background {
                                    if showLayerPanel {
                                        Circle().fill(Color.orange)
                                    } else {
                                        Circle().fill(.ultraThinMaterial)
                                    }
                                }
                                .overlay(Circle().strokeBorder(showLayerPanel ? Color.orange.opacity(0.5) : .white.opacity(0.25), lineWidth: 0.5))
                                .shadow(color: showLayerPanel ? Color.orange.opacity(0.4) : .black.opacity(0.18), radius: 8, x: 0, y: 4)
                        }
                    }

                    Spacer()

                    // Right card: session toggle
                    sessionToggleButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }

            // MARK: Layer Panel
            if showLayerPanel {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            showLayerPanel = false
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        LayerPanelView(settings: layerSettings)
                            .padding(.leading, 16)
                            .padding(.bottom, 148)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(4)
            }

            // MARK: Exploration Prompt (launch)
            if showExplorationPrompt {
                explorationPromptOverlay
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(10)
            }

            // MARK: Unexplored Area Prompt (location-triggered)
            if showUnexploredAreaPrompt {
                unexploredAreaPromptOverlay
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(10)
            }

            // MARK: Achievement Banner & Confetti
            // Banner slides down from top when a new achievement is unlocked.
            // Multiple unlocks are queued and shown one after another.
            if showAchievementBanner, let achievement = newlyUnlocked.first {
                AchievementBannerView(achievement: achievement) {
                    showNextBanner()
                }
                .zIndex(1)
                
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false) // Prevents confetti particles from blocking map taps
                    .zIndex(2)
            }
            
            // MARK: Overlays
            if showRegionDetails {
                regionDetailsOverlay
            }
            
            if showStats {
                statsOverlay
            }
        }
    }
    
    // MARK: - Session UI

    private var sessionToggleButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            if locationManager.isSessionActive {
                locationManager.stopSession()
            } else {
                locationManager.startSession()
            }
        } label: {
            HStack(spacing: 8) {
                if locationManager.isSessionActive {
                    Circle()
                        .fill(.red)
                        .frame(width: 9, height: 9)
                    Text("Stop")
                        .font(.subheadline).bold()
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption).bold()
                        .foregroundStyle(.white)
                    Text("Explore")
                        .font(.subheadline).bold()
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(locationManager.isSessionActive ? Color.red.opacity(0.15) : Color.green)
            .clipShape(Capsule())
            .shadow(radius: 4)
        }
    }

    private var explorationPromptOverlay: some View {
        Color.black.opacity(0.45)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                VStack(spacing: 20) {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 52))
                        .foregroundStyle(.orange)

                    VStack(spacing: 8) {
                        Text("Exploring somewhere new today?")
                            .font(.title2).bold()
                            .multilineTextAlignment(.center)

                        Text("Start a session to scratch new hexes on your map. GPS runs only while exploring.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        locationManager.startSession()
                        withAnimation { showExplorationPrompt = false }
                    } label: {
                        Label("Start Exploring", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.green)
                            .cornerRadius(16)
                    }

                    Button {
                        withAnimation { showExplorationPrompt = false }
                    } label: {
                        Text("Not right now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(28)
                .background(.ultraThickMaterial)
                .cornerRadius(28)
                .shadow(radius: 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
    }

    private var unexploredAreaPromptOverlay: some View {
        Color.black.opacity(0.45)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                VStack(spacing: 20) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.orange)

                    VStack(spacing: 8) {
                        Text("New territory ahead!")
                            .font(.title2).bold()
                            .multilineTextAlignment(.center)

                        Text("You've stepped into an area you've never explored. Start a session to scratch it onto your map.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        locationManager.startSession()
                        withAnimation { showUnexploredAreaPrompt = false }
                    } label: {
                        Label("Start Exploring", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.green)
                            .cornerRadius(16)
                    }

                    Button {
                        withAnimation { showUnexploredAreaPrompt = false }
                    } label: {
                        Text("Not right now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(28)
                .background(.ultraThickMaterial)
                .cornerRadius(28)
                .shadow(radius: 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
    }

    // MARK: - HUD Pill Logic
    
    /// Strips secondary names from bilingual Swiss place names (e.g. "Biel/Bienne" → "Biel")
    private func getPrimaryName(from fullName: String) -> String {
        let separators = CharacterSet(charactersIn: "/,(")
        let parts = fullName.components(separatedBy: separators)
        return parts.first?.trimmingCharacters(in: .whitespaces) ?? fullName
    }
    
    /// Location name shown in the left side of the HUD pill.
    /// Adapts to zoom level: World → Switzerland → Canton → Municipality.
    /// Always reflects the map crosshair — not the user's GPS position.
    private var currentZoomLabel: String {
        if currentSpan >= 10.0 { return "World" }
        if currentSpan >= 1.8  { return "Switzerland" }
        if currentSpan >= 0.18 { return centeredCantonName }
        return centeredMunicipalityName
    }
    
    /// Exploration stat shown in the right side of the HUD pill.
    /// Adapts to zoom level: country count → town count → municipality count → hex % explored.
    private var currentZoomPercentage: String {
        if currentSpan >= 10.0 { return "1 Country" }
        if currentSpan >= 1.8  { return "\(regions.count) Towns" }
        
        if currentSpan >= 0.18 {
            let cantonID = layerManager.cantons.first(where: {
                getPrimaryName(from: $0.name) == centeredCantonName
            })?.id ?? ""
            return "\(visitedCountPerCanton[cantonID] ?? 0) Towns"
        }
        
        // Street level: show % of the active municipality explored
        guard let regionID = centeredRegionID,
              let region = regions.first(where: { $0.regionID == regionID }) else {
            return "0%"
        }
        return "\(String(format: "%.1f", region.explorationPercentage))%"
    }
    
    // MARK: - Crosshair Region Update
    
    /// Updates the centered region state for both the HUD pill and Location Details overlay.
    /// Called on every location update (walking) and every map pan end (browsing).
    /// Runs H3 conversion and SQLite lookup off the main thread to avoid UI stutters.
    private func updateCenteredRegion(coordinate: CLLocationCoordinate2D) {
        centeredRegionTask?.cancel()
        centeredRegionTask = Task {
            do {
                try await Task.sleep(nanoseconds: 250_000_000) // 250 ms debounce
            } catch {
                return // cancelled before debounce elapsed
            }

            // H3 index generation — off main thread to avoid blocking map gestures
            let (hex10, hex9) = await Task.detached(priority: .userInitiated) {
                let latRads = coordinate.latitude * .pi / 180.0
                let lonRads = coordinate.longitude * .pi / 180.0
                var coord = LatLng(lat: latRads, lng: lonRads)

                var h3Index10: H3Index = 0
                var h3Index9: H3Index = 0
                latLngToCell(&coord, Int32(10), &h3Index10)
                latLngToCell(&coord, Int32(9), &h3Index9)

                return (String(h3Index10, radix: 16), String(h3Index9, radix: 16))
            }.value

            guard !Task.isCancelled else { return }

            // SQLite region lookup — also off main thread via OfflineDatabase's serial queue
            let regionData = await Task.detached(priority: .userInitiated) {
                OfflineDatabase.shared.getRegionData(res10: hex10, res9: hex9)
            }.value

            guard !Task.isCancelled else { return }

            // All @State mutations must happen on the main thread
            await MainActor.run {
                guard let regionData else {
                    centeredRegionID = nil
                    centeredMunicipalityName = "Unknown Area"
                    centeredCantonName = "Unknown Canton"
                    return
                }

                centeredRegionID = regionData.regionID

                guard let metadata = RegionMetadataManager.shared.municipalities[regionData.regionID] else {
                    return
                }

                centeredMunicipalityName = getPrimaryName(from: metadata.name)

                // Look up total hexes for the Location Details progress bar
                centeredMuniTotalHexes = regions.first(where: {
                    $0.regionID == regionData.regionID
                })?.totalHexes ?? 0

                if let canton = layerManager.cantons.first(where: { $0.id == metadata.cantonID }) {
                    centeredCantonName = getPrimaryName(from: canton.name)
                } else {
                    centeredCantonName = "Canton \(metadata.cantonID)"
                }
            }
        }
    }
    
    // MARK: - Location Details Overlay
    
    /// Shown when the user taps the HUD pill. Displays municipality, canton, and country progress
    /// for the area currently at the map crosshair.
    private var regionDetailsOverlay: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture { withAnimation { showRegionDetails = false } }
            .overlay {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Location Details")
                                .font(.title2).bold()
                            Text("Current Crosshair Area")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { withAnimation { showRegionDetails = false } } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding()
                    
                    VStack(spacing: 20) {
                        // Municipality row — hexes explored vs total in this municipality
                        let exploredCount = regions.first(where: {
                            $0.regionID == centeredRegionID
                        })?.exploredHexes.count ?? 0
                        detailCard(
                            icon: "mappin.and.ellipse",
                            title: centeredMunicipalityName,
                            subtitle: "Municipality",
                            progressText: "\(exploredCount) / \(centeredMuniTotalHexes) Hexes Explored",
                            percentage: centeredMuniTotalHexes > 0 ? Double(exploredCount) / Double(centeredMuniTotalHexes) : 0
                        )
                        
                        // Canton row — municipalities visited vs total in this canton
                        let cantonID = layerManager.cantons.first(where: {
                            getPrimaryName(from: $0.name) == centeredCantonName
                        })?.id
                        let visitedInCanton = visitedCountPerCanton[cantonID ?? ""] ?? 0
                        let totalInCanton = RegionMetadataManager.shared.municipalities.values.filter {
                            $0.cantonID == cantonID
                        }.count
                        detailCard(
                            icon: "map",
                            title: centeredCantonName,
                            subtitle: "Canton",
                            progressText: "\(visitedInCanton) / \(totalInCanton) Towns Visited",
                            percentage: totalInCanton > 0 ? Double(visitedInCanton) / Double(totalInCanton) : 0
                        )
                        
                        // Country row — cantons visited vs Switzerland's 26
                        detailCard(
                            icon: "globe.europe.africa.fill",
                            title: "Switzerland",
                            subtitle: "Country",
                            progressText: "\(cachedVisitedCantonCount) / 26 Cantons Visited",
                            percentage: Double(cachedVisitedCantonCount) / 26.0
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: 360)
                .background(.ultraThickMaterial)
                .cornerRadius(24)
                .shadow(radius: 20)
                .transition(.scale.combined(with: .opacity))
            }
    }
    
    /// Reusable card used in the Location Details overlay for each geographic level
    private func detailCard(icon: String, title: String, subtitle: String, progressText: String, percentage: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(progressText)
                    .font(.subheadline).bold()
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.gray.opacity(0.2)).frame(height: 8).cornerRadius(4)
                        Rectangle().fill(.orange)
                            .frame(width: geo.size.width * CGFloat(min(percentage, 1.0)), height: 8)
                            .cornerRadius(4)
                    }
                }
                .frame(height: 8)
            }
            .padding(.leading, 40)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Explorer Profile Overlay
    
    /// Full stats overlay — shows hex count, area, national discovery progress, and unlocked achievements
    private var statsOverlay: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture { withAnimation { showStats = false } }
            .overlay {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(explorerTitle)
                                .font(.caption).bold().foregroundStyle(.orange)
                            Text("Explorer Profile")
                                .font(.title2).bold()
                        }
                        Spacer()
                        Button { withAnimation { showStats = false } } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding()
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            // Summary cards — hex count, towns visited, area explored
                            HStack(spacing: 15) {
                                statCard(icon: "hexagon.fill", title: "Hexes", value: "\(exploredHexes.count)")
                                statCard(icon: "map.fill", title: "Towns", value: "\(regions.count)")
                                statCard(icon: "globe.europe.africa.fill", title: "Area", value: "\(calculateArea()) km²")
                            }
                            .padding(.horizontal)

                            // Streak cards
                            HStack(spacing: 15) {
                                streakCard(
                                    icon: "flame.fill",
                                    title: "Streak",
                                    value: streakResult.current == 0 ? "–" : "\(streakResult.current)d",
                                    color: streakResult.current > 0 ? .orange : .gray
                                )
                                streakCard(
                                    icon: "trophy.fill",
                                    title: "Best",
                                    value: streakResult.best == 0 ? "–" : "\(streakResult.best)d",
                                    color: .yellow
                                )
                            }
                            .padding(.horizontal)

                            // National progress — cantons and municipalities vs Swiss totals
                            VStack(alignment: .leading, spacing: 12) {
                                Text("National Discovery").font(.headline)
                                
                                progressRow(title: "Cantons Visited", current: cachedVisitedCantonCount, total: 26)
                                progressRow(
                                    title: "Municipalities Visited",
                                    current: regions.count,
                                    total: RegionMetadataManager.shared.municipalities.count
                                )
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                            .padding(.horizontal)
                            
                            // Canton Passport entry point
                        Button {
                            withAnimation { showStats = false }
                            // Delay matches the stats sheet's dismiss animation — presenting
                            // a new sheet while another is mid-dismiss crashes on iOS 16.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showPassport = true
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "book.closed.fill")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Canton Passport")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(cachedVisitedCantonCount) / 26 cantons explored")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                        }
                        .padding(.horizontal)

                        // Achievements — only unlocked ones shown, empty state handled
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Achievements").font(.headline)
                                
                                if currentUnlockedAchievements.isEmpty {
                                    Text("Explore your first few hexes to unlock badges!")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(currentUnlockedAchievements.reversed()) {
                                        AchievementRow(achievement: $0)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(maxWidth: 360, maxHeight: 650)
                .background(.ultraThickMaterial)
                .cornerRadius(24)
                .shadow(radius: 20)
                .transition(.scale.combined(with: .opacity))
            }
    }
    
    // MARK: - Stats Helpers

    private func streakCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(value).font(.title3).bold()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }

    /// Estimates explored area in km² using the H3 resolution-10 average cell area
    /// of ~0.015 km² (~15,047 m²). This is a global average; actual Swiss cell sizes
    /// vary slightly by latitude but the approximation is accurate within ~2%.
    private func calculateArea() -> String {
        let sqKm = Double(exploredHexes.count) * 0.015
        return String(format: "%.2f", sqKm)
    }
    
    /// Explorer rank title shown at the top of the stats overlay — based on total hex count
    private var explorerTitle: String {
        let count = exploredHexes.count
        if count < 100  { return "NOVICE WANDERER" }
        if count < 1000 { return "LOCAL GUIDE" }
        if count < 5000 { return "CITY CARTOGRAPHER" }
        return "MASTER PATHFINDER"
    }
    
    /// Reusable summary card used in the top row of the Explorer Profile
    private func statCard(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.orange)
            Text(value).font(.title3).bold()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
    
    /// Reusable progress row used in the National Discovery section
    private func progressRow(title: String, current: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(current) / \(total)").font(.subheadline).bold().foregroundStyle(.orange)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.gray.opacity(0.2)).frame(height: 8).cornerRadius(4)
                    Rectangle().fill(.orange)
                        .frame(width: geo.size.width * CGFloat(Double(current) / Double(total)), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
    }
    
    // MARK: - Canton Count Cache

    /// Rebuilds canton visit counts in one O(N) pass over regions.
    /// Called on appear and whenever the visited-region count changes.
    private func rebuildCantonCounts() {
        var countPerCanton = [String: Int]()
        for region in regions {
            if let cantonID = RegionMetadataManager.shared.municipalities[region.regionID]?.cantonID {
                countPerCanton[cantonID, default: 0] += 1
            }
        }
        visitedCountPerCanton    = countPerCanton
        cachedVisitedCantonCount = countPerCanton.count
    }

    // MARK: - Streak

    private func rebuildStreak() {
        streakResult = StreakCalculator.calculate(dates: exploredHexes.map { $0.firstVisited })
    }

    // MARK: - Achievement Logic

    /// Compares current unlocked achievements against persisted titles from previous launches.
    /// Newly unlocked achievements are queued for banner display one at a time.
    private func checkAchievements() {
        let previousTitles = Set(unlockedAchievementTitles.split(separator: ",").map(String.init))
        let newOnes = currentUnlockedAchievements.filter { !previousTitles.contains($0.title) }
        
        // Persist updated unlocked set using stable title strings (not UUID which regenerates each launch)
        unlockedAchievementTitles = currentUnlockedAchievements.map { $0.title }.joined(separator: ",")
        
        if !newOnes.isEmpty {
            bannerQueue.append(contentsOf: newOnes)
            if !showAchievementBanner {
                showNextBanner()
            }
        }
    }
    
    /// Dequeues the next achievement for banner display, or hides the banner if the queue is empty
    private func showNextBanner() {
        guard !bannerQueue.isEmpty else {
            showAchievementBanner = false
            return
        }
        newlyUnlocked = [bannerQueue.removeFirst()]
        showAchievementBanner = true
    }
    
    // MARK: - Data Repair
    
    /// Fixes RegionExploration records where totalHexes was saved as 0 due to a SQLite race condition.
    /// Runs once on launch, self-eliminates when all records are healthy, costs nothing on subsequent launches.
    private func repairRegionTotals() {
        let zeroRegions = regions.filter { $0.totalHexes == 0 }
        guard !zeroRegions.isEmpty else { return }
        
        print("🔧 Repairing \(zeroRegions.count) regions with totalHexes = 0")
        
        for region in zeroRegions {
            let total = OfflineDatabase.shared.getTotalHexes(for: region.regionID)
            if total > 0 {
                region.totalHexes = total
                print("✅ Repaired \(region.name): \(total) total hexes")
            }
        }
        
        try? modelContext.save()
    }
}
