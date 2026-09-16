import Foundation

struct VideoItem: Identifiable, Codable, Hashable {
    let id: UUID
    let localIdentifier: String
    var displayName: String
    var dateAdded: Date
    var duration: TimeInterval

    init(
        localIdentifier: String,
        displayName: String = "Untitled",
        dateAdded: Date = Date(),
        duration: TimeInterval = 0
    ) {
        self.id = UUID()
        self.localIdentifier = localIdentifier
        self.displayName = displayName
        self.dateAdded = dateAdded
        self.duration = duration
    }

    enum CodingKeys: String, CodingKey {
        case id, localIdentifier, displayName, dateAdded, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        localIdentifier = try container.decode(String.self, forKey: .localIdentifier)
        displayName = try container.decode(String.self, forKey: .displayName)
        dateAdded = try container.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
    }
}
