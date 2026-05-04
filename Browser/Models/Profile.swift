import Foundation
import SwiftUI

struct Profile: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorIndex: Int
    let dataStoreUUID: UUID

    init(id: UUID = UUID(),
         name: String,
         colorIndex: Int = 0,
         dataStoreUUID: UUID = UUID()) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.dataStoreUUID = dataStoreUUID
    }

    var color: Color {
        Self.palette[colorIndex % Self.palette.count]
    }

    var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(1)).uppercased()
    }

    static let palette: [Color] = [
        Color(red: 0.31, green: 0.27, blue: 0.90), // indigo
        Color(red: 0.20, green: 0.51, blue: 0.96), // blue
        Color(red: 0.13, green: 0.69, blue: 0.45), // green
        Color(red: 0.95, green: 0.55, blue: 0.10), // orange
        Color(red: 0.93, green: 0.28, blue: 0.60), // pink
        Color(red: 0.65, green: 0.33, blue: 0.92), // purple
        Color(red: 0.06, green: 0.72, blue: 0.71), // teal
        Color(red: 0.91, green: 0.27, blue: 0.27), // red
    ]
}
