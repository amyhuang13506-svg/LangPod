import Foundation

/// API service for fetching episodes from the server.
/// Falls back to local mock data when the server is unreachable.
///
/// 多语言：所有内容 URL / 缓存文件名统一拼 `ContentLanguage.current` 的后缀
/// （zh 为空串 → 与历史行为逐字节一致；ko 起为 "_ko"）。
actor APIService {
    static let shared = APIService()

    /// Origin OSS host — what the pipeline bakes into index.json URLs.
    /// Used to rewrite embedded audio/thumbnail URLs to the configured host.
    private static let originOSSHost = "castlingo.oss-ap-southeast-1.aliyuncs.com"

    /// 内容语言的文件后缀（"" / "_ko" / …），进程内固定。
    private nonisolated static var langSuffix: String { ContentLanguage.current.fileSuffix }

    /// 缓存 schema 版本。=1 时用无版本段的老目录（保住 zh 升级用户的缓存）；
    /// 未来 schema 演进 bump 到 2 → 路径变 CastlingoEpisodes/v2/，老缓存整体作废重拉。
    private nonisolated static let cacheSchemaVersion = 1

    /// Base URL for fetching index + detail. Reads `OSSBaseURL` from Info.plist
    /// (set this to the CDN/accelerate host once provisioned), falls back to
    /// direct OSS. Swap = one Info.plist edit, no code recompile semantics.
    private var baseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "OSSBaseURL") as? String
            ?? "https://\(Self.originOSSHost)"
    }

    /// Extracted host from configured base URL — used for URL rewriting.
    private var configuredHost: String {
        URL(string: baseURL)?.host ?? Self.originOSSHost
    }

    /// 内容 URL 统一出口：`dir` 是 OSS 目录（"episodes/easy"），`file` 是不带
    /// 扩展名的文件名（"index"）。自动拼语言后缀 + .json。
    private func contentURL(dir: String, file: String) -> URL? {
        URL(string: "\(baseURL)/\(dir)/\(file)\(Self.langSuffix).json")
    }

    /// Rewrite any origin-OSS hosts inside a JSON blob to the configured host
    /// (CDN/accelerate). No-op when host is unchanged. Operates on the raw
    /// UTF-8 blob so it catches embedded audio + thumbnail + vocab audio URLs
    /// in one pass without needing to walk the decoded model.
    private func rewriteURLs(_ data: Data) -> Data {
        let newHost = configuredHost
        guard newHost != Self.originOSSHost else { return data }
        guard var text = String(data: data, encoding: .utf8) else { return data }
        text = text.replacingOccurrences(of: Self.originOSSHost, with: newHost)
        return Data(text.utf8)
    }

    // MARK: - Caching primitives（全部缓存路径的唯一出口）

    /// 缓存目录（含版本段），按需创建。nonisolated：sync 读方法也从这里走。
    nonisolated private static func cacheDirectory() -> URL {
        var dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CastlingoEpisodes", isDirectory: true)
        if cacheSchemaVersion > 1 {
            dir.appendPathComponent("v\(cacheSchemaVersion)", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 缓存文件 URL：`name` 不带扩展名（"episodes_easy"），自动拼语言后缀 + .json。
    nonisolated private static func cacheFile(_ name: String) -> URL {
        cacheDirectory().appendingPathComponent("\(name)\(langSuffix).json")
    }

    // MARK: - Episode List

    /// Fetch episode index for a level. Returns lightweight Episodes (no script/vocabulary).
    /// Caller should lazy-load full details via fetchEpisodeDetail when needed.
    func fetchEpisodes(for level: PodcastLevel) async -> [Episode] {
        guard let url = contentURL(dir: "episodes/\(level.rawValue)", file: "index") else {
            debugLog("❌ Invalid URL for \(level.rawValue)")
            return []
        }

        do {
            debugLog("📡 Fetching index: \(url)")
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                debugLog("❌ Index HTTP \(code)")
                return []
            }

            let rewritten = rewriteURLs(data)
            let index = try JSONDecoder.castlingo().decode(EpisodeIndex.self, from: rewritten)
            debugLog("✅ Index loaded: \(index.total) episodes")

            // Convert index items to lightweight Episodes (no script/vocabulary yet)
            var episodes = index.episodes.map { Episode(from: $0) }
            episodes.sort { $0.date < $1.date }

            // Cache for offline use
            if !episodes.isEmpty {
                cacheEpisodes(episodes, for: level)
            }
            return episodes
        } catch {
            debugLog("❌ Fetch error: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch full episode detail by ID. Used for lazy loading script/vocabulary on play.
    func fetchEpisodeDetail(id: String, level: PodcastLevel) async -> Episode? {
        guard let url = contentURL(dir: "episodes/\(level.rawValue)/\(id)", file: "episode") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                debugLog("⚠️ Detail \(id): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            let rewritten = rewriteURLs(data)
            return try JSONDecoder.castlingo().decode(Episode.self, from: rewritten)
        } catch {
            debugLog("⚠️ Detail \(id) decode error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Raw Podcast (硅谷原声)

    /// 拉「硅谷原声」master 列表（pipeline A 写到 OSS 的）。
    /// 失败时返回 nil；DataStore 会回到 bundle 里的种子数据。
    func fetchRawPodcasts() async -> [RawPodcast]? {
        guard let url = contentURL(dir: "raw_podcasts", file: "raw_podcasts") else {
            return nil
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                debugLog("⚠️ raw_podcasts HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            let rewritten = rewriteURLs(data)
            let items = try JSONDecoder.castlingo().decode([RawPodcast].self, from: rewritten)
            cacheRawPodcasts(items)
            debugLog("✅ raw_podcasts loaded: \(items.count) items")
            return items
        } catch {
            debugLog("⚠️ raw_podcasts fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    private func cacheRawPodcasts(_ items: [RawPodcast]) {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: Self.cacheFile("raw_podcasts"))
        }
    }

    /// 拉「硅谷原声」单期字幕。**网络优先，失败回缓存**（避免老缓存吞掉新版字幕）。
    /// transcriptUrl 来自 master 文件（各语言的 master 已指向各自的 transcript 文件），
    /// 所以这里不需要再拼语言后缀。
    func fetchTranscript(transcriptUrl: String, podcastId: String) async -> RawTranscript? {
        guard let url = URL(string: transcriptUrl) else {
            return loadCachedTranscriptSync(podcastId: podcastId)
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return loadCachedTranscriptSync(podcastId: podcastId)
            }
            let transcript = try JSONDecoder.castlingo().decode(RawTranscript.self, from: data)
            cacheTranscript(transcript, podcastId: podcastId)
            return transcript
        } catch {
            debugLog("⚠️ transcript fetch error: \(error.localizedDescription)")
            return loadCachedTranscriptSync(podcastId: podcastId)
        }
    }

    private func cacheTranscript(_ transcript: RawTranscript, podcastId: String) {
        if let data = try? JSONEncoder().encode(transcript) {
            try? data.write(to: Self.cacheFile("transcript_\(podcastId)"))
        }
    }

    nonisolated func loadCachedTranscriptSync(podcastId: String) -> RawTranscript? {
        guard let data = try? Data(contentsOf: Self.cacheFile("transcript_\(podcastId)")),
              let t = try? JSONDecoder.castlingo().decode(RawTranscript.self, from: data) else {
            return nil
        }
        return t
    }

    /// 拉一集预翻译的词典（从 raw_podcasts/<id>/words*.json）。
    /// 把 transcript URL 的最后一段文件名 transcript*.json 替换为 words*.json
    /// （兼容 transcript.json / transcript_ko.json 等语言变体）。
    func fetchPodcastWords(transcriptUrl: String, podcastId: String) async -> RawPodcastWords? {
        guard let base = URL(string: transcriptUrl) else {
            return loadCachedWordsSync(podcastId: podcastId)
        }
        let wordsFile = base.lastPathComponent.replacingOccurrences(of: "transcript", with: "words")
        let url = base.deletingLastPathComponent().appendingPathComponent(wordsFile)
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return loadCachedWordsSync(podcastId: podcastId)
            }
            let words = try JSONDecoder.castlingo().decode(RawPodcastWords.self, from: data)
            cacheWords(words, podcastId: podcastId)
            return words
        } catch {
            debugLog("⚠️ words fetch error: \(error.localizedDescription)")
            return loadCachedWordsSync(podcastId: podcastId)
        }
    }

    private func cacheWords(_ words: RawPodcastWords, podcastId: String) {
        if let data = try? JSONEncoder().encode(words) {
            try? data.write(to: Self.cacheFile("words_\(podcastId)"))
        }
    }

    nonisolated func loadCachedWordsSync(podcastId: String) -> RawPodcastWords? {
        guard let data = try? Data(contentsOf: Self.cacheFile("words_\(podcastId)")),
              let w = try? JSONDecoder.castlingo().decode(RawPodcastWords.self, from: data) else {
            return nil
        }
        return w
    }

    nonisolated func loadCachedRawPodcastsSync() -> [RawPodcast]? {
        guard let data = try? Data(contentsOf: Self.cacheFile("raw_podcasts")),
              let items = try? JSONDecoder.castlingo().decode([RawPodcast].self, from: data),
              !items.isEmpty else {
            return nil
        }
        return items
    }

    /// Public access to disk cache (used by DataStore for instant startup display)
    nonisolated func loadCachedEpisodesSync(for level: PodcastLevel) -> [Episode]? {
        guard let data = try? Data(contentsOf: Self.cacheFile("episodes_\(level.rawValue)")),
              let episodes = try? JSONDecoder.castlingo().decode([Episode].self, from: data),
              !episodes.isEmpty else {
            return nil
        }
        return episodes
    }

    // MARK: - 词汇小课堂 (Scene Lessons)

    /// 拉国家列表（含各国课堂数）。失败回缓存，再失败回内置默认。
    func fetchLessonCountries() async -> [LessonCountry] {
        guard let url = contentURL(dir: "lessons", file: "countries") else {
            return LessonCountry.defaults
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return loadCachedLessonCountriesSync() ?? LessonCountry.defaults
            }
            let decoded = try JSONDecoder.castlingo().decode(LessonCountriesResponse.self, from: rewriteURLs(data))
            try? rewriteURLs(data).write(to: Self.cacheFile("lesson_countries"))
            return decoded.countries
        } catch {
            debugLog("⚠️ lesson countries fetch error: \(error.localizedDescription)")
            return loadCachedLessonCountriesSync() ?? LessonCountry.defaults
        }
    }

    nonisolated func loadCachedLessonCountriesSync() -> [LessonCountry]? {
        guard let data = try? Data(contentsOf: Self.cacheFile("lesson_countries")),
              let decoded = try? JSONDecoder.castlingo().decode(LessonCountriesResponse.self, from: data),
              !decoded.countries.isEmpty else { return nil }
        return decoded.countries
    }

    /// 拉某国课堂目录。成功后写磁盘缓存（各国独立），失败返回空。
    func fetchLessonIndex(country: String) async -> [SceneLessonIndexItem] {
        guard let url = contentURL(dir: "lessons/\(country)", file: "index") else { return [] }
        do {
            debugLog("📡 Fetching lesson index: \(country)")
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                debugLog("❌ lesson index HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return []
            }
            let rewritten = rewriteURLs(data)
            let index = try JSONDecoder.castlingo().decode(SceneLessonIndex.self, from: rewritten)
            if !index.lessons.isEmpty {
                try? rewritten.write(to: Self.cacheFile("lessons_index_\(country)"))
            }
            debugLog("✅ lesson index \(country): \(index.total)")
            return index.lessons
        } catch {
            debugLog("⚠️ lesson index fetch error: \(error.localizedDescription)")
            return []
        }
    }

    /// 拉全局今日每日课（lessons/today.json）。跨国家，独立于当前所选国家。失败返回 nil。
    func fetchTodayLesson() async -> SceneLessonToday? {
        guard let url = contentURL(dir: "lessons", file: "today") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let rewritten = rewriteURLs(data)
            return try JSONDecoder.castlingo().decode(SceneLessonToday.self, from: rewritten)
        } catch {
            debugLog("⚠️ today lesson fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated func loadCachedLessonIndexSync(country: String) -> [SceneLessonIndexItem]? {
        guard let data = try? Data(contentsOf: Self.cacheFile("lessons_index_\(country)")),
              let index = try? JSONDecoder.castlingo().decode(SceneLessonIndex.self, from: data),
              !index.lessons.isEmpty else { return nil }
        return index.lessons
    }

    /// 拉课堂详情。网络优先，失败回缓存（看过的课堂离线可用）。
    func fetchLessonDetail(country: String, id: String) async -> SceneLesson? {
        guard let url = contentURL(dir: "lessons/\(country)/\(id)", file: "lesson") else {
            return loadCachedLessonDetailSync(id: id)
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return loadCachedLessonDetailSync(id: id)
            }
            let rewritten = rewriteURLs(data)
            let lesson = try JSONDecoder.castlingo().decode(SceneLesson.self, from: rewritten)
            try? rewritten.write(to: Self.cacheFile("lesson_\(id)"))
            return lesson
        } catch {
            debugLog("⚠️ lesson detail \(id) error: \(error.localizedDescription)")
            return loadCachedLessonDetailSync(id: id)
        }
    }

    nonisolated func loadCachedLessonDetailSync(id: String) -> SceneLesson? {
        guard let data = try? Data(contentsOf: Self.cacheFile("lesson_\(id)")),
              let lesson = try? JSONDecoder.castlingo().decode(SceneLesson.self, from: data) else { return nil }
        return lesson
    }

    // MARK: - 口语表达库 (Expressions)

    func fetchExpressionIndex() async -> [ExpressionGroup] {
        guard let url = contentURL(dir: "expressions", file: "index") else { return [] }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return loadCachedExpressionIndexSync() ?? []
            }
            let rewritten = rewriteURLs(data)
            let index = try JSONDecoder.castlingo().decode(ExpressionIndex.self, from: rewritten)
            if !index.groups.isEmpty {
                try? rewritten.write(to: Self.cacheFile("expressions_index"))
            }
            return index.groups
        } catch {
            debugLog("⚠️ expression index error: \(error.localizedDescription)")
            return loadCachedExpressionIndexSync() ?? []
        }
    }

    nonisolated func loadCachedExpressionIndexSync() -> [ExpressionGroup]? {
        guard let data = try? Data(contentsOf: Self.cacheFile("expressions_index")),
              let index = try? JSONDecoder.castlingo().decode(ExpressionIndex.self, from: data),
              !index.groups.isEmpty else { return nil }
        return index.groups
    }

    /// 分类详情。网络优先，失败回缓存（看过的分类离线可用）。
    func fetchExpressionCategory(id: String) async -> ExpressionCategory? {
        guard let url = contentURL(dir: "expressions", file: id) else {
            return loadCachedExpressionCategorySync(id: id)
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return loadCachedExpressionCategorySync(id: id)
            }
            let rewritten = rewriteURLs(data)
            let category = try JSONDecoder.castlingo().decode(ExpressionCategory.self, from: rewritten)
            try? rewritten.write(to: Self.cacheFile("expressions_\(id)"))
            return category
        } catch {
            debugLog("⚠️ expression category \(id) error: \(error.localizedDescription)")
            return loadCachedExpressionCategorySync(id: id)
        }
    }

    nonisolated func loadCachedExpressionCategorySync(id: String) -> ExpressionCategory? {
        guard let data = try? Data(contentsOf: Self.cacheFile("expressions_\(id)")),
              let category = try? JSONDecoder.castlingo().decode(ExpressionCategory.self, from: data) else { return nil }
        return category
    }

    // MARK: - Episode cache write

    private func cacheEpisodes(_ episodes: [Episode], for level: PodcastLevel) {
        guard let data = try? JSONEncoder().encode(episodes) else { return }
        try? data.write(to: Self.cacheFile("episodes_\(level.rawValue)"))
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[API] \(message)")
        #endif
    }
}

// MARK: - Index Model

/// Lightweight index returned by the server (no full scripts)
struct EpisodeIndex: Codable {
    let level: String
    let episodes: [EpisodeIndexItem]
    let total: Int
}

struct EpisodeIndexItem: Codable {
    let id: String
    let title: String
    let level: String
    let date: String
    let durationSeconds: Int
    let audio: EpisodeAudio
    let thumbnail: String?
    let vocabularyCount: Int
    let patterns: [Pattern]?

    enum CodingKeys: String, CodingKey {
        case id, title, level, date, audio, thumbnail, patterns
        case durationSeconds = "duration_seconds"
        case vocabularyCount = "vocabulary_count"
    }
}
