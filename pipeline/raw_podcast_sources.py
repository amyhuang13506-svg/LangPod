"""
硅谷原声 内容源清单。
- YouTube 频道：监听新视频上传（大佬演讲 / 公司发布会 / 重大事件 keynote）
- RSS feeds：监听新播客集（访谈 / 行业分析 / 科技新闻）
- 重大事件：除人物外，覆盖新模型发布、产品发布、财报等

每条记录：
  - handle / url    : 源识别
  - label           : 显示用的简短名
  - topic           : Castlingo 内容主题分类
  - tier            : 1=必追（每天看）2=次要（隔天看）3=低频
  - kind            : speaker | company | model_release | news | analysis
"""

# YouTube 频道（公司官方 + 大佬个人 + 优质访谈节目）
# category: tech_keynote = 「硅谷原声」section / explore = 「探索」section
YOUTUBE_CHANNELS = [
    # === 公司官方频道（产品/模型/财报发布的第一手）===
    {"handle": "@NVIDIA",            "label": "NVIDIA",         "topic": "AI · 芯片",       "tier": 1, "kind": "company",  "category": "tech_keynote"},
    {"handle": "@OpenAI",            "label": "OpenAI",         "topic": "AI · 模型",       "tier": 1, "kind": "company",  "category": "tech_keynote"},
    {"handle": "@anthropic-ai",      "label": "Anthropic",      "topic": "AI · 模型",       "tier": 1, "kind": "company",  "category": "tech_keynote"},
    {"handle": "@Apple",             "label": "Apple",          "topic": "硬件 · 苹果",     "tier": 1, "kind": "company",  "category": "tech_keynote"},
    {"handle": "@Google",            "label": "Google",         "topic": "AI · 搜索",       "tier": 1, "kind": "company",  "category": "tech_keynote"},
    {"handle": "@GoogleDeepMind",    "label": "DeepMind",       "topic": "AI · 模型",       "tier": 1, "kind": "company",  "category": "tech_keynote"},
    {"handle": "@Microsoft",         "label": "Microsoft",      "topic": "AI · 云",         "tier": 1, "kind": "company",  "category": "tech_keynote"},
    {"handle": "@Meta",              "label": "Meta",           "topic": "AR/VR · AI",      "tier": 1, "kind": "company",  "category": "tech_keynote"},
    {"handle": "@xAI",               "label": "xAI",            "topic": "AI · 模型",       "tier": 2, "kind": "company",  "category": "tech_keynote"},

    # === 优质访谈 / 长播客频道（视频版）===
    {"handle": "@lexfridman",        "label": "Lex Fridman",    "topic": "AI · 访谈",       "tier": 1, "kind": "analysis", "category": "tech_keynote"},
    {"handle": "@DwarkeshPatel",     "label": "Dwarkesh",       "topic": "AI · 访谈",       "tier": 1, "kind": "analysis", "category": "tech_keynote"},
    {"handle": "@AcquiredFM",        "label": "Acquired",       "topic": "商业 · 战略",     "tier": 2, "kind": "analysis", "category": "tech_keynote"},
    {"handle": "@allin",             "label": "All-In",         "topic": "硅谷 · 科技",     "tier": 2, "kind": "analysis", "category": "tech_keynote"},

    # === 探索：TED / Stanford / YC（经典思想 + 创业）===
    {"handle": "@TED",               "label": "TED",            "topic": "思想 · 演讲",     "tier": 1, "kind": "speaker",  "category": "explore"},
    {"handle": "@Stanford",          "label": "Stanford",       "topic": "学术 · 演讲",     "tier": 2, "kind": "speaker",  "category": "explore"},
    {"handle": "@YCombinator",       "label": "Y Combinator",   "topic": "创业 · 投资",     "tier": 1, "kind": "speaker",  "category": "explore"},

    # === 探索：科普 + 思考 ===
    {"handle": "@veritasium",        "label": "Veritasium",     "topic": "科学 · 科普",     "tier": 1, "kind": "speaker",  "category": "explore"},
    {"handle": "@kurzgesagt",        "label": "Kurzgesagt",     "topic": "科学 · 动画",     "tier": 1, "kind": "speaker",  "category": "explore"},
    {"handle": "@3blue1brown",       "label": "3Blue1Brown",    "topic": "数学 · 可视化",   "tier": 2, "kind": "speaker",  "category": "explore"},

    # === 探索：访谈 + 思想 ===
    {"handle": "@hubermanlab",       "label": "Huberman Lab",   "topic": "健康 · 神经科学", "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@TheDiaryOfACEO",    "label": "Diary of a CEO", "topic": "商业 · 访谈",     "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@ChrisWillx",        "label": "Modern Wisdom", "topic": "思想 · 访谈",     "tier": 2, "kind": "analysis", "category": "explore"},
    {"handle": "@TimFerriss",        "label": "Tim Ferriss",    "topic": "商业 · 访谈",     "tier": 2, "kind": "analysis", "category": "explore"},

    # === 探索：科技产品评测 / 文化 ===
    {"handle": "@mkbhd",             "label": "MKBHD",          "topic": "科技 · 评测",     "tier": 2, "kind": "analysis", "category": "explore"},
]

# RSS feeds 已停用 —— 用户决策：硅谷原声只收视频访谈（YouTube）。
# 真人画面 + 听清原音的体验远好于纯音频，且大佬访谈在 YouTube 上覆盖最全
# （Lex Fridman / Acquired / Dwarkesh / All-In 都同步发 YouTube）。
# 如未来想加纯播客，开新 section 不与硅谷原声混。
RSS_FEEDS: list[dict] = []

# 选题打分（默认权重，pipeline 会按这个优先级排序）
TIER_BONUS = {1: 30, 2: 15, 3: 5}
KIND_BONUS = {
    "company":        20,    # 公司官方 = 第一手
    "speaker":        15,    # 大佬演讲
    "model_release":  25,    # 新模型发布优先级最高
    "news":           10,    # 一般新闻
    "analysis":       12,    # 解读类
}
