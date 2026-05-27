import HealthKit
import CoreLocation
import SwiftData
import H3

// MARK: - Preview / Result types

/// Lightweight summary built from workout metadata only — no GPS route fetching.
/// Handed to the UI so the user can review before confirming the import.
/// Retains the workouts array so importWorkouts(_:) can reuse them without re-querying.
struct GarminSyncPreview {
    let workouts: [HKWorkout]

    var workoutCount: Int { workouts.count }

    var dateRange: (first: Date, last: Date)? {
        guard !workouts.isEmpty else { return nil }
        let dates = workouts.map { $0.startDate }
        return (dates.min()!, dates.max()!)
    }

    /// Sum of all workout durations, in seconds.
    var totalDuration: TimeInterval {
        workouts.reduce(0) { $0 + $1.duration }
    }

    /// Total distance in km across activities that carry distance metadata.
    var totalDistanceKm: Double {
        let meters = workouts
            .compactMap { $0.totalDistance?.doubleValue(for: .meter()) }
            .reduce(0, +)
        return meters / 1000.0
    }
}

struct GarminSyncResult {
    let newHexCount: Int
    let newRegionCount: Int
    let workoutsProcessed: Int
    /// How many of the processed workouts had an HKWorkoutRoute attached.
    /// If this is 0 while workoutsProcessed > 0, Garmin Connect is not syncing
    /// GPS route data to HealthKit — the user needs to export GPX files instead.
    let workoutsWithRoutes: Int
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "HealthKit is not available on this device."
        }
    }
}

// MARK: - HealthKitImporter

/// Reads Garmin Connect workout routes from HealthKit and converts them to ExploredHex records.
///
/// The pipeline mirrors GPXImporter:
///   1. fetchGarminWorkouts  — metadata only, fast, used for the preview step
///   2. importWorkouts       — fetches GPS routes, runs H3 conversion off-thread, batch-inserts
///
/// Incremental sync: the last-imported workout's end date is persisted in UserDefaults under
/// `lastSyncKey`. buildPreview/importWorkouts both accept an optional `since:` date that
/// callers should set to lastSyncDate to avoid re-processing old activities.
///
/// HealthKit setup (done once in Xcode):
///   • Target → Signing & Capabilities → + Capability → HealthKit
///   • Info.plist must contain NSHealthShareUsageDescription
@MainActor
final class HealthKitImporter {
    private let healthStore = HKHealthStore()
    let modelContext: ModelContext

    /// UserDefaults key storing the sync watermark (TimeInterval since 1970).
    static let lastSyncKey = "garminHealthKitLastSyncDate"

