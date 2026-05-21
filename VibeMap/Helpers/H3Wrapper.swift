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

}

