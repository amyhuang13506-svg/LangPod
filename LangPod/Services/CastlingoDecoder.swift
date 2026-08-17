import Foundation

/// 全 App 唯一的**内容** JSON 解码器（服务器/bundle/磁盘缓存里的内容文件）。
///
/// 多语言方案：新语言文件（episode_ko.json 等）用语言无关字段名（translation、
/// example_translation…），中文 legacy 文件保留 *_zh 字段名不动。
/// 本解码器把 legacy key 在解码时改写成 generic key，于是新老文件命中同一套
/// CodingKeys，模型层不需要写任何双 key 逻辑。
///
/// 注意：UserDefaults 里的用户数据（SavedWord 等）不走这里——它们用裸
/// JSONDecoder + 各自的 legacy key 兼容（见 SavedWord.init(from:)）。
extension JSONDecoder {
    /// legacy(zh) JSON key → generic key。与 pipeline 侧映射表保持一致（唯一真源
    /// 见 docs/多语言版方案_20260814.md「字段映射表」）。
    private static let legacyKeyMap: [String: String] = [
        "translation_zh": "translation",
        "example_zh": "example_translation",
        "text_zh": "text_translation",
        "title_zh": "title_translation",
        "category_zh": "category_translation",
        "name_zh": "name_translation",
        "country_zh": "country_translation",
        "culture_tips_zh": "culture_tips",
        "setup_zh": "setup",
        "your_role_zh": "your_role",
        "other_role_zh": "other_role",
        "note_zh": "note",
        "meaning_zh": "meaning",
        "usage_zh": "usage",
        "country_note_zh": "country_note",
        "summary_zh": "summary",
        "group_zh": "group_translation",
        "zh": "translation",
        "chinese": "translation",
    ]

    static func castlingo() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { codingPath in
            guard let last = codingPath.last else {
                return CastlingoCodingKey(stringValue: "")
            }
            if let mapped = legacyKeyMap[last.stringValue] {
                return CastlingoCodingKey(stringValue: mapped)
            }
            return last
        }
        return decoder
    }
}

struct CastlingoCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
