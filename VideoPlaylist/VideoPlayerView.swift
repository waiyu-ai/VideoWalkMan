import SwiftUI
import AVKit
import AVFoundation
import Photos
import Combine
import OSLog

private let playbackLogger = Logger(subsystem: "com.example.VideoPlaylist", category: "Playback")

struct VideoPlayerView: View {
    var playlist: Playlist

    @EnvironmentObject var store: PlaylistStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @StateObject private var photoManager = PhotoLibraryManager()

    @State private var player: AVQueuePlayer?
    @State private var orderedItems: [VideoItem] = []
    @State private var playerItems: [AVPlayerItem] = []
    @State private var queueStartIndex: Int = 0
    @State private var currentIndex: Int = 0
    @State private var isPlaying = false
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var playbackSpeed: Float = 1.0
    @State private var sleepRemainingSeconds: Int = 0
    @State private var sleepTimerActive = false
    @State private var endObserver: AnyCancellable?
    @State private var currentItemObserver: NSKeyValueObservation?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var readyObserver: NSKeyValueObservation?
    @State private var didApplyResume = false
    @State private var hasResolvedOrder = false
    @State private var isPlayerReady = false

    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    private let sleepTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var totalCount: Int { orderedItems.count }

    private var currentLocalIdentifier: String? {
        guard orderedItems.indices.contains(currentIndex) else { return nil }
        return orderedItems[currentIndex].localIdentifier
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading videos…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if loadFailed {
                VStack(spacing: 16) {
                    Text("Unable to load videos from Photos.")
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await prepareAndPlay(startingAt: 0, applyResume: true, resetOrder: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Retry loading playlist")
                }
                .padding()
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()

                if !isPlayerReady {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Preparing playback")
                }
            }

            if player != nil, !isLoading, !loadFailed, isPlayerReady {
                controlsOverlay
            }
        }
        .onAppear {
            Task { await prepareAndPlay(startingAt: 0, applyResume: true, resetOrder: true) }
        }
        .onDisappear {
            persistResumePosition()
            tearDownPlayer()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active {
                persistResumePosition()
            }
        }
        .onReceive(sleepTicker) { _ in
            guard sleepTimerActive else { return }
            if sleepRemainingSeconds <= 1 {
                player?.pause()
                isPlaying = false
                persistResumePosition()
                sleepTimerActive = false
                sleepRemainingSeconds = 0
            } else {
                sleepRemainingSeconds -= 1
            }
        }
    }

    // MARK: - Overlay

