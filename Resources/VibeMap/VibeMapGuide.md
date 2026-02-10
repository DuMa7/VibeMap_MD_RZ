import SwiftUI
import SwiftData

@main
struct VibeMapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var locationManager = LocationManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView(locationManager: locationManager)
        }
        .modelContainer(for: [ExploredHex.self, LocationPoint.self, CityExploration.self])
        // iOS 17+ overload supports old/new values when you include `initial:`
        .onChange(of: scenePhase, initial: false) { oldPhase, newPhase in
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
