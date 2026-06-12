import Foundation
import CoreLocation
import H3

/// Pure stateless wrappers around the H3 package. Explicitly nonisolated so the
/// recording, import, and map pipelines can call them inside detached tasks
/// (the project's default actor isolation is MainActor).
nonisolated struct H3Wrapper {

    static func getVertices(for index: UInt64) -> [CLLocationCoordinate2D] {
        do {
            return try cellToBoundary(cell: index)
        } catch {
            return []
        }
    }

    static func getVertices(for h3String: String) -> [CLLocationCoordinate2D] {
        guard let index = UInt64(h3String, radix: 16) else { return [] }
        return getVertices(for: index)
    }

    /// Returns the res-`childRes` child cell whose centroid is closest to the parent's centroid.
    /// Used by the res-9 → res-10 migration to pick a single representative child for each
    /// legacy res-9 record. The mapping is deterministic and requires no original GPS data.
    static func cellToCenterChild(h3Index: String, childRes: Int32) -> String? {
        guard let index = UInt64(h3Index, radix: 16) else { return nil }
        do {
            let child = try H3.cellToCenterChild(cell: index, childResolution: Int(childRes))
            return String(child, radix: 16)
        } catch {
            return nil
        }
    }

    /// Returns the geographic centroid of an H3 cell by averaging its boundary vertices.
    /// For a convex hexagon the centroid equals the vertex average exactly, so no approximation
    /// is needed. Used for viewport filtering before passing indices to HexMerger.
    static func cellCenter(h3Index: String) -> CLLocationCoordinate2D? {
        let verts = getVertices(for: h3Index)
        guard !verts.isEmpty else { return nil }
        return CLLocationCoordinate2D(
            latitude:  verts.map { $0.latitude  }.reduce(0, +) / Double(verts.count),
            longitude: verts.map { $0.longitude }.reduce(0, +) / Double(verts.count)
        )
    }
}
