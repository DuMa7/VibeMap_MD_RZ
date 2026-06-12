import Foundation
import SwiftData

// Two complementary models represent exploration data at different granularities:
//
//   ExploredHex — one record per H3 cell visited. Used for map outline rendering,
//                 achievement hex counts, and the in-memory suppression set that
//                 LocationManager builds at session start.
//
//   LocationPoint — raw GPS coordinates (currently unused; reserved for a future
//                   breadcrumb trail or route replay feature).
//
// RegionExploration (defined separately) aggregates hexes at the municipality level
// for progress stats and canton-level rollups.

@Model
class ExploredHex {
    // Unique constraint enforced by SwiftData — duplicate inserts throw at the model layer.
    // LocationManager's exploredHexSet prevents ever reaching that path during normal use.
    @Attribute(.unique) var h3Index: String
    var resolution: Int
    // visitCount is always 1 — each hex is recorded exactly once and never updated.
    // The property is kept in the model to avoid a SwiftData schema migration;
    // remove it alongside a VersionedSchema bump if the model is ever versioned.
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
}

// Currently unused — the app records hexes rather than raw coordinates.
// Kept for a potential future breadcrumb trail or route replay feature.
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
