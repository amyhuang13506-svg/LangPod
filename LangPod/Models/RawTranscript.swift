import Foundation

/// 「硅谷原声」字幕。从 OSS 上的 transcript.json 解码：
/// {"podcast_id": "...", "segments": [{"start": 0.0, "end": 5.2, "en": "...", "zh": "..."}, ...]}
struct RawTranscript: Codable {
    let podcastId: String
    let segments: [RawTranscriptSegment]

    enum CodingKeys: String, CodingKey {
        case podcastId = "podcast_id"
        case segments
    }
}

struct RawTranscriptSegment: Codable, Identifiable {
    let start: Double
    let end: Double
    let en: String
    let zh: String?
    /// 词级时间戳（pipeline v2 起新加，老 transcript.json 没有）。
    /// 用于 Karaoke 风格 —— 当前正在说的词高亮、点词跳音频
    let words: [WordTimestamp]?

    var id: String { "\(start)-\(end)" }
}

/// 单词级时间戳。w = 词原文（含尾标点）、s = start 秒、e = end 秒。
struct WordTimestamp: Codable, Hashable {
    let w: String
    let s: Double
    let e: Double
}

/// 「油管播客」预翻译词典。pipeline 在生成 transcript 时一并产出，
/// 上 OSS 在 raw_podcasts/<id>/words.json。App 拉到后用作点词查询的本地查表，
/// 命中时即时返回，未命中再走 GPT。
///
/// schema：{ podcast_id, words: { word_lower: { phonetic, pos, zh, example } } }
struct RawPodcastWords: Codable, Sendable {
    let podcastId: String
    let words: [String: WordEntry]

    enum CodingKeys: String, CodingKey {
        case podcastId = "podcast_id"
        case words
    }

    struct WordEntry: Codable, Sendable {
        let phonetic: String?
        let pos: String?
        let zh: String
        let example: String?
    }
}
