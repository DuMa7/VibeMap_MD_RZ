import SwiftUI

struct SessionSummaryView: View {
    let summary: SessionSummary
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    statsRow
                    if !summary.newRegionNames.isEmpty {
                        newRegionsSection
                    }
                    motivationalMessage
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle("Session Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.checkered.2.crossed")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text(summaryHeadline)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var statsRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                statCard(
                    value: "\(summary.newHexCount)",
                    label: summary.newHexCount == 1 ? "New hex" : "New hexes",
                    icon: "hexagon.fill",
                    color: .blue
                )
                statCard(
                    value: "\(summary.newRegionCount)",
                    label: summary.newRegionCount == 1 ? "New area" : "New areas",
                    icon: "map.fill",
                    color: .orange
                )
                statCard(
                    value: formattedDuration,
                    label: "Duration",
                    icon: "clock.fill",
                    color: .purple
                )
            }
            if summary.currentStreak > 0 {
                streakBanner
            }
        }
    }

    private var streakBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
            Text(summary.currentStreak == 1
                 ? "Day 1 streak — keep it going tomorrow!"
                 : "\(summary.currentStreak)-day streak! 🔥")
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var newRegionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("New areas discovered", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.primary)
            VStack(spacing: 0) {
                ForEach(summary.newRegionNames, id: \.self) { name in
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(name)
                            .font(.body)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    if name != summary.newRegionNames.last {
                        Divider().padding(.leading, 40)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var motivationalMessage: some View {
        Text(motivationalText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    // MARK: - Helpers

    private var summaryHeadline: String {
        switch (summary.newHexCount, summary.newRegionCount) {
        case (0, 0):
            return "No new territory this time"
        case (let h, 0):
            return "You mapped \(h) new \(h == 1 ? "hex" : "hexes")!"
        case (0, let r):
            return "You entered \(r) new \(r == 1 ? "area" : "areas")!"
        default:
            return "You discovered \(summary.newHexCount) new \(summary.newHexCount == 1 ? "hex" : "hexes") and entered \(summary.newRegionCount) new \(summary.newRegionCount == 1 ? "area" : "areas")!"
        }
    }

    private var motivationalText: String {
        switch summary.newHexCount {
        case 0:
            return "Familiar ground. Try a new route next time."
        case 1...10:
            return "Every hex counts. Keep exploring!"
        case 11...50:
            return "Solid session. Switzerland is getting smaller."
        case 51...200:
            return "You covered serious ground today!"
        default:
            return "Epic session. The map remembers every step."
        }
    }

    private var formattedDuration: String {
        let total = Int(summary.duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
}

#Preview {
    SessionSummaryView(
        summary: SessionSummary(
            duration: 3720,
            newHexCount: 42,
            newRegionNames: ["Bern", "Köniz", "Ostermundigen"],
            currentStreak: 5
        ),
        onDismiss: {}
    )
}
