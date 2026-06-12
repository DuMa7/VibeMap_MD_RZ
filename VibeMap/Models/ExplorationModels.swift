import Foundation
import SwiftData

// ExploredHex — one record per H3 cell visited. Used for map outline rendering,
// achievement hex counts, and the in-memory suppression set that LocationManager
// builds at session start.
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
