import SwiftUI
import MapKit

struct MapView: View {
    @Binding var position: MapCameraPosition
    @Binding var currentSpan: Double
    @Binding var centerCoordinate: CLLocationCoordinate2D?

    // MARK: - Spatial Index

    /// Grid bucket side-length in degrees. 0.1° ≈ 7 km at Swiss latitudes —
    /// each bucket holds ~50 hexes at 50k total, ~200 at 200k.
    /// Viewport lookup at span 0.15 touches ~36 buckets regardless of total hex count.
    private static let gridBucketSize = 0.1

    /// 2D bucket key. Both fields are `Int` so the struct is automatically Sendable.
    private struct GridKey: Hashable, Sendable {
        let lat: Int
        let lon: Int
    }

    /// Spatial index: grid bucket → h3Index strings of hexes whose centroid falls in that bucket.
    /// Rebuilt entirely off the main thread when `exploredHexes` changes.
    /// Lookup at render time is O(buckets_in_viewport) ≈ O(36) instead of O(total_hexes).
    @State private var spatialGrid: [GridKey: [String]] = [:]

    /// Handle for the in-flight grid rebuild — cancelled and replaced on each exploredHexes change.
    @State private var spatialGridTask: Task<Void, Never>?

    // MARK: - Outline State

    /// Merged outline polygons — updated after each viewport query + HexMerger run.
    @State private var hexOutlines: [[CLLocationCoordinate2D]] = []

    /// Handle for the in-flight outline rebuild.
    @State private var hexOutlineTask: Task<Void, Never>?

    // MARK: - Region Caches

    /// Canton IDs of all visited regions — O(1) filter for the canton zoom layer.
    @State private var cachedCantonIDs: Set<String> = []

    /// Region IDs of all visited municipalities — O(1) filter for the municipality zoom layer.
    @State private var cachedMunicipalityIDs: Set<String> = []

    /// Fast colour lookup per municipality — avoids O(N) scan per visible polygon per render.
    @State private var regionLookup: [String: RegionExploration] = [:]

    /// Exploration % per canton (visited municipalities / total municipalities).
    @State private var cantonExplorationPct: [String: Double] = [:]

    // MARK: - Input

    var exploredHexes: [ExploredHex]
    var regions: [RegionExploration]
    var layerManager: MapLayerManager
    var layerSettings: MapLayerSettings
    var userLocation: CLLocationCoordinate2D?

    var body: some View {
        // Zoom threshold ladder (latitudeDelta of the visible region):
        //   ≥ 10.0        — world/continent scale — nothing drawn
        //   2.0 – 10.0   — canton polygons
        //   0.15 – 2.0   — municipality fill polygons (opacity ∝ exploration %)
        //   < 0.15       — res-10 hex outlines, viewport-culled via spatial grid
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
                } else if currentSpan >= 0.15 {
                    ForEach(layerManager.municipalities.filter { cachedMunicipalityIDs.contains($0.id) }) { muni in
                        ForEach(0..<muni.polygons.count, id: \.self) { i in
                            MapPolygon(coordinates: muni.polygons[i])
                                .foregroundStyle(colorForRegion(muni.id))
                                .stroke(.white.opacity(0.3), lineWidth: 0.5)
                        }
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
            // Grid rebuild triggers rebuildHexOutlines when complete — no direct call needed.
            rebuildSpatialGrid(exploredHexes)
        }
        .onChange(of: exploredHexes) { _, newHexes in
            rebuildSpatialGrid(newHexes)
        }
        .onChange(of: regions) { _, _ in
            rebuildRegionCaches()
        }
        // Viewport changes (pan or zoom) rebuild outlines using the current grid.
        .onChange(of: currentSpan) { _, newSpan in
            if newSpan < 0.15 { rebuildHexOutlines() }
        }
        .onChange(of: centerCoordinate) { _, _ in
            if currentSpan < 0.15 { rebuildHexOutlines() }
        }
    }

    // MARK: - Spatial Grid Builder

    /// Rebuilds the spatial index from scratch whenever `exploredHexes` changes.
    ///
    /// The main thread does one O(n) pass to snapshot h3Index strings, then yields.
    /// H3 centroid computation (the expensive part) runs entirely in a detached task.
    /// When the grid is ready it is assigned back on the main actor, then
    /// `rebuildHexOutlines` is triggered so the map reflects the updated data.
    private func rebuildSpatialGrid(_ hexes: [ExploredHex]) {
        let indices    = hexes.map { $0.h3Index }   // snapshot — just String references, O(n) but cheap
        let bucketSize = Self.gridBucketSize

        spatialGridTask?.cancel()
        spatialGridTask = Task {
            let grid = await Task.detached(priority: .userInitiated) {
                var g = [GridKey: [String]]()
                g.reserveCapacity(max(1, indices.count / 50))
                for h3Index in indices {
                    guard let c = H3Wrapper.cellCenter(h3Index: h3Index) else { continue }
                    let key = GridKey(lat: Int(floor(c.latitude  / bucketSize)),
                                     lon: Int(floor(c.longitude / bucketSize)))
                    g[key, default: []].append(h3Index)
                }
                return g
            }.value
            guard !Task.isCancelled else { return }
            spatialGrid = grid
            if currentSpan < 0.15 { rebuildHexOutlines() }
            print("🗺️ Spatial grid: \(grid.values.reduce(0) { $0 + $1.count }) hexes in \(grid.count) buckets")
        }
    }

