VibeMap 🌍
VibeMap is an iOS application that gamifies urban exploration. By tracking your location as you move, the app "uncovers" the world on a hexagonal grid, allowing you to visualize your footprint and track exploration statistics for different cities.

🚀 Features
Hexagonal "Fog of War": The world is divided into hexagonal cells (Resolution 10) using Uber's H3 grid system. Hexes light up on the map as you physically visit them.

City Exploration Stats: The app automatically detects which city you are in and calculates an "Exploration Percentage" based on the city's approximate radius.

Background Tracking: efficient location tracking using "Significant Location Changes" and "Visit Monitoring" to record your exploration even when the app is closed.

Persistent History: All explored hexes and location points are saved locally using SwiftData.

Interactive Map: * View your explored territories overlaid on the map.

Switch between Standard, Satellite, and Imagery map styles.

Centers on your location and tracks movement.

Detailed Statistics: View total hexes explored, cities visited, and a leaderboard-style list of your most explored cities.

🛠 Tech Stack
Language: Swift 5.0

UI Framework: SwiftUI

Persistence: SwiftData

Mapping: MapKit

Location: CoreLocation (Significant Changes & Monitoring Visits)

Concurrency: Swift Concurrency (async/await)

State Management: Observation Framework (@Observable)

External Dependencies:

swift-h3: A Swift wrapper for the Uber H3 hierarchical geospatial indexing system.

📱 Requirements
iOS: 17.0+ (Requires SwiftData and @Observable support).

Xcode: 15.0+

📂 Project Structure
VibeMapApp.swift: Application entry point; configures the SwiftData ModelContainer.

ContentView.swift: The main UI coordinator. Handles the transition between the Splash Screen and the Map, and displays the exploration stats overlay.

LocationManager.swift: The core logic engine. Handles permissions, background location updates, H3 index conversion, and city detection.

MapView.swift: A SwiftUI wrapper for the map interface. Renders the user's location and the polygons for explored hexes.

H3Wrapper.swift: Helper struct interfacing with the C-based H3 library to convert coordinates to indices and retrieve hexagon boundary vertices.

Models (ExplorationModels.swift, CityExploration.swift):

ExploredHex: Represents a unique H3 index visited by the user.

CityExploration: Tracks stats for a specific city (e.g., total hexes vs. explored hexes).

🔧 Installation
Clone the repository:

Bash
git clone <repository-url>
Open the project: Open VibeMap.xcodeproj in Xcode.

Resolve Dependencies: Xcode should automatically fetch the swift-h3 package via Swift Package Manager. If not, go to File > Packages > Resolve Package Versions.

Permissions: To test the full functionality, you must allow "Always" location access when prompted. This enables the app to track your exploration while it is in the background.

🧩 How It Works
Grid Generation: When the location manager receives a coordinate, it converts it into an H3 index (a hexadecimal string representing a specific hexagon on the globe).

Data Recording: If the hex hasn't been visited before, it is saved to the SwiftData database.

City Detection: The app performs a reverse geocode lookup to identify the city. It then calculates a theoretical "boundary" for that city (defaulting to a 5km radius) to estimate how much of the city you have "conquered".

Visualization: The MapView fetches the stored hex indices, calculates their polygon vertices using H3Wrapper, and draws them as green overlays on the map.
