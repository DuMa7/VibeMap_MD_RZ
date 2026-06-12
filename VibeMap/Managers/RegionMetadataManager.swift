import Foundation

class RegionMetadataManager {
    static let shared = RegionMetadataManager()

    /// Maps municipality ID → (name, cantonID).
    /// Populated by MapLayerManager during its single GeoJSON parse pass.
    var municipalities: [String: (name: String, cantonID: String)] = [:]

    private init() {}
}
