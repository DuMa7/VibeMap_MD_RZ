import Foundation
import CoreLocation
import h3lib

struct H3Wrapper {

    // Pre-calculated constants to avoid repeated division in hot paths
    private static let toRad = Double.pi / 180.0
    private static let toDeg = 180.0 / Double.pi

    // MARK: - Core Raw API (Fast Path)
    // Use these when possible to avoid String conversion overhead.
    // Only convert to String at the persistence boundary (e.g. SwiftData).

    /// Converts a coordinate to a raw H3Index (UInt64). Returns nil on failure.
    /// This is the zero-allocation fast path — prefer this over getH3Index
    /// when you don't immediately need a String.
    static func getRawIndex(
        from coordinate: CLLocationCoordinate2D,
        resolution: Int32 = 10
    ) -> H3Index? {
        var g = LatLng(
            lat: coordinate.latitude * toRad,
            lng: coordinate.longitude * toRad
        )
        var index: H3Index = 0
        let error = latLngToCell(&g, resolution, &index)
        // Always propagate the H3 error code rather than relying on index == 0,
        // which is an implementation detail rather than a guaranteed API contract.
        guard error == E_SUCCESS else { return nil }
        return index
    }

    /// Converts a raw H3Index to its parent at the given resolution. Returns nil on failure.
    static func cellToParent(index: H3Index, parentRes: Int32) -> H3Index? {
        var parentIndex: H3Index = 0
        let error = h3lib.cellToParent(index, parentRes, &parentIndex)
        guard error == 0 else { return nil }
        return parentIndex
    }

    /// Returns the boundary vertices for a raw H3Index.
    static func getVertices(for index: H3Index) -> [CLLocationCoordinate2D] {
        var boundary = CellBoundary()
        cellToBoundary(index, &boundary)

        let count = Int(boundary.numVerts)
        guard count > 0 else { return [] }

        // Allocate with exact capacity (no resizing) and bind memory once outside the loop.
        return Array(unsafeUninitializedCapacity: count) { buffer, initializedCount in
            withUnsafeBytes(of: boundary.verts) { rawPtr in
                let latLngs = rawPtr.bindMemory(to: LatLng.self)
                for i in 0..<count {
                    let vertex = latLngs[i]
                    buffer[i] = CLLocationCoordinate2D(
                        latitude: vertex.lat * toDeg,
                        longitude: vertex.lng * toDeg
                    )
                }
            }
            initializedCount = count
        }
    }

    // MARK: - String API (Persistence / Display boundary)
    // Use these at the SwiftData / UI layer where Strings are required.

    /// Converts a coordinate into an H3 hex string.
    static func getH3Index(
        from coordinate: CLLocationCoordinate2D,
        resolution: Int32 = 10
    ) -> String? {
        guard let index = getRawIndex(from: coordinate, resolution: resolution) else {
            return nil
        }
        return String(index, radix: 16)
    }

    /// Returns boundary vertices for a hex string.
    static func getVertices(for h3String: String) -> [CLLocationCoordinate2D] {
        guard let index = UInt64(h3String, radix: 16) else { return [] }
        return getVertices(for: index)
    }

    /// Converts a hex string to its parent hex string at the given resolution.
    static func cellToParent(h3Index: String, parentRes: Int32) -> String? {
        guard let index = UInt64(h3Index, radix: 16) else { return nil }
        guard let parent = cellToParent(index: index, parentRes: parentRes) else { return nil }
        return String(parent, radix: 16)
    }

    // MARK: - Polygon Merging

    /// Merges a set of H3 hex indices into their combined outline polygons using the
    /// half-edge boundary algorithm.
    ///
    /// For each hex, all 6 directed edges (A→B in vertex winding order) are collected.
    /// An edge is on the outer boundary if and only if its reverse (B→A) does not appear
    /// in any neighbouring hex. Walking those boundary edges forms closed outline rings.
    ///
    /// Result: one ring per contiguous cluster of hexes (plus any interior holes).
    /// Reduces N individual MapPolygon views to a handful of merged boundaries.
    static func mergeHexOutlines(_ h3Indices: [String]) -> [[CLLocationCoordinate2D]] {
        guard !h3Indices.isEmpty else { return [] }

        struct DirectedEdge: Hashable {
            let from: CoordKey
            let to: CoordKey
        }

        // Build the full directed-edge set for every hex.
        var edgeSet = Set<DirectedEdge>(minimumCapacity: h3Indices.count * 7)
        for h3Index in h3Indices {
            let verts = getVertices(for: h3Index)
            guard verts.count >= 3 else { continue }
            for i in 0..<verts.count {
                edgeSet.insert(DirectedEdge(
                    from: CoordKey(verts[i]),
                    to:   CoordKey(verts[(i + 1) % verts.count])
                ))
            }
        }

        // Boundary: A→B is on the outline iff B→A is absent.
        // Shared (interior) edges appear in both directions and cancel.
        var adjacency = [CoordKey: CoordKey](minimumCapacity: edgeSet.count / 3)
        for edge in edgeSet where !edgeSet.contains(DirectedEdge(from: edge.to, to: edge.from)) {
            adjacency[edge.from] = edge.to
        }

        // Walk each chain of boundary edges into a closed ring.
        var rings: [[CLLocationCoordinate2D]] = []
        var visited = Set<CoordKey>(minimumCapacity: adjacency.count)
        for start in adjacency.keys where !visited.contains(start) {
            var ring: [CLLocationCoordinate2D] = []
            var cur = start
            while !visited.contains(cur), let next = adjacency[cur] {
                visited.insert(cur)
                ring.append(cur.coordinate)
                cur = next
            }
            if ring.count >= 3 { rings.append(ring) }
        }

        return rings
    }
}

// MARK: - CoordKey

/// Hashable coordinate wrapper. Rounds to 7 decimal places (~1 cm) to safely
/// compare H3 boundary vertices across independently-computed adjacent cells.
struct CoordKey: Hashable {
    let lat: Int64
    let lon: Int64

    init(_ c: CLLocationCoordinate2D) {
        lat = Int64((c.latitude  * 1e7).rounded())
        lon = Int64((c.longitude * 1e7).rounded())
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: Double(lat) / 1e7, longitude: Double(lon) / 1e7)
    }
}
