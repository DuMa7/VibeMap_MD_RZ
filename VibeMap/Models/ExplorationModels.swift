import Foundation
import SwiftData

@Model
class ExploredHex {
    @Attribute(.unique) var h3Index: String
    var resolution: Int
    var visitCount: Int = 1
    var firstVisited: Date = Date()
    var lastVisited: Date = Date()
    var regionID: String?
    
    init(h3Index: String, resolution: Int, regionID: String? = nil) {
        self.h3Index = h3Index
        self.resolution = resolution
        self.regionID = regionID
        self.firstVisited = Date()
        self.lastVisited = Date()
        self.visitCount = 1
    }
    
    func recordVisit() {
        visitCount += 1
        lastVisited = Date()
    }
}

@Model
class LocationPoint {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var h3Index: String
    
    init(latitude: Double, longitude: Double, h3Index: String, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.h3Index = h3Index
        self.timestamp = timestamp
    }
}
