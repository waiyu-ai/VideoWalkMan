import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var videoItems: [VideoItem]

    init(name: String, videoItems: [VideoItem] = []) {
        self.id = UUID()
        self.name = name
        self.videoItems = videoItems
    }
}
