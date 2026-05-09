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

    # === 探索：娱乐 / 名人访谈（轻松输入 + 真实英语口语）===
    {"handle": "@FirstWeFeast",      "label": "Hot Ones",       "topic": "娱乐 · 名人访谈", "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@VanityFair",        "label": "Vanity Fair",    "topic": "娱乐 · 文化",     "tier": 2, "kind": "analysis", "category": "explore"},
    {"handle": "@WIRED",             "label": "WIRED",          "topic": "娱乐 · 科技文化", "tier": 2, "kind": "analysis", "category": "explore"},
    {"handle": "@Vogue",             "label": "Vogue",          "topic": "娱乐 · 时尚",     "tier": 2, "kind": "analysis", "category": "explore"},

    # === 探索：脱口秀 / 喜剧（纯单口 + 明星娱乐导向，避开政治晚间秀）===
    # Jimmy Fallon: 主打游戏 / 明星互动 / Lip Sync Battle，政治含量低
    {"handle": "@TheTonightShow",    "label": "Jimmy Fallon",    "topic": "娱乐 · 文化", "tier": 1, "kind": "analysis", "category": "explore"},
    # Netflix Is A Joke: 纯 stand-up specials 片段（Kevin Hart / Ali Wong / Trevor Noah 等）
    {"handle": "@NetflixIsAJoke",    "label": "Netflix Stand-up", "topic": "娱乐 · 文化", "tier": 1, "kind": "analysis", "category": "explore"},
    # JustForLaughs: 加拿大喜剧节官方，纯 stand-up 专场
    {"handle": "@JustForLaughs",     "label": "Just for Laughs", "topic": "娱乐 · 文化", "tier": 2, "kind": "analysis", "category": "explore"},
    # Dry Bar Comedy: 干净 stand-up（无政治、无脏话）
    {"handle": "@DryBarComedy",      "label": "Dry Bar Comedy",  "topic": "娱乐 · 文化", "tier": 2, "kind": "analysis", "category": "explore"},
    # Conan O'Brien Needs A Friend: Conan 名人访谈播客（轻喜剧），政治极少
    {"handle": "@TeamCoco",          "label": "Conan O'Brien",   "topic": "娱乐 · 文化", "tier": 2, "kind": "analysis", "category": "explore"},

    # === 探索：两性 / 关系 / 心理 ===
    {"handle": "@MatthewHussey",     "label": "Matthew Hussey", "topic": "两性 · 沟通",     "tier": 1, "kind": "speaker",  "category": "explore"},
    {"handle": "@JayShetty",         "label": "Jay Shetty",     "topic": "两性 · 人生导师", "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@TheSchoolofLife",   "label": "School of Life", "topic": "两性 · 心理动画", "tier": 1, "kind": "speaker",  "category": "explore"},
    {"handle": "@IAmMarkManson",     "label": "Mark Manson",    "topic": "两性 · 心理",     "tier": 2, "kind": "speaker",  "category": "explore"},
    {"handle": "@medcircle",         "label": "MedCircle",      "topic": "心理 · 专家访谈", "tier": 2, "kind": "analysis", "category": "explore"},

    # === 探索：娱乐 · 名人访谈（华人喜爱方向重点扩充）===
    {"handle": "@callherdaddy",          "label": "Call Her Daddy",   "topic": "两性 · 访谈",     "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@armchairexpertpod",     "label": "Armchair Expert",  "topic": "娱乐 · 名人访谈", "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@SmartLess",             "label": "SmartLess",        "topic": "娱乐 · 名人访谈", "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@AccessHollywood",       "label": "Access Hollywood", "topic": "娱乐 · 八卦",     "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@Variety",               "label": "Variety",          "topic": "娱乐 · 明星访谈", "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@GrahamNortonOfficial",  "label": "Graham Norton",    "topic": "娱乐 · 明星访谈", "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@Glamour",               "label": "Glamour",          "topic": "娱乐 · 明星访谈", "tier": 2, "kind": "analysis", "category": "explore"},
    {"handle": "@people",                "label": "PEOPLE",           "topic": "娱乐 · 明星访谈", "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@AmeliaDimoldenberg",    "label": "Chicken Shop Date","topic": "娱乐 · 明星访谈", "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@CapitalOfficial",       "label": "Capital FM",       "topic": "娱乐 · 明星访谈", "tier": 2, "kind": "analysis", "category": "explore"},
    {"handle": "@BUILDseriesNYC",        "label": "BUILD Series",     "topic": "娱乐 · 明星访谈", "tier": 2, "kind": "analysis", "category": "explore"},

    # === 探索：两性 · 关系顶流 / 喜剧 ===
    {"handle": "@EstherPerel",           "label": "Esther Perel",     "topic": "两性 · 关系",     "tier": 1, "kind": "speaker",  "category": "explore"},
    {"handle": "@whitneycummings",       "label": "Whitney Cummings", "topic": "两性 · 喜剧",     "tier": 2, "kind": "analysis", "category": "explore"},

    # === 探索：心理 · 情感（短视频博主，TikTok 已火）===
    {"handle": "@DrJulie",               "label": "Dr Julie Smith",   "topic": "心理 · 情感",     "tier": 1, "kind": "speaker",  "category": "explore"},

    # === 探索：美食 · 制作 / vlog（华人爱看吃，听力轻松）===
    {"handle": "@bonappetit",            "label": "Bon Appétit",      "topic": "美食 · 制作",     "tier": 1, "kind": "analysis", "category": "explore"},
    {"handle": "@JoshuaWeissman",        "label": "Joshua Weissman",  "topic": "美食 · vlog",     "tier": 2, "kind": "analysis", "category": "explore"},
    {"handle": "@MarkWiens",             "label": "Mark Wiens",       "topic": "美食 · 旅游",     "tier": 1, "kind": "analysis", "category": "explore"},

    # === 探索：旅游 · vlog ===
    {"handle": "@DrewBinsky",            "label": "Drew Binsky",      "topic": "旅游 · vlog",     "tier": 2, "kind": "analysis", "category": "explore"},
    {"handle": "@KaraandNate",           "label": "Kara and Nate",    "topic": "旅游 · vlog",     "tier": 2, "kind": "analysis", "category": "explore"},
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
# Topic 加权 —— 华人英语学习者偏好的内容方向，按 topic 字段前缀匹配。
# 设计原则：娱乐/两性 > company(20) 让生活类内容能压过科技公司发布会冒头，
# AI / 商业等给小幅减分（不归零）确保科技源仍偶尔上榜不被完全淹没。
TOPIC_BONUS = {
    "娱乐": 28,
    "两性": 25,
    "心理": 18,
    "美食": 15,
    "旅游": 12,
    "AI":   -8,   # 降权，但有重大发布时仍可凭 model_release 加分上位
    "商业": -3,
    "硬件": 0,
    "科技": 0,
    "思想": 5,
    "学术": 0,
    "AR/VR": 0,
}
