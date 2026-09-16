import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: UUID

    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var photoManager: PhotoLibraryManager

    @AppStorage("lastPlayedPlaylistID") private var lastPlayedPlaylistID = ""

    @State private var isPresentingVideoSelection = false
    @State private var isPresentingPlayer = false
    @State private var playerPlaylist: Playlist?
    @State private var sortOption: SortOption = .custom
    @State private var searchText = ""
    @State private var editMode: EditMode = .inactive
    @State private var selectedVideoIDs: Set<UUID> = []
    @State private var exportFileURL: URL?
    @State private var isPresentingShareSheet = false
    @State private var isConfirmingReshuffle = false

    private var playlist: Playlist? {
        playlistStore.playlists.first { $0.id == playlistID }
    }

    private var displayedVideos: [VideoItem] {
        let sorted = playlistStore.sortedVideos(in: playlistID, by: sortOption)
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    private var canReorder: Bool {
        sortOption == .custom && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var totalDuration: TimeInterval {
        playlist?.videoItems.reduce(0) { $0 + max(0, $1.duration) } ?? 0
    }

    var body: some View {
        List(selection: $selectedVideoIDs) {
            if let playlist {
                ForEach(displayedVideos) { video in
                    videoRow(video)
                        .tag(video.id)
                }
                .onDelete { offsets in
                    deleteVideos(at: offsets, from: displayedVideos)
                }
                .onMove { source, destination in
                    guard canReorder else { return }
                    let sourceIDs = source.map { displayedVideos[$0].id }
                    let mappedSource = IndexSet(
                        playlist.videoItems.indices.filter { sourceIDs.contains(playlist.videoItems[$0].id) }
                    )
                    let destinationID: UUID? = {
                        if destination >= displayedVideos.count { return nil }
                        return displayedVideos[destination].id
                    }()
                    let mappedDestination: Int = {
                        if let destinationID,
                           let index = playlist.videoItems.firstIndex(where: { $0.id == destinationID }) {
                            return index
                        }
                        return playlist.videoItems.count
                    }()

                    playlistStore.moveVideos(
                        in: playlistID,
                        from: mappedSource,
                        to: mappedDestination,
                        selectedIDs: selectedVideoIDs
                    )
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(playlist?.name ?? "Playlist")
                        .font(.headline)
                    if totalDuration > 0 {
                        Text(formatDuration(totalDuration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Total duration \(formatDuration(totalDuration))")
                    }
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
                    .accessibilityLabel("Edit playlist order")
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    playAll()
                } label: {
                    Image(systemName: "play.fill")
                }
                .disabled(playlist?.videoItems.isEmpty ?? true)
                .accessibilityLabel("Play All")

                Button {
                    shufflePlay()
                } label: {
                    Image(systemName: "shuffle")
                }
                .disabled(playlist?.videoItems.isEmpty ?? true)
                .accessibilityLabel("Shuffle Play")

                Menu {
                    ForEach(SortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            HStack {
                                Text(option.title)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .accessibilityLabel("Sort by \(option.title)")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort videos")

                Button {
                    isConfirmingReshuffle = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(!canReorder || (playlist?.videoItems.isEmpty ?? true))
                .accessibilityLabel("Reshuffle playlist order")

                Button {
                    exportPlaylist()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(playlist == nil)
                .accessibilityLabel("Export Playlist")

                Button {
                    isPresentingVideoSelection = true
                } label: {
                    Image(systemName: "video.badge.plus")
                }
                .accessibilityLabel("Add Videos")
            }
        }
        .searchable(text: $searchText, prompt: "Search videos")
        .alert("Reshuffle Playlist?", isPresented: $isConfirmingReshuffle) {
            Button("Cancel", role: .cancel) {}
            Button("Reshuffle", role: .destructive) {
                playlistStore.reshuffleVideos(in: playlistID)
            }
        } message: {
            Text("This randomly reorders the videos in this playlist.")
        }
        .sheet(isPresented: $isPresentingVideoSelection) {
            NavigationStack {
                VideoSelectionView { videos in
                    playlistStore.addVideos(videos, to: playlistID)
                    isPresentingVideoSelection = false
                }
            }
            .environmentObject(playlistStore)
            .environmentObject(photoManager)
        }
        .fullScreenCover(isPresented: $isPresentingPlayer) {
            if let playerPlaylist {
                VideoPlayerView(playlist: playerPlaylist)
                    .environmentObject(playlistStore)
            }
        }
        .sheet(isPresented: $isPresentingShareSheet) {
            if let exportFileURL {
                ShareSheet(fileURL: exportFileURL, title: "Share Playlist")
            }
        }
        .overlay {
            if let playlist, playlist.videoItems.isEmpty {
                AppUnavailableView(
                    title: "No Videos",
                    systemImage: "film",
                    description: "Add videos from your Photos library."
                )
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func videoRow(_ video: VideoItem) -> some View {
        HStack(spacing: 12) {
            Button {
                playSingleVideo(video)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(video.displayName)")

            VStack(alignment: .leading, spacing: 2) {
                Text(video.displayName)
                    .font(.body)
                if video.duration > 0 {
                    Text(formatDuration(video.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if playlistStore.hasResumePosition(for: video.localIdentifier) {
                Button {
                    playSingleVideo(video, resume: true)
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.body)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume \(video.displayName) from saved position")
            }

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private func playAll() {
        guard let playlist, !playlist.videoItems.isEmpty else { return }
        if playlistStore.playbackMode == .shuffle {
            playlistStore.setPlaybackMode(.normal)
        }
        beginPlayback(with: playlist)
    }

    private func shufflePlay() {
        guard let playlist, !playlist.videoItems.isEmpty else { return }
        playlistStore.setPlaybackMode(.shuffle)
        beginPlayback(with: playlist)
    }

    private func beginPlayback(with playlist: Playlist) {
        lastPlayedPlaylistID = playlistID.uuidString
        playerPlaylist = playlist
        isPresentingPlayer = true
    }

    private func playSingleVideo(_ video: VideoItem, resume: Bool = false) {
        guard let playlist,
              let index = playlist.videoItems.firstIndex(where: { $0.id == video.id }) else {
            return
        }
        let rotated = Array(playlist.videoItems[index...]) + Array(playlist.videoItems[..<index])
        let playable = Playlist(name: playlist.name, videoItems: rotated)
        _ = resume
        lastPlayedPlaylistID = playlistID.uuidString
        playerPlaylist = playable
        isPresentingPlayer = true
    }

    private func deleteVideos(at offsets: IndexSet, from videos: [VideoItem]) {
        let videosToRemove = offsets.map { videos[$0] }
        playlistStore.removeVideos(videosToRemove, from: playlistID)
        selectedVideoIDs.subtract(videosToRemove.map(\.id))
    }

    private func exportPlaylist() {
        guard let playlist,
              let data = playlistStore.exportPlaylistJSON(for: playlist) else {
            return
        }

        let fileName = sanitizeFileName(playlist.name) + ".json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            exportFileURL = url
            isPresentingShareSheet = true
        } catch {
            exportFileURL = nil
        }
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "playlist" : cleaned
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        PlaylistDetailView(playlistID: UUID())
            .environmentObject(PlaylistStore())
            .environmentObject(PhotoLibraryManager())
    }
}
