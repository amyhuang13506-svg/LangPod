import Foundation

// MARK: - 词汇小课堂（场景图解词汇）

/// 国家元数据（词汇小课堂按国家分类，随时可切，像平级频道）
struct LessonCountry: Codable, Identifiable, Hashable {
    let id: String        // "us" / "uk" / "au" / "ca" / "nz" / "sg"
    let nameZh: String
    let flag: String
    let accent: String    // BCP-47 口音代码，发音跟随课堂国家
    let lessonCount: Int

    enum CodingKeys: String, CodingKey {
        case id, flag, accent
        case nameZh = "name_zh"
        case lessonCount = "lesson_count"
    }

    /// 离线兜底：服务器 countries.json 拉不到时使用
    static let defaults: [LessonCountry] = [
        LessonCountry(id: "us", nameZh: "美国", flag: "🇺🇸", accent: "en-US", lessonCount: 0),
        LessonCountry(id: "uk", nameZh: "英国", flag: "🇬🇧", accent: "en-GB", lessonCount: 0),
        LessonCountry(id: "au", nameZh: "澳洲", flag: "🇦🇺", accent: "en-AU", lessonCount: 0),
        LessonCountry(id: "ca", nameZh: "加拿大", flag: "🇨🇦", accent: "en-US", lessonCount: 0),
        LessonCountry(id: "nz", nameZh: "新西兰", flag: "🇳🇿", accent: "en-AU", lessonCount: 0),
        LessonCountry(id: "sg", nameZh: "新加坡", flag: "🇸🇬", accent: "en-SG", lessonCount: 0),
    ]
}

struct LessonCountriesResponse: Codable {
    let countries: [LessonCountry]
}

/// 课堂目录条目（lessons/{country}/index.json）
struct SceneLessonIndex: Codable {
    let country: String
    let countryZh: String
    let flag: String
    let lessons: [SceneLessonIndexItem]
    let total: Int

    enum CodingKeys: String, CodingKey {
        case country, flag, lessons, total
        case countryZh = "country_zh"
    }
}

struct SceneLessonIndexItem: Codable, Identifiable, Hashable {
    let id: String
    let titleZh: String
    let titleEn: String
    let category: String
    let categoryZh: String
    let icon: String
    let cover: String
    let isFree: Bool
    let isDaily: Bool
    let date: String
    let wordCount: Int
    let zoneCount: Int

    enum CodingKeys: String, CodingKey {
        case id, category, icon, cover, date
        case titleZh = "title_zh"
        case titleEn = "title_en"
        case categoryZh = "category_zh"
        case isFree = "is_free"
        case isDaily = "is_daily"
        case wordCount = "word_count"
        case zoneCount = "zone_count"
    }
}

/// 完整课堂（lessons/{country}/{id}/lesson.json）
struct SceneLesson: Codable, Identifiable {
    let id: String
    let country: String
    let titleZh: String
    let titleEn: String
    let category: String
    let categoryZh: String
    let icon: String
    let cover: String
    let isFree: Bool
    let isDaily: Bool
    let date: String
    let wordCount: Int
    let zones: [SceneZone]
    let sentences: [SceneSentence]
    let cultureTipsZh: [String]?

    enum CodingKeys: String, CodingKey {
        case id, country, category, icon, cover, date, zones, sentences
        case titleZh = "title_zh"
        case titleEn = "title_en"
        case categoryZh = "category_zh"
        case isFree = "is_free"
        case isDaily = "is_daily"
        case wordCount = "word_count"
        case cultureTipsZh = "culture_tips_zh"
    }

    /// 全部单词（图上 + 更多表达），用于「全部加入单词本」
    var allWords: [SceneWord] {
        zones.flatMap { $0.hotspots + $0.extraWords }
    }

    /// 全部发音音频 URL（进课堂时预取，点击零延迟）
    var allAudioUrls: [String] {
        allWords.flatMap { [$0.audio, $0.exampleAudio] }.compactMap { $0 }
            + sentences.compactMap { $0.audio }
    }
}

struct SceneZone: Codable, Identifiable {
    let id: String
    let nameZh: String
    let nameEn: String
    let image: String
    let hotspots: [SceneWord]
    let extraWords: [SceneWord]

    enum CodingKeys: String, CodingKey {
        case id, image, hotspots
        case nameZh = "name_zh"
        case nameEn = "name_en"
        case extraWords = "extra_words"
    }
}

/// 一个词条。hotspots 带归一化坐标 (x, y)，extra_words 无坐标。
/// audio / exampleAudio 为 ElevenLabs 预生成发音（可能为空 → 回落系统 TTS）。
struct SceneWord: Codable, Identifiable, Hashable {
    let word: String
    let phonetic: String
    let translationZh: String
    let example: String
    let exampleZh: String?
    let difficulty: String?
    let audio: String?
    let exampleAudio: String?
    let x: Double?
    let y: Double?

    var id: String { word }

    enum CodingKeys: String, CodingKey {
        case word, phonetic, example, difficulty, audio, x, y
        case translationZh = "translation_zh"
        case exampleZh = "example_zh"
        case exampleAudio = "example_audio"
    }

    var asVocabularyItem: VocabularyItem {
        VocabularyItem(
            word: word,
            phonetic: phonetic,
            translationZh: translationZh,
            example: example,
            exampleZh: exampleZh,
            audio: ""
        )
    }

    var difficultyLabel: String {
        switch difficulty {
        case "easy": "初级"
        case "medium": "中级"
        case "hard": "高级"
        default: ""
        }
    }
}

struct SceneSentence: Codable, Identifiable, Hashable {
    let english: String
    let chinese: String
    let audio: String?
    var id: String { english }
}

// MARK: - 付费门控

/// 免费课堂人人可进；每日新场景当天免费；其余 Pro。
enum LessonAccessGate {
    static func canAccess(isFree: Bool, isDaily: Bool, date: String, isPro: Bool) -> Bool {
        if isPro || isFree { return true }
        if isDaily && isToday(date) { return true }
        return false
    }

    /// 本地时区判断（与 PatternAccessGate 同思路）
    static func isToday(_ dateString: String) -> Bool {
        guard !dateString.isEmpty else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date()) == String(dateString.prefix(10))
    }
}
