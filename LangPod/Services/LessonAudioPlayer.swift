import AVFoundation
import CryptoKit
import Foundation

/// 词汇小课堂发音播放器：播放 ElevenLabs 预生成的 mp3（下载 + 沙盒缓存），
/// 拿不到音频（离线且未缓存 / 字段为空）时调用 fallback（系统 TTS 兜底）。
final class LessonAudioPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = LessonAudioPlayer()

    private var player: AVAudioPlayer?
    private var playTask: Task<Void, Never>?
    private var segmentStopTask: Task<Void, Never>?

    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CastlingoLessonAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 播放一段发音。urlString 为空或获取失败时执行 fallback。
    func play(_ urlString: String?, fallback: @escaping () -> Void) {
        play(urlString, from: nil, to: nil, fallback: fallback)
    }

    /// 截段播放：从长音频（如句型讲解 mp3）里播 [from, to] 区间。
    /// 用于句型例句发音——例句在讲解音频里被完整朗读过且有时间戳，零成本复用。
    func play(_ urlString: String?, from start: Double?, to end: Double?, fallback: @escaping () -> Void) {
        playTask?.cancel()
        segmentStopTask?.cancel()
        guard let urlString, !urlString.isEmpty else {
            debugLog("empty url → fallback")
            fallback()
            return
        }
        debugLog("play: \(urlString.suffix(50)) [\(start ?? 0)-\(end ?? 0)]")
        playTask = Task { [weak self] in
            guard let self else { return }
            guard let file = await self.localFile(for: urlString), !Task.isCancelled else {
                self.debugLog("no local file → fallback")
                if !Task.isCancelled { await MainActor.run { fallback() } }
                return
            }
            await MainActor.run {
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .duckOthers)
                    try AVAudioSession.sharedInstance().setActive(true)
                    self.player?.stop()
                    let player = try AVAudioPlayer(contentsOf: file)
                    player.delegate = self
                    if let start, start > 0 {
                        player.currentTime = start
                    }
                    let ok = player.play()
                    self.player = player
                    self.debugLog("player.play() = \(ok), duration \(player.duration)")
                    if !ok {
                        fallback()
                        return
                    }
                    // 截段：到 end 时停（留 0.15s 尾巴避免吞掉最后一个音）
                    if let end, end > (start ?? 0) {
                        let seconds = end - (start ?? 0) + 0.15
                        self.segmentStopTask = Task { [weak self] in
                            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                            guard !Task.isCancelled else { return }
                            await MainActor.run { self?.player?.stop() }
                        }
                    }
                } catch {
                    self.debugLog("play error: \(error) → fallback")
                    fallback()
                }
            }
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[LessonAudio] \(message)")
        #endif
    }

    /// 进课堂时预取全部发音（静默、逐个、失败忽略），保证点击零延迟。
    func prefetch(_ urlStrings: [String]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for urlString in urlStrings where !urlString.isEmpty {
                _ = await self.localFile(for: urlString)
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    // MARK: - Cache

    private func localFile(for urlString: String) async -> URL? {
        let name = Self.cacheKey(urlString) + ".mp3"
        let file = cacheDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) {
            return file
        }
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                return nil
            }
            try data.write(to: file)
            return file
        } catch {
            return nil
        }
    }

    private static func cacheKey(_ urlString: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(urlString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
