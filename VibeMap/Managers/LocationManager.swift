import UIKit
import H3
import Foundation
import CoreLocation
import Observation
import SwiftData

// MARK: - Session Summary

/// Snapshot of what was discovered during a single exploration session.
/// Built in `stopSession()` after the final flush, before session state is cleared.
struct SessionSummary: Equatable {
    let duration: TimeInterval
    let newHexCount: Int
    /// Municipality names first entered during this session, sorted alphabetically.
    let newRegionNames: [String]
    /// Current exploration streak in days (including today) after this session ends.
    let currentStreak: Int

    var newRegionCount: Int { newRegionNames.count }
}

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var userLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var modelContext: ModelContext?

    /// Whether an exploration session is currently active.
    /// GPS only records hexes during an active session.
    var isSessionActive: Bool = false

    /// Set to `true` when the user enters a Swiss hex that has never been explored
    /// while no session is active. ContentView observes this to show the exploration prompt.
    /// ContentView resets it to `false` immediately after consuming it.
    var shouldPromptUnexploredArea: Bool = false

    /// Populated at the end of each session; ContentView observes this to present the summary sheet.
    var completedSessionSummary: SessionSummary? = nil

    private var sessionStartDate: Date? = nil

    /// Last hex for which an unexplored-area check was run — prevents re-prompting
    /// while the user stays in the same cell, or for an already-checked explored cell.
    private var lastCheckedHex: String? = nil

    // Two-layer deduplication to minimise SwiftData and SQLite traffic:
    //   1. lastSavedHex  — cheapest check: skip if still in the same hex as the previous update
    //   2. exploredHexSet — O(1) full-history check: skip hexes recorded in any past session
    //
    // pendingHexes is a dict rather than an array so writing the same hex twice within one
    // batch is a silent no-op (dict insert overwrites the existing entry).
    private var lastSavedHex: String?
    private var pendingHexes: [String: (resolution: Int, regionID: String)] = [:]

    // Populated from SwiftData at session start; cleared at session end.
    // Hexes in this set skip SQLite → SwiftData entirely on subsequent visits.
    private var exploredHexSet: Set<String> = []

    private var lastFlushTime: Date? = nil
    private var isInForeground = true
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        // Tracking starts only when a session is explicitly started
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Session Control

    func startSession() {
        guard !isSessionActive else { return }
        isSessionActive = true
        shouldPromptUnexploredArea = false
        lastCheckedHex = nil
        sessionStartDate = Date()
        completedSessionSummary = nil
        buildExploredSet()
        if authorizationStatus == .notDetermined {
            requestPermission()
        } else if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            startTracking()
        }
        print("▶️ Exploration session started")
    }

    func stopSession() {
        guard isSessionActive else { return }
        flushPendingData()
        if let startDate = sessionStartDate {
            completedSessionSummary = buildSessionSummary(startDate: startDate)
        }
        isSessionActive = false
        shouldPromptUnexploredArea = false
        lastCheckedHex = nil
        sessionStartDate = nil
        exploredHexSet.removeAll()
        manager.stopUpdatingLocation()
        // Significant-change monitoring keeps userLocation roughly updated at minimal battery cost
        manager.startMonitoringSignificantLocationChanges()
        print("⏹️ Exploration session stopped")
    }

    private func buildSessionSummary(startDate: Date) -> SessionSummary {
        let duration = Date().timeIntervalSince(startDate)
        guard let context = modelContext else {
            return SessionSummary(duration: duration, newHexCount: 0, newRegionNames: [], currentStreak: 0)
        }

        let hexDesc = FetchDescriptor<ExploredHex>(
            predicate: #Predicate { $0.firstVisited >= startDate }
        )
        let newHexCount = (try? context.fetch(hexDesc))?.count ?? 0

        let regionDesc = FetchDescriptor<RegionExploration>(
            predicate: #Predicate { $0.firstVisited >= startDate }
        )
        let newRegionNames = ((try? context.fetch(regionDesc)) ?? [])
            .map { $0.name }
            .sorted()

        let allDates = ((try? context.fetch(FetchDescriptor<ExploredHex>())) ?? []).map { $0.firstVisited }
        let streak = StreakCalculator.calculate(dates: allDates)

        return SessionSummary(duration: duration, newHexCount: newHexCount, newRegionNames: newRegionNames, currentStreak: streak.current)
    }

    private func buildExploredSet() {
        guard let context = modelContext else { return }
        let allHexes = (try? context.fetch(FetchDescriptor<ExploredHex>())) ?? []
        exploredHexSet = Set(allHexes.map { $0.h3Index })
        print("🧠 Suppression set: \(exploredHexSet.count) known hexes loaded")
    }

    func startTracking() {
        applySessionProfile()
    }

    // MARK: - Session Accuracy Profile

    /// Two-tier GPS profile for active sessions.
    /// Foreground: best accuracy for precise hex detection while the user is watching the map.
    /// Background: relaxed accuracy to conserve battery while still catching hex transitions.
    /// Outside a session the manager runs significant-change monitoring only (see stopSession).
    private func applySessionProfile() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()

        if isInForeground {
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 15
            print("📍 Session profile: FOREGROUND (best accuracy, 15 m)")
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 50
            print("📍 Session profile: BACKGROUND (10 m accuracy, 50 m filter)")
        }
        manager.startUpdatingLocation()
    }
    
    // MARK: - Smart Flushing System
    
    func flushPendingData() {
        guard let context = modelContext else { return }
        guard !pendingHexes.isEmpty else { return }
            
        print("💾 Flushing \(pendingHexes.count) hexes to SwiftData...")
            
        beginBackgroundTask()
            
        // Process the Hexagons
        let pendingKeys = Array(pendingHexes.keys)
        let batchDescriptor = FetchDescriptor<ExploredHex>(
            predicate: #Predicate<ExploredHex> { hex in
                pendingKeys.contains(hex.h3Index)
            }
        )
        let alreadyExplored = Set(
            ((try? context.fetch(batchDescriptor)) ?? []).map { $0.h3Index }
        )

        var newHexIndices: [String] = []

        // Batch-fetch all RegionExploration records that will be touched in this flush.
        // Replaces N per-iteration FetchDescriptor calls with one query.
        let candidateRegionIDs = Array(Set(
            pendingHexes.compactMap { alreadyExplored.contains($0.key) ? nil : $0.value.regionID }
        ))
        let regionBatchDescriptor = FetchDescriptor<RegionExploration>(
            predicate: #Predicate<RegionExploration> { candidateRegionIDs.contains($0.regionID) }
        )
        var regionCache: [String: RegionExploration] = Dictionary(
            uniqueKeysWithValues: ((try? context.fetch(regionBatchDescriptor)) ?? []).map { ($0.regionID, $0) }
        )

        for (hexIndex, data) in pendingHexes {
            if alreadyExplored.contains(hexIndex) { continue }

            // 1. Insert the new hex
            context.insert(ExploredHex(h3Index: hexIndex, resolution: data.resolution, regionID: data.regionID))
            newHexIndices.append(hexIndex)

            // 2. Update or create the region tracker using the in-memory cache
            if let region = regionCache[data.regionID] {
                region.addExploredHex(hexIndex)
            } else {
                print("✨ Discovered a brand new region with ID: \(data.regionID)")
                let metadata  = RegionMetadataManager.shared.municipalities[data.regionID]
                let newRegion = RegionExploration(
                    regionID:   data.regionID,
                    name:       metadata?.name ?? "Unknown Region",
                    type:       "Municipality",
                    totalHexes: OfflineDatabase.shared.getTotalHexes(for: data.regionID)
                )
                newRegion.addExploredHex(hexIndex)
                context.insert(newRegion)
                regionCache[data.regionID] = newRegion  // cache for subsequent hexes in same region
            }
        }

        do {
            try context.save()
            print("✅ Successfully flushed data to database")
            for hexIndex in newHexIndices { exploredHexSet.insert(hexIndex) }
            pendingHexes.removeAll()
            lastFlushTime = Date()
        } catch {
            print("❌ Error flushing data: \(error.localizedDescription)")
        }
        
        endBackgroundTask()
    }
    
    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    func applicationDidBecomeActive() {
        isInForeground = true
        flushPendingData()
        if isSessionActive { applySessionProfile() }
    }

    func applicationDidEnterBackground() {
        isInForeground = false
        flushPendingData()
        if isSessionActive { applySessionProfile() }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if isSessionActive {
                // Auth came in while a session was starting — begin full tracking
                startTracking()
            } else {
                // Low-power monitoring so userLocation stays roughly updated
                manager.startMonitoringSignificantLocationChanges()
            }
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let locationAge = abs(location.timestamp.timeIntervalSinceNow)
        // Reject fixes older than 10 s — stale cached positions (e.g. from a cold GPS start)
        // can map to the wrong hex and produce phantom exploration records.
        guard locationAge < 10 else { return }
        // Negative accuracy = invalid fix; >100 m is too imprecise to reliably resolve a
        // res-10 hex (~15 m edge length). Tighter than Apple's default to reduce false positives.
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 100 else { return }

        userLocation = location.coordinate

        // Compute H3 indices for both recording (session active) and
        // unexplored-area detection (session inactive). Both paths need the same pair.
        let latRads = location.coordinate.latitude * .pi / 180.0
        let lonRads = location.coordinate.longitude * .pi / 180.0
        var coord = LatLng(lat: latRads, lng: lonRads)

        // Generate both res-10 (~15 m cells, primary) and res-9 (parent, fallback).
        // We pass both to OfflineDatabase so the lookup can find a regionID even when
        // a boundary area is only indexed at res-9. The res-10 index is always what gets
        // saved — consistent cell granularity regardless of which DB row was matched.
        var h3Index10: H3Index = 0
        var h3Index9:  H3Index = 0
        latLngToCell(&coord, Int32(10), &h3Index10)
        latLngToCell(&coord, Int32(9),  &h3Index9)
        let hex10 = String(h3Index10, radix: 16)
        let hex9  = String(h3Index9,  radix: 16)

        guard isSessionActive else {
            // Outside a session: check whether we've stepped into unexplored territory.
            checkUnexploredArea(hex10: hex10, hex9: hex9)
            return
        }

        // SQLite lookup is synchronous but takes <1 ms on the bundled database (no network)
        if let regionData = OfflineDatabase.shared.getRegionData(res10: hex10, res9: hex9) {
            // Always use the res-10 index as the canonical hex — never the matched DB row's index
            let activeHex = hex10

            // Cheap geofence: same hex as last update — skip immediately
            guard activeHex != lastSavedHex else { return }

            // Already-explored suppression: O(1) check, no SwiftData needed
            guard !exploredHexSet.contains(activeHex) else {
                lastSavedHex = activeHex
                return
            }

            print("📍 New hex entered: \(activeHex) (res-10)")
            lastSavedHex = activeHex
            pendingHexes[activeHex] = (resolution: 10, regionID: regionData.regionID)

            // Foreground: flush every new hex immediately so the map updates in real time.
            // Background: flush immediately too — background execution time is limited and
            // we can't predict when the next didUpdateLocations call will arrive.
            if isInForeground {
                if pendingHexes.count >= 1 { flushPendingData() }
            } else {
                flushPendingData()
            }
        }
    }

    /// Checks whether `hex10` is within Switzerland and has not yet been explored.
    /// Called only when no session is active (significant-change monitoring, ~500 m intervals).
    /// Sets `shouldPromptUnexploredArea = true` the first time a new unexplored cell is detected.
    private func checkUnexploredArea(hex10: String, hex9: String) {
        // Skip if we already ran this check for the same cell
        guard hex10 != lastCheckedHex else { return }
        lastCheckedHex = hex10

        // Only prompt for cells inside Switzerland
        guard OfflineDatabase.shared.getRegionData(res10: hex10, res9: hex9) != nil else { return }
        guard let context = modelContext else { return }

        let desc = FetchDescriptor<ExploredHex>(
            predicate: #Predicate { $0.h3Index == hex10 }
        )
        let alreadyExplored = (try? context.fetch(desc))?.isEmpty == false
        if !alreadyExplored {
            print("🔔 Unexplored area detected: \(hex10) — prompting user")
            shouldPromptUnexploredArea = true
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }
    
    // CLVisit events fire when CoreLocation detects the user has arrived at or departed from
    // a significant place. They are delivered even when the app is not running in the foreground,
    // making them useful for passively catching hex transitions that occur outside active sessions.
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        userLocation = visit.coordinate

        // Only record hexes during an active exploration session
        guard isSessionActive else { return }

        beginBackgroundTask()

        let latRads = visit.coordinate.latitude * .pi / 180.0
        let lonRads = visit.coordinate.longitude * .pi / 180.0
        var coord = LatLng(lat: latRads, lng: lonRads)
        
        var h3Index10: H3Index = 0
        var h3Index9: H3Index = 0
        latLngToCell(&coord, Int32(10), &h3Index10)
        latLngToCell(&coord, Int32(9), &h3Index9)
        
        let hex10 = String(h3Index10, radix: 16)
        let hex9 = String(h3Index9, radix: 16)
        
        if let regionData = OfflineDatabase.shared.getRegionData(res10: hex10, res9: hex9) {
            let activeHex = hex10   // always res-10

            if activeHex != lastSavedHex {
                lastSavedHex = activeHex
                if !exploredHexSet.contains(activeHex) {
                    pendingHexes[activeHex] = (resolution: 10, regionID: regionData.regionID)
                    flushPendingData()
                }
            }
        }

        endBackgroundTask()
    }
    
    deinit {
        flushPendingData()
        endBackgroundTask()
    }
}
