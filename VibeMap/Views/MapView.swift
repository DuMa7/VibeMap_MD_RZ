import SwiftUI
import MapKit

struct MapView: View {
    @Binding var position: MapCameraPosition
    @Binding var currentSpan: Double
    @Binding var centerCoordinate: CLLocationCoordinate2D?

    /// Merged outline polygons for all explored hexes — rebuilt asynchronously when hexes change.
    /// Replaces N individual MapPolygon views with a handful of cluster outlines.
    @State private var hexOutlines: [[CLLocationCoordinate2D]] = []

    /// Merged outline polygons for res-9 hexes only — used at intermediate zoom levels.
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
    }

    // MARK: - Outline Builder

    /// Merges all explored hexes into cluster outlines off the main thread.
    /// O(N) in hex count. Two separate merges: all hexes + res-9 only.
    private func rebuildOutlines(_ hexes: [ExploredHex]) {
        // Extract Strings (Sendable) before the detached task — ExploredHex is a
        // SwiftData @Model class and cannot be safely captured in a @Sendable closure.
        let allIndices  = hexes.map { $0.h3Index }
        let res9Indices = hexes.filter { $0.resolution == 9 }.map { $0.h3Index }

        outlineTask?.cancel()
        outlineTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 s debounce
            } catch {
                return // cancelled before debounce elapsed
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
            print("📐 Merged outlines: \(hexOutlines.count) rings from \(allIndices.count) hexes")
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

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
