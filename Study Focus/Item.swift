//
//  Item.swift
//  Study Focus
//
//  Created by Tinchi on 7/11/26.
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
