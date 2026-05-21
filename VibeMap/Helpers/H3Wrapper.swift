import Foundation
import CoreLocation
import H3

struct H3Wrapper {

    static func getRawIndex(
        from coordinate: CLLocationCoordinate2D,
        resolution: Int32 = 10
    ) -> UInt64? {
        do {
            return try latLngToCell(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                resolution: Int(resolution)
            )
        } catch {
            return nil
        }
    }

    static func cellToParent(index: UInt64, parentRes: Int32) -> UInt64? {
        do {
            return try H3.cellToParent(
                cell: index,
                resolution: Int(parentRes)
            )
        } catch {
            return nil
        }
    }

    static func getVertices(for index: UInt64) -> [CLLocationCoordinate2D] {
        do {
            return try cellToBoundary(cell: index)
        } catch {
            return []
        }
    }

    static func getH3Index(
        from coordinate: CLLocationCoordinate2D,
        resolution: Int32 = 10
    ) -> String? {
        guard let index = getRawIndex(from: coordinate, resolution: resolution) else {
            return nil
        }
        return String(index, radix: 16)
    }

    static func getVertices(for h3String: String) -> [CLLocationCoordinate2D] {
        guard let index = UInt64(h3String, radix: 16) else { return [] }
        return getVertices(for: index)
    }

    static func cellToParent(h3Index: String, parentRes: Int32) -> String? {
        guard let index = UInt64(h3Index, radix: 16) else { return nil }
        guard let parent = cellToParent(index: index, parentRes: parentRes) else { return nil }
        return String(parent, radix: 16)
    }
}
