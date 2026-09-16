import SwiftUI

@main
struct VideoPlaylistApp: App {
    @StateObject private var playlistStore = PlaylistStore()
    @StateObject private var photoManager = PhotoLibraryManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playlistStore)
                .environmentObject(photoManager)
        }
    }
}
