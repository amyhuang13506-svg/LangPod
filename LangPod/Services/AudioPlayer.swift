import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Playback phase within a single episode's 5-round flow
enum PlaybackPhase: Equatable {
    case englishRound(Int)   // 1, 2, 3, or 5 (final)
    case translationRound    // round 4
    case finished            // all 5 rounds done

    var label: String {
        switch self {
        case .englishRound(let n):
            if n <= 3 { return "第 \(n)/5 遍 · 英语原音" }
            return "第 5/5 遍 · 英语原音"
        case .translationRound:
            return "第 4/5 遍 · 中文翻译"
        case .finished:
            return "播放完成"
        }
    }

    var roundDisplay: String {
        switch self {
        case .englishRound(let n):
            if n <= 3 { return "第 \(n)/5 遍" }
            return "第 5/5 遍"
        case .translationRound:
            return "第 4/5 遍"
        case .finished:
            return "已完成"
        }
    }

    var roundIndex: Int {
        switch self {
        case .englishRound(let n): return n <= 3 ? n : 5
        case .translationRound: return 4
        case .finished: return 5
        }
    }
}

@Observable
class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var currentEpisode: Episode?
    var phase: PlaybackPhase = .englishRound(1)
    var progress: Double = 0
    var duration: Double = 0
    var showSubtitles = false
    var playbackRate: Float = 1.0

    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var userPaused = false

    // Queue of episodes
    var episodeQueue: [Episode] = []

    // Completion callback — more reliable than onChange for enum
    var onEpisodeFinished: (() -> Void)?

    // MARK: - Play Episode

    func playEpisode(_ episode: Episode, in queue: [Episode] = []) {
        currentEpisode = episode
        if !queue.isEmpty { episodeQueue = queue }
        phase = .englishRound(1)
        startCurrentPhase()
    }

    // MARK: - Phase Flow

    /// The 5-round sequence:
    /// 1. English × 3 (rounds 1-3)
    /// 2. Translation × 1 (round 4)
    /// 3. English × 1 (round 5)
    private func startCurrentPhase() {
        guard let episode = currentEpisode else { return }

        let urlString: String
        switch phase {
        case .englishRound:
            urlString = episode.audio.english
        case .translationRound:
            urlString = episode.audio.translationZh
        case .finished:
            return
        }

        // Try bundle file (bundle://filename format)
        if urlString.hasPrefix("bundle://") {
            let filename = String(urlString.dropFirst("bundle://".count))
            if let bundleURL = Bundle.main.url(forResource: filename, withExtension: "mp3") {
                playAudioFile(bundleURL)
                return
            }
        }

        // Then try cached file, then stream from URL
        if let cachedURL = cachedFileURL(for: urlString) {
            playAudioFile(cachedURL)
        } else if let url = URL(string: urlString) {
            // For MVP with mock data, use a placeholder silent approach
            // In production, this would stream from the URL
            playFromRemote(url)
        }

        updateNowPlayingInfo()
    }

    private func advancePhase() {
        switch phase {
        case .englishRound(1):
            phase = .englishRound(2)
            startAfterDelay(1.0)
        case .englishRound(2):
            phase = .englishRound(3)
            startAfterDelay(1.0)
        case .englishRound(3):
            phase = .translationRound
            startAfterDelay(1.0)
        case .translationRound:
            phase = .englishRound(5)
            startAfterDelay(1.0)
        case .englishRound:
            phase = .finished
            isPlaying = false
            stopTimer()
            onEpisodeFinished?()
        case .finished:
            break
        }
    }

    private func startAfterDelay(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.userPaused else { return }
            self.startCurrentPhase()
        }
    }

    // MARK: - AVAudioPlayer

    private func playAudioFile(_ url: URL) {
        stopTimer()
        player?.stop()
        print("🎵 AudioPlayer: Playing file: \(url.lastPathComponent)")

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.enableRate = true
            player?.rate = playbackRate
            player?.play()
            isPlaying = true
            userPaused = false
            duration = player?.duration ?? 0
            progress = 0
            startTimer()
        } catch {
            // Audio file not playable, advance to next phase
            advancePhase()
        }
    }

    private func playFromRemote(_ url: URL) {
        // Check if this is a placeholder mock URL
        if url.absoluteString.contains("oss.langpod.com") && !url.absoluteString.hasPrefix("http://47.") {
            // Try to download and play real audio
            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        await MainActor.run { simulatePlayback() }
                        return
                    }
                    // Cache the downloaded audio
                    let key = cacheKey(for: url.absoluteString)
                    let cachedFile = cacheDirectory.appendingPathComponent(key)
                    try data.write(to: cachedFile)
                    await MainActor.run { playAudioFile(cachedFile) }
                } catch {
                    await MainActor.run { simulatePlayback() }
                }
            }
        } else {
            // Placeholder URL, simulate playback
            simulatePlayback()
        }
    }

    /// Simulate a short playback for mock data
    private func simulatePlayback() {
        guard currentEpisode != nil else { return }
        // Short duration for testing with mock data (5 seconds per round)
        let simulatedDuration = 5.0
        duration = simulatedDuration
        progress = 0
        isPlaying = true
        userPaused = false

        stopTimer()
        let startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            self.progress = min(elapsed, self.duration)
            if elapsed >= self.duration {
                self.stopTimer()
                self.advancePhase()
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag, !userPaused else { return }
        DispatchQueue.main.async {
            self.cacheIfNeeded()
            self.advancePhase()
        }
    }

    // MARK: - Controls

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.enableRate = true
        player?.rate = rate
    }

    func togglePlayPause() {
        if let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                userPaused = true
            } else {
                player.play()
                isPlaying = true
                userPaused = false
            }
        } else {
            // Simulated playback toggle
            userPaused.toggle()
            isPlaying = !userPaused
        }
    }

    func skipToNextEpisode() {
        guard let current = currentEpisode else { return }
        guard let idx = episodeQueue.firstIndex(where: { $0.id == current.id }),
              idx + 1 < episodeQueue.count else { return }
        playEpisode(episodeQueue[idx + 1])
    }

    func skipToPreviousEpisode() {
        guard let current = currentEpisode else { return }
        guard let idx = episodeQueue.firstIndex(where: { $0.id == current.id }),
              idx > 0 else {
            // Restart current episode
            phase = .englishRound(1)
            startCurrentPhase()
            return
        }
        playEpisode(episodeQueue[idx - 1])
    }

    func skipCurrentRound() {
        stopTimer()
        player?.stop()
        advancePhase()
    }

    func seek(to time: Double) {
        player?.currentTime = time
        progress = time
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        isPlaying = false
        userPaused = false
        progress = 0
        duration = 0
    }

    // MARK: - Cache

    private var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LangPodAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheKey(for urlString: String) -> String {
        urlString.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private func cachedFileURL(for urlString: String) -> URL? {
        let file = cacheDirectory.appendingPathComponent(cacheKey(for: urlString))
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private func cacheIfNeeded() {
        // In production: move downloaded temp file to cache directory
        // Enforce 50-episode limit by removing oldest files
    }

    // MARK: - Now Playing Info (Lock Screen)

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipToNextEpisode()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipToPreviousEpisode()
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else { return }
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = episode.title
        info[MPMediaItemPropertyArtist] = "LangPod · \(phase.label)"
        info[MPMediaItemPropertyAlbumTitle] = episode.podcastLevel?.tabName ?? ""
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0

        // Artwork from thumbnail
        if let artwork = loadArtwork(for: episode) {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkEpisodeId: String?

    private func loadArtwork(for episode: Episode) -> MPMediaItemArtwork? {
        // Return cached if same episode
        if cachedArtworkEpisodeId == episode.id, let cached = cachedArtwork {
            return cached
        }

        var image: UIImage?

        if let thumbnail = episode.thumbnail {
            if thumbnail.hasPrefix("bundle://") {
                let name = String(thumbnail.dropFirst("bundle://".count))
                for ext in ["jpg", "png", "webp", "jpeg"] {
                    if let url = Bundle.main.url(forResource: name, withExtension: ext),
                       let data = try? Data(contentsOf: url) {
                        image = UIImage(data: data)
                        break
                    }
                }
            } else if let url = URL(string: thumbnail),
                      let data = try? Data(contentsOf: url) {
                image = UIImage(data: data)
            }
        }

        // Fallback: generate a simple colored image
        if image == nil {
            image = generateFallbackArtwork(for: episode)
        }

        guard let img = image else { return nil }

        let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        cachedArtwork = artwork
        cachedArtworkEpisodeId = episode.id
        return artwork
    }

    private func generateFallbackArtwork(for episode: Episode) -> UIImage? {
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors: (UIColor, UIColor) = {
                switch episode.level {
                case "easy": return (UIColor(red: 0.13, green: 0.77, blue: 0.45, alpha: 1),
                                     UIColor(red: 0.06, green: 0.73, blue: 0.51, alpha: 1))
                case "medium": return (UIColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1),
                                       UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1))
                case "hard": return (UIColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1),
                                     UIColor(red: 0.92, green: 0.35, blue: 0.05, alpha: 1))
                default: return (UIColor.gray, UIColor.darkGray)
                }
            }()

            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: [colors.0.cgColor, colors.1.cgColor] as CFArray,
                                       locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient,
                                             start: .zero,
                                             end: CGPoint(x: size.width, y: size.height),
                                             options: [])
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let p = self.player else { return }
            self.progress = p.currentTime
            self.updateNowPlayingInfo()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Init

    override init() {
        super.init()
        setupRemoteCommands()
    }
}