    /// The two HealthKit types VibeMap reads. Share access only — VibeMap never writes to Health.
    static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute()
    ]

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// The end date of the last successfully imported batch, or nil if never synced.
    var lastSyncDate: Date? {
        let t = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw HealthKitError.notAvailable }
        // requestAuthorization never throws for a denied response — it silently succeeds and
        // subsequent queries return empty results. The UI must handle the zero-result case.
        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: - Fetch Garmin workouts (metadata only)

    /// Returns all workouts whose source is Garmin Connect, optionally filtered by start date.
    /// Garmin Connect identifies itself with a bundle ID and app name containing "garmin".
    func fetchGarminWorkouts(since date: Date? = nil) async throws -> [HKWorkout] {
        let predicate: NSPredicate? = date.map {
            HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                                    ascending: true)]
            ) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                let garmin = (samples as? [HKWorkout] ?? []).filter { workout in
                    let id   = workout.sourceRevision.source.bundleIdentifier.lowercased()
                    let name = workout.sourceRevision.source.name.lowercased()
                    return id.contains("garmin") || name.contains("garmin")
                }
                continuation.resume(returning: garmin)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Preview (no DB writes)

    /// Builds a preview from workout metadata. Fast — does not query GPS routes.
    func buildPreview(since date: Date? = nil) async throws -> GarminSyncPreview {
        let workouts = try await fetchGarminWorkouts(since: date)
        return GarminSyncPreview(workouts: workouts)
    }

    // MARK: - Import (DB writes)

    /// Fetches GPS routes for the supplied workouts, converts to H3 hexes, and inserts into SwiftData.
    /// Only hexes not already in the database are written. On success, advances the sync watermark.
    ///
    /// If workoutsWithRoutes == 0 in the returned result, Garmin Connect is syncing workout
    /// summaries but not GPS track data to HealthKit. In that case the caller should direct
    /// the user to export GPX files from Garmin Connect instead.
    func importWorkouts(_ workouts: [HKWorkout]) async throws -> GarminSyncResult {
        guard !workouts.isEmpty else {
            return GarminSyncResult(newHexCount: 0, newRegionCount: 0,
                                    workoutsProcessed: 0, workoutsWithRoutes: 0)
        }

        // 1. Collect all CLLocation objects across all workout routes. Count how many workouts
        //    actually have route data so we can surface a useful diagnostic when it's 0.
        var rawLocations: [(coordinate: CLLocationCoordinate2D, date: Date)] = []
        var workoutsWithRoutes = 0
        for workout in workouts {
            let locations = try await fetchLocations(for: workout)
            if !locations.isEmpty {
                workoutsWithRoutes += 1
                for loc in locations {
                    rawLocations.append((loc.coordinate, loc.timestamp))
                }
            }
        }

        // No route data at all — return gracefully so the UI can show a targeted message.
        // This is the expected outcome when Garmin Connect is the source: it writes workout
        // summaries to HealthKit but does not attach HKWorkoutRoute GPS track data.
        guard !rawLocations.isEmpty else {
            print("⚠️ Garmin sync: \(workouts.count) workout(s) found, 0 had GPS route data. " +
                  "Garmin Connect does not sync GPS routes to HealthKit. " +
                  "Export GPX files from Garmin Connect instead.")
            return GarminSyncResult(newHexCount: 0, newRegionCount: 0,
                                    workoutsProcessed: workouts.count, workoutsWithRoutes: 0)
        }

        // 2. Coordinate → H3 conversion off the main thread (CPU-bound).
        //    Mirrors the GPXImporter pipeline exactly: consecutive dedup + set dedup.
        typealias PendingHex = (index: String, resolution: Int, regionID: String, date: Date)
        let pendingHexes: [PendingHex] = await Task.detached(priority: .userInitiated) {
            var result: [PendingHex] = []
            var seenIndices = Set<String>()
            var lastHex: String?

            for item in rawLocations {
                let lat = item.coordinate.latitude  * .pi / 180.0
                let lon = item.coordinate.longitude * .pi / 180.0
                var coord = LatLng(lat: lat, lng: lon)

                var idx10: H3Index = 0
                var idx9:  H3Index = 0
                latLngToCell(&coord, 10, &idx10)
                latLngToCell(&coord, 9,  &idx9)

                let hex10 = String(idx10, radix: 16)
                let hex9  = String(idx9,  radix: 16)

                // swiss_index.sqlite only covers Switzerland — skip coordinates outside it
                guard let regionData = OfflineDatabase.shared.getRegionData(
                    res10: hex10, res9: hex9
                ) else { continue }

                let activeHex = regionData.matchedHex
                // lastHex: consecutive duplicate (dense GPS trace while standing still)
                // seenIndices: non-consecutive revisit within this import batch
                guard activeHex != lastHex, !seenIndices.contains(activeHex) else {
                    lastHex = activeHex
                    continue
                }
                lastHex = activeHex
                seenIndices.insert(activeHex)
                result.append((activeHex, regionData.resolution, regionData.regionID, item.date))
            }
            return result
        }.value

        guard !pendingHexes.isEmpty else {
            return GarminSyncResult(newHexCount: 0, newRegionCount: 0,
                                    workoutsProcessed: workouts.count,
                                    workoutsWithRoutes: workoutsWithRoutes)
        }

        // 3. One batch fetch to find hexes already in SwiftData
        let candidateKeys = pendingHexes.map { $0.index }
        let alreadyExplored: Set<String> = {
            let desc = FetchDescriptor<ExploredHex>(
                predicate: #Predicate { candidateKeys.contains($0.h3Index) }
            )
            return Set((try? modelContext.fetch(desc))?.map { $0.h3Index } ?? [])
        }()

        // 4. Insert new hexes and update/create RegionExploration records.
        //    Per-region cache avoids repeated FetchDescriptor calls for the same region.
        var regionCache    = [String: RegionExploration]()
        var newHexCount    = 0
        var newRegionCount = 0

        for item in pendingHexes where !alreadyExplored.contains(item.index) {
            let hex = ExploredHex(h3Index: item.index, resolution: item.resolution,
                                  regionID: item.regionID)
            hex.firstVisited = item.date
            hex.lastVisited  = item.date
            modelContext.insert(hex)
            newHexCount += 1

            if let cached = regionCache[item.regionID] {
                cached.addExploredHex(item.index)
            } else {
                let rid  = item.regionID
                let desc = FetchDescriptor<RegionExploration>(
                    predicate: #Predicate { $0.regionID == rid }
                )
                if let existing = (try? modelContext.fetch(desc))?.first {
                    existing.addExploredHex(item.index)
                    regionCache[rid] = existing
                } else {
                    let meta   = RegionMetadataManager.shared.municipalities[rid]
                    let region = RegionExploration(
                        regionID: rid,
                        name: meta?.name ?? "Unknown Region",
                        type: "Municipality",
                        totalHexes: OfflineDatabase.shared.getTotalHexes(for: rid)
                    )
                    region.firstVisited = item.date
                    region.lastVisited  = item.date
                    region.addExploredHex(item.index)
                    modelContext.insert(region)
                    regionCache[rid] = region
                    newRegionCount += 1
                }
            }
        }

        try modelContext.save()

        // Advance the watermark so the next sync only fetches newer activities
        if let latestEnd = workouts.map({ $0.endDate }).max() {
            UserDefaults.standard.set(latestEnd.timeIntervalSince1970, forKey: Self.lastSyncKey)
        }

        print("✅ Garmin sync: \(newHexCount) new hexes, \(newRegionCount) new regions " +
              "from \(workoutsWithRoutes)/\(workouts.count) workouts with routes, " +
              "\(rawLocations.count) GPS points")
        return GarminSyncResult(newHexCount: newHexCount, newRegionCount: newRegionCount,
                                workoutsProcessed: workouts.count,
                                workoutsWithRoutes: workoutsWithRoutes)
    }

    // MARK: - Private: GPS route fetching

    /// Loads all CLLocation points across every HKWorkoutRoute attached to a workout.
    private func fetchLocations(for workout: HKWorkout) async throws -> [CLLocation] {
        // Step 1: get the HKWorkoutRoute samples associated with this workout
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKAnchoredObjectQuery(
                type: HKSeriesType.workoutRoute(),
                predicate: predicate,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, error in
                if let error = error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }
            healthStore.execute(query)
        }

        // Step 2: stream the actual CLLocation data from each route
        var all: [CLLocation] = []
        for route in routes {
            let batch = try await locationStream(route: route)
            all.append(contentsOf: batch)
        }
        return all
    }

    /// Collects batched CLLocation callbacks from HKWorkoutRouteQuery until done = true.
    /// The query fires multiple times with chunks of ~500 locations; we accumulate them all.
    private func locationStream(route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var accumulated: [CLLocation] = []
            var resumed = false          // guard against the callback firing after resume

            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error = error {
                    if !resumed { resumed = true; continuation.resume(throwing: error) }
                    return
                }
                accumulated.append(contentsOf: locations ?? [])
                if done, !resumed {
                    resumed = true
                    continuation.resume(returning: accumulated)
                }
            }
            healthStore.execute(query)
        }
    }
}
