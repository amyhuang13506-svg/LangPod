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
        // 语言后缀防止切系统语言后命中另一语言的释义（zh 为空 = 老缓存继续有效）
        return "\(w)|\(ctxHash)\(ContentLanguage.current.cacheSuffix)"
    }

    // MARK: - GPT 查词

    /// 各内容语言的词典 prompt 参数（目标语描述 + 释义/专有名词指令）。
    private var dictionaryTarget: (langName: String, glossRule: String, properNounRule: String) {
        switch ContentLanguage.current {
        case .ko:
            return ("EN→KO", "1-2 common Korean glosses, comma-separated, fitting this sentence's context",
                    "set translation to \"(고유명사) <standard Korean transliteration>\"")
        case .ja:
            return ("EN→JA", "1-2 common Japanese glosses, comma-separated, fitting this sentence's context",
                    "set translation to \"（固有名詞）<standard Japanese transliteration>\"")
        case .es:
            return ("EN→ES", "1-2 common Spanish glosses, comma-separated, fitting this sentence's context",
                    "set translation to \"(nombre propio) <name>\"")
        case .ptBR:
            return ("EN→PT-BR", "1-2 common Brazilian Portuguese glosses, comma-separated, fitting this sentence's context",
                    "set translation to \"(nome próprio) <name>\"")
        case .zhHant:
            return ("EN→ZH-Hant", "1-2 個繁體中文（台灣用詞）常用釋義，逗號分隔，要符合本句上下文",
                    "set translation to \"（專有名詞）<音譯或公司名>\"")
        case .zh:
            return ("EN→ZH", "1-2 个中文常用释义，逗号分隔，要符合本句上下文",
                    "set translation to \"（专有名词）<音译或公司名>\"")
        }
    }

    private func fetchFromGPT(word: String, context: String) async -> WordLookup? {
        let target = dictionaryTarget
        let prompt = """
        You are a bilingual \(target.langName) dictionary. Look up the word "\(word)" as it appears in this sentence:

        "\(context)"

        Output STRICT JSON only (no markdown, no extra text):
        {
          "phonetic": "/IPA/",
          "part_of_speech": "n." | "v." | "adj." | "adv." | "phr." | "...",
          "translation": "\(target.glossRule)",
          "example": "a simple English example sentence using \(word) in another common context (optional)"
        }

        If the word is a proper noun (person/company name), \(target.properNounRule) and part_of_speech to "n.".
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

// MARK: - 句子快照跨语言重翻译（我的句子/连词成句显示层用）

/// 英文句子批量直翻到当前内容语言（单次 GPT 调用）。
enum SentenceRelocalizer {
    static func translate(_ sentences: [String], to lang: ContentLanguage) async -> [String: String]? {
        guard !sentences.isEmpty else { return [:] }
        let langName = lang.englishName
        guard let payloadData = try? JSONSerialization.data(withJSONObject: sentences),
              let payloadStr = String(data: payloadData, encoding: .utf8) else { return nil }

        let noHan = lang.rejectsHanInOutput ? " Never output Chinese characters in \(langName) output." : ""
        let prompt = """
        Translate these English sentences (from an English-learning app) into natural, \
        conversational \(langName).\(noHan)

        INPUT: \(payloadStr)

        OUTPUT strict JSON only: {"<english sentence>": "<\(langName) translation>", ...} — \
        every sentence exactly once, keys copied verbatim.
        """

        guard let url = URL(string: "https://api.v3.cm/v1/chat/completions") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(GPTAPIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "response_format": ["type": "json_object"],
            "temperature": 0.2,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ChatCompletion.self, from: data),
              let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: contentData) as? [String: String]
        else { return nil }

        var result: [String: String] = [:]
        for s in sentences {
            guard let t = raw[s], !t.isEmpty else { continue }
            if lang.rejectsHanInOutput && t.contains(where: { "一" <= $0 && $0 <= "鿿" }) { continue }
            result[s] = t
        }
        return result
    }
}

// MARK: - 中文标签跨语言重翻译（句子快照的场景/来源标签显示层用）

/// 异语言快照里的短标签（分类名/场景名，如「厨房」「口头禅与填充词」）批量翻到当前内容语言。
enum LabelRelocalizer {
    static func translate(_ labels: [String], to lang: ContentLanguage) async -> [String: String]? {
        guard !labels.isEmpty else { return [:] }
        let langName = lang.englishName
        guard let payloadData = try? JSONSerialization.data(withJSONObject: labels),
              let payloadStr = String(data: payloadData, encoding: .utf8) else { return nil }

        let noHan = lang.rejectsHanInOutput ? " Never output Chinese characters in \(langName) output." : ""
        let prompt = """
        These are short category/tag labels from an English-learning app \
        (e.g. lesson scene names, expression category names), possibly in another language. \
        Translate each into a concise, natural \(langName) label. Keep them short \
        (a few words).\(noHan)

        INPUT: \(payloadStr)

        OUTPUT strict JSON only: {"<original label>": "<\(langName) label>", ...} — \
        every label exactly once, keys copied verbatim.
        """

        guard let url = URL(string: "https://api.v3.cm/v1/chat/completions") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(GPTAPIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "response_format": ["type": "json_object"],
            "temperature": 0.2,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ChatCompletion.self, from: data),
              let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: contentData) as? [String: String]
        else { return nil }

        var result: [String: String] = [:]
        for label in labels {
            guard let t = raw[label], !t.isEmpty else { continue }
            if lang.rejectsHanInOutput && t.contains(where: { "一" <= $0 && $0 <= "鿿" }) { continue }
            result[label] = t
        }
        return result
    }
}

// MARK: - 词汇快照跨语言重翻译（单词本显示层用）

/// 把老语言快照的释义批量翻成当前内容语言（单次 GPT 调用）。
/// 输入带原释义 + 例句做上下文，输出目标语言的词典式释义 + 例句翻译。
enum GlossRelocalizer {
    static func translate(
        _ words: [SavedWord],
        to lang: ContentLanguage
    ) async -> [String: VocabularyStore.RelocalizedGloss]? {
        guard !words.isEmpty else { return [:] }
        let langName = lang.englishName

        let payload = words.map { w in
            ["word": w.word, "old_gloss": w.translation,
             "example": w.example, "old_example_tr": w.exampleTranslation ?? ""]
        }
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadStr = String(data: payloadData, encoding: .utf8) else { return nil }

        let prompt = """
        These are saved vocabulary entries from an English-learning app, with glosses in \
        another language. Produce \(langName) glosses instead.
        For each entry output: "t" = concise dictionary-style \(langName) gloss of the word \
        (match the sense shown by old_gloss/example), "et" = natural \(langName) translation \
        of the example sentence ("" if no example).\(lang.rejectsHanInOutput
            ? " Never output Chinese characters in \(langName) output." : "")

        INPUT: \(payloadStr)

        OUTPUT strict JSON only: {"<word>": {"t": "...", "et": "..."}, ...} — every word exactly once.
        """

        guard let url = URL(string: "https://api.v3.cm/v1/chat/completions") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(GPTAPIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "response_format": ["type": "json_object"],
            "temperature": 0.2,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ChatCompletion.self, from: data),
              let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: contentData) as? [String: [String: String]]
        else { return nil }

        var result: [String: VocabularyStore.RelocalizedGloss] = [:]
        for w in words {
            guard let entry = raw[w.word] ?? raw[w.word.lowercased()],
                  let t = entry["t"], !t.isEmpty else { continue }
            // 汉字串漏 = 没翻，丢弃（下次重试）；ja/zh 系正常含汉字，不查
            if lang.rejectsHanInOutput && t.contains(where: { "一" <= $0 && $0 <= "鿿" }) { continue }
            let et = entry["et"] ?? ""
            result[w.word] = VocabularyStore.RelocalizedGloss(
                translation: t, exampleTranslation: et.isEmpty ? nil : et)
        }
        return result
    }
}
