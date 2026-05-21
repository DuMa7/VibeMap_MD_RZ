import Foundation
import CoreLocation

/// Merges sets of H3 hex indices into their combined outline polygons using the
/// half-edge boundary algorithm.
///
/// For each hex, all 6 directed edges (A→B in vertex winding order) are collected.
/// An edge is on the outer boundary if and only if its reverse (B→A) does not appear
/// in any neighbouring hex. Walking those boundary edges forms closed outline rings.
///
/// Result: one ring per contiguous cluster of hexes (plus any interior holes).
/// Reduces N individual MapPolygon views to a handful of merged boundaries.
enum HexMerger {
    static func mergeHexOutlines(_ h3Indices: [String]) -> [[CLLocationCoordinate2D]] {
        guard !h3Indices.isEmpty else { return [] }

        struct DirectedEdge: Hashable {
            let from: CoordKey
            let to: CoordKey
        }

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

        // Boundary: A→B is on the outline iff B→A is absent.
        var adjacency = [CoordKey: CoordKey](minimumCapacity: edgeSet.count / 3)
        for edge in edgeSet where !edgeSet.contains(DirectedEdge(from: edge.to, to: edge.from)) {
            adjacency[edge.from] = edge.to
        }

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
