import SwiftUI
import MapKit

struct MapView: View {
    @Binding var position: MapCameraPosition
    @Binding var currentSpan: Double
    @Binding var centerCoordinate: CLLocationCoordinate2D?

    @State private var mapStyle: MapStyle = .standard

    /// Merged outline polygons for all explored hexes — rebuilt asynchronously when hexes change.
    /// Replaces N individual MapPolygon views with a handful of cluster outlines.
    @State private var hexOutlines: [[CLLocationCoordinate2D]] = []

    /// Merged outline polygons for res-9 hexes only — used at intermediate zoom levels.
    @State private var res9Outlines: [[CLLocationCoordinate2D]] = []

    /// Canton IDs of all visited regions — cached to avoid recomputing on every render pass
    @State private var cachedCantonIDs: Set<String> = []

    var exploredHexes: [ExploredHex]
    var regions: [RegionExploration]
    var layerManager: MapLayerManager
    var userLocation: CLLocationCoordinate2D?

    var body: some View {
        Map(position: $position) {
            UserAnnotation()

            if currentSpan >= 10.0 {
                // World level — no overlays
            } else if currentSpan >= 2.0 {
                ForEach(layerManager.cantons.filter { cachedCantonIDs.contains($0.id) }) { canton in
                    ForEach(0..<canton.polygons.count, id: \.self) { i in
                        MapPolygon(coordinates: canton.polygons[i])
                            .foregroundStyle(.orange.opacity(0.5))
                            .stroke(.white, lineWidth: 1.5)
                    }
                }
            } else if currentSpan >= 0.2 {
                ForEach(layerManager.municipalities.filter { muni in
                    regions.contains(where: { $0.regionID == muni.id })
                }) { muni in
                    ForEach(0..<muni.polygons.count, id: \.self) { i in
                        MapPolygon(coordinates: muni.polygons[i])
                            .foregroundStyle(colorForRegion(muni.id))
                            .stroke(.white.opacity(0.3), lineWidth: 0.5)
                    }
                }
            } else if currentSpan >= 0.02 {
                // Neighbourhood level — res-9 merged outlines (rural/lake areas)
                ForEach(res9Outlines.indices, id: \.self) { i in
                    MapPolygon(coordinates: res9Outlines[i])
                        .foregroundStyle(.orange.opacity(0.4))
                        .stroke(.orange, lineWidth: 1)
                }
            } else {
                // Street level — all hexes as merged outlines
                ForEach(hexOutlines.indices, id: \.self) { i in
                    MapPolygon(coordinates: hexOutlines[i])
                        .foregroundStyle(.orange.opacity(0.4))
                        .stroke(.orange, lineWidth: 1)
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControlVisibility(.hidden)
        .animation(.easeInOut(duration: 0.5), value: currentSpan)
        .onMapCameraChange(frequency: .onEnd) { context in
            currentSpan = context.region.span.latitudeDelta
            centerCoordinate = context.region.center
        }
        .onAppear {
            cachedCantonIDs = buildCantonIDs()
            rebuildOutlines(exploredHexes)
        }
        .onChange(of: exploredHexes) { _, newHexes in
            cachedCantonIDs = buildCantonIDs()
            rebuildOutlines(newHexes)
        }
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button { mapStyle = .standard } label: { Label("Standard", systemImage: "map") }
                Button { mapStyle = .hybrid }  label: { Label("Satellite", systemImage: "globe.americas.fill") }
                Button { mapStyle = .imagery } label: { Label("Imagery", systemImage: "photo") }
            } label: {
                Image(systemName: "map.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.gray.opacity(0.8))
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Outline Builder

    /// Merges all explored hexes into cluster outlines off the main thread.
    /// O(N) in hex count. Two separate merges: all hexes + res-9 only.
    private func rebuildOutlines(_ hexes: [ExploredHex]) {
        Task.detached(priority: .userInitiated) {
            let allIndices  = hexes.map { $0.h3Index }
            let res9Indices = hexes.filter { $0.resolution == 9 }.map { $0.h3Index }

            let all  = H3Wrapper.mergeHexOutlines(allIndices)
            let res9 = H3Wrapper.mergeHexOutlines(res9Indices)

            print("📐 Merged outlines: \(all.count) rings from \(allIndices.count) hexes")

            await MainActor.run {
                hexOutlines  = all
                res9Outlines = res9
            }
        }
    }

    // MARK: - Canton Cache

    private func buildCantonIDs() -> Set<String> {
        Set(regions.compactMap { region in
            RegionMetadataManager.shared.municipalities[region.regionID]?.cantonID
        })
    }

    // MARK: - Region Color

    /// Returns an opacity-scaled orange style for a region based on its exploration percentage.
    /// Regions with 0 totalHexes return clear to avoid division by zero.
    private func colorForRegion(_ id: String) -> AnyShapeStyle {
        guard let region = regions.first(where: { $0.regionID == id }), region.totalHexes > 0 else {
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
