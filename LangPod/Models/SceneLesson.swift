import Foundation

// MARK: - 词汇小课堂（场景图解词汇）

/// 国家元数据（词汇小课堂按国家分类，随时可切，像平级频道）
struct LessonCountry: Codable, Identifiable, Hashable {
    let id: String        // "us" / "uk" / "au" / "ca" / "nz" / "sg"
    let nameTranslation: String
    let flag: String
    let accent: String    // BCP-47 口音代码，发音跟随课堂国家
    let lessonCount: Int

    enum CodingKeys: String, CodingKey {
        case id, flag, accent
        case nameTranslation = "name_translation"
        case lessonCount = "lesson_count"
    }

    /// 离线兜底：服务器 countries.json 拉不到时使用
    static let defaults: [LessonCountry] = [
        LessonCountry(id: "us", nameTranslation: "美国", flag: "🇺🇸", accent: "en-US", lessonCount: 0),
        LessonCountry(id: "uk", nameTranslation: "英国", flag: "🇬🇧", accent: "en-GB", lessonCount: 0),
        LessonCountry(id: "au", nameTranslation: "澳洲", flag: "🇦🇺", accent: "en-AU", lessonCount: 0),
        LessonCountry(id: "ca", nameTranslation: "加拿大", flag: "🇨🇦", accent: "en-US", lessonCount: 0),
        LessonCountry(id: "nz", nameTranslation: "新西兰", flag: "🇳🇿", accent: "en-AU", lessonCount: 0),
        LessonCountry(id: "sg", nameTranslation: "新加坡", flag: "🇸🇬", accent: "en-SG", lessonCount: 0),
    ]
}

struct LessonCountriesResponse: Codable {
    let countries: [LessonCountry]
}

/// 课堂目录条目（lessons/{country}/index.json）
struct SceneLessonIndex: Codable {
    let country: String
    let countryTranslation: String
    let flag: String
    let lessons: [SceneLessonIndexItem]
    let total: Int

    enum CodingKeys: String, CodingKey {
        case country, flag, lessons, total
        case countryTranslation = "country_translation"
    }
}

/// 全局今日每日课指针（lessons/today.json）。每天由 pipeline 轮换国家产出后重写，
/// App 不依赖当前所选国家，顶部固定展示当天这一课。
struct SceneLessonToday: Codable {
    let country: String
    let countryTranslation: String
    let flag: String
    let accent: String?
    let date: String
    let lesson: SceneLessonIndexItem

    enum CodingKeys: String, CodingKey {
        case country, flag, accent, date, lesson
        case countryTranslation = "country_translation"
    }
}

struct SceneLessonIndexItem: Codable, Identifiable, Hashable {
    let id: String
    let titleTranslation: String
    let titleEn: String
    let category: String
    let categoryTranslation: String
    let icon: String
    let cover: String
    let isFree: Bool
    let isDaily: Bool
    let date: String
    let wordCount: Int
    let zoneCount: Int

    enum CodingKeys: String, CodingKey {
        case id, category, icon, cover, date
        case titleTranslation = "title_translation"
        case titleEn = "title_en"
        case categoryTranslation = "category_translation"
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
    let titleTranslation: String
    let titleEn: String
    let category: String
    let categoryTranslation: String
    let icon: String
    let cover: String
    let isFree: Bool
    let isDaily: Bool
    let date: String
    let wordCount: Int
    let zones: [SceneZone]
    let sentences: [SceneSentence]
    let cultureTips: [String]?
    /// 模拟现场对话（角色扮演，可选：老课堂没有该字段）
    var roleplay: LessonRoleplay?

    enum CodingKeys: String, CodingKey {
        case id, country, category, icon, cover, date, zones, sentences, roleplay
        case titleTranslation = "title_translation"
        case titleEn = "title_en"
        case categoryTranslation = "category_translation"
        case isFree = "is_free"
        case isDaily = "is_daily"
        case wordCount = "word_count"
        case cultureTips = "culture_tips"
    }

    /// 全部单词（图上 + 更多表达），用于「全部加入单词本」
    var allWords: [SceneWord] {
        zones.flatMap { $0.hotspots + $0.extraWords }
    }

    /// 全部发音音频 URL（进课堂时预取，点击零延迟）
    var allAudioUrls: [String] {
        allWords.flatMap { [$0.audio, $0.exampleAudio] }.compactMap { $0 }
            + sentences.compactMap { $0.audio }
            + (roleplay?.dialogue.compactMap { $0.audio } ?? [])
    }
}

/// 模拟现场对话：进入场景后的完整角色扮演（你 = 顾客视角，对方 = 店员/柜员等）
struct LessonRoleplay: Codable, Hashable {
    let setup: String       // 场景设定（"你走进 Chase 网点，要开一个 checking account"）
    let yourRole: String    // 你的角色（"顾客"）
    let otherRole: String   // 对方角色（"银行柜员"）
    let dialogue: [RoleplayLine]
    /// gpt-image-1 生成的人物头像（缺失时回落 person.fill 圆形图标）
    var youAvatar: String?
    var otherAvatar: String?

    enum CodingKeys: String, CodingKey {
        case dialogue
        case setup = "setup"
        case yourRole = "your_role"
        case otherRole = "other_role"
        case youAvatar = "you_avatar"
        case otherAvatar = "other_avatar"
    }
}

struct RoleplayLine: Codable, Identifiable, Hashable {
    let speaker: String       // "you" / "other"
    let en: String
    let translation: String
    let audio: String?
    /// GPT 教学解析（关键表达/语气/文化习惯，场景模拟答题后展示）
    var note: String?
    var id: String { speaker + en }

    enum CodingKeys: String, CodingKey {
        case speaker, en, translation, audio
        case note = "note"
    }

    var isYou: Bool { speaker == "you" }
}

struct SceneZone: Codable, Identifiable {
    let id: String
    let nameTranslation: String
    let nameEn: String
    let image: String
    let hotspots: [SceneWord]
    let extraWords: [SceneWord]

    enum CodingKeys: String, CodingKey {
        case id, image, hotspots
        case nameTranslation = "name_translation"
        case nameEn = "name_en"
        case extraWords = "extra_words"
    }
}

/// 一个词条。hotspots 带归一化坐标 (x, y)，extra_words 无坐标。
/// audio / exampleAudio 为 ElevenLabs 预生成发音（可能为空 → 回落系统 TTS）。
struct SceneWord: Codable, Identifiable, Hashable {
    let word: String
    let phonetic: String
    let translation: String
    let example: String
    let exampleTranslation: String?
    let difficulty: String?
    let audio: String?
    let exampleAudio: String?
    let x: Double?
    let y: Double?

    var id: String { word }

    enum CodingKeys: String, CodingKey {
        case word, phonetic, example, difficulty, audio, x, y
        case translation = "translation"
        case exampleTranslation = "example_translation"
        case exampleAudio = "example_audio"
    }

    var asVocabularyItem: VocabularyItem {
        VocabularyItem(
            word: word,
            phonetic: phonetic,
            translation: translation,
            example: example,
            exampleTranslation: exampleTranslation,
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
    let translation: String
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
