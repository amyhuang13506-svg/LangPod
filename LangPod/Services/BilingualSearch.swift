import Foundation

/// 中英文双向搜索辅助。把用户输入扩展成所有等价词条，
/// 在 haystack 文本里命中任一就算匹配。
/// 例：搜索「Tesla」→ 同时匹配「特斯拉」；搜索「特斯拉」→ 同时匹配「Tesla」。
enum BilingualSearch {
    /// 公司 / 人物 / 主题的中英对照表。key = 英文小写，value = 中文等价词数组。
    /// 双向查询：英→中（key 命中扩中文）+ 中→英（中文命中扩 key）+ 子串匹配。
    private static let mappings: [String: [String]] = [
        // 公司 / 品牌
        "tesla":          ["特斯拉"],
        "nvidia":         ["英伟达", "英偉達"],
        "apple":          ["苹果"],
        "google":         ["谷歌"],
        "openai":         ["OpenAI"],
        "anthropic":      ["Anthropic"],
        "microsoft":      ["微软"],
        "meta":           ["脸书", "Facebook"],
        "facebook":       ["脸书"],
        "deepmind":       ["DeepMind"],
        "y combinator":   ["YC", "孵化器"],
        "ted":            ["TED 演讲"],
        "stanford":       ["斯坦福"],
        "huberman":       ["休伯曼"],
        "lex fridman":    ["Lex", "弗里德曼"],
        "veritasium":     ["真理元素"],
        "kurzgesagt":     ["简而言之"],
        "diary of a ceo": ["CEO日记"],
        "all-in":         ["All In", "硅谷四叔"],
        "acquired":       ["公司战略复盘"],
        "dwarkesh":       ["Dwarkesh", "帕特尔"],
        "mkbhd":          ["科技评测"],

        // 人物
        "jensen huang":    ["黄仁勋"],
        "jensen":          ["黄仁勋"],
        "elon musk":       ["马斯克"],
        "elon":            ["马斯克"],
        "tim cook":        ["库克"],
        "sam altman":      ["奥特曼", "山姆"],
        "altman":          ["奥特曼"],
        "sundar pichai":   ["皮查伊"],
        "sundar":          ["皮查伊"],
        "satya nadella":   ["纳德拉"],
        "satya":           ["纳德拉"],
        "mark zuckerberg": ["扎克伯格", "小扎"],
        "zuckerberg":      ["扎克伯格"],
        "dario amodei":    ["阿莫代", "阿莫德伊"],
        "demis hassabis":  ["哈萨比斯"],
        "steve jobs":      ["乔布斯"],
        "bill gates":      ["盖茨"],

        // 主题 / 关键词
        "ai":              ["人工智能"],
        "agi":             ["通用人工智能"],
        "chip":            ["芯片"],
        "gpu":             ["图形处理器"],
        "podcast":         ["播客"],
        "interview":       ["访谈", "采访"],
        "keynote":         ["主旨演讲", "发布会"],
        "earnings":        ["财报"],
        "startup":         ["创业"],
        "neuroscience":    ["神经科学"],
        "science":         ["科学"],

        // App 学习内容（级别 / 模块）—— 让用户能用「初级」搜到 easy 级 episode
        "easy":            ["初级", "简单"],
        "medium":          ["中级", "中等"],
        "hard":            ["高级", "困难"],
        "pattern":         ["句型", "句型讲解", "讲解"],
        "vocabulary":      ["词汇", "单词", "生词"],
        "episode":         ["集", "播客集", "学习播客"],
    ]

    /// 把单条查询扩展成所有等价词（包含原查询本身）
    static func expand(_ query: String) -> [String] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var terms = Set([q])

        // 1. 完全匹配：英文 → 中文
        if let alts = mappings[q] {
            for a in alts { terms.insert(a.lowercased()) }
        }
        // 2. 完全匹配：中文 → 英文
        for (key, alts) in mappings {
            if alts.contains(where: { $0.lowercased() == q }) {
                terms.insert(key)
            }
        }
        // 3. 子串匹配：query 包含 key（如「Sam Altman 的演讲」也命中「奥特曼」）
        for (key, alts) in mappings {
            if q.contains(key) {
                terms.insert(key)
                for a in alts { terms.insert(a.lowercased()) }
            }
            for alt in alts where q.contains(alt.lowercased()) {
                terms.insert(key)
                for a2 in alts { terms.insert(a2.lowercased()) }
            }
        }
        return Array(terms)
    }

    /// 检查 haystack 中是否命中查询的任一扩展词（不区分大小写）。
    /// 先做直接 contains 兜底（最快路径），再走中英扩展匹配。
    static func matches(query: String, in haystack: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }

        let h = haystack.lowercased()
        if h.contains(q) { return true }
        for t in expand(query) where h.contains(t) { return true }
        return false
    }
}
