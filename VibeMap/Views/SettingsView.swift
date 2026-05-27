import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var hexes: [ExploredHex]
    @Query private var regions: [RegionExploration]

    // Export
    @State private var exportURL: URL?
    @State private var showShareSheet = false

    // Backup import / restore
    @State private var showFilePicker = false
    @State private var pendingRestoreData: Data?
    @State private var pendingPreview: BackupPreview?
    @State private var showRestorePreview = false

    // GPX import
    @State private var showGPXPicker = false
    @State private var pendingGPXFiles: [GPXFile] = []
    @State private var gpxSummary: GPXImportSummary?
    @State private var showGPXPreview = false
    @State private var isImportingGPX = false

    // Garmin / HealthKit sync
    // Watermark stored as Double (TimeInterval) because @AppStorage doesn't support Date directly.
    // HealthKitImporter writes the same key via UserDefaults; @AppStorage observes it automatically.
    @AppStorage(HealthKitImporter.lastSyncKey) private var garminLastSyncTimestamp: Double = 0
    @State private var garminPreview: GarminSyncPreview?
    @State private var showGarminPreview = false
    @State private var isLoadingGarminPreview = false
    @State private var isSyncingGarmin = false

    var garminLastSyncDate: Date? {
        garminLastSyncTimestamp > 0 ? Date(timeIntervalSince1970: garminLastSyncTimestamp) : nil
    }

    // Feedback
    @State private var alertMessage = ""
    @State private var showAlert = false

    // Auto-backup status (refreshed on appear)
    @State private var lastBackupDate: Date?

    private var manager: BackupManager { BackupManager(modelContext: modelContext) }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Auto-backup status
                Section {
                    HStack {
                        Label("Last Auto-Backup", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        if let date = lastBackupDate {
                            Text(date, style: .relative)
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            Text("Never")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }

                    Button {
                        do {
                            try manager.saveAutoBackup()
                            lastBackupDate = manager.lastAutoBackupDate()
                            alertMessage = "Backup saved to device (\(hexes.count) hexes, \(regions.count) towns)."
                            showAlert = true
                        } catch {
                            alertMessage = "Backup failed: \(error.localizedDescription)"
                            showAlert = true
                        }
                    } label: {
                        Label("Back Up Now", systemImage: "icloud.and.arrow.up")
                    }
                } header: {
                    Text("Auto-Backup")
                } footer: {
                    Text("Saved to this device and included in iCloud device backup when enabled.")
                }

                // MARK: GPX import
                Section {
                    Button {
                        showGPXPicker = true
                    } label: {
                        if isImportingGPX {
                            HStack {
                                ProgressView().padding(.trailing, 4)
                                Text("Importing…")
                            }
                        } else {
                            Label("Import GPX Tracks", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                        }
                    }
                    .disabled(isImportingGPX)
                } header: {
                    Text("Import Activity Data")
                } footer: {
                    Text("Import .gpx files from Garmin, Strava, Apple Fitness, AllTrails, and more to retroactively scratch hexes.")
                }

                // MARK: Garmin sync
                if HealthKitImporter.isAvailable {
                    Section {
                        Button {
                            isLoadingGarminPreview = true
                            Task {
                                do {
                                    let importer = HealthKitImporter(modelContext: modelContext)
                                    try await importer.requestAuthorization()
                                    let preview = try await importer.buildPreview(since: garminLastSyncDate)
                                    if preview.workoutCount == 0 {
                                        alertMessage = garminLastSyncDate == nil
                                            ? "No Garmin activities found in Apple Health. Open Garmin Connect and make sure it is syncing to Health."
                                            : "No new Garmin activities since \(garminLastSyncDate!.formatted(date: .abbreviated, time: .omitted))."
                                        showAlert = true
                                    } else {
                                        garminPreview = preview
                                        showGarminPreview = true
                                    }
                                } catch {
                                    alertMessage = "Could not access Garmin activities: \(error.localizedDescription)"
                                    showAlert = true
                                }
                                isLoadingGarminPreview = false
                            }
                        } label: {
                            if isLoadingGarminPreview {
                                HStack {
                                    ProgressView().padding(.trailing, 4)
                                    Text("Checking Garmin…")
                                }
                            } else if isSyncingGarmin {
                                HStack {
                                    ProgressView().padding(.trailing, 4)
                                    Text("Syncing…")
                                }
                            } else {
                                Label("Sync from Garmin", systemImage: "figure.run.circle.fill")
                            }
                        }
                        .disabled(isLoadingGarminPreview || isSyncingGarmin)

                        if let lastSync = garminLastSyncDate {
                            HStack {
                                Label("Last Synced", systemImage: "checkmark.circle")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(lastSync, style: .relative)
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                        }
                    } header: {
                        Text("Garmin Connect")
                    } footer: {
                        Text("Imports activities synced from Garmin Connect to Apple Health. Garmin Connect → Health sync must be enabled in the Garmin Connect iOS app.")
                    }
                }

                // MARK: Manual export / import
                Section("Manual Transfer") {
                    Button {
                        do {
                            exportURL = try manager.createBackupFile()
                            showShareSheet = true
                        } catch BackupError.noData {
                            alertMessage = "Nothing to export yet — explore some hexes first."
                            showAlert = true
                        } catch {
                            alertMessage = "Export failed: \(error.localizedDescription)"
                            showAlert = true
                        }
                    } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                            .foregroundStyle(.blue)
                    }
                }

                // MARK: Danger zone
                Section("Danger Zone") {
                    Button(role: .destructive) {
                        do {
                            try modelContext.delete(model: ExploredHex.self)
                            try modelContext.delete(model: RegionExploration.self)
                            try modelContext.delete(model: LocationPoint.self)
                            alertMessage = "All exploration data erased."
                            showAlert = true
                        } catch {
                            alertMessage = "Reset failed: \(error.localizedDescription)"
                            showAlert = true
                        }
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                    }
                }

                Section("About") {
                    Text("VibeMap v1.0")
                    Text("Made with 📍 & 🗺️")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                lastBackupDate = manager.lastAutoBackupDate()
            }
            // MARK: Export share sheet
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
            // MARK: Restore preview sheet
            .sheet(isPresented: $showRestorePreview) {
                if let preview = pendingPreview, let data = pendingRestoreData {
                    RestorePreviewSheet(
                        preview: preview,
                        currentHexCount: hexes.count,
                        currentRegionCount: regions.count
                    ) {
                        Task {
                            do {
                                try await manager.restoreFromData(data)
                                lastBackupDate = manager.lastAutoBackupDate()
                                alertMessage = "Restored \(preview.hexCount) hexes across \(preview.regionCount) towns."
                            } catch {
                                alertMessage = "Restore failed: \(error.localizedDescription)"
                            }
                            showAlert = true
                            pendingRestoreData = nil
                            pendingPreview = nil
                        }
                    }
                }
            }
            // MARK: File picker
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // Read data synchronously while security scope is open
                    guard url.startAccessingSecurityScopedResource() else {
                        alertMessage = "Could not access the selected file."
                        showAlert = true
                        return
                    }
                    let data = try? Data(contentsOf: url)
                    url.stopAccessingSecurityScopedResource()

                    guard let data else {
                        alertMessage = "Could not read the selected file."
                        showAlert = true
                        return
                    }

                    do {
                        let preview = try manager.previewBackup(data: data)
                        pendingRestoreData = data
                        pendingPreview = preview
                        showRestorePreview = true
                    } catch {
                        alertMessage = "Invalid backup file: \(error.localizedDescription)"
                        showAlert = true
                    }

                case .failure(let error):
                    alertMessage = "File picker error: \(error.localizedDescription)"
                    showAlert = true
                }
            }
            // MARK: GPX file picker
            .fileImporter(
                isPresented: $showGPXPicker,
                allowedContentTypes: [.gpx, .xml],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    // Read all files while security scopes are open
                    var items: [(filename: String, data: Data)] = []
                    for url in urls {
                        guard url.startAccessingSecurityScopedResource() else { continue }
                        if let data = try? Data(contentsOf: url) {
                            items.append((url.lastPathComponent, data))
                        }
                        url.stopAccessingSecurityScopedResource()
                    }
                    guard !items.isEmpty else {
                        alertMessage = "Could not read the selected file(s)."
                        showAlert = true
                        return
                    }

                    // Parse GPX off the picker callback (still on main thread but fast XML parse)
                    let parsed = GPXImporter.parse(items)
                    guard !parsed.isEmpty else {
                        alertMessage = "No track points found in the selected file(s)."
                        showAlert = true
                        return
                    }

                    pendingGPXFiles = parsed
                    gpxSummary = GPXImporter.summarise(parsed)
                    showGPXPreview = true

                case .failure(let error):
                    alertMessage = "File picker error: \(error.localizedDescription)"
                    showAlert = true
                }
            }
            // MARK: Garmin preview sheet
            .sheet(isPresented: $showGarminPreview) {
                if let preview = garminPreview {
                    GarminSyncPreviewSheet(preview: preview, lastSyncDate: garminLastSyncDate) {
                        showGarminPreview = false
                        isSyncingGarmin = true
                        Task {
                            do {
                                let importer = HealthKitImporter(modelContext: modelContext)
                                let result = try await importer.importWorkouts(preview.workouts)
                                // @AppStorage observes the same key; read back explicitly for safety
                                garminLastSyncTimestamp = UserDefaults.standard.double(
                                    forKey: HealthKitImporter.lastSyncKey
                                )
                                if result.newHexCount == 0 {
                                    let n = result.workoutsProcessed
                                    alertMessage = "All \(n) activit\(n == 1 ? "y was" : "ies were") already on your map — nothing new to add."
                                } else {
                                    let h = result.newHexCount
                                    let r = result.newRegionCount
                                    let w = result.workoutsProcessed
                                    alertMessage = "Synced \(h) new hex\(h == 1 ? "" : "es") across \(r) new town\(r == 1 ? "" : "s") from \(w) activit\(w == 1 ? "y" : "ies")."
                                }
                            } catch {
                                alertMessage = "Sync failed: \(error.localizedDescription)"
                            }
                            isSyncingGarmin = false
                            garminPreview = nil
                            showAlert = true
                        }
                    }
                }
            }
            // MARK: GPX import preview sheet
            .sheet(isPresented: $showGPXPreview) {
                if let summary = gpxSummary {
                    GPXImportPreviewSheet(summary: summary) {
                        showGPXPreview = false
                        isImportingGPX = true
                        Task {
                            do {
                                let importer = GPXImporter(modelContext: modelContext)
                                let result = try await importer.importFiles(pendingGPXFiles)
                                if result.newHexCount == 0 {
                                    alertMessage = "All \(result.processedPoints) track points were already in your map — nothing new to add."
                                } else {
                                    alertMessage = "Imported \(result.newHexCount) new hex\(result.newHexCount == 1 ? "" : "es") across \(result.newRegionCount) new town\(result.newRegionCount == 1 ? "" : "s") from \(result.processedPoints) track points."
                                }
                            } catch {
                                alertMessage = "Import failed: \(error.localizedDescription)"
                            }
                            isImportingGPX = false
                            pendingGPXFiles = []
                            gpxSummary = nil
                            showAlert = true
                        }
                    }
                }
            }
            .alert("Status", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
}

