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

    // Import / restore
    @State private var showFilePicker = false
    @State private var pendingRestoreData: Data?
    @State private var pendingPreview: BackupPreview?
    @State private var showRestorePreview = false

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
            .alert("Status", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
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
