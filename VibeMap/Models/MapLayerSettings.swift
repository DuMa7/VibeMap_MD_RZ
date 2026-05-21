import Foundation
import _MapKit_SwiftUI
import MapKit

enum MapBaseStyle: CaseIterable {
    case standard, hybrid, imagery

    var mapStyle: MapStyle {
        switch self {
        case .standard: return .standard
        case .hybrid:   return .hybrid
        case .imagery:  return .imagery
        }
    }

    var label: String {
        switch self {
        case .standard: return "Map"
        case .hybrid:   return "Satellite"
        case .imagery:  return "Imagery"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "map"
        case .hybrid:   return "globe.americas.fill"
        case .imagery:  return "photo"
        }
    }
}

@Observable
class MapLayerSettings {
    var baseStyle: MapBaseStyle = .standard
    var showExploredHexes: Bool = true
}
