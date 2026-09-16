import SwiftUI
import PhotosUI
import Photos
import UIKit

struct VideoSelectionView: View {
    /// When provided (e.g. from PlaylistDetailView), videos are added directly.
    /// When nil (Select Videos tab), a playlist picker sheet is shown.
    var onAddToPlaylist: (([VideoItem]) -> Void)? = nil

    @EnvironmentObject private var store: PlaylistStore
    @EnvironmentObject private var photoManager: PhotoLibraryManager

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selectedVideos: [SelectedVideo] = []
    @State private var isLoading = false
    @State private var pendingVideos: [VideoItem] = []
    @State private var isPresentingPlaylistPicker = false

    private let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12)
    ]

    private var isLimitedAccess: Bool {
        photoManager.authorizationStatus == .limited
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLimitedAccess {
                limitedAccessBanner
            }

            PhotosPicker(
                selection: $pickerItems,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                Label("Select Videos", systemImage: "video.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding()

            ZStack {
                if selectedVideos.isEmpty && !isLoading {
                    AppUnavailableView(
                        title: "No videos selected",
                        systemImage: "film.stack",
                        description: "Use Select Videos to pick clips from your library."
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach($selectedVideos) { $video in
                                SelectedVideoCell(video: $video)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }

                if isLoading {
                    ProgressView("Loading videos…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                commitSelection()
            } label: {
                Text("Add to Playlist")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedVideos.isEmpty || isLoading)
            .padding()
        }
        .navigationTitle("Select Videos")
        .onChange(of: pickerItems) { newItems in
            Task { await loadSelectedVideos(from: newItems) }
        }
        .sheet(isPresented: $isPresentingPlaylistPicker) {
            PlaylistDestinationPicker(
                playlists: store.playlists,
                onCancel: {
                    isPresentingPlaylistPicker = false
                    pendingVideos = []
                },
                onSelect: { playlistID in
                    store.addVideos(pendingVideos, to: playlistID)
                    pendingVideos = []
                    selectedVideos = []
                    pickerItems = []
                    isPresentingPlaylistPicker = false
                }
            )
        }
    }

    private var limitedAccessBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Photos access is limited. Some videos may be missing.")
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button("Manage Access") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.footnote.weight(.semibold))
            .accessibilityLabel("Manage Access")
        }
        .padding(12)
        .background(Color.orange.opacity(0.15))
    }

    private func commitSelection() {
        let items = selectedVideos.map {
            VideoItem(
                localIdentifier: $0.localIdentifier,
                displayName: $0.displayName,
                dateAdded: Date(),
                duration: $0.duration
            )
        }
        if let onAddToPlaylist {
            onAddToPlaylist(items)
        } else {
            pendingVideos = items
            isPresentingPlaylistPicker = true
        }
    }

    @MainActor
    private func loadSelectedVideos(from items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }

        let identifiers = items.compactMap(\.itemIdentifier)
        var assetByID: [String: PHAsset] = [:]
        if !identifiers.isEmpty {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            result.enumerateObjects { asset, _, _ in
                assetByID[asset.localIdentifier] = asset
            }
        }

        var loaded = Array(repeating: SelectedVideo?.none, count: items.count)

        await withTaskGroup(of: (Int, SelectedVideo).self) { group in
            var inFlight = 0
            var nextIndex = 0
            let maxConcurrent = 4

            func enqueueIfNeeded() {
                while inFlight < maxConcurrent, nextIndex < items.count {
                    let index = nextIndex
                    let item = items[index]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        let video = await Self.loadVideo(
                            item: item,
                            index: index,
                            assetByID: assetByID
                        )
                        return (index, video)
                    }
                }
            }

            enqueueIfNeeded()

            for await (index, video) in group {
                loaded[index] = video
                inFlight -= 1
                enqueueIfNeeded()
            }
        }

        selectedVideos = loaded.compactMap { $0 }
    }

    private static func loadVideo(
        item: PhotosPickerItem,
        index: Int,
        assetByID: [String: PHAsset]
    ) async -> SelectedVideo {
        let fallbackName = "Video \(index + 1)"
        let localIdentifier = item.itemIdentifier ?? ""

        var displayName = fallbackName
        var thumbnail: UIImage?
        var duration: TimeInterval = 0

        if !localIdentifier.isEmpty, let asset = assetByID[localIdentifier] {
            displayName = defaultName(for: asset, fallback: fallbackName)
            duration = asset.duration
            thumbnail = await requestThumbnail(for: asset)
        } else if let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) {
            thumbnail = image
        }

        return SelectedVideo(
            id: localIdentifier.isEmpty ? UUID().uuidString : localIdentifier,
            localIdentifier: localIdentifier.isEmpty ? UUID().uuidString : localIdentifier,
            displayName: displayName,
            thumbnail: thumbnail,
            duration: duration
        )
    }

    private static func defaultName(for asset: PHAsset, fallback: String) -> String {
        guard let date = asset.creationDate else { return fallback }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Video \(formatter.string(from: date))"
    }

    private static func requestThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

private struct PlaylistDestinationPicker: View {
    let playlists: [Playlist]
    var onCancel: () -> Void
    var onSelect: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    AppUnavailableView(
                        title: "No Playlists",
                        systemImage: "list.bullet.rectangle",
                        description: "Create a playlist first, then add videos to it."
                    )
                } else {
                    List(playlists) { playlist in
                        Button {
                            onSelect(playlist.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                    .font(.headline)
                                Text("\(playlist.videoItems.count) videos")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("Add to \(playlist.name)")
                    }
                }
            }
            .navigationTitle("Choose Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

private struct SelectedVideo: Identifiable {
    let id: String
    let localIdentifier: String
    var displayName: String
    var thumbnail: UIImage?
    var duration: TimeInterval
}

private struct SelectedVideoCell: View {
    @Binding var video: SelectedVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumbnail = video.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.15)
                        Image(systemName: "video")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 100)
            .frame(maxWidth: .infinity)
            .clipped()
            .cornerRadius(8)

            TextField("Video name", text: $video.displayName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    NavigationStack {
        VideoSelectionView()
            .environmentObject(PlaylistStore())
            .environmentObject(PhotoLibraryManager())
    }
}