    // MARK: - Outline Builder

    /// Queries the spatial grid for the current viewport and merges hex outlines off the main thread.
    ///
    /// Main-thread work per call:
    ///   • CoW copy of spatialGrid — O(1), no allocation if not mutated
    ///   • Estimate visible count via bucket sizes — O(~36) integer additions
    ///   • Launch/cancel Task — O(1)
    ///
    /// All remaining work (grid lookup + HexMerger) runs in a detached task.
    private func rebuildHexOutlines() {
        guard let center = centerCoordinate else { return }

        // Snapshot all values needed by the detached task on the main actor.
        let span       = currentSpan
        let grid       = spatialGrid    // CoW: O(1) — shared read-only storage, no copy until mutation
        let centerLat  = center.latitude
        let centerLon  = center.longitude
        let bucketSize = Self.gridBucketSize

        // Estimate visible hex count from bucket sizes — O(buckets in viewport) ≈ O(36).
        // Used to tune debounce: close zoom → small set → fast update;
        // wider zoom → larger set → let previous result stay visible while new one renders.
        let approxCount: Int = {
            let buf = span * 2.0
            let minLatB = Int(floor((centerLat - buf) / bucketSize))
            let maxLatB = Int(floor((centerLat + buf) / bucketSize))
            let minLonB = Int(floor((centerLon - buf) / bucketSize))
            let maxLonB = Int(floor((centerLon + buf) / bucketSize))
            var n = 0
            for lb in minLatB...maxLatB {
                for lo in minLonB...maxLonB { n += grid[GridKey(lat: lb, lon: lo)]?.count ?? 0 }
            }
            return n
        }()
        let debounceNs: UInt64 = approxCount < 1_000 ? 200_000_000 : 500_000_000

        hexOutlineTask?.cancel()
        hexOutlineTask = Task {
            do { try await Task.sleep(nanoseconds: debounceNs) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                // Collect h3Index strings from all grid buckets in the buffered viewport.
                // No H3 calls here — the grid already maps spatial position to index strings.
                let buf    = span * 2.0
                let minLatB = Int(floor((centerLat - buf) / bucketSize))
                let maxLatB = Int(floor((centerLat + buf) / bucketSize))
                let minLonB = Int(floor((centerLon - buf) / bucketSize))
                let maxLonB = Int(floor((centerLon + buf) / bucketSize))
                var indices: [String] = []
                for lb in minLatB...maxLatB {
                    for lo in minLonB...maxLonB {
                        if let hexes = grid[GridKey(lat: lb, lon: lo)] {
                            indices.append(contentsOf: hexes)
                        }
                    }
                }
                return HexMerger.mergeHexOutlines(indices)
            }.value
            guard !Task.isCancelled else { return }
            hexOutlines = result
            print("📐 Hex outlines: \(result.count) rings, ~\(approxCount) hexes (span \(String(format: "%.3f", span)))")
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

        var totalPerCanton = [String: Int]()
        for (_, meta) in RegionMetadataManager.shared.municipalities {
            totalPerCanton[meta.cantonID, default: 0] += 1
        }

        var pct = [String: Double]()
        for (cantonID, visitedCount) in visitedPerCanton {
            pct[cantonID] = Double(visitedCount) / Double(totalPerCanton[cantonID] ?? 1)
        }

        cachedCantonIDs       = cantonIDs
        cachedMunicipalityIDs = muniIDs
        regionLookup          = lookup
        cantonExplorationPct  = pct
    }

    // MARK: - Region Colour

    /// Orange fill whose opacity scales with the municipality's hex exploration %.
    /// Floor 0.15 keeps barely-visited municipalities visible; ceiling 0.6 avoids solid blobs.
    private func colorForRegion(_ id: String) -> AnyShapeStyle {
        guard let region = regionLookup[id] else { return AnyShapeStyle(.clear) }
        let opacity = max(0.15, (region.explorationPercentage / 100.0) * 0.6)
        return AnyShapeStyle(.orange.opacity(opacity))
    }

    /// Same floor/ceiling as colorForRegion — canton opacity ∝ fraction of municipalities visited.
    private func colorForCanton(_ id: String) -> AnyShapeStyle {
        let opacity = max(0.15, (cantonExplorationPct[id] ?? 0.0) * 0.6)
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
