import SwiftUI
import SwiftData

@main
struct VibeMapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    // 1. This is the SINGLE "Source of Truth" for the whole app
    @State private var locationManager = LocationManager()
    
    var body: some Scene {
        WindowGroup {
            // 2. Inject it into ContentView
            ContentView()
                .environment(locationManager)
        }
        .modelContainer(for: [ExploredHex.self, LocationPoint.self, CityExploration.self])
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                print("📱 App became active")
                locationManager.applicationDidBecomeActive()
            case .background:
                print("📱 App entering background")
                locationManager.applicationDidEnterBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
