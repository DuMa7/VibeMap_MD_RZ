import SwiftUI
import MapKit

struct MapView: View {
    @Binding var position: MapCameraPosition
    @Binding var currentSpan: Double
    @Binding var centerCoordinate: CLLocationCoordinate2D?

    /// Merged outline polygons for all explored hexes — rebuilt asynchronously when hexes change.
    /// Replaces N individual MapPolygon views with a handful of cluster outlines.
    @State private var hexOutlines: [[CLLocationCoordinate2D]] = []

    /// Merged outline polygons for all explored hexes promoted to res-9 — used at intermediate zoom levels.
    /// Built by converting every res-10 hex to its res-9 parent, then merging. Gives complete
    /// coarse coverage at mid-zoom rather than just the sparse boundary-fallback hexes.
    @State private var res9Outlines: [[CLLocationCoordinate2D]] = []

    /// Canton IDs of all visited regions — cached to avoid recomputing on every render pass
    @State private var cachedCantonIDs: Set<String> = []

    /// Region IDs of all visited municipalities — O(1) filter for the municipality zoom layer
    @State private var cachedMunicipalityIDs: Set<String> = []

    /// Fast lookup for region colour — avoids O(N) scan per visible municipality per render
    @State private var regionLookup: [String: RegionExploration] = [:]

    /// Exploration % per canton (visited municipalities / total municipalities in that canton).
    /// Computed in rebuildRegionCaches and used to shade canton polygons.
    @State private var cantonExplorationPct: [String: Double] = [:]

    /// Handle for the in-flight street-zoom (res-10) outline rebuild
    @State private var streetOutlineTask: Task<Void, Never>?

    /// Handle for the in-flight mid-zoom (res-9) outline rebuild
    @State private var midZoomOutlineTask: Task<Void, Never>?

    var exploredHexes: [ExploredHex]
    var regions: [RegionExploration]
    var layerManager: MapLayerManager
    var layerSettings: MapLayerSettings
    var userLocation: CLLocationCoordinate2D?

    var body: some View {
        // Zoom threshold ladder (latitudeDelta of the visible region):
        //   ≥ 10.0        — world/continent scale — nothing drawn
        //   2.0 – 10.0   — canton polygons
        //   0.2 – 2.0    — municipality fill polygons (opacity scales with exploration %)
        //   0.02 – 0.2   — merged res-9 hex outlines (~city-block scale)
        //   < 0.02       — full res-10 hex outlines (street level, ~15 m cells)
        Map(position: $position) {
            UserAnnotation()

            if layerSettings.showExploredHexes && currentSpan < 10.0 {
                if currentSpan >= 2.0 {
                    ForEach(layerManager.cantons.filter { cachedCantonIDs.contains($0.id) }) { canton in
                        ForEach(0..<canton.polygons.count, id: \.self) { i in
                            MapPolygon(coordinates: canton.polygons[i])
                                .foregroundStyle(colorForCanton(canton.id))
                                .stroke(.white, lineWidth: 1.5)
                        }
                    }
                } else if currentSpan >= 0.2 {
                    ForEach(layerManager.municipalities.filter { cachedMunicipalityIDs.contains($0.id) }) { muni in
                        ForEach(0..<muni.polygons.count, id: \.self) { i in
                            MapPolygon(coordinates: muni.polygons[i])
                                .foregroundStyle(colorForRegion(muni.id))
                                .stroke(.white.opacity(0.3), lineWidth: 0.5)
                        }
                    }
                } else if currentSpan >= 0.02 {
                    ForEach(res9Outlines.indices, id: \.self) { i in
                        MapPolygon(coordinates: res9Outlines[i])
                            .foregroundStyle(.orange.opacity(0.4))
                            .stroke(.orange, lineWidth: 1)
                    }
                } else {
                    ForEach(hexOutlines.indices, id: \.self) { i in
                        MapPolygon(coordinates: hexOutlines[i])
                            .foregroundStyle(.orange.opacity(0.4))
                            .stroke(.orange, lineWidth: 1)
                    }
                }
            }
        }
        .mapStyle(layerSettings.baseStyle.mapStyle)
        .mapControlVisibility(.hidden)
        .animation(.easeInOut(duration: 0.5), value: currentSpan)
        .onMapCameraChange(frequency: .onEnd) { context in
            currentSpan = context.region.span.latitudeDelta
            centerCoordinate = context.region.center
        }
        .onAppear {
            rebuildRegionCaches()
            rebuildMidZoomOutlines(exploredHexes)
            if currentSpan < 0.02 { rebuildStreetOutlines(exploredHexes) }
        }
        .onChange(of: exploredHexes) { _, newHexes in
            // Keep both outline sets current regardless of the active zoom level —
            // the user may zoom between layers at any time.
            rebuildMidZoomOutlines(newHexes)
            if currentSpan < 0.02 { rebuildStreetOutlines(newHexes) }
        }
        .onChange(of: regions) { _, _ in
            rebuildRegionCaches()
        }
        // Zoom trigger: fires when the user pinch-zooms (span changes).
        // Handles the common case where the map centre stays constant —
        // onChange(of: centerCoordinate) would not fire for a pure zoom gesture.
        .onChange(of: currentSpan) { _, newSpan in
            if newSpan < 0.02 { rebuildStreetOutlines(exploredHexes) }
        }
        // Pan trigger: fires when the user pans at street zoom (centre changes, span stays).
        .onChange(of: centerCoordinate) { _, _ in
            if currentSpan < 0.02 { rebuildStreetOutlines(exploredHexes) }
        }
    }

