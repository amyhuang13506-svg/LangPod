import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Playback phase within a single episode's 5-round flow
enum PlaybackPhase: Equatable {
    case englishRound(Int)   // 1, 2, 3, or 5 (final)
    case translationRound    // round 4
    case proUpsell           // free users: pause to show 5th-round upsell
    case finished            // all rounds done

    func label(isPro: Bool = true) -> String {
        let total = isPro ? 5 : 4
        switch self {
        case .englishRound(let n):
            if n <= 3 { return "第 \(n)/\(total) 遍 · 英语原音" }
            return "第 \(total)/\(total) 遍 · 英语原音"
        case .translationRound:
            return "第 4/\(total) 遍 · 中文翻译"
        case .proUpsell:
            return "第 4/4 遍 · 播放完成"
        case .finished:
            return "播放完成"
        }
    }

    // Keep backward-compatible non-parameterized version
    var label: String { label() }

    func roundDisplay(isPro: Bool = true) -> String {
        let total = isPro ? 5 : 4
        switch self {
        case .englishRound(let n):
            if n <= 3 { return "第 \(n)/\(total) 遍" }
            return "第 \(total)/\(total) 遍"
        case .translationRound:
            return "第 4/\(total) 遍"
        case .proUpsell:
            return "已完成"
        case .finished:
            return "已完成"
        }
    }

    // Keep backward-compatible non-parameterized version
    var roundDisplay: String { roundDisplay() }