// MARK: - GPX Import Preview Sheet

private struct GPXImportPreviewSheet: View {
    let summary: GPXImportSummary
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .padding(.top, 32)
                    .padding(.bottom, 20)

                Text(summary.displayTitle)
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let earliest = summary.earliestDate, let latest = summary.latestDate {
                    let sameDay = Calendar.current.isDate(earliest, inSameDayAs: latest)
                    Text(sameDay
                         ? earliest.formatted(date: .abbreviated, time: .omitted)
                         : "\(earliest.formatted(date: .abbreviated, time: .omitted)) – \(latest.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                Spacer().frame(height: 28)

                // Stats grid
                HStack(spacing: 16) {
                    statCard(value: "\(summary.fileCount)",
                             label: summary.fileCount == 1 ? "File" : "Files",
                             icon: "doc.fill")
                    statCard(value: summary.totalPoints >= 1000
                                    ? String(format: "%.1fk", Double(summary.totalPoints) / 1000)
                                    : "\(summary.totalPoints)",
                             label: "Track Points",
                             icon: "location.fill")
                }
                .padding(.horizontal)

                Text("New hexes will be scratched for any location not already on your map.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        onConfirm()
                    } label: {
                        Text("Import Tracks")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.orange)
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                    }

                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.orange)
            Text(value).font(.title3).bold()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(14)
    }
}

