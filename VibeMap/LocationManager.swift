import H3
import Foundation
import CoreLocation
import Observation
import SwiftData
import MapKit // Add this

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    var userLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var modelContext: ModelContext?
    
    private var currentCity: String?
    private var currentCountry: String?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }
    
    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }
    
    func startTracking() {
        // Use significant location changes (battery efficient)
        // This triggers when you move ~500 meters
        manager.startMonitoringSignificantLocationChanges()
        
        // Optional: Also use visit monitoring (detects when you stay in one place)
        manager.startMonitoringVisits()
    }
    
    func stopTracking() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
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
        
        userLocation = location.coordinate
        
        let latRads = location.coordinate.latitude * .pi / 180.0
        let lonRads = location.coordinate.longitude * .pi / 180.0
        var coord = LatLng(lat: latRads, lng: lonRads)
        var h3Index: H3Index = 0
        let error = latLngToCell(&coord, Int32(9), &h3Index)
        
        if error == 0 {
            let hexString = String(h3Index, radix: 16)
            
            print("📍 Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            print("🔷 H3 Index: \(hexString)")
            
            saveLocation(latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        h3Index: hexString)
        } else {
            print("⚠️ H3 Error: Could not generate index. Error code: \(error)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        print("📍 Visit detected: \(visit.coordinate.latitude), \(visit.coordinate.longitude)")
        print("   Arrival: \(visit.arrivalDate)")
        print("   Departure: \(visit.departureDate)")
        
        // Treat visits as location updates
        userLocation = visit.coordinate
        
        let latRads = visit.coordinate.latitude * .pi / 180.0
        let lonRads = visit.coordinate.longitude * .pi / 180.0
        var coord = LatLng(lat: latRads, lng: lonRads)
        var h3Index: H3Index = 0
        let error = latLngToCell(&coord, Int32(9), &h3Index)
        
        if error == 0 {
            let hexString = String(h3Index, radix: 16)
            saveLocation(latitude: visit.coordinate.latitude,
                        longitude: visit.coordinate.longitude,
                        h3Index: hexString)
        }
    }
    
    // MARK: - Data Persistence
    
    private func saveLocation(latitude: Double, longitude: Double, h3Index: String) {
        guard let context = modelContext else { return }
        
        let locationPoint = LocationPoint(latitude: latitude, longitude: longitude, h3Index: h3Index)
        context.insert(locationPoint)
        
        let descriptor = FetchDescriptor<ExploredHex>(
            predicate: #Predicate { $0.h3Index == h3Index }
        )
        
        if let existingHex = try? context.fetch(descriptor).first {
            existingHex.recordVisit()
        } else {
            let newHex = ExploredHex(h3Index: h3Index)
            context.insert(newHex)
            print("✨ New hex discovered!")
        }
        
        let location = CLLocation(latitude: latitude, longitude: longitude)
        detectCity(from: location, h3Index: h3Index)
        
        try? context.save()
    }
    
    // MARK: - City Detection (Modern MapKit)

    private func detectCity(from location: CLLocation, h3Index: String) {
        guard let context = modelContext else { return }
        
        Task {
            do {
                // Use MKLocalSearch with coordinate query
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
                    print("⚠️ Could not determine city")
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
}
