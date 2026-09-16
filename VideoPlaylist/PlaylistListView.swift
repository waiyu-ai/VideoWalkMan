import SwiftUI

struct PlaylistListView: View {
    @EnvironmentObject private var playlistStore: PlaylistStore
    @State private var isPresentingCreateSheet = false
    @State private var newPlaylistName = ""

    var body: some View {
        List {
            ForEach(playlistStore.playlists) { playlist in
                NavigationLink(value: playlist.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name)
                            .font(.headline)
                        Text(videoCountLabel(for: playlist.videoItems.count))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deletePlaylists)
        }
        .navigationTitle("Playlists")
        .navigationDestination(for: UUID.self) { playlistID in
            PlaylistDetailView(playlistID: playlistID)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                playbackModeMenu
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newPlaylistName = ""
                    isPresentingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Playlist")
            }
        }
        .sheet(isPresented: $isPresentingCreateSheet) {
            CreatePlaylistSheet(
                name: $newPlaylistName,
                onCancel: { isPresentingCreateSheet = false },
                onCreate: {
                    let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    playlistStore.addPlaylist(Playlist(name: trimmed))
                    isPresentingCreateSheet = false
                }
            )
        }
        .overlay {
            if playlistStore.playlists.isEmpty {
                AppUnavailableView(
                    title: "No Playlists",
                    systemImage: "list.bullet.rectangle",
                    description: "Tap + to create your first playlist."
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var playbackModeMenu: some View {
        Menu {
            ForEach(PlaybackMode.allCases) { mode in
                Button {
                    playlistStore.setPlaybackMode(mode)
                } label: {
                    HStack {
                        Label(mode.title, systemImage: mode.systemImage)
                        if playlistStore.playbackMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityLabel("Set playback mode to \(mode.title)")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: playlistStore.playbackMode.systemImage)
                Text(playlistStore.playbackMode.title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: Capsule())
        }
        .accessibilityLabel("Playback mode \(playlistStore.playbackMode.title)")
    }

    private func videoCountLabel(for count: Int) -> String {
        count == 1 ? "1 video" : "\(count) videos"
    }

    private func deletePlaylists(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            playlistStore.removePlaylist(at: index)
        }
    }
}

private struct CreatePlaylistSheet: View {
    @Binding var name: String
    var onCancel: () -> Void
    var onCreate: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Playlist Name", text: $name)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: onCreate)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlaylistListView()
            .environmentObject(PlaylistStore())
    }
}
