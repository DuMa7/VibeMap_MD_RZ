import SwiftUI

// MARK: - Data

struct CantonStat: Identifiable {
    let id: String
    let name: String
    let abbreviation: String
    let visitedMunicipalities: Int
    let totalMunicipalities: Int
    let firstVisited: Date?

    var isVisited: Bool { visitedMunicipalities > 0 }
    var percentage: Double {
        guard totalMunicipalities > 0 else { return 0 }
        return Double(visitedMunicipalities) / Double(totalMunicipalities)
    }
}

// MARK: - Passport View

struct PassportView: View {
    let regions: [RegionExploration]
    let cantons: [GeoRegion]

    @Environment(\.dismiss) private var dismiss

    // Swiss Federal canton numbers (KTNR) → ISO abbreviation
    private static let abbreviations: [String: String] = [
        "1": "ZH", "2": "BE",  "3": "LU",  "4": "UR",  "5": "SZ",
        "6": "OW", "7": "NW",  "8": "GL",  "9": "ZG",  "10": "FR",
        "11": "SO", "12": "BS", "13": "BL", "14": "SH", "15": "AR",
        "16": "AI", "17": "SG", "18": "GR", "19": "AG", "20": "TG",
        "21": "TI", "22": "VD", "23": "VS", "24": "NE", "25": "GE",
        "26": "JU"
    ]

    private var stats: [CantonStat] {
        let allMunis = RegionMetadataManager.shared.municipalities

        var totalPerCanton  = [String: Int]()
        for (_, meta) in allMunis {
            totalPerCanton[meta.cantonID, default: 0] += 1
        }

        var visitedPerCanton      = [String: Int]()
        var firstVisitedPerCanton = [String: Date]()
        for region in regions {
            guard let meta = allMunis[region.regionID] else { continue }
            let cid = meta.cantonID
            visitedPerCanton[cid, default: 0] += 1
            let date = region.firstVisited
            if let existing = firstVisitedPerCanton[cid] {
                if date < existing { firstVisitedPerCanton[cid] = date }
            } else {
                firstVisitedPerCanton[cid] = date
            }
        }

        return cantons.map { canton in
            CantonStat(
                id: canton.id,
                name: canton.name,
                abbreviation: Self.abbreviations[canton.id] ?? "??",
                visitedMunicipalities: visitedPerCanton[canton.id] ?? 0,
                totalMunicipalities: totalPerCanton[canton.id] ?? 0,
                firstVisited: firstVisitedPerCanton[canton.id]
            )
        }
        .sorted { a, b in
            if a.isVisited != b.isVisited { return a.isVisited }
            if a.isVisited {
                return (a.firstVisited ?? .distantFuture) < (b.firstVisited ?? .distantFuture)
            }
            return a.name < b.name
        }
    }

    private var visitedCount: Int { stats.filter(\.isVisited).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(stats) { CantonCard(stat: $0) }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .navigationTitle("Canton Passport")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(visitedCount)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(.orange)
                Text("of 26 cantons")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("explored")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(.gray.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(visitedCount) / 26.0)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6), value: visitedCount)
                Text("\(Int((Double(visitedCount) / 26.0) * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }
            .frame(width: 88, height: 88)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.orange.opacity(0.06))
        .cornerRadius(20)
        .padding(.horizontal)
    }
}

// MARK: - Canton Card

private struct CantonCard: View {
    let stat: CantonStat

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(
                        stat.isVisited ? Color.orange : Color.gray.opacity(0.25),
                        lineWidth: 2.5
                    )
                    .frame(width: 64, height: 64)
                Text(stat.abbreviation)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(stat.isVisited ? .orange : Color.gray.opacity(0.3))
            }

            Text(stat.name)
                .font(.caption).bold()
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(stat.isVisited ? .primary : Color.gray.opacity(0.45))

            if stat.isVisited {
                Text("\(stat.visitedMunicipalities) / \(stat.totalMunicipalities) towns")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.gray.opacity(0.2))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.orange)
                            .frame(width: geo.size.width * CGFloat(min(stat.percentage, 1)), height: 4)
                    }
                }
                .frame(height: 4)

                if let date = stat.firstVisited {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundStyle(.orange.opacity(0.85))
                }
            } else {
                Text("\(stat.totalMunicipalities) towns")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary.opacity(0.5))
                Text("Not yet visited")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary.opacity(0.35))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(stat.isVisited ? Color.orange.opacity(0.06) : Color.gray.opacity(0.04))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    stat.isVisited ? Color.orange.opacity(0.2) : Color.gray.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}
