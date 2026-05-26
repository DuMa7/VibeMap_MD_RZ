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

    /// Handle for the in-flight debounced outline rebuild — cancelled when a newer change arrives
    @State private var outlineTask: Task<Void, Never>?

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
                                .foregroundStyle(.orange.opacity(0.5))
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
            rebuildOutlines(exploredHexes)
        }
        .onChange(of: exploredHexes) { _, newHexes in
            rebuildOutlines(newHexes)
        }
        .onChange(of: regions) { _, _ in
            rebuildRegionCaches()
        }
        // When the user pans while at street zoom the set of visible hexes changes,
        // so rebuild the outline for the new viewport position.
        .onChange(of: centerCoordinate) { _, _ in
            if currentSpan < 0.02 {
                rebuildOutlines(exploredHexes)
            }
        }
    }

    // MARK: - Outline Builder

    /// Merges explored hexes into cluster outlines off the main thread.
    /// At street zoom the input is restricted to the visible viewport to keep
    /// HexMerger's O(N) work proportional to what's on screen, not the full history.
    private func rebuildOutlines(_ hexes: [ExploredHex]) {
        // At street zoom, cull to the visible viewport before extracting index strings.
        // At wider zooms, pass everything — municipality/canton layers are GeoJSON-driven
        // and don't go through HexMerger, so no culling is needed there.
        let allIndices: [String]
        if currentSpan < 0.02, let center = centerCoordinate {
            allIndices = viewportFilteredIndices(from: hexes, center: center, span: currentSpan)
        } else {
            allIndices = hexes.map { $0.h3Index }
        }

        // res-9 covers a much wider area at mid-zoom; no viewport culling needed since
        // the promoted set is already ~7× smaller than the full res-10 set.
        let res9Indices = Array(Set(hexes.compactMap { hex -> String? in
            if hex.resolution == 9 { return hex.h3Index }
            return H3Wrapper.cellToParent(h3Index: hex.h3Index, parentRes: 9)
        }))

        // Adaptive debounce: after viewport culling, allIndices is small during live
        // exploration at street zoom, so 300 ms feels responsive. The longer debounce
        // protects the CPU when processing a large viewport or the full res-9 set.
        let debounceNs: UInt64 = allIndices.count < 500 ? 300_000_000 : 1_500_000_000

        outlineTask?.cancel()
        outlineTask = Task {
            do {
                try await Task.sleep(nanoseconds: debounceNs)
            } catch {
                return // cancelled before debounce elapsed — a newer change arrived
            }

            async let all  = Task.detached(priority: .userInitiated) {
                HexMerger.mergeHexOutlines(allIndices)
            }.value
            async let res9 = Task.detached(priority: .userInitiated) {
                HexMerger.mergeHexOutlines(res9Indices)
            }.value
            let allResult  = await all
            let res9Result = await res9

            guard !Task.isCancelled else { return }
            hexOutlines  = allResult
            res9Outlines = res9Result
            print("📐 Merged outlines: \(hexOutlines.count) rings from \(allIndices.count) visible hexes (\(hexes.count) total)")
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

    /// Rebuilds all three region-derived caches in one pass over `regions`.
    /// Called on appear and on every regions change — NOT on exploredHexes change,
    /// since canton/municipality membership only changes when a new region is discovered.
    private func rebuildRegionCaches() {
        var cantonIDs    = Set<String>()
        var muniIDs      = Set<String>()
        var lookup       = [String: RegionExploration](minimumCapacity: regions.count)
        for region in regions {
            muniIDs.insert(region.regionID)
            lookup[region.regionID] = region
            if let cantonID = RegionMetadataManager.shared.municipalities[region.regionID]?.cantonID {
                cantonIDs.insert(cantonID)
            }
        }
        cachedCantonIDs      = cantonIDs
        cachedMunicipalityIDs = muniIDs
        regionLookup         = lookup
    }

    // MARK: - Region Color

    /// Returns an opacity-scaled orange style for a region based on its exploration percentage.
    /// Regions with 0 totalHexes return clear to avoid division by zero.
    private func colorForRegion(_ id: String) -> AnyShapeStyle {
        guard let region = regionLookup[id], region.totalHexes > 0 else {
            return AnyShapeStyle(.clear)
        }
        let percentage = Double(region.exploredHexes.count) / Double(region.totalHexes)
        return AnyShapeStyle(.orange.opacity(max(0.15, percentage)))
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
