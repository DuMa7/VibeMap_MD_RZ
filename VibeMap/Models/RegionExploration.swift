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
        // totalHexes == 0 can only come from a record written before OfflineDatabase
        // finished opening (startup race). Those records are repaired once per launch
        // by ContentView.repairRegionTotals() — the getter stays pure so that view
        // rendering never mutates the model.
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

    /// Replaces `oldIndex` with `newIndex` in the hex list. Called by the res-9 → res-10
    /// migration for each converted record. If `newIndex` is already present (because the
    /// user recorded the res-10 cell after the recording fix was applied), the old entry is
    /// simply removed and no duplicate is introduced. The set is kept in sync throughout.
    func replaceHex(old oldIndex: String, new newIndex: String) {
        guard let position = exploredHexes.firstIndex(of: oldIndex) else { return }
        if exploredSet.contains(newIndex) {
            // res-10 version already recorded — remove the stale res-9 entry only
            exploredHexes.remove(at: position)
            _exploredSet?.remove(oldIndex)
        } else {
            // Swap in place — preserves array length
            exploredHexes[position] = newIndex
            _exploredSet?.remove(oldIndex)
            _exploredSet?.insert(newIndex)
        }
    }
}