// MARK: - Restore Preview Sheet

private struct RestorePreviewSheet: View {
    let preview: BackupPreview
    let currentHexCount: Int
    let currentRegionCount: Int
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header icon
                Image(systemName: "arrow.counterclockwise.icloud")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .padding(.top, 32)
                    .padding(.bottom, 20)

                Text("Restore Backup?")
                    .font(.title2).bold()
                    .padding(.bottom, 8)

                Text("Saved \(preview.timestamp, style: .date) at \(preview.timestamp, style: .time)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 28)

                // Comparison cards
                HStack(spacing: 16) {
                    comparisonCard(title: "This Backup",
                                   hexes: preview.hexCount,
                                   towns: preview.regionCount,
                                   accent: .orange)
                    comparisonCard(title: "Your Current Data",
                                   hexes: currentHexCount,
                                   towns: currentRegionCount,
                                   accent: .blue)
                }
                .padding(.horizontal)

                Text("Your current data will be permanently replaced.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 20)

                Spacer()

                VStack(spacing: 12) {
                    Button(role: .destructive) {
                        dismiss()
                        onConfirm()
                    } label: {
                        Text("Restore Backup")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.orange)
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                    }

                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
    }

    private func comparisonCard(title: String, hexes: Int, towns: Int, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption).bold()
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 6) {
                Label("\(hexes) hexes", systemImage: "hexagon.fill")
                    .font(.subheadline).bold()
                Label("\(towns) towns", systemImage: "map.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(14)
    }
}

// MARK: - Garmin Sync Preview Sheet

private struct GarminSyncPreviewSheet: View {
    let preview: GarminSyncPreview
    let lastSyncDate: Date?
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .padding(.top, 32)
                    .padding(.bottom, 20)

