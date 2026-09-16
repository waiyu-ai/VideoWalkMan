import SwiftUI
import UIKit
import Photos
import Foundation

struct ContentView: View {
    @EnvironmentObject private var store: PlaylistStore
    @EnvironmentObject private var photoManager: PhotoLibraryManager

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("lastPlayedPlaylistID") private var lastPlayedPlaylistID = ""

    @State private var selectedTab = 0

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView {
                    hasSeenOnboarding = true
                }
            } else if isPhotosAccessBlocked {
                PhotosAccessBlockedView()
            } else {
                mainTabs
            }
        }
        .task {
            if photoManager.authorizationStatus == .notDetermined {
                photoManager.requestAuthorization()
            }
        }
    }

    private var isPhotosAccessBlocked: Bool {
        let status = photoManager.authorizationStatus
        return status == .denied || status == .restricted
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PlaylistListView()
            }
            .tabItem {
                Label("Playlists", systemImage: "list.bullet")
            }
            .badge(store.playlists.count)
            .tag(0)
            .accessibilityLabel("Playlists tab, \(store.playlists.count) playlists")

            NavigationStack {
                VideoSelectionView()
            }
            .tabItem {
                Label("Select Videos", systemImage: "plus.rectangle.on.rectangle")
            }
            .tag(1)
            .accessibilityLabel("Select Videos tab")

            NavigationStack {
                NowPlayingTabView(lastPlayedPlaylistID: lastPlayedPlaylistID)
            }
            .tabItem {
                Label("Now Playing", systemImage: "play.circle")
            }
            .tag(2)
            .accessibilityLabel("Now Playing tab")
        }
    }
}

private struct NowPlayingTabView: View {
    let lastPlayedPlaylistID: String

    @EnvironmentObject private var store: PlaylistStore

    private var lastPlaylist: Playlist? {
        guard let id = UUID(uuidString: lastPlayedPlaylistID) else { return nil }
        return store.playlists.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let lastPlaylist, !lastPlaylist.videoItems.isEmpty {
                VideoPlayerView(playlist: lastPlaylist)
            } else {
                AppUnavailableView(
                    title: "Nothing Playing",
                    systemImage: "play.circle",
                    description: "Play a playlist from the Playlists tab to see it here."
                )
            }
        }
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhotosAccessBlockedView: View {
    var body: some View {
        AppUnavailableView(
            title: "Photos Access Needed",
            systemImage: "photo.on.rectangle.angled",
            description: "VideoPlaylist needs access to your Photos library so you can pick videos for playlists."
        ) {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Open Settings")
        }
    }
}

struct OnboardingView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Welcome to VideoPlaylist")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                onboardingRow(
                    symbol: "list.bullet",
                    title: "Playlists",
                    detail: "Create playlists and organize your videos."
                )
                onboardingRow(
                    symbol: "plus.rectangle.on.rectangle",
                    title: "Select Videos",
                    detail: "Pick clips from Photos and add them to a playlist."
                )
                onboardingRow(
                    symbol: "play.circle",
                    title: "Now Playing",
                    detail: "Jump back into the playlist you played last."
                )
                onboardingRow(
                    symbol: "hand.raised",
                    title: "Photos Permission",
                    detail: "You’ll be asked for Photos access so the app can load your videos."
                )
            }
            .padding(.horizontal)

            Spacer()

            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Get Started")
            .padding(.bottom, 32)
        }
        .padding()
    }

    private func onboardingRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// ContentUnavailableView-compatible placeholder for iOS 16+.
struct AppUnavailableView<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String
    @ViewBuilder var actions: () -> Actions

    init(
        title: String,
        systemImage: String,
        description: String,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(description)
            } actions: {
                actions()
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.bold())
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                actions()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PlaylistStore())
        .environmentObject(PhotoLibraryManager())
}
