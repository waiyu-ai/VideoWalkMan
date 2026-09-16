import Foundation
import Combine
import UIKit

enum PlaybackMode: String, CaseIterable, Codable, Identifiable {
    case normal
    case shuffle
    case repeatAll
    case repeatOne

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .shuffle: return "Shuffle"
        case .repeatAll: return "Repeat All"
        case .repeatOne: return "Repeat One"
        }
    }

    var systemImage: String {
        switch self {
        case .normal: return "arrow.right"
        case .shuffle: return "shuffle"
        case .repeatAll: return "repeat"
        case .repeatOne: return "repeat.1"
        }
    }
}

enum SortOption: String, CaseIterable, Identifiable {
    case custom
    case titleAZ
    case dateAddedNewest
    case durationLongest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom: return "Custom Order"
        case .titleAZ: return "Title (A-Z)"
        case .dateAddedNewest: return "Date Added (Newest First)"
        case .durationLongest: return "Duration (Longest First)"
        }
    }
}

struct ExportPayload: Codable {
    let name: String
    let videos: [VideoItem]
}

enum HapticFeedback {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    static func light() {
        lightGenerator.prepare()
        lightGenerator.impactOccurred()
    }

    static func medium() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred()
    }
}

final class PlaylistStore: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var playbackMode: PlaybackMode = .normal {
        didSet { persistPlaybackMode() }
    }
    @Published var resumePositions: [String: Double] = [:]

    private let playlistsKey = "savedPlaylists"
    private let playbackModeKey = "playbackMode"
    private let resumePositionsKey = "resumePositions"

    init() {
        load()
        loadPlaybackMode()
        loadResumePositions()
    }

    // MARK: - Persistence

    func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.standard.set(data, forKey: playlistsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: playlistsKey),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data) else {
            return
        }
        playlists = decoded
    }

    private func persistPlaybackMode() {
        UserDefaults.standard.set(playbackMode.rawValue, forKey: playbackModeKey)
    }

    private func loadPlaybackMode() {
        if let raw = UserDefaults.standard.string(forKey: playbackModeKey),
           let mode = PlaybackMode(rawValue: raw) {
            playbackMode = mode
        }
    }

    private func persistResumePositions() {
        guard let data = try? JSONEncoder().encode(resumePositions) else { return }
        UserDefaults.standard.set(data, forKey: resumePositionsKey)
    }

    private func loadResumePositions() {
        guard let data = UserDefaults.standard.data(forKey: resumePositionsKey),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return
        }
        resumePositions = decoded
    }

    // MARK: - Playlist CRUD

    func addPlaylist(_ playlist: Playlist) {
        playlists.append(playlist)
        save()
    }

    func removePlaylist(at index: Int) {
        guard playlists.indices.contains(index) else { return }
        playlists.remove(at: index)
        save()
        HapticFeedback.medium()
    }

    func addVideos(_ videos: [VideoItem], to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].videoItems.append(contentsOf: videos)
        save()
    }

    func removeVideo(_ video: VideoItem, from playlistID: UUID) {
        removeVideos([video], from: playlistID)
    }

    func removeVideos(_ videos: [VideoItem], from playlistID: UUID) {
        guard !videos.isEmpty,
              let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let ids = Set(videos.map(\.id))
        playlists[index].videoItems.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - Reordering

    func moveVideos(
        in playlistID: UUID,
        from source: IndexSet,
        to destination: Int,
        selectedIDs: Set<UUID> = []
    ) {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var items = playlists[playlistIndex].videoItems

        let indicesToMove: IndexSet
        if !selectedIDs.isEmpty,
           source.contains(where: { selectedIDs.contains(items[$0].id) }) {
            indicesToMove = IndexSet(items.indices.filter { selectedIDs.contains(items[$0].id) })
        } else {
            indicesToMove = source
        }

        items.move(fromOffsets: indicesToMove, toOffset: destination)
        playlists[playlistIndex].videoItems = items
        save()
        HapticFeedback.light()
    }

    func reshuffleVideos(in playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].videoItems.shuffle()
        save()
        HapticFeedback.light()
    }

    // MARK: - Sort (non-mutating)

    func sortedVideos(in playlistID: UUID, by option: SortOption) -> [VideoItem] {
        guard let playlist = playlists.first(where: { $0.id == playlistID }) else { return [] }
        switch option {
        case .custom:
            return playlist.videoItems
        case .titleAZ:
            return playlist.videoItems.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .dateAddedNewest:
            return playlist.videoItems.sorted { $0.dateAdded > $1.dateAdded }
        case .durationLongest:
            return playlist.videoItems.sorted { $0.duration > $1.duration }
        }
    }

    // MARK: - Playback mode

    func setPlaybackMode(_ mode: PlaybackMode) {
        guard playbackMode != mode else { return }
        playbackMode = mode
        HapticFeedback.light()
    }

    // MARK: - Resume playback

    func saveResumePosition(for localIdentifier: String, seconds: Double) {
        let clamped = max(0, seconds)
        if clamped == 0 {
            resumePositions.removeValue(forKey: localIdentifier)
        } else {
            resumePositions[localIdentifier] = clamped
        }
        persistResumePositions()
    }

    func resumePosition(for localIdentifier: String) -> Double? {
        guard let value = resumePositions[localIdentifier], value > 0 else { return nil }
        return value
    }

    func hasResumePosition(for localIdentifier: String) -> Bool {
        resumePosition(for: localIdentifier) != nil
    }

    // MARK: - Export

    func exportPayload(for playlist: Playlist) -> ExportPayload {
        ExportPayload(name: playlist.name, videos: playlist.videoItems)
    }

    func exportPlaylistJSON(for playlist: Playlist) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(exportPayload(for: playlist))
    }
}