    var roundIndex: Int {
        switch self {
        case .englishRound(let n): return n <= 3 ? n : 5
        case .translationRound: return 4
        case .proUpsell: return 4
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

    /// Set by the view layer based on SubscriptionManager.isProUser
    var isProUser = false

    /// Set by the view layer from DataStore.dailyPatternIDsPlayedToday so the
    /// auto-advance logic can skip patterns a free user is no longer entitled to.
    var dailyPatternIDsPlayedToday: Set<String> = []

    /// Called when a pattern actually begins playing. View layer wires this to
    /// DataStore.recordPatternPlayed so the daily-quota counter advances and
    /// persists across app launches.
    var onPatternStarted: ((String) -> Void)?

    // Sleep timer
    var sleepTimerMinutes: Int? = nil
    var sleepTimerEndDate: Date? = nil
    private var sleepTimer: Timer?

    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    static let sleepTimerOptions: [Int] = [15, 30, 60]

    private var player: AVAudioPlayer?
    private var streamPlayer: AVPlayer?           // for remote streaming
    private var streamEndObserver: NSObjectProtocol?
    private var streamTimeObserver: Any?
    private var timer: Timer?
    private var userPaused = false
    private var recentlyPlayed: [String] = []  // track last 3 episode IDs for shuffle

    // Queue of episodes (legacy view; mirrors `playQueue` filtered to episodes only)
    var episodeQueue: [Episode] = []

    /// Unified play queue — episodes interleaved with their patterns when `playPatternsAlongside` is on.
    /// Drives skipToNext / skipToPrevious / shuffle. `episodeQueue` is kept in sync for legacy reads.
    var playQueue: [PlayItem] = []

    /// The currently-playing item (episode or pattern). Setting this also syncs `currentEpisode`
    /// for back-compat reads from view layer (HomeView, PlayerView).
    var currentPlayItem: PlayItem? {
        didSet {
            if let item = currentPlayItem {
                currentEpisode = item.parentEpisode
            }
        }
    }

    /// Whether to interleave a parent episode's patterns into the queue after its 5 rounds.
    /// Persisted; read by `buildPlayQueue()`. User can flip in Profile → 学习设置.
    var playPatternsAlongside: Bool {
        get { UserDefaults.standard.object(forKey: "playPatternsAlongside") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "playPatternsAlongside") }
    }

    // Completion callback — more reliable than onChange for enum
    var onEpisodeFinished: (() -> Void)?

    /// Gate check before playing a new episode. Return true to allow, false to block.
    var playGate: ((Episode) -> Bool)?

    /// Lazy fetcher for full episode details (script + vocabulary).
    /// Called when playing a lightweight episode.
    var episodeEnricher: ((String) async -> Episode?)?

    private var interruptionObserver: NSObjectProtocol?

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // System paused audio (phone call, alarm, etc.) — sync UI
            isPlaying = false
            userPaused = true
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // System says we can resume — do so automatically
                    if let sp = streamPlayer {
                        sp.rate = playbackRate
                    } else {
                        player?.play()
                    }
                    isPlaying = true
                    userPaused = false
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Play Episode / Pattern / Item

    /// Returns true if playback started, false if blocked by gate.
    @discardableResult
    func playEpisode(_ episode: Episode, in queue: [Episode] = []) -> Bool {
        // Gate check: only block when switching to a DIFFERENT episode
        if episode.id != currentEpisode?.id {
            if let gate = playGate, !gate(episode) {
                return false
            }
        }
        currentPlayItem = .episode(episode)  // syncs currentEpisode via didSet
        if !queue.isEmpty {
            episodeQueue = queue
            playQueue = .build(from: queue, includePatterns: playPatternsAlongside)
        } else if episodeQueue.isEmpty {
            episodeQueue = [episode]
            playQueue = .build(from: [episode], includePatterns: playPatternsAlongside)
        }
        phase = .englishRound(1)
        startCurrentPhase()

        // Lazy-load full detail (script/vocabulary) in background if missing
        if episode.isLightweight, let enricher = episodeEnricher {
            let episodeId = episode.id
            Task { @MainActor [weak self] in
                if let enriched = await enricher(episodeId) {
                    guard let self else { return }
                    if self.currentEpisode?.id == enriched.id {
                        self.currentPlayItem = .episode(enriched)
                        // Rebuild queue if needed so newly-loaded patterns join
                        if let idx = self.episodeQueue.firstIndex(where: { $0.id == enriched.id }) {
                            self.episodeQueue[idx] = enriched
                            self.playQueue = .build(from: self.episodeQueue, includePatterns: self.playPatternsAlongside)
                        }
                    }
                }
            }
        }
        return true
    }

    /// Play a pattern (single-pass; no 5-round loop).
    /// Enforces PatternAccessGate as a defensive safety net — if a caller
    /// forgets to pre-check, we bail out here rather than silently play a
    /// locked pattern. Callers should still gate upstream so they can surface
    /// the paywall; when this returns false, callers should too.
    /// Fires `onPatternStarted` so DataStore can record the play for quota.
    @discardableResult
    func playPattern(_ pattern: Pattern, parentEpisode: Episode, in queue: [PlayItem] = []) -> Bool {
        let allowed = PatternAccessGate.canAccess(
            pattern: pattern,
            parentEpisode: parentEpisode,
            isPro: isProUser,
            playedTodayIds: dailyPatternIDsPlayedToday
        )
        guard allowed else { return false }

        currentPlayItem = .pattern(pattern, parentEpisode: parentEpisode)
        if !queue.isEmpty {
            playQueue = queue
        } else if playQueue.isEmpty {
            playQueue = [.pattern(pattern, parentEpisode: parentEpisode)]
        }
        startPatternPlayback(pattern)
        onPatternStarted?(pattern.id)
        return true
    }

    /// Unified entry — dispatches to playEpisode / playPattern based on item type.
    @discardableResult
    func playItem(_ item: PlayItem) -> Bool {
        switch item {
        case .episode(let ep):
            return playEpisode(ep)
        case .pattern(let p, let parent):
            return playPattern(p, parentEpisode: parent)
        }
    }

    /// Rebuild playQueue from current episodeQueue, respecting current `playPatternsAlongside`.
    /// Call after toggling the setting.
    func rebuildQueueAfterSettingChange() {
        if !episodeQueue.isEmpty {
            playQueue = .build(from: episodeQueue, includePatterns: playPatternsAlongside)
        }
    }

    private func startPatternPlayback(_ pattern: Pattern) {
        let urlString = pattern.audioUrl

        if urlString.hasPrefix("bundle://") {
            let filename = String(urlString.dropFirst("bundle://".count))
            if let bundleURL = Bundle.main.url(forResource: filename, withExtension: "mp3") {
                playAudioFile(bundleURL)
                updateNowPlayingInfo()
                return
            }
        }

        if let cachedURL = cachedFileURL(for: urlString) {
            playAudioFile(cachedURL)
        } else if let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" {
            playFromRemote(url)
        } else {
            // No valid URL — skip to next item
            skipToNext()
        }

        updateNowPlayingInfo()
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
        case .proUpsell, .finished:
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
            if isProUser {
                phase = .englishRound(5)
                startAfterDelay(1.0)
            } else {
                // Free users: show Pro upsell for 5th round, then finish
                phase = .proUpsell
                isPlaying = false
                stopTimer()
                // Auto-advance to finished after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self, self.phase == .proUpsell else { return }
                    self.finishCurrentEpisode()
                }
            }
        case .proUpsell:
            // Manual advance (user tapped skip or timeout)
            finishCurrentEpisode()
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

    private func finishCurrentEpisode() {
        if playOrder == .repeatOne {
            phase = .englishRound(1)
            startAfterDelay(1.0)
            return
        }
        phase = .finished
        isPlaying = false
        stopTimer()
        onEpisodeFinished?()
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
        stopStreamPlayer()
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
        guard url.scheme == "http" || url.scheme == "https" else {
            simulatePlayback()
            return
        }

        // Use AVPlayer for streaming — starts playback within ~500ms
        // (AVAudioPlayer requires full download first, which takes 2-4s)
        stopStreamPlayer()
        stopTimer()
        player?.stop()
        player = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {}

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.rate = playbackRate
        streamPlayer = avPlayer

        isPlaying = true
        userPaused = false
        progress = 0
        duration = 0

        // Observe completion
        streamEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.cacheIfNeeded()
            self?.handleItemFinished()
        }