                Text("Garmin Activities")
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)

                if let range = preview.dateRange {
                    let sameDay = Calendar.current.isDate(range.first, inSameDayAs: range.last)
                    Text(sameDay
                         ? range.first.formatted(date: .abbreviated, time: .omitted)
                         : "\(range.first.formatted(date: .abbreviated, time: .omitted)) – \(range.last.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                Spacer().frame(height: 28)

                HStack(spacing: 16) {
                    statCard(
                        value: "\(preview.workoutCount)",
                        label: preview.workoutCount == 1 ? "Activity" : "Activities",
                        icon: "figure.run"
                    )
                    if preview.totalDistanceKm > 0 {
                        statCard(
                            value: String(format: "%.0f km", preview.totalDistanceKm),
                            label: "Distance",
                            icon: "map"
                        )
                    } else {
                        statCard(
                            value: formatDuration(preview.totalDuration),
                            label: "Total Time",
                            icon: "clock"
                        )
                    }
                }
                .padding(.horizontal)

                Group {
                    if let lastSync = lastSyncDate {
                        Text("Activities since \(lastSync.formatted(date: .abbreviated, time: .omitted)).")
                    } else {
                        Text("All Garmin activities in Apple Health will be scratched onto your map.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        onConfirm()
                    } label: {
                        Text("Sync to Map")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.orange)
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                    }
                    Button { dismiss() } label: {
                        Text("Cancel").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.orange)
            Text(value).font(.title3).bold()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(14)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems,
                                 applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
