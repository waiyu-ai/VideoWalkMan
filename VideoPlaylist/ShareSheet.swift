import SwiftUI
import UIKit

/// UIActivityViewController wrapper that deletes the temporary export file on teardown.
struct ShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    var title: String = "Share Playlist"

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Presented under the "Share Playlist" flow from PlaylistDetailView.
        _ = title
        return UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    static func dismantleUIViewController(
        _ uiViewController: UIActivityViewController,
        coordinator: Coordinator
    ) {
        try? FileManager.default.removeItem(at: coordinator.fileURL)
    }

    final class Coordinator {
        let fileURL: URL
        init(fileURL: URL) {
            self.fileURL = fileURL
        }
    }
}
