import Foundation
import CoreLocation
import SwiftData
import H3
import UniformTypeIdentifiers

// MARK: - Data Types
// All parse-side types are nonisolated so parsing can run inside detached tasks
// (the project's default actor isolation is MainActor).

nonisolated struct GPXPoint {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date?
}

nonisolated struct GPXFile {
    let name: String?
    let points: [GPXPoint]
}

/// Aggregated summary shown in the import preview sheet (before writing to DB).
nonisolated struct GPXImportSummary {
    let fileCount: Int
    let totalPoints: Int
    let earliestDate: Date?
    let latestDate: Date?
    let trackNames: [String]

    var displayTitle: String {
        if trackNames.isEmpty { return "\(fileCount) file\(fileCount == 1 ? "" : "s")" }
        if trackNames.count == 1 { return trackNames[0] }
        return "\(trackNames.count) tracks"
    }
}

nonisolated struct GPXImportResult {
    let newHexCount: Int
    let newRegionCount: Int
    let processedPoints: Int
}

nonisolated enum GPXImportError: LocalizedError {
    case noTrackPoints

    var errorDescription: String? {
        switch self {
        case .noTrackPoints: return "No track points found in this file."
        }
    }
}

// MARK: - UTType

extension UTType {
    /// GPX track files from Garmin, Strava, Apple Fitness, AllTrails, etc.
    static let gpx: UTType = UTType(filenameExtension: "gpx") ?? .xml
}

// MARK: - GPX Parser

/// SAX-based (streaming) GPX XML parser. Handles trkpt, wpt, rtept elements across
/// multiple tracks and segments. Returns a GPXFile with all extracted points.
///
/// SAX is used instead of a DOM parser to avoid loading the full XML tree into memory —
/// Strava and Garmin exports can contain tens of thousands of track points per file.
nonisolated final class GPXParser: NSObject, XMLParserDelegate {

    private var points: [GPXPoint] = []
    private var trackName: String?

    // Per-element state
    private var pendingLat: Double?
    private var pendingLon: Double?
    private var pendingTime: Date?
    private var characterBuffer = ""
    private var inPointElement = false
    private var capturingTime = false
    private var capturingName = false

    private static let pointTags: Set<String> = ["trkpt", "wpt", "rtept"]

    // Two formatters because GPX producers disagree on fractional seconds:
    // Garmin/AllTrails include them ("2024-01-15T10:30:00.000Z"), older Strava does not.
    // Try the stricter format first; fall back to the lenient one on failure.
    private lazy var isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private lazy var isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func parse(data: Data) -> GPXFile? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return GPXFile(name: trackName, points: points)
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attrs: [String: String] = [:]) {
        characterBuffer = ""

        if Self.pointTags.contains(element) {
            pendingLat = attrs["lat"].flatMap(Double.init)
            pendingLon = attrs["lon"].flatMap(Double.init)
            pendingTime = nil
            inPointElement = true
        }

        capturingTime = (element == "time")
        capturingName = (element == "name")
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingTime || capturingName {
            characterBuffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        if capturingTime {
            let s = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingTime = isoFull.date(from: s) ?? isoBasic.date(from: s)
            capturingTime = false
        }

        if capturingName {
            let s = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty, trackName == nil { trackName = s }
            capturingName = false
        }

        if Self.pointTags.contains(element), inPointElement,
           let lat = pendingLat, let lon = pendingLon {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if CLLocationCoordinate2DIsValid(coord) {
                points.append(GPXPoint(coordinate: coord, timestamp: pendingTime))
            }
            inPointElement = false
        }
    }
}

// MARK: - GPX Importer

@MainActor
final class GPXImporter {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: Parse (no DB writes)

    /// Parses one or more GPX data blobs without touching the database.
    /// Call this first to build the preview summary shown before import.
    nonisolated static func parse(_ dataItems: [(filename: String, data: Data)]) -> [GPXFile] {
        dataItems.compactMap { item in
            let parser = GPXParser()
            guard let file = parser.parse(data: item.data), !file.points.isEmpty else { return nil }
            // Fall back to filename (minus extension) if GPX has no track name
            let name = file.name ?? String(item.filename.prefix(while: { $0 != "." }))
            return GPXFile(name: name, points: file.points)
        }
    }

    static func summarise(_ files: [GPXFile]) -> GPXImportSummary {
        let allPoints = files.flatMap { $0.points }
        let allDates  = allPoints.compactMap { $0.timestamp }
        return GPXImportSummary(
            fileCount:    files.count,
            totalPoints:  allPoints.count,
            earliestDate: allDates.min(),
            latestDate:   allDates.max(),
            trackNames:   files.compactMap { $0.name }
        )
    }

