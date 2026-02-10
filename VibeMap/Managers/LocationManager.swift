import H3
import Foundation
import CoreLocation
import Observation
import SwiftData
import MapKit
import CoreMotion

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let activityManager = CMMotionActivityManager()
    
    var userLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var modelContext: ModelContext?
    
    private var currentCity: String?
    private var currentCountry: String?
    
    // PHASE 1: Batch updates & hex geofencing
    private var lastSavedHex: String?
    private var pendingHexes: Set<String> = []
    private var pendingLocationPoints: [(latitude: Double, longitude: Double, h3Index: String)] = []
    private var lastFlushTime = Date()
    private let flushInterval: TimeInterval = 15 * 60 // 15 minutes
    private var flushTimer: Timer?
    
    // PHASE 2: Motion detection
    private var currentProfile: TrackingProfile = .unknown
    
    enum TrackingProfile {
        case walking      // Active movement
        case stationary   // Not moving
        case driving      // Fast movement
        case unknown      // Fallback
        
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
        
        // Start with unknown profile
        applyProfile(.unknown)
        
        // Setup auto-flush timer
        setupFlushTimer()
    }
    
    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }
    
    func startTracking() {
        // Start motion detection if available
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
        
        // Flush any pending data before stopping
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
        
        // Only reconfigure if profile actually changed
        if newProfile != currentProfile {
            print("🔄 Activity changed: \(currentProfile.description) → \(newProfile.description)")
            currentProfile = newProfile
            applyProfile(newProfile)
        }
    }
    
    private func applyProfile(_ profile: TrackingProfile) {
        // Stop all tracking first
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        
        switch profile {
        case .walking:
            // High precision for walking
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 20 // ~1/8 of a hex at resolution 9
            manager.startUpdatingLocation()
            print("📍 Tracking mode: WALKING (20m filter, best accuracy)")
            
        case .driving:
            // Medium precision for driving
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 50 // Faster movement = larger filter OK
            manager.startUpdatingLocation()
            print("📍 Tracking mode: DRIVING (50m filter, medium accuracy)")
            
        case .stationary:
            // Ultra low power when stationary
            manager.stopUpdatingLocation()
            manager.startMonitoringSignificantLocationChanges()
            print("📍 Tracking mode: STATIONARY (significant changes only)")
            
        case .unknown:
            // Balanced default
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 30
            manager.startUpdatingLocation()
            print("📍 Tracking mode: UNKNOWN (30m filter, medium accuracy)")
        }
    }
    
    // MARK: - Batch Update System
    
    private func setupFlushTimer() {
        // Invalidate any existing timer
        flushTimer?.invalidate()
        
        // Create timer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.flushTimer = Timer.scheduledTimer(withTimeInterval: self.flushInterval, repeats: true) { [weak self] _ in
                print("⏰ Timer triggered flush")
                self?.flushPendingData()
            }
            
            // Ensure timer runs in background
            if let timer = self.flushTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    
    func flushPendingData() {
        guard let context = modelContext else { return }
        guard !pendingHexes.isEmpty || !pendingLocationPoints.isEmpty else { return }
        
        let hexCount = pendingHexes.count
        let pointCount = pendingLocationPoints.count
        
        print("💾 Flushing \(hexCount) hexes and \(pointCount) location points to database...")
        
        // Save all pending location points
        for point in pendingLocationPoints {
            let locationPoint = LocationPoint(
                latitude: point.latitude,
                longitude: point.longitude,
                h3Index: point.h3Index
            )
            context.insert(locationPoint)
        }
        
        // Save all pending hexes
        for hexIndex in pendingHexes {
            let descriptor = FetchDescriptor<ExploredHex>(
                predicate: #Predicate { $0.h3Index == hexIndex }
            )
            
            if let existingHex = try? context.fetch(descriptor).first {
                existingHex.recordVisit()
            } else {
                let isBigCity = PopulationManager.shared.isBigCity(self.currentCity ?? "", threshold: 10000)
                let newHex = ExploredHex(h3Index: hexIndex, isUrban: isBigCity)
                
                context.insert(newHex)
            }
        }
        
        // Save to database
        do {
            try context.save()
            print("✅ Successfully flushed data to database")
            
            // Clear pending data
            pendingHexes.removeAll()
            pendingLocationPoints.removeAll()
            lastFlushTime = Date()
        } catch {
            print("❌ Error flushing data: \(error.localizedDescription)")
        }
    }
    
    func applicationDidBecomeActive() {
        print("📱 App became active - flushing pending data")
        flushPendingData()
    }
    
    func applicationDidEnterBackground() {
        print("📱 App entering background - flushing pending data")
        flushPendingData()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            print("✅ Location permission granted")
            startTracking()
        case .denied, .restricted:
            print("❌ Location permission denied")
        case .notDetermined:
            print("⏳ Location permission not determined")
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Filter out stale locations (older than 10 seconds)
        let locationAge = abs(location.timestamp.timeIntervalSinceNow)
        guard locationAge < 10 else {
            print("⏭️ Skipping stale location (age: \(Int(locationAge))s)")
            return
        }
        
        userLocation = location.coordinate
        
        let latRads = location.coordinate.latitude * .pi / 180.0
        let lonRads = location.coordinate.longitude * .pi / 180.0
        var coord = LatLng(lat: latRads, lng: lonRads)
        var h3Index: H3Index = 0
        let error = latLngToCell(&coord, Int32(10), &h3Index)
        
        if error == 0 {
            let hexString = String(h3Index, radix: 16)
            
            // HEX GEOFENCING: Only process if we entered a new hex
            if hexString != lastSavedHex {
                print("📍 New hex entered: \(hexString) [\(currentProfile.description)]")
                
                lastSavedHex = hexString
                
                // Add to pending batch
                pendingHexes.insert(hexString)
                pendingLocationPoints.append((
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    h3Index: hexString
                ))
                
                // Trigger city detection
                let clLocation = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                detectCity(from: clLocation, h3Index: hexString)
                
                print("🔄 Batched (pending: \(pendingHexes.count) hexes)")
            }
        } else {
            print("⚠️ H3 Error: Could not generate index. Error code: \(error)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        print("📍 Visit detected: \(visit.coordinate.latitude), \(visit.coordinate.longitude)")
        
        userLocation = visit.coordinate
        
        let latRads = visit.coordinate.latitude * .pi / 180.0
        let lonRads = visit.coordinate.longitude * .pi / 180.0
        var coord = LatLng(lat: latRads, lng: lonRads)
        var h3Index: H3Index = 0
        let error = latLngToCell(&coord, Int32(9), &h3Index)
        
        if error == 0 {
            let hexString = String(h3Index, radix: 16)
            
            if hexString != lastSavedHex {
                lastSavedHex = hexString
                pendingHexes.insert(hexString)
                pendingLocationPoints.append((
                    latitude: visit.coordinate.latitude,
                    longitude: visit.coordinate.longitude,
                    h3Index: hexString
                ))
                
                print("🔄 Visit batched")
            }
        }
    }
    
    // MARK: - City Detection (Modern MapKit)
    
    private func detectCity(from location: CLLocation, h3Index: String) {
        guard let context = modelContext else { return }
        
        Task {
            do {
                let searchRequest = MKLocalSearch.Request()
                searchRequest.naturalLanguageQuery = "city"
                searchRequest.region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                searchRequest.resultTypes = .address
                
                let search = MKLocalSearch(request: searchRequest)
                let response = try await search.start()
                
                guard let firstItem = response.mapItems.first,
                      let city = firstItem.placemark.locality ?? firstItem.placemark.subLocality,
                      let country = firstItem.placemark.country else {
                    return
                }
                
                await MainActor.run {
                    if self.currentCity != city {
                        self.currentCity = city
                        self.currentCountry = country
                        print("🏙️ Entered: \(city), \(country)")
                    }
                    
                    self.updateCityExploration(city: city, country: country, location: location, h3Index: h3Index, context: context)
                }
                
            } catch {
                print("⚠️ Geocoding error: \(error.localizedDescription)")
            }
        }
    }
    
    private func updateCityExploration(city: String, country: String, location: CLLocation, h3Index: String, context: ModelContext) {
        let descriptor = FetchDescriptor<CityExploration>(
            predicate: #Predicate { $0.cityName == city }
        )
        
        let cityExploration: CityExploration
        if let existing = try? context.fetch(descriptor).first {
            cityExploration = existing
        } else {
            cityExploration = CityExploration(
                cityName: city,
                country: country,
                centerLat: location.coordinate.latitude,
                centerLon: location.coordinate.longitude,
                radius: 10000
            )
            context.insert(cityExploration)
            
            Task {
                await self.calculateTotalHexes(for: cityExploration, context: context)
            }
            
            print("✨ New city discovered: \(city)!")
        }
        
        cityExploration.addExploredHex(h3Index)
        try? context.save()
    }
    
    private func calculateTotalHexes(for city: CityExploration, context: ModelContext) async {
        let center = CLLocationCoordinate2D(latitude: city.centerLatitude, longitude: city.centerLongitude)
        let radiusInDegrees = city.radiusInMeters / 111000.0
        
        var hexSet = Set<String>()
        
        let steps = 50
        for latStep in 0..<steps {
            for lonStep in 0..<steps {
                let lat = center.latitude - radiusInDegrees + (2 * radiusInDegrees * Double(latStep) / Double(steps))
                let lon = center.longitude - radiusInDegrees + (2 * radiusInDegrees * Double(lonStep) / Double(steps))
                
                let point = CLLocation(latitude: lat, longitude: lon)
                let distance = point.distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
                
                if distance <= city.radiusInMeters {
                    let latRads = lat * .pi / 180.0
                    let lonRads = lon * .pi / 180.0
                    var coord = LatLng(lat: latRads, lng: lonRads)
                    var h3Index: H3Index = 0
                    let error = latLngToCell(&coord, Int32(9), &h3Index)
                    
                    if error == 0 {
                        hexSet.insert(String(h3Index, radix: 16))
                    }
                }
            }
        }
        
        await MainActor.run {
            city.totalHexesInBoundary = hexSet.count
            try? context.save()
            print("🔷 \(city.cityName): \(hexSet.count) total hexes calculated")
        }
    }
    
    deinit {
        flushTimer?.invalidate()
        flushPendingData()
    }
}
