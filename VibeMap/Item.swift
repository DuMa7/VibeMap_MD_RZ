//
//  Item.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 07.02.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
