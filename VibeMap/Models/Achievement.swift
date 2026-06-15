import Foundation
import SwiftUI

struct Achievement: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    // Closure over an enum-based approach: criteria can freely mix hexCount and cityCount,
    // and future achievements with compound conditions (e.g. "50 hexes AND 3 cities") require
    // no additional cases or switch boilerplate.
    // Inputs are always (totalHexCount, visitedMunicipalityCount).
    let criteria: (Int, Int) -> Bool
}

// Achievement.id is a new UUID on every launch, so persistence uses title strings
// (see ContentView.unlockedAchievementTitles). Titles must remain stable across releases —
// renaming an achievement here will cause it to re-trigger for existing users.
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
            title: "Swiss Clockwork",
            description: "Meticulously explore 2,000 hexes",
            icon: "gearshape.fill",
            color: .gray,
            criteria: { hexes, _ in hexes >= 2000 }
        ),
        Achievement(
            title: "City Slicker",
            description: "Visit your first municipality",
            icon: "map.fill",
            color: .orange,
            criteria: { _, cities in cities >= 1 }
        ),
        Achievement(
            title: "Globetrotter",
            description: "Visit 3 different municipalities",
            icon: "globe.americas.fill",
            color: .red,
            criteria: { _, cities in cities >= 3 }
        ),
        Achievement(
            title: "Canton Hopper",
            description: "Visit 10 different municipalities",
            icon: "train.side.front.car",
            color: .teal,
            criteria: { _, cities in cities >= 10 }
        )
    ]
    
    // Helper to calculate unlocked status
    static func getUnlocked(hexCount: Int, cityCount: Int) -> [Achievement] {
        return all.filter { $0.criteria(hexCount, cityCount) }
    }
}

// MARK: - Visual Component
struct AchievementRow: View {
    let achievement: Achievement
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: achievement.icon)
                .font(.title2)
                .foregroundStyle(achievement.color)
                .frame(width: 48, height: 48)
                .background(achievement.color.opacity(0.2))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(achievement.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(achievement.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