        // Observe time progress
        streamTimeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.progress = time.seconds
            // Update duration once available
            if let d = self.streamPlayer?.currentItem?.duration, d.isNumeric, d.seconds > 0 {
                self.duration = d.seconds
            }
            self.updateNowPlayingInfo()
        }

        // Background: download for caching (next play will use instant cached path)
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { return }
                let key = cacheKey(for: url.absoluteString)
                let cachedFile = cacheDirectory.appendingPathComponent(key)
                try data.write(to: cachedFile)
            } catch {}
        }
    }

    private func stopStreamPlayer() {
        if let obs = streamEndObserver {
            NotificationCenter.default.removeObserver(obs)
            streamEndObserver = nil
        }
        if let obs = streamTimeObserver {
            streamPlayer?.removeTimeObserver(obs)
            streamTimeObserver = nil
        }
        streamPlayer?.pause()
        streamPlayer = nil
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cacheIfNeeded()
            self.handleItemFinished()
        }
    }

    /// Routing from low-level audio finish → either advance the 5-round phase
    /// (episodes) or skip to the next queue item (patterns).
    private func handleItemFinished() {
        if case .pattern(let pattern, let parent) = currentPlayItem {
            Analytics.track(.patternListenComplete, params: [
                "pattern_id": pattern.id,
                "episode_id": parent.id,
            ])
            // Patterns are single-pass: just go to the next queue item.
            // repeatOne is honored by replaying the same pattern.
            if playOrder == .repeatOne {
                startPatternPlayback(pattern)
                return
            }
            skipToNext()
            return
        }
        advancePhase()
    }

    // MARK: - Controls

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if let player {
            player.enableRate = true
            player.rate = rate
        }
        if let sp = streamPlayer, sp.rate != 0 {
            sp.rate = rate
        }
    }

    func togglePlayPause() {
        if let sp = streamPlayer {
            if sp.rate != 0 {
                sp.pause()
                isPlaying = false
                userPaused = true
            } else {
                sp.rate = playbackRate
                isPlaying = true
                userPaused = false
            }
        } else if let player {
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
            userPaused.toggle()
            isPlaying = !userPaused
        }
    }

    /// True if this user is entitled to play a given queue item right now.
    /// Episodes are always "accessible" here (episode-level quota is gated
    /// separately, before the queue is built). Patterns go through
    /// PatternAccessGate so historical + over-quota ones are skipped during
    /// sequential auto-advance.
    private func isItemAccessible(_ item: PlayItem) -> Bool {
        switch item {
        case .episode:
            return true
        case .pattern(let p, let parent):
            return PatternAccessGate.canAccess(
                pattern: p,
                parentEpisode: parent,
                isPro: isProUser,
                playedTodayIds: dailyPatternIDsPlayedToday
            )
        }
    }

    /// Skip to next item in playQueue (works for both episodes and patterns).
    /// shuffle treats "episode + its patterns" as a unit.
    @discardableResult
    func skipToNext() -> Bool {
        guard let current = currentPlayItem else { return false }
        if playQueue.isEmpty { playQueue = [current] }

        // Track recently-played PARENT episode (not pattern) for shuffle dedup
        let currentParentId = current.parentEpisode.id
        if !recentlyPlayed.contains(currentParentId) {
            recentlyPlayed.append(currentParentId)
            if recentlyPlayed.count > 3 { recentlyPlayed.removeFirst() }
        }

        let nextItem: PlayItem?
        switch playOrder {
        case .sequential:
            guard let idx = playQueue.firstIndex(where: { $0.id == current.id }) else { return false }
            // Walk forward until we hit an item this user can access. Patterns a
            // free user can't play (historical, or over daily quota) are silently
            // skipped so mixed playback doesn't stall on a locked item.
            var step = 1
            var candidate: PlayItem?
            while step <= playQueue.count {
                let probe = playQueue[(idx + step) % playQueue.count]
                if isItemAccessible(probe) { candidate = probe; break }
                step += 1
            }
            nextItem = candidate
        case .shuffle:
            // Pick a different episode at random; jump to its first occurrence in playQueue
            // (patterns ride along because they're inserted right after their parent).
            let allEpisodeIds = playQueue.compactMap { item -> String? in
                if case .episode(let ep) = item { return ep.id }
                return nil
            }
            let uniqueIds = Array(Set(allEpisodeIds))
            let candidates = uniqueIds.filter { !recentlyPlayed.contains($0) }
            let chosenId = candidates.randomElement() ?? uniqueIds.randomElement()
            if let chosenId,
               let idx = playQueue.firstIndex(where: {
                   if case .episode(let ep) = $0 { return ep.id == chosenId }
                   return false
               }) {
                nextItem = playQueue[idx]
            } else {
                nextItem = nil
            }
        case .repeatOne:
            nextItem = current  // includes patterns: same item replays
        }

        if let next = nextItem {
            return playItem(next)
        }
        return false
    }

    /// Restart current item, or step back one in playQueue.
    @discardableResult
    func skipToPrevious() -> Bool {
        guard let current = currentPlayItem else { return false }
        guard let idx = playQueue.firstIndex(where: { $0.id == current.id }), idx > 0 else {
            // Restart current item
            switch current {
            case .episode:
                phase = .englishRound(1)
                startCurrentPhase()
            case .pattern(let p, _):
                startPatternPlayback(p)
            }
            return true
        }
        return playItem(playQueue[idx - 1])
    }

    /// Back-compat aliases — call sites in PlayerView/HomeView use the *Episode names.
    @discardableResult
    func skipToNextEpisode() -> Bool { skipToNext() }

    @discardableResult
    func skipToPreviousEpisode() -> Bool { skipToPrevious() }

    func skipCurrentRound() {
        stopTimer()
        stopStreamPlayer()
        player?.stop()
        advancePhase()
    }

    func seek(to time: Double) {
        if streamPlayer != nil {
            streamPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        } else {
            player?.currentTime = time
        }
        progress = time
    }

    func stop() {
        stopTimer()
        stopStreamPlayer()
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
        guard let item = currentPlayItem else { return }
        var info = [String: Any]()

        switch item {
        case .episode(let episode):
            info[MPMediaItemPropertyTitle] = episode.title
            info[MPMediaItemPropertyArtist] = "Castlingo · \(phase.label)"
            info[MPMediaItemPropertyAlbumTitle] = episode.podcastLevel?.tabName ?? ""
            if let artwork = loadArtwork(for: episode) {
                info[MPMediaItemPropertyArtwork] = artwork
            }
        case .pattern(let pattern, _):
            info[MPMediaItemPropertyTitle] = pattern.template
            info[MPMediaItemPropertyArtist] = "Castlingo · 今日句型讲解"
            info[MPMediaItemPropertyAlbumTitle] = pattern.scene
            if let artwork = patternArtwork(for: pattern) {
                info[MPMediaItemPropertyArtwork] = artwork
            }
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private var cachedPatternArtwork: MPMediaItemArtwork?
    private var cachedPatternArtworkId: String?

    /// Generate a beige card artwork for a pattern (no album cover; pattern is text content).
    private func patternArtwork(for pattern: Pattern) -> MPMediaItemArtwork? {
        if cachedPatternArtworkId == pattern.id, let cached = cachedPatternArtwork {
            return cached
        }
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            // Background — beige / scene-tinted
            let hex = pattern.thumbnailColor ?? "#E8DCC4"
            let bg = uiColor(hex: hex)
            bg.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Template text — large, centered
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .semibold),
                .foregroundColor: UIColor(white: 0.15, alpha: 1),
                .paragraphStyle: para,
            ]
            let textRect = CGRect(x: 32, y: 200, width: size.width - 64, height: 240)
            (pattern.template as NSString).draw(in: textRect, withAttributes: attrs)
        }
        let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        cachedPatternArtwork = artwork
        cachedPatternArtworkId = pattern.id
        return artwork
    }

    private func uiColor(hex: String) -> UIColor {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else {
            return UIColor(red: 0.91, green: 0.86, blue: 0.77, alpha: 1)  // default beige
        }
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1)
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
            } else {
                // Remote thumbnail: NEVER block main thread.
                // Try synchronous disk-cache hit only; otherwise kick off async fetch
                // and use fallback for now (lock screen will refresh when ready).
                if let cached = ImageCache.shared.diskHitSync(for: thumbnail) {
                    image = cached
                } else {
                    fetchRemoteArtworkAsync(for: episode, urlString: thumbnail)
                }
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

    /// Background fetch the remote thumbnail; once ready, refresh now-playing info.
    private func fetchRemoteArtworkAsync(for episode: Episode, urlString: String) {
        let episodeId = episode.id
        Task { @MainActor [weak self] in
            guard let img = await ImageCache.shared.image(for: urlString) else { return }
            guard let self else { return }
            // Only refresh if we're still on the same episode
            guard self.currentEpisode?.id == episodeId else { return }
            let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            self.cachedArtwork = artwork
            self.cachedArtworkEpisodeId = episodeId
            // Refresh now-playing info with the loaded artwork
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
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
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
    }

    deinit {
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
