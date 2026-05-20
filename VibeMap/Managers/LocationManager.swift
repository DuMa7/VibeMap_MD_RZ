import UIKit
import H3
import Foundation
import CoreLocation
import Observation
import SwiftData
import CoreMotion

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let activityManager = CMMotionActivityManager()
    
    var userLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var modelContext: ModelContext?

    /// Whether an exploration session is currently active.
    /// GPS only records hexes during an active session.
    var isSessionActive: Bool = false
    
    // PHASE 3: Improved batch system using Dictionary to hold DB context
    private var lastSavedHex: String?
    private var pendingHexes: [String: (resolution: Int, regionID: String)] = [:]
    
    // Track the last time we flushed pending data
    private var lastFlushTime: Date? = nil
    
    // Track app state
    private var isInForeground = true
    
    // Background task identifier
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Motion detection
    private var currentProfile: TrackingProfile = .unknown
    
    enum TrackingProfile {
        case walking
        case stationary
        case driving
        case unknown
        
        var description: String {
            switch self {
            case .walking: return "Walking 🚶"
            case .stationary: return "Stationary 🛑"
            case .driving: return "Driving 🚗"
            case .unknown: return "Unknown ❓"
            }
        }
    }
    
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
        manager.stopUpdatingLocation()
        activityManager.stopActivityUpdates()
        // Fall back to low-power monitoring so userLocation stays roughly updated
        manager.startMonitoringSignificantLocationChanges()
        print("⏹️ Exploration session stopped")
    }

    func startTracking() {
        if CMMotionActivityManager.isActivityAvailable() {
            startMotionDetection()
        } else {
            print("⚠️ Motion detection not available - using default profile")
            applyProfile(.unknown)
        }
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        activityManager.stopActivityUpdates()

        flushPendingData()
    }
    
    // MARK: - Motion Detection
    
    private func startMotionDetection() {
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            self.handleActivityChange(activity)
        }
    }
    
    private func handleActivityChange(_ activity: CMMotionActivity) {
        let newProfile: TrackingProfile
        
        if activity.stationary {
            newProfile = .stationary
        } else if activity.walking || activity.running {
            newProfile = .walking
        } else if activity.automotive {
            newProfile = .driving
        } else {
            newProfile = .unknown
        }
        
        if newProfile != currentProfile {
            print("🔄 Activity changed: \(currentProfile.description) → \(newProfile.description)")
            currentProfile = newProfile
            applyProfile(newProfile)
        }
    }
    
    private func applyProfile(_ profile: TrackingProfile) {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        
        switch profile {
        case .walking:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 20
            manager.startUpdatingLocation()
            print("📍 Tracking mode: WALKING")
            
        case .driving:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 50
            manager.startUpdatingLocation()
            print("📍 Tracking mode: DRIVING")
            
        case .stationary:
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoringVisits()
            print("📍 Tracking mode: STATIONARY")
            
        case .unknown:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 30
            manager.startUpdatingLocation()
            print("📍 Tracking mode: UNKNOWN")
        }
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

        for (hexIndex, data) in pendingHexes {
            // O(1) set lookup instead of a database round trip
            if alreadyExplored.contains(hexIndex) {
                continue
            } else {
                // 1. Save the brand new hex to SwiftData
                let newHex = ExploredHex(h3Index: hexIndex, resolution: data.resolution, regionID: data.regionID)
                    context.insert(newHex)
                    
                // 2. INCREMENT REGION PROGRESS
                let regionIdToFind = data.regionID
                let regionDescriptor = FetchDescriptor<RegionExploration>(
                    predicate: #Predicate { $0.regionID == regionIdToFind }
                )
                    
                if let region = try? context.fetch(regionDescriptor).first {
                    // The region tracker already exists, just add the new hex!
                    region.addExploredHex(hexIndex)
                } else {
                    // 3. FIRST TIME DISCOVERY
                    print("✨ Discovered a brand new region with ID: \(data.regionID)")
                                        
                    // Look up the real name and Canton ID from our GeoJSON metadata
                    let metadata = RegionMetadataManager.shared.municipalities[data.regionID]
                    let regionName = metadata?.name ?? "Unknown Region"
                                        
                    // Ask SQLite exactly how many hexes make up this municipality
                    let totalHexes = OfflineDatabase.shared.getTotalHexes(for: data.regionID)
                                        
                    // Create the progress tracker!
                    let newRegion = RegionExploration(
                        regionID: data.regionID,
                        name: regionName,
                        type: "Municipality",
                        totalHexes: totalHexes
                    )
                                        
                    newRegion.addExploredHex(hexIndex)
                    context.insert(newRegion)
                                        
                    // Bonus: You can now easily expand this right here to create
                    // a tracker for metadata?.cantonID to power your Canton zoom view!
                }
            }
        }
            
        do {
            try context.save()
            print("✅ Successfully flushed data to database")
                 
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
        if isSessionActive, CMMotionActivityManager.isActivityAvailable() {
            startMotionDetection()
        }
    }

    func applicationDidEnterBackground() {
        isInForeground = false
        flushPendingData()
        if isSessionActive {
            applyProfile(.unknown)
        }
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
            
            // 3. HEX GEOFENCING
            if activeHex != lastSavedHex {
                print("📍 New hex entered: \(activeHex) (Res \(regionData.resolution))")
                
                lastSavedHex = activeHex
                
                // Add to Dictionary batch with database info
                pendingHexes[activeHex] = (resolution: regionData.resolution, regionID: regionData.regionID)
                
                if isInForeground {
                    if pendingHexes.count >= 1 { flushPendingData() } //change this later to 5 again otherwise will constantly refresh
                } else {
                    flushPendingData()
                }
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
                pendingHexes[activeHex] = (resolution: regionData.resolution, regionID: regionData.regionID)
                flushPendingData()
            }
        }
        
        endBackgroundTask()
    }
    
    deinit {
        flushPendingData()
        endBackgroundTask()
    }
}
