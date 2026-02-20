import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showShareSheet = false
    @State private var showFilePicker = false
    @State private var backupJSON: String?
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Data Management") {
                    // EXPORT BUTTON
                    Button {
                        let manager = BackupManager(modelContext: modelContext)
                        if let json = manager.createBackupJSON() {
                            backupJSON = json
                            showShareSheet = true
                        }
                    } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }
                    
                    // IMPORT BUTTON
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                            .foregroundStyle(.blue)
                    }
                }
                
                Section("Danger Zone") {
                    Button(role: .destructive) {
                        do {
                            // Updated to use the new Phase 2 models
                            try modelContext.delete(model: ExploredHex.self)
                            try modelContext.delete(model: RegionExploration.self)
                            try modelContext.delete(model: LocationPoint.self)
                            alertMessage = "All data erased."
                            showAlert = true
                        } catch {
                            alertMessage = "Error: \(error.localizedDescription)"
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
            // EXPORT SHEET
            .sheet(isPresented: $showShareSheet) {
                if let json = backupJSON {
                    ShareSheet(activityItems: [json])
                }
            }
            // IMPORT PICKER
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    let manager = BackupManager(modelContext: modelContext)
                    Task {
                        do {
                            try await manager.restoreFromJSON(url: url)
                            alertMessage = "Backup restored successfully!"
                            showAlert = true
                        } catch {
                            alertMessage = "Restore failed: \(error.localizedDescription)"
                            showAlert = true
                        }
                    }
                case .failure(let error):
                    print("Import failed: \(error.localizedDescription)")
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

// Helper for iOS Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
