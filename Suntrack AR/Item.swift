//
//  Item.swift
//  Suntrack AR
//
//  Created by Dwaipayan Ray on 17/11/25.
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
