import Foundation

struct Episode: Codable, Identifiable {
    let id: String
    let title: String
    let level: String
    let date: String
    let durationSeconds: Int
    let audio: EpisodeAudio
    let script: [ScriptLine]
    let vocabulary: [VocabularyItem]
    var thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id, title, level, date, thumbnail
        case durationSeconds = "duration_seconds"
        case audio, script, vocabulary
    }

    var podcastLevel: PodcastLevel? {
        PodcastLevel(rawValue: level)
    }

    var dateDisplay: String {
        // "2026-04-02" → "4月2日"
        if let d = DateFormatter.episodeDate.date(from: date) {
            let f = DateFormatter()
            f.dateFormat = "M月d日"
            return f.string(from: d)
        }
        return date
    }

    var durationDisplay: String {
        if durationSeconds >= 60 {
            let min = durationSeconds / 60
            let sec = durationSeconds % 60
            return sec > 0 ? "\(min)分\(sec)秒" : "\(min)分钟"
        }
        return "\(durationSeconds)秒"
    }
}

struct EpisodeAudio: Codable {
    let english: String
    let translationZh: String

    enum CodingKeys: String, CodingKey {
        case english
        case translationZh = "translation_zh"
    }
}

struct ScriptLine: Codable, Identifiable {
    let speaker: String
    let text: String
    var start: Double?
    var end: Double?
    let translationZh: String

    var id: String { "\(speaker)-\(text.prefix(20))" }

    enum CodingKeys: String, CodingKey {
        case speaker, text, start, end
        case translationZh = "translation_zh"
    }
}

struct VocabularyItem: Codable, Identifiable {
    let word: String
    let phonetic: String
    let translationZh: String
    let example: String
    var exampleZh: String?
    let audio: String

    var id: String { word }

    enum CodingKeys: String, CodingKey {
        case word, phonetic, example, audio
        case translationZh = "translation_zh"
        case exampleZh = "example_zh"
    }
}
