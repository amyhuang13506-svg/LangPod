import Foundation

/// One section of a pattern's explainer audio.
/// Drives subtitle highlighting as the audio plays.
enum PatternSection: String, Codable, CaseIterable {
    case pronunciation = "pronunciation"
    case pronunciationDrill = "pronunciation_drill"
    case meaning = "meaning"
    case sceneAndFeeling = "scene_and_feeling"
    case example1 = "example1"
    case example2 = "example2"
    case example3 = "example3"

    var label: String {
        switch self {
        case .pronunciation: "读音"
        case .pronunciationDrill: "跟读练习"
        case .meaning: "字面意思"
        case .sceneAndFeeling: "场景与感觉"
        case .example1: "例句 1"
        case .example2: "例句 2"
        case .example3: "例句 3"
        }
    }

    var icon: String {
        switch self {
        case .pronunciation: "waveform"
        case .pronunciationDrill: "repeat"
        case .meaning: "text.bubble"
        case .sceneAndFeeling: "scope"
        case .example1, .example2, .example3: "quote.bubble.fill"
        }
    }
}

/// One subtitle line in a pattern explainer.
/// `start` / `end` are seconds; nullable for fallback when timestamps are missing.
struct PatternScriptLine: Codable, Identifiable {
    let section: PatternSection
    let textZh: String              // 中文讲解
    let textEn: String              // 英文示范 (跟读段或例句段才有内容)
    var start: Double?
    var end: Double?

    var id: String { "\(section.rawValue)-\(textZh.prefix(20))" }

    enum CodingKeys: String, CodingKey {
        case section
        case textZh = "text_zh"
        case textEn = "text_en"
        case start, end
    }
}

/// Three example sentences attached to each pattern.
/// Phase 2: feed these into the connect-words practice pool.
struct PatternExample: Codable, Identifiable {
    let english: String
    let chinese: String

    var id: String { english }
}

/// A sentence pattern with a 6-section explainer audio. Embedded in Episode JSON.
/// All users see the same content; per-user state lives only in playback queue
/// and access gating (today free, history Pro).
struct Pattern: Codable, Identifiable {
    let id: String                  // "pattern_easy_20260420_1"
    let episodeId: String           // 关联回所属 episode
    let template: String            // "Could I ___ ___, please?"
    let translationZh: String       // "我可以...吗？（礼貌请求）"
    let scene: String               // "餐厅 / 借东西 / 公共请求"
    let audioUrl: String            // OSS 讲解音频 URL
    let durationSeconds: Int
    let explainerScript: [PatternScriptLine]
    let exampleSentences: [PatternExample]
    var thumbnailColor: String?     // hex, defaults applied at view layer

    var durationDisplay: String {
        if durationSeconds >= 60 {
            let min = durationSeconds / 60
            let sec = durationSeconds % 60
            return sec > 0 ? "\(min)分\(sec)秒" : "\(min)分钟"
        }
        return "\(durationSeconds)秒"
    }

    enum CodingKeys: String, CodingKey {
        case id, template, scene
        case episodeId = "episode_id"
        case translationZh = "translation_zh"
        case audioUrl = "audio_url"
        case durationSeconds = "duration_seconds"
        case explainerScript = "explainer_script"
        case exampleSentences = "example_sentences"
        case thumbnailColor = "thumbnail_color"
    }
}
