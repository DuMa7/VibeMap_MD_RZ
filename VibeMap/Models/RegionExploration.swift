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
    
    // Transient: not persisted, rebuilt from exploredHexes on first access
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
        // If totalHexes is corrupt, re-query SQLite and repair inline
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
