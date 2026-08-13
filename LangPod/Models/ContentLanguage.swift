import Foundation

/// App 的「内容语言」：决定 OSS 取哪套衍生文件（`index.json` vs `index_ko.json`）、
/// 词汇快照的语言标记、GPT 点词词典的目标语言。
///
/// UI 语言与内容语言同源，都由系统语言推导（iOS 切系统语言会重启 App，
/// 因此启动时解析一次、进程内不变是安全的）。UI 侧无需引用本类型——
/// String Catalog 自带 per-locale fallback。
enum ContentLanguage: String, CaseIterable, Codable, Sendable {
    case zh        // legacy schema（中文，文件无后缀，字段 *_zh）
    case zhHant = "zh-Hant"  // 繁中：文本繁化，翻译音频复用 zh
    case ko
    case ja
    case es
    case ptBR = "pt-BR"

    /// 已上线内容的语言。未上线语言即使命中系统语言也回落 zh，
    /// 避免 App 去请求 OSS 上还不存在的 `_xx` 文件。
    /// 每上线一门语言，把它加进来即可。
    /// ko: 2026-08-14 起 OSS 有 index_ko/episode_ko（存量回填进行中）。
    static let enabled: Set<ContentLanguage> = [.zh, .ko]

    /// 启动时解析一次即可。
    static let current: ContentLanguage = resolve(from: Locale.preferredLanguages)

    /// 扫全量 preferredLanguages（不是只看第一个）：
    /// 手机用英文 UI 的韩国用户，ko 通常也在偏好列表里，能被正确命中。
    /// 其他系统语言 fallback zh（翻译音轨是 5 遍流程的第 4 遍，没有"无翻译模式"，
    /// 且 zh 内容目录最全）。
    static func resolve(from preferred: [String]) -> ContentLanguage {
        for id in preferred {
            let locale = Locale(identifier: id)
            guard let code = locale.language.languageCode?.identifier else { continue }
            let candidate: ContentLanguage?
            switch code {
            case "zh":
                // 繁体判定：script Hant（zh-TW / zh-HK / zh-Hant-*）
                candidate = locale.language.script?.identifier == "Hant" ? .zhHant : .zh
            case "ko": candidate = .ko
            case "ja": candidate = .ja
            case "es": candidate = .es
            case "pt": candidate = .ptBR
            default: candidate = nil
            }
            if let c = candidate, Self.enabled.contains(c) { return c }
        }
        return .zh
    }

    /// OSS 衍生文件名后缀："" / "_ko" / "_ja"…（zh 保持老文件名，兼容线上老版本）
    var fileSuffix: String {
        self == .zh ? "" : "_\(rawValue)"
    }

    /// 本地缓存文件名后缀，规则同上（zh 老缓存文件名不变，升级无感）。
    var cacheSuffix: String { fileSuffix }
}
