//
//  Achievement.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 08.02.2026.
//


import Foundation
import SwiftUI

struct Achievement: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    // The condition to unlock. Inputs: (hexCount, cityCount)
    let criteria: (Int, Int) -> Bool
}

// Static definition of all available achievements
struct AchievementLibrary {
    static let all: [Achievement] = [
        Achievement(
            title: "First Steps",
            description: "Explore your very first hex",
            icon: "shoeprints.fill",
            color: .blue,
            criteria: { hexes, _ in hexes >= 1 }
        ),
        Achievement(
            title: "Neighborhood Watch",
            description: "Explore 50 hexes",
            icon: "figure.walk",
            color: .green,
            criteria: { hexes, _ in hexes >= 50 }
        ),
        Achievement(
            title: "Urban Legend",
            description: "Explore 500 hexes",
            icon: "building.2.crop.circle.fill",
            color: .purple,
            criteria: { hexes, _ in hexes >= 500 }
        ),
        Achievement(
            title: "City Slicker",
            description: "Visit your first city",
            icon: "map.fill",
            color: .orange,
            criteria: { _, cities in cities >= 1 }
        ),
        Achievement(
            title: "Globetrotter",
            description: "Visit 3 different cities",
            icon: "globe.americas.fill",
            color: .red,
            criteria: { _, cities in cities >= 3 }
        )
    ]
    
    // Helper to calculate unlocked status
    static func getUnlocked(hexCount: Int, cityCount: Int) -> [Achievement] {
        return all.filter { $0.criteria(hexCount, cityCount) }
    }
}