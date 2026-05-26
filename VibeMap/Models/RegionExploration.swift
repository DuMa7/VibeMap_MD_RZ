import Foundation
import SwiftData

@Model
class RegionExploration {
    @Attribute(.unique) var regionID: String
    var name: String
    var type: String
    var totalHexes: Int
    var exploredHexes: [String]
    var firstVisited: Date
    var lastVisited: Date
    
    // SwiftData cannot persist Set<String>, so the set is derived from the array on demand.
    // @Transient tells SwiftData to skip this field entirely — it starts nil on every fetch
    // and is lazily populated from exploredHexes on first access.
    //
    // INVARIANT: all mutations to exploredHexes MUST go through addExploredHex to keep
    // _exploredSet in sync. Direct appends to exploredHexes bypass the O(1) dedup check.
    @Transient private var _exploredSet: Set<String>? = nil

    private var exploredSet: Set<String> {
        if _exploredSet == nil {
            _exploredSet = Set(exploredHexes)
        }
        return _exploredSet!
    }
    
    init(regionID: String, name: String, type: String, totalHexes: Int) {
        self.regionID = regionID
        self.name = name
        self.type = type
        self.totalHexes = totalHexes
        self.exploredHexes = []
        self.firstVisited = Date()
        self.lastVisited = Date()
    }
    
    var explorationPercentage: Double {
        // totalHexes can be 0 if the region was written before OfflineDatabase finished opening
        // on first launch (a startup race condition). Rather than a migration, we repair inline:
        // the fix is cheap, self-healing, and requires no schema version bump.
        if totalHexes == 0 {
            let repaired = OfflineDatabase.shared.getTotalHexes(for: regionID)
            if repaired > 0 {
                totalHexes = repaired
            }
        }
        guard totalHexes > 0 else { return 0 }
        return (Double(exploredHexes.count) / Double(totalHexes)) * 100
    }
    
    func addExploredHex(_ h3Index: String) {
        // O(1) check instead of O(n) array scan
        guard !exploredSet.contains(h3Index) else { return }
        
        exploredHexes.append(h3Index)
        _exploredSet?.insert(h3Index) // Keep the set in sync, no rebuild needed
        lastVisited = Date()
    }
}
