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
        guard let pop = cityPopulations[cityName] else {
            // City not in list? Assume Rural (Small)
            return false
        }
        return pop >= threshold
    }
    
    func getPopulation(for cityName: String) -> Int? {
        return cityPopulations[cityName]
    }
}