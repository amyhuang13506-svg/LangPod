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

/// Play order mode
enum PlayOrder: String, CaseIterable {
    case sequential  // 列表循环
    case shuffle     // 随机播放
    case repeatOne   // 单集循环

    var icon: String {
        switch self {
        case .sequential: return "repeat"
        case .shuffle: return "shuffle"
        case .repeatOne: return "repeat.1"
        }
    }

    var label: String {
        switch self {
        case .sequential: return "列表循环"
        case .shuffle: return "随机播放"
        case .repeatOne: return "单集循环"
        }
    }

    var next: PlayOrder {
        switch self {
        case .sequential: return .shuffle
        case .shuffle: return .repeatOne
        case .repeatOne: return .sequential
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
    var playOrder: PlayOrder = PlayOrder(rawValue: UserDefaults.standard.string(forKey: "playOrder") ?? "") ?? .sequential {
        didSet { UserDefaults.standard.set(playOrder.rawValue, forKey: "playOrder") }
    }

    // Sleep timer
    var sleepTimerMinutes: Int? = nil
    var sleepTimerEndDate: Date? = nil
    private var sleepTimer: Timer?

    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    static let sleepTimerOptions: [Int] = [15, 30, 60]

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var userPaused = false
    private var recentlyPlayed: [String] = []  // track last 3 episode IDs for shuffle

    // Queue of episodes
    var episodeQueue: [Episode] = []

    // Completion callback — more reliable than onChange for enum
    var onEpisodeFinished: (() -> Void)?

    // MARK: - Play Episode

    func playEpisode(_ episode: Episode, in queue: [Episode] = []) {
        currentEpisode = episode
        if !queue.isEmpty { episodeQueue = queue }
        if episodeQueue.isEmpty { episodeQueue = [episode] }
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

        // Then try cached file, then download from URL
        if let cachedURL = cachedFileURL(for: urlString) {
            playAudioFile(cachedURL)
        } else if let url = URL(string: urlString) {
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
            // Single episode repeat: restart from round 1 instead of finishing
            if playOrder == .repeatOne {
                phase = .englishRound(1)
                startAfterDelay(1.0)
                return
            }
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

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
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
        // Try to download and play any real HTTP(S) URL
        if url.scheme == "http" || url.scheme == "https" {
            // Show loading state immediately so UI doesn't feel stuck
            isPlaying = true
            progress = 0
            duration = 0

            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        await MainActor.run { simulatePlayback() }
                        return
                    }
                    let key = cacheKey(for: url.absoluteString)
                    let cachedFile = cacheDirectory.appendingPathComponent(key)
                    try data.write(to: cachedFile)
                    await MainActor.run { playAudioFile(cachedFile) }
                } catch {
                    await MainActor.run { simulatePlayback() }
                }
            }
        } else {
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
        guard !userPaused else { return }
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
        guard let current = currentEpisode, !episodeQueue.isEmpty else { return }

        // Track recently played for shuffle dedup
        if !recentlyPlayed.contains(current.id) {
            recentlyPlayed.append(current.id)
            if recentlyPlayed.count > 3 { recentlyPlayed.removeFirst() }
        }

        let nextEpisode: Episode?
        switch playOrder {
        case .sequential:
            guard let idx = episodeQueue.firstIndex(where: { $0.id == current.id }) else { return }
            let nextIdx = (idx + 1) % episodeQueue.count
            nextEpisode = episodeQueue[nextIdx]
        case .shuffle:
            let candidates = episodeQueue.filter { !recentlyPlayed.contains($0.id) }
            nextEpisode = candidates.randomElement() ?? episodeQueue.randomElement()
        case .repeatOne:
            nextEpisode = current
        }

        if let next = nextEpisode {
            playEpisode(next)
        }
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

    // MARK: - Sleep Timer

    func setSleepTimer(_ minutes: Int) {
        cancelSleepTimer()
        sleepTimerMinutes = minutes
        sleepTimerEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let endDate = self.sleepTimerEndDate else { return }
            if Date() >= endDate {
                self.stop()
                self.cancelSleepTimer()
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerMinutes = nil
        sleepTimerEndDate = nil
    }

    var sleepTimerRemainingText: String? {
        guard let endDate = sleepTimerEndDate else { return nil }
        let remaining = Int(endDate.timeIntervalSinceNow)
        guard remaining > 0 else { return nil }
        return "\(remaining / 60):\(String(format: "%02d", remaining % 60))"
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
