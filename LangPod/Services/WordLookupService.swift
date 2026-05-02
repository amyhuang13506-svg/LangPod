import Foundation

/// 单词点击查词。在线请求 GPT（api.v3.cm 代理）拿音标 + 词性 + 中文释义，
/// 结果存磁盘缓存避免重复请求。结合上下文（例句）让 GPT 选最贴切的释义。
struct WordLookup: Codable, Sendable {
    let phonetic: String?
    let partOfSpeech: String?
    let translation: String          // 中文释义
    let example: String?             // 来源例句

    enum CodingKeys: String, CodingKey {
        case phonetic, translation, example
        case partOfSpeech = "part_of_speech"
    }
}

actor WordLookupService {
    static let shared = WordLookupService()

    private var memoryCache: [String: WordLookup] = [:]

    /// 上下文相关的查词。同一单词在不同上下文都缓存（key = word|context_hash）
    func lookup(word: String, context: String) async -> WordLookup? {
        let key = cacheKey(word: word, context: context)
        if let cached = memoryCache[key] { return cached }
        if let onDisk = loadFromDisk(key: key) {
            memoryCache[key] = onDisk
            return onDisk
        }

        guard let result = await fetchFromGPT(word: word, context: context) else {
            return nil
        }
        memoryCache[key] = result
        saveToDisk(key: key, lookup: result)
        return result
    }

    private func cacheKey(word: String, context: String) -> String {
        let w = word.lowercased()
        // 上下文 hash 防止命中错误意思
        let ctxHash = String(context.lowercased().hashValue)
        return "\(w)|\(ctxHash)"
    }

    // MARK: - GPT 查词

    private func fetchFromGPT(word: String, context: String) async -> WordLookup? {
        let prompt = """
        You are a bilingual EN→ZH dictionary. Look up the word "\(word)" as it appears in this sentence:

        "\(context)"

        Output STRICT JSON only (no markdown, no extra text):
        {
          "phonetic": "/IPA/",
          "part_of_speech": "n." | "v." | "adj." | "adv." | "phr." | "...",
          "translation": "1-2 个中文常用释义，逗号分隔，要符合本句上下文",
          "example": "\(word) 在另一个常见语境中的简单英文例句（可选）"
        }

        If the word is a proper noun (person/company name), set translation to "（专有名词）<音译或公司名>" and part_of_speech to "n.".
        """
        guard let url = URL(string: "https://api.v3.cm/v1/chat/completions") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(GPTAPIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",          // 查词用 mini 足够，便宜快
            "messages": [["role": "user", "content": prompt]],
            "response_format": ["type": "json_object"],
            "temperature": 0.2,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(ChatCompletion.self, from: data)
            guard let content = decoded.choices.first?.message.content,
                  let contentData = content.data(using: .utf8),
                  let lookup = try? JSONDecoder().decode(WordLookup.self, from: contentData) else {
                return nil
            }
            return lookup
        } catch {
            return nil
        }
    }

    // MARK: - 磁盘缓存

    private var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WordLookups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadFromDisk(key: String) -> WordLookup? {
        let safeKey = key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        let file = cacheDirectory.appendingPathComponent("\(safeKey).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WordLookup.self, from: data)
    }

    private func saveToDisk(key: String, lookup: WordLookup) {
        let safeKey = key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        let file = cacheDirectory.appendingPathComponent("\(safeKey).json")
        if let data = try? JSONEncoder().encode(lookup) {
            try? data.write(to: file)
        }
    }
}

// 走 Bundle 配置，避免硬编码（key 实际从 Info.plist 或 hardcoded constant 读）
private var GPTAPIKey: String {
    // 与 pipeline/config.py 同款 key（Castlingo 自家 GPT 代理）
    // 生产应放进 Info.plist 或服务端中转，这里先用同 key 跑通
    "sk-tBDzHrm9YY8hYrBAA8257c605d134d3a95143b39C3E3048d"
}

// MARK: - GPT 响应模型

private struct ChatCompletion: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
    }
    struct Message: Decodable {
        let content: String
    }
}
