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
    let audio: String

    var id: String { word }

    enum CodingKeys: String, CodingKey {
        case word, phonetic, example, audio
        case translationZh = "translation_zh"
    }
}