    // MARK: Import (DB writes)

    /// Converts all track points in the supplied GPX files to explored hexes and
    /// inserts them into SwiftData. Skips hexes already in the database.
    func importFiles(_ files: [GPXFile]) async throws -> GPXImportResult {
        let allPoints = files.flatMap { $0.points }
        guard !allPoints.isEmpty else { throw GPXImportError.noTrackPoints }

        // 1. Convert coordinates → (hexIndex, resolution, regionID, timestamp)
        //    off the main thread. Only keeps one entry per hex (first occurrence).
        typealias PendingHex = (index: String, resolution: Int, regionID: String, date: Date?)
        let pendingHexes: [PendingHex] = await Task.detached(priority: .userInitiated) {
            var result: [PendingHex] = []
            var seenIndices = Set<String>()
            var lastHex: String?

            for point in allPoints {
                let lat = point.coordinate.latitude  * .pi / 180.0
                let lon = point.coordinate.longitude * .pi / 180.0
                var coord = LatLng(lat: lat, lng: lon)

                var idx10: H3Index = 0
                var idx9:  H3Index = 0
                latLngToCell(&coord, 10, &idx10)
                latLngToCell(&coord, 9,  &idx9)

                let hex10 = String(idx10, radix: 16)
                let hex9  = String(idx9,  radix: 16)

                guard let regionData = OfflineDatabase.shared.getRegionData(res10: hex10, res9: hex9) else {
                    continue
                }

                // Always use the res-10 index — regionID comes from the DB match
                // (which may have been a res-9 fallback for boundary areas).
                let activeHex = hex10
                // lastHex catches consecutive duplicates cheaply (dense GPS tracks from slow movement).
                // seenIndices catches non-consecutive revisits within the same import batch.
                // Together they avoid storing multiple entries for the same hex in pendingHexes.
                guard activeHex != lastHex, !seenIndices.contains(activeHex) else {
                    lastHex = activeHex
                    continue
                }

                lastHex = activeHex
                seenIndices.insert(activeHex)
                result.append((activeHex, 10, regionData.regionID, point.timestamp))
            }

            return result
        }.value

        guard !pendingHexes.isEmpty else {
            return GPXImportResult(newHexCount: 0, newRegionCount: 0, processedPoints: allPoints.count)
        }

        // 2. Fetch which of these hexes are already in the DB (one batch fetch)
        let candidateKeys = pendingHexes.map { $0.index }
        let alreadyExplored: Set<String> = {
            let desc = FetchDescriptor<ExploredHex>(
                predicate: #Predicate { candidateKeys.contains($0.h3Index) }
            )
            return Set((try? modelContext.fetch(desc))?.map { $0.h3Index } ?? [])
        }()

        // 3. Insert only genuinely new hexes; maintain a per-region cache to
        //    avoid repeated fetches for the same region within this import.
        var regionCache = [String: RegionExploration]()
        var newHexCount    = 0
        var newRegionCount = 0
        let fallbackDate   = Date()

        for item in pendingHexes where !alreadyExplored.contains(item.index) {
            let visitDate = item.date ?? fallbackDate

            // Insert hex
            let hex = ExploredHex(h3Index: item.index, resolution: item.resolution,
                                  regionID: item.regionID)
            hex.firstVisited = visitDate
            hex.lastVisited  = visitDate
            modelContext.insert(hex)
            newHexCount += 1

            // Update or create region
            if let cached = regionCache[item.regionID] {
                cached.addExploredHex(item.index)
            } else {
                let rid = item.regionID
                let desc = FetchDescriptor<RegionExploration>(
                    predicate: #Predicate { $0.regionID == rid }
                )
                if let existing = (try? modelContext.fetch(desc))?.first {
                    existing.addExploredHex(item.index)
                    regionCache[rid] = existing
                } else {
                    let meta      = RegionMetadataManager.shared.municipalities[rid]
                    let name      = meta?.name ?? "Unknown Region"
                    let total     = OfflineDatabase.shared.getTotalHexes(for: rid)
                    let region    = RegionExploration(regionID: rid, name: name,
                                                      type: "Municipality", totalHexes: total)
                    region.firstVisited = visitDate
                    region.lastVisited  = visitDate
                    region.addExploredHex(item.index)
                    modelContext.insert(region)
                    regionCache[rid] = region
                    newRegionCount += 1
                }
            }
        }

        try modelContext.save()
        print("✅ GPX import: \(newHexCount) new hexes, \(newRegionCount) new regions, \(allPoints.count) points processed")
        return GPXImportResult(newHexCount: newHexCount, newRegionCount: newRegionCount,
                               processedPoints: allPoints.count)
    }
}
