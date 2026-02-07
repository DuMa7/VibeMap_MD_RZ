//
//  VibeMapApp.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 07.02.2026.
//

import SwiftUI
import SwiftData

@main
struct VibeMapApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [ExploredHex.self, LocationPoint.self, CityExploration.self])
    }
}
