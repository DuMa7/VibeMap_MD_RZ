//
//  CityData.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 08.02.2026.
//


import Foundation

struct CityData: Codable {
    let name: String
    let population: Int
}

class PopulationManager {
    static let shared = PopulationManager()
    
    private var cityPopulations: [String: Int] = [:]
    
    init() {
        loadData()
    }
    
    private func loadData() {
        guard let url = Bundle.main.url(forResource: "SwissCities", withExtension: "json") else {
            print("⚠️ SwissCities.json not found in bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let cities = try JSONDecoder().decode([CityData].self, from: data)
            
            // Convert array to dictionary for fast lookup
            for city in cities {
                cityPopulations[city.name] = city.population
            }
            print("🇨🇭 Loaded \(cities.count) Swiss cities.")
        } catch {
            print("❌ Failed to load city data: \(error)")
        }
    }
    
    /// Returns true if the city has more than the threshold population
    func isBigCity(_ cityName: String, threshold: Int = 10000) -> Bool {
        // 1. Direct match
        if let pop = cityPopulations[cityName] {
            return pop >= threshold
        }
            
        // 2. Case-insensitive match (Backup)
        let lowerName = cityName.lowercased()
        let match = cityPopulations.first { key, _ in
            key.lowercased() == lowerName
        }
            
        if let (_, pop) = match {
            return pop >= threshold
        }
            
        // 3. Debugging: Print failure to help you fix missing names
        print("⚠️ City not found in DB: '\(cityName)'. Defaulting to Rural.")
        return false
    }
    
    func getPopulation(for cityName: String) -> Int? {
        return cityPopulations[cityName]
    }
}
