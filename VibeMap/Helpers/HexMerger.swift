import Foundation
import CoreLocation

/// Merges sets of H3 hex indices into combined outline polygons using the
/// half-edge boundary algorithm, then groups the resulting rings into clusters
/// of (outer boundary + interior holes).
///
/// For each hex, all 6 directed edges (A→B in vertex winding order) are collected.
/// An edge is on the outer boundary if and only if its reverse (B→A) does not appear
/// in any neighbouring hex. Walking those boundary edges forms closed rings —
/// one per contiguous cluster, plus one per interior hole (a skipped cell inside
/// a walked area).
///
/// Grouping holes back onto their containing outer lets the map render each cluster
/// as a single polygon with even-odd interior holes. That keeps the fill opacity
/// uniform: without it, a hole ring filled on top of the body fill doubles the
/// opacity, which is why densely-walked areas used to read as darker blobs.
///
/// Pure stateless geometry — explicitly nonisolated so the map pipeline can
/// run it inside detached tasks (the project's default isolation is MainActor).
nonisolated enum HexMerger {

    /// One renderable cluster: a filled outer boundary plus any interior holes.
    /// `Sendable` so it can be returned from the detached merge task.
    struct HexCluster: Sendable {
        let outer: [CLLocationCoordinate2D]
        let holes: [[CLLocationCoordinate2D]]
    }

    static func mergeHexOutlines(_ h3Indices: [String]) -> [HexCluster] {
        guard !h3Indices.isEmpty else { return [] }

        // Each hex contributes 6 directed edges; ×7 leaves headroom for H3's shared-boundary topology.
        var edgeSet = Set<DirectedEdge>(minimumCapacity: h3Indices.count * 7)
        for h3Index in h3Indices {
            let verts = H3Wrapper.getVertices(for: h3Index)
            guard verts.count >= 3 else { continue }
            for i in 0..<verts.count {
                edgeSet.insert(DirectedEdge(
                    from: CoordKey(verts[i]),
                    to:   CoordKey(verts[(i + 1) % verts.count])
                ))
            }
        }

        // Boundary edges are those with no matching reverse edge — interior shared edges cancel out.
        // The adjacency dict maps each boundary vertex to the next one in winding order.
        var adjacency = [CoordKey: CoordKey](minimumCapacity: edgeSet.count / 3)
        for edge in edgeSet where !edgeSet.contains(DirectedEdge(from: edge.to, to: edge.from)) {
            adjacency[edge.from] = edge.to
        }

        // Walk every unvisited start node to completion. Each walk produces one closed ring.
        // Multiple rings arise from non-contiguous clusters or interior holes.
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

        return groupRings(rings)
    }

    // MARK: - Ring grouping (outer + holes)

    /// Groups a flat list of rings into clusters using containment parity, which is
    /// independent of winding order (H3's boundary winding is not assumed):
    ///   • A ring contained in an EVEN number of other rings is a solid body (outer):
    ///     depth 0 = a top-level cluster, depth 2 = an island inside a hole, etc.
    ///   • A ring contained in an ODD number is a hole; its parent is the deepest
    ///     (smallest) ring that contains it.
    /// Each hole is attached to its parent outer so the renderer can punch it out
    /// with an even-odd fill.
    private static func groupRings(_ rings: [[CLLocationCoordinate2D]]) -> [HexCluster] {
        let n = rings.count
        guard n > 0 else { return [] }

        // containers[i] = indices of rings that contain ring i's representative point.
        var containers = [[Int]](repeating: [], count: n)
        for i in 0..<n {
            let p = rings[i][0]
            for j in 0..<n where j != i && contains(rings[j], p) {
                containers[i].append(j)
            }
        }

        var clusters: [HexCluster] = []
        for i in 0..<n where containers[i].count % 2 == 0 {        // even depth → outer body
            // Holes whose immediate (deepest) container is this outer.
            let holes = (0..<n)
                .filter { containers[$0].count % 2 == 1 }
                .filter { h in
                    containers[h].max(by: { containers[$0].count < containers[$1].count }) == i
                }
                .map { rings[$0] }
            clusters.append(HexCluster(outer: rings[i], holes: holes))
        }
        return clusters
    }

    /// Ray-casting point-in-polygon test (longitude = x, latitude = y).
    private static func contains(_ ring: [CLLocationCoordinate2D], _ p: CLLocationCoordinate2D) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let yi = ring[i].latitude,  xi = ring[i].longitude
            let yj = ring[j].latitude,  xj = ring[j].longitude
            if (yi > p.latitude) != (yj > p.latitude),
               p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

// MARK: - DirectedEdge / CoordKey

/// Directed edge (A→B in vertex winding order) between two rounded coordinates.
/// File-scope and nonisolated (rather than function-local) so its synthesized
/// Hashable conformance is usable from the nonisolated merge pipeline.
private nonisolated struct DirectedEdge: Hashable {
    let from: CoordKey
    let to: CoordKey
}

/// Hashable coordinate wrapper. Rounds to 7 decimal places (~1 cm) to safely
/// compare H3 boundary vertices across independently-computed adjacent cells.
nonisolated struct CoordKey: Hashable {
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
