import AVFoundation
import CryptoKit
import Foundation

/// 词汇小课堂发音播放器：播放 ElevenLabs 预生成的 mp3（下载 + 沙盒缓存），
/// 拿不到音频（离线且未缓存 / 字段为空）时调用 fallback（系统 TTS 兜底）。
final class LessonAudioPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = LessonAudioPlayer()

    private var player: AVAudioPlayer?
    private var playTask: Task<Void, Never>?

    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CastlingoLessonAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 播放一段发音。urlString 为空或获取失败时执行 fallback。
    func play(_ urlString: String?, fallback: @escaping () -> Void) {
        playTask?.cancel()
        guard let urlString, !urlString.isEmpty else {
            fallback()
            return
        }
        playTask = Task { [weak self] in
            guard let self else { return }
            guard let file = await self.localFile(for: urlString), !Task.isCancelled else {
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
                    player.play()
                    self.player = player
                } catch {
                    fallback()
                }
            }
        }
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