    // MARK: - Outline Builders

    /// Builds viewport-culled res-10 outlines for the street-zoom layer (span < 0.02).
    /// Only called when already at street zoom — never precomputed for other levels.
    /// Uses its own task handle so mid-zoom rebuilds cannot cancel it.
    private func rebuildStreetOutlines(_ hexes: [ExploredHex]) {
        guard let center = centerCoordinate else { return }
        let indices = viewportFilteredIndices(from: hexes, center: center, span: currentSpan)
        // Adaptive debounce: post-cull count is small at street zoom → fast and responsive.
        let debounceNs: UInt64 = indices.count < 500 ? 300_000_000 : 1_500_000_000

        streetOutlineTask?.cancel()
        streetOutlineTask = Task {
            do { try await Task.sleep(nanoseconds: debounceNs) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                HexMerger.mergeHexOutlines(indices)
            }.value
            guard !Task.isCancelled else { return }
            hexOutlines = result
            print("📐 Street outlines: \(result.count) rings from \(indices.count) visible hexes (\(hexes.count) total)")
        }
    }

    /// Builds global res-9 outlines for the mid-zoom layer (span 0.02 – 0.2).
    /// No viewport culling: at mid-zoom the visible area spans several km and the
    /// promoted res-9 set is already ~7× smaller than the full res-10 set.
    /// Uses its own task handle so street-zoom pans cannot cancel it.
    private func rebuildMidZoomOutlines(_ hexes: [ExploredHex]) {
        let res9Indices = Array(Set(hexes.compactMap { hex -> String? in
            if hex.resolution == 9 { return hex.h3Index }
            return H3Wrapper.cellToParent(h3Index: hex.h3Index, parentRes: 9)
        }))

        midZoomOutlineTask?.cancel()
        midZoomOutlineTask = Task {
            do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                HexMerger.mergeHexOutlines(res9Indices)
            }.value
            guard !Task.isCancelled else { return }
            res9Outlines = result
            print("📐 Mid-zoom outlines: \(result.count) rings from \(res9Indices.count) res-9 cells")
        }
    }

    /// Returns the h3Index strings of hexes whose centroid falls within the viewport bounding box.
    /// A 2× buffer beyond the visible span lets the user pan slightly without triggering a rebuild.
    private func viewportFilteredIndices(
        from hexes: [ExploredHex],
        center: CLLocationCoordinate2D,
        span: Double
    ) -> [String] {
        let buffer = span * 2.0
        let minLat = center.latitude  - buffer
        let maxLat = center.latitude  + buffer
        let minLon = center.longitude - buffer
        let maxLon = center.longitude + buffer

        return hexes.compactMap { hex in
            guard let c = H3Wrapper.cellCenter(h3Index: hex.h3Index) else {
                return hex.h3Index // include if centroid is unavailable — safe fallback
            }
            guard c.latitude  >= minLat, c.latitude  <= maxLat,
                  c.longitude >= minLon, c.longitude <= maxLon else { return nil }
            return hex.h3Index
        }
    }

    // MARK: - Region Caches

    /// Rebuilds all region-derived caches in one pass over `regions`.
    /// Called on appear and on every regions change — NOT on exploredHexes change,
    /// since canton/municipality membership only changes when a new region is discovered.
    private func rebuildRegionCaches() {
        var cantonIDs        = Set<String>()
        var muniIDs          = Set<String>()
        var lookup           = [String: RegionExploration](minimumCapacity: regions.count)
        var visitedPerCanton = [String: Int]()

        for region in regions {
            muniIDs.insert(region.regionID)
            lookup[region.regionID] = region
            if let cantonID = RegionMetadataManager.shared.municipalities[region.regionID]?.cantonID {
                cantonIDs.insert(cantonID)
                visitedPerCanton[cantonID, default: 0] += 1
            }
        }

        // Total municipalities per canton — derived from bundled metadata, constant at runtime.
        // Computed here (not cached globally) because rebuildRegionCaches is called rarely.
        var totalPerCanton = [String: Int]()
        for (_, meta) in RegionMetadataManager.shared.municipalities {
            totalPerCanton[meta.cantonID, default: 0] += 1
        }

        // Canton exploration % = visited municipalities / total municipalities in that canton
        var pct = [String: Double]()
        for (cantonID, visitedCount) in visitedPerCanton {
            let total = totalPerCanton[cantonID] ?? 1
            pct[cantonID] = Double(visitedCount) / Double(total)
        }

        cachedCantonIDs       = cantonIDs
        cachedMunicipalityIDs = muniIDs
        regionLookup          = lookup
        cantonExplorationPct  = pct
    }

    // MARK: - Region Color

    /// Returns an orange fill whose opacity scales with the municipality's hex exploration %.
    /// Floor of 0.15 keeps even barely-visited municipalities visible on the map.
    /// Ceiling of 0.6 avoids solid orange blobs at full coverage.
    private func colorForRegion(_ id: String) -> AnyShapeStyle {
        guard let region = regionLookup[id] else { return AnyShapeStyle(.clear) }
        let pct = region.explorationPercentage / 100.0   // explorationPercentage is 0–100
        let opacity = max(0.15, pct * 0.6)
        return AnyShapeStyle(.orange.opacity(opacity))
    }

    /// Returns an orange fill whose opacity scales with the fraction of municipalities visited
    /// in the canton (cantonExplorationPct is pre-computed in rebuildRegionCaches).
    /// Same floor/ceiling as colorForRegion so the two zoom levels look consistent.
    private func colorForCanton(_ id: String) -> AnyShapeStyle {
        let pct = cantonExplorationPct[id] ?? 0.0   // already 0.0–1.0
        let opacity = max(0.15, pct * 0.6)
        return AnyShapeStyle(.orange.opacity(opacity))
    }
}

// @retroactive conformance: CLLocationCoordinate2D (CoreLocation) to Equatable (stdlib).
// Required so SwiftUI's onChange(of:) can diff camera positions that embed coordinates.
// The @retroactive attribute suppresses the "conformance to external protocol" compiler warning.
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
