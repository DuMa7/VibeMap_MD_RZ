//
//  H3Wrapper.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 07.02.2026.
//


import Foundation
import CoreLocation
import h3lib // Import the C library

struct H3Wrapper {
    
    /// Converts a standard coordinate into an H3 Hexagon String
    static func getH3Index(from coordinate: CLLocationCoordinate2D, resolution: Int32 = 10) -> String? {
        // 1. Convert Lat/Lon to Radians (required by H3)
        let latRad = coordinate.latitude * .pi / 180.0
        let lonRad = coordinate.longitude * .pi / 180.0
        var g = LatLng(lat: latRad, lng: lonRad)
        
        // 2. Generate the H3 Index (UInt64)
        var index: H3Index = 0
        let error = latLngToCell(&g, resolution, &index)
        
        guard error == E_SUCCESS else { return nil }
        
        // 3. Convert UInt64 to a readable Hexadecimal String
        var charBuffer = [CChar](repeating: 0, count: 17)
        h3ToString(index, &charBuffer, 17)
        
        return String(cString: charBuffer)
    }
    
    /// Returns the points needed to draw the hexagon on a map
    static func getVertices(for h3String: String) -> [CLLocationCoordinate2D] {
        var index: H3Index = 0
        stringToH3(h3String, &index)
        
        var boundary = CellBoundary()
        cellToBoundary(index, &boundary)
        
        var coords: [CLLocationCoordinate2D] = []
        
        // Accessing C-arrays in Swift requires 'withUnsafePointer'
        // because they are imported as fixed-size tuples.
        for i in 0..<Int(boundary.numVerts) {
            let vertex = withUnsafePointer(to: boundary.verts) { ptr in
                ptr.withMemoryRebound(to: LatLng.self, capacity: Int(boundary.numVerts)) { latLngs in
                    latLngs[i]
                }
            }
            coords.append(CLLocationCoordinate2D(
                latitude: vertex.lat * 180.0 / .pi,
                longitude: vertex.lng * 180.0 / .pi
            ))
        }
        return coords
    }
}
    