    private var controlsOverlay: some View {
        VStack {
            topBar
            Spacer()
            if sleepTimerActive, sleepRemainingSeconds > 0 {
                Text(sleepCountdownLabel)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Sleep timer remaining \(sleepCountdownLabel)")
            }
            transportBar
                .padding(.bottom, 40)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                persistResumePosition()
                tearDownPlayer()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .accessibilityLabel("Close player")

            Spacer()

            Text("\(displayIndex) of \(totalCount)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel("Video \(displayIndex) of \(totalCount)")

            Spacer()

            speedButton
            sleepTimerMenu
        }
        .padding()
    }

    private var displayIndex: Int {
        totalCount == 0 ? 0 : min(currentIndex + 1, totalCount)
    }

    private var transportBar: some View {
        HStack(spacing: 36) {
            Button {
                playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .disabled(totalCount <= 1 || currentIndex <= 0)
            .accessibilityLabel("Previous video")

            Button {
                togglePlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button {
                playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .disabled(totalCount <= 1 || currentIndex >= totalCount - 1)
            .accessibilityLabel("Next video")
        }
    }

    private var speedButton: some View {
        Button {
            cycleSpeed()
        } label: {
            Text(speedLabel(playbackSpeed))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.2), in: Capsule())
        }
        .accessibilityLabel("Playback speed \(speedLabel(playbackSpeed))")
    }

    private var sleepTimerMenu: some View {
        Menu {
            Button("Off") {
                sleepTimerActive = false
                sleepRemainingSeconds = 0
            }
            Button("5 minutes") { startSleepTimer(minutes: 5) }
            Button("15 minutes") { startSleepTimer(minutes: 15) }
            Button("30 minutes") { startSleepTimer(minutes: 30) }
            Button("60 minutes") { startSleepTimer(minutes: 60) }
        } label: {
            Image(systemName: "moon.zzz")
                .font(.title3)
                .foregroundStyle(.white)
                .padding(8)
        }
        .accessibilityLabel("Sleep timer")
    }

    private var sleepCountdownLabel: String {
        String(format: "%d:%02d", sleepRemainingSeconds / 60, sleepRemainingSeconds % 60)
    }

    // MARK: - Load queue

    @MainActor
    private func prepareAndPlay(startingAt startIndex: Int, applyResume: Bool, resetOrder: Bool) async {
        isLoading = true
        loadFailed = false
        didApplyResume = false
        tearDownPlayer()

        if resetOrder || !hasResolvedOrder {
            switch store.playbackMode {
            case .shuffle:
                orderedItems = playlist.videoItems.shuffled()
            case .normal, .repeatAll, .repeatOne:
                orderedItems = playlist.videoItems
            }
            hasResolvedOrder = true
        }

        guard !orderedItems.isEmpty else {
            isLoading = false
            loadFailed = true
            playbackLogger.error("Playlist \(self.playlist.name, privacy: .public) has no videos")
            return
        }

        let clampedStart = min(max(0, startIndex), orderedItems.count - 1)
        let playbackSlice = Array(orderedItems[clampedStart...])

        let identifiers = playbackSlice.map(\.localIdentifier)
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assetByID: [String: PHAsset] = [:]
        assetByID.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            assetByID[asset.localIdentifier] = asset
        }

        var builtItems: [AVPlayerItem] = []
        builtItems.reserveCapacity(playbackSlice.count)

        for item in playbackSlice {
            guard let asset = assetByID[item.localIdentifier] else {
                playbackLogger.error("Missing PHAsset for \(item.localIdentifier, privacy: .public)")
                continue
            }
            do {
                let avAsset = try await photoManager.getAVAsset(from: asset)
                builtItems.append(AVPlayerItem(asset: avAsset))
            } catch {
                playbackLogger.error(
                    "Failed AVAsset for \(item.localIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        guard !builtItems.isEmpty else {
            isLoading = false
            loadFailed = true
            playbackLogger.error("All items failed to load for playlist \(self.playlist.name, privacy: .public)")
            return
        }

        // If some failed, playerItems may be shorter than the slice; index mapping uses queueStartIndex + offset.
        queueStartIndex = clampedStart
        currentIndex = clampedStart
        playerItems = builtItems

        let queuePlayer = AVQueuePlayer(items: builtItems)
        player = queuePlayer
        isPlayerReady = false
        attachObservers(to: queuePlayer)
        observeReadyToPlay(for: builtItems[0])
        isLoading = false

        if applyResume, clampedStart == 0 {
            applyResumeIfNeeded(on: queuePlayer, firstItem: builtItems[0])
        }

        queuePlayer.play()
        isPlaying = true
        applyPlaybackSpeed()
    }

    // MARK: - Transport

    private func togglePlayPause() {
        guard let player else { return }
        if isPlaying || player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
            persistResumePosition()
        } else {
            player.play()
            isPlaying = true
            applyPlaybackSpeed()
        }
    }

    private func playNext() {
        guard let player, currentIndex < totalCount - 1 else { return }
        player.advanceToNextItem()
        currentIndex += 1
        applyPlaybackSpeed()
        isPlaying = true
    }

    private func playPrevious() {
        guard currentIndex > 0 else { return }
        Task {
            await prepareAndPlay(startingAt: currentIndex - 1, applyResume: false, resetOrder: false)
            if let player {
                await player.seek(to: .zero)
                player.play()
                isPlaying = true
                applyPlaybackSpeed()
            }
        }
    }

    private func cycleSpeed() {
        if let index = speedOptions.firstIndex(of: playbackSpeed) {
            playbackSpeed = speedOptions[(index + 1) % speedOptions.count]
        } else {
            playbackSpeed = 1.0
        }
        applyPlaybackSpeed()
    }

    private func applyPlaybackSpeed() {
        guard let player, isPlaying || player.timeControlStatus == .playing else { return }
        player.rate = playbackSpeed
    }

    private func speedLabel(_ rate: Float) -> String {
        switch rate {
        case 0.5: return "0.5x"
        case 0.75: return "0.75x"
        case 1.0: return "1x"
        case 1.25: return "1.25x"
        case 1.5: return "1.5x"
        case 2.0: return "2x"
        default: return String(format: "%.2gx", rate)
        }
    }

    private func startSleepTimer(minutes: Int) {
        sleepRemainingSeconds = minutes * 60
        sleepTimerActive = true
    }

    // MARK: - Resume

    private func observeReadyToPlay(for item: AVPlayerItem) {
        readyObserver?.invalidate()
        readyObserver = item.observe(\.status, options: [.new, .initial]) { item, _ in
            Task { @MainActor in
                if item.status == .readyToPlay {
                    self.isPlayerReady = true
                } else if item.status == .failed {
                    self.isPlayerReady = false
                    playbackLogger.error("First AVPlayerItem failed to become ready")
                }
            }
        }
    }

    private func applyResumeIfNeeded(on queuePlayer: AVQueuePlayer, firstItem: AVPlayerItem) {
        guard let identifier = orderedItems.first?.localIdentifier,
              let seconds = store.resumePosition(for: identifier),
              seconds > 0 else { return }

        statusObserver?.invalidate()
        statusObserver = firstItem.observe(\.status, options: [.new, .initial]) { item, _ in
            Task { @MainActor in
                guard item.status == .readyToPlay, !self.didApplyResume else { return }
                self.didApplyResume = true
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                await queuePlayer.seek(to: time)
                queuePlayer.play()
                self.isPlaying = true
                self.applyPlaybackSpeed()
            }
        }
    }

    private func persistResumePosition() {
        guard let player, let identifier = currentLocalIdentifier else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        store.saveResumePosition(for: identifier, seconds: seconds)
    }

    // MARK: - Observers / repeat

    private func attachObservers(to queuePlayer: AVQueuePlayer) {
        tearDownObserversOnly()

        currentItemObserver = queuePlayer.observe(\.currentItem, options: [.new]) { player, _ in
            Task { @MainActor in
                self.syncCurrentIndex(with: player)
                self.applyPlaybackSpeed()
            }
        }

        endObserver = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: RunLoop.main)
            .sink { notification in
                self.handleItemDidPlayToEnd(notification)
            }
    }

    private func syncCurrentIndex(with player: AVQueuePlayer) {
        guard let current = player.currentItem,
              let offset = playerItems.firstIndex(where: { $0 === current }) else { return }
        currentIndex = min(queueStartIndex + offset, max(totalCount - 1, 0))
    }

    private func handleItemDidPlayToEnd(_ notification: Notification) {
        guard let player,
              let ended = notification.object as? AVPlayerItem,
              playerItems.contains(where: { $0 === ended }) || player.currentItem === ended else {
            return
        }

        switch store.playbackMode {
        case .repeatOne:
            Task { @MainActor in
                await ended.seek(to: .zero)
                await player.seek(to: .zero)
                player.play()
                isPlaying = true
                applyPlaybackSpeed()
            }
        case .repeatAll:
            let atEnd = currentIndex >= totalCount - 1 || player.items().count <= 1
            if atEnd {
                Task { await prepareAndPlay(startingAt: 0, applyResume: false, resetOrder: false) }
            } else {
                currentIndex = min(currentIndex + 1, totalCount - 1)
                applyPlaybackSpeed()
            }
        case .normal, .shuffle:
            if currentIndex < totalCount - 1 {
                currentIndex += 1
            }
            persistResumePosition()
            applyPlaybackSpeed()
        }
    }

    private func tearDownObserversOnly() {
        currentItemObserver?.invalidate()
        currentItemObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        readyObserver?.invalidate()
        readyObserver = nil
        endObserver?.cancel()
        endObserver = nil
    }

    private func tearDownPlayer() {
        tearDownObserversOnly()
        player?.pause()
        player?.removeAllItems()
        player = nil
        playerItems = []
        isPlaying = false
        isPlayerReady = false
    }
}
