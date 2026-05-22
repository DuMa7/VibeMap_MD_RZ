import UIKit
import H3
import Foundation
import CoreLocation
import Observation
import SwiftData

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var userLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var modelContext: ModelContext?

    /// Whether an exploration session is currently active.
    /// GPS only records hexes during an active session.
    var isSessionActive: Bool = false

    private var lastSavedHex: String?
    private var pendingHexes: [String: (resolution: Int, regionID: String)] = [:]

    // Already-explored suppression (6.3): O(1) set built at session start.
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
        isSessionActive = false
        exploredHexSet.removeAll()
        manager.stopUpdatingLocation()
        // Significant-change monitoring keeps userLocation roughly updated at minimal battery cost
        manager.startMonitoringSignificantLocationChanges()
        print("⏹️ Exploration session stopped")
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
        guard locationAge < 10 else { return }
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 100 else { return }

        userLocation = location.coordinate

        // Only record hexes during an active exploration session
        guard isSessionActive else { return }

        let latRads = location.coordinate.latitude * .pi / 180.0
        let lonRads = location.coordinate.longitude * .pi / 180.0
        var coord = LatLng(lat: latRads, lng: lonRads)
        
        // 1. Generate both Res 10 and Res 9 indices natively in C
        var h3Index10: H3Index = 0
        var h3Index9: H3Index = 0
        latLngToCell(&coord, Int32(10), &h3Index10)
        latLngToCell(&coord, Int32(9), &h3Index9)
        
        let hex10 = String(h3Index10, radix: 16)
        let hex9 = String(h3Index9, radix: 16)
        
        // 2. Query the SQLite database natively (NO NETWORK!)
        if let regionData = OfflineDatabase.shared.getRegionData(res10: hex10, res9: hex9) {
            let activeHex = regionData.matchedHex

            // 3. Cheap geofence: same hex as last update — skip immediately
            guard activeHex != lastSavedHex else { return }

            // 4. Already-explored suppression: O(1) check, no SwiftData needed
            guard !exploredHexSet.contains(activeHex) else {
                lastSavedHex = activeHex
                return
            }

            print("📍 New hex entered: \(activeHex) (Res \(regionData.resolution))")
            lastSavedHex = activeHex
            pendingHexes[activeHex] = (resolution: regionData.resolution, regionID: regionData.regionID)

            if isInForeground {
                if pendingHexes.count >= 1 { flushPendingData() }
            } else {
                flushPendingData()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }
    
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
            let activeHex = regionData.matchedHex

            if activeHex != lastSavedHex {
                lastSavedHex = activeHex
                if !exploredHexSet.contains(activeHex) {
                    pendingHexes[activeHex] = (resolution: regionData.resolution, regionID: regionData.regionID)
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
