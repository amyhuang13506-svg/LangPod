# 词汇 Tab 改版方案 v2：日常词汇 + 生活场景双区块

> 状态：待确认。确认后按「分期执行」动代码。
> 日期：2026-07-17

## 1. 背景与目标

**现状：**
- 词汇小课堂以国家为一级导航（6 国 chips），共 131 课，实际只有 41 个独立场景（同场景 ×6 国重复生成）
- 内容偏「落地办事」（海关、开户、DMV），缺少高频日常词（身体、颜色、数字、食材、日用品）
- 免费面极窄：仅美国第一课（bank_account）+ 每日课当天免费

**目标：**
1. 新增「日常词汇」内容线：按语义主题组织的图解词汇课（图解词典模式）
2. 词汇 tab 改为「日常词汇 | 生活场景」左右双区块：日常词汇带主题分类子 chips；生活场景保留现有国家 chips 原样，不加子 chips
3. 免费深度加大：固定免费课从 1 课扩到 6 课，让免费用户有完整体验

## 2. 信息架构与 UI

```
┌──────────────────────────────────────┐
│            词汇小课堂         [我的]   │
│                                      │
│   ┌────────────┐  ┌────────────┐     │
│   │  日常词汇   │  │  生活场景    │     │  ← 左右两个等宽大区块（选中填充色）
│   └────────────┘  └────────────┘     │     @AppStorage 记住上次停留
│                                      │
│   [今日课堂全局大卡]                    │  ← 保留，跨区块置顶（免费钩子）
│                                      │
│   ── 选中「日常词汇」──                 │
│   身体 · 基础 · 家居 · 食物 · 穿着 · 自然 │  ← 主题分类 chips（横滑）
│   → 该大类主题课卡片（复用 LessonCoverCard）│
│                                      │
│   ── 选中「生活场景」──                 │
│   🇺🇸美国 🇬🇧英国 🇦🇺澳洲 🇨🇦加拿大 …    │  ← 现有国家 chips 原样保留
│   → 现有分区横滑列表（按分类分区 +       │
│     查看更多），完全不动                 │
└──────────────────────────────────────┘
```

**设计细节：**
- 大区块切换：两个等宽胶囊左右排布，类似 segmented control 但视觉上是两张大 chips
- 生活场景区 = 现状原样搬入：CountryChipsRow + 按 category 分区的横滑列表 + 「查看更多」网格页（LessonCategoryAllView），不加场景分类子 chips，**该区块零改动**
- 日常词汇区：一排主题分类 chips（6 大类），选中显示该大类主题课卡片

## 3. 日常词汇内容目录 v1

6 大类，每课结构与场景课一致（zones + hotspots + extra_words + 例句 + 发音）：

| 大类 id | 中文 | 主题课（首批粗体） |
|---|---|---|
| body | 人与身体 | **身体部位**、**脸与五官**、日常动作、情绪感受 |
| basics | 基础概念 | **数字与时间**、**颜色与形状**、天气与季节、方位与位置 |
| home | 家与日用 | **厨房**、**随身物品**（钥匙/卡/充电器）、客厅与卧室、浴室 |
| grocery | 食物食材 | **水果**、**蔬菜**、肉蛋奶与饮料、调料与餐具 |
| clothing | 穿着 | **衣物**、鞋帽与配饰 |
| outdoor | 户外与自然 | **交通工具**、街道设施、动物、植物花草 |

首批 12 课（加粗），全目录约 22 课，后续按每日/隔日节奏补齐。

**与场景课的差异：**
- 无国家维度：一版全球通用，拼写与口音默认美音（en-US）→ 生成成本是场景课的 1/6
- 无 roleplay；culture_tips 改为「用法小贴士」（如 hand/arm 的边界、a pair of 的用法）
- 插画从「环境场景」改为「图解板」（diagram）：浅底、单一主体 + 物品铺排、预留热点空间（正面人体图、摊开的厨房台面、一排水果）
- sentences 保留：用本课高频词造 6-8 个日常短句

## 4. 数据模型与 OSS 结构

**核心决定：复用现有 SceneLesson 全套模型，主题课伪装成一个特殊「国家」`daily`。**

- OSS：`lessons/daily/index.json` + `lessons/daily/{id}/lesson.json`，与 `lessons/{country}/` 完全同构
- `country` 字段填 `"daily"`，`category` 填主题大类 id（body/basics/home/grocery/clothing/outdoor）
- APIService 现有 `fetchLessonIndex(country:)` / `fetchLessonDetail(country:id:)` 直接可用，**零接口新增**
- ⚠️ `daily` 不加进 `countries.json`（老版本 App 会把它当国家渲染出来）；新版 App 直接请求 `lessons/daily/index.json`
- 课堂 id 约定：`lesson_daily_{slug}`（如 `lesson_daily_body_parts`）

**LessonStore 新增：**
- `section: LessonSection`（@AppStorage，daily / scene）
- `themeIndex`（daily 目录加载 + 缓存，复用现有 index 缓存逻辑）
- `selectedThemeCategory` 筛选状态（仅日常词汇区；不持久化，进 tab 默认第一个大类）

## 5. 免费策略（加深免费体验）

固定免费课 1 → 6，每日课不变：

| 区块 | 免费课 | 说明 |
|---|---|---|
| 日常词汇 | 身体部位、数字与时间、水果 | 3 课，覆盖 3 个大类，图解体验最好的选题 |
| 生活场景 | bank_account（保留）+ coffee_order + supermarket | 新增 2 课，仅美国版免费，其他国家版本仍 Pro（保留升级动机） |
| 每日课 | 当天免费 | 不变 |

- 实现走内容 `is_free` 字段：老内容只需脚本改 JSON 字段重传 index + lesson，**不重新生成**
- App 端 `isFreeSample` 的「第一国第一课」特判逻辑删除，统一信任 `is_free` + 每日课判定（LessonAccessGate 收口）
- 对老版本 App 同样生效（免费面变宽方向的变更，无风险）
- 二期可选：Pro 课允许免费用户看第一个 zone，点第二个 zone 弹付费墙（「预览式付费墙」，本期不做）

## 6. Pipeline 改动清单

1. **`theme_catalog.py`（新）**：THEME_CATEGORIES + THEME_BOARDS 人工定稿目录，风格同 lesson_catalog.py（每课 zones + hint）
2. **`generate_lessons.py`**：支持 `--theme` 模式（country 固定 daily；prompt 去掉国家品牌锚点，改图解板语境；不生成 roleplay）
3. **`generate_lesson_images.py`**：新增 diagram 风格 prompt 模板（浅底图解板、物品铺排、留热点空间，画风与现有插画统一）
4. **`generate_lesson_audio.py`**：直接复用（en-US 音色）
5. **`upload_lessons.py`**：支持 daily 目录上传 + index 生成
6. **免费位脚本（一次性）**：把 coffee_order/supermarket（美国版）及 3 门主题课的 `is_free` 置 true 并重传

## 7. App 改动清单

- **VocabularyView**：顶部加双区块 segmented；生活场景区 = 现有内容原样（CountryChipsRow + 分区列表，不动）；日常词汇区 = 主题分类 chips + 课卡列表
- **SceneLessonSection**：不改
- **LessonStore**：见第 4 节；`freeSampleLessonId` 逻辑删除，统一走 is_free
- **Analytics 新事件**：
  - `vocab_section_switch`（daily / scene）
  - `theme_lesson_open`（lesson_id, category）
  - `theme_category_filter`（category）
- **空态**：日常词汇区在内容未上线前显示「即将上线」占位（P1 先出框架时用）

## 8. 兼容与迁移

- `lessons/{country}/` 路径与内容全部不动，老版本 App 完全不受影响
- `daily` 目录是新增路径，老版本不会请求
- `lessonCountry` @AppStorage 语义保留（生活场景区的国家选择）
- is_free 扩宽对新老版本一致生效

## 9. 分期执行

- **P1（纯客户端 + 免费位，半天）**：双区块框架（生活场景区原样搬入）+ 免费位脚本重传。日常词汇区先挂「即将上线」占位或先隐藏区块开关
- **P2（内容首发，2-3 天）**：theme_catalog 定稿 → 首批 12 课生成（脚本/图/音频）→ 上传 → 日常词汇区上线
- **P3（后续迭代）**：主题课补齐全目录；「核心生活词覆盖率」进度条（有限集合才能做百分比，强留存钩子 + Pro 锚点）；Pro 课首 zone 预览；句型场景标签打通

## 10. 待确认决策

1. 大区块命名就用「日常词汇 / 生活场景」？（备选：基础词汇 / 场景实战）
2. 免费 6 课的具体选择（第 5 节表格）是否 OK？
3. 首批主题课 12 课（每大类 2 课）够不够，还是直接上 18 课？
4. 「核心词覆盖率」进度条放 P3 还是提前到 P2？

**已定决策：**
- ~~生活场景区加场景分类子 chips / 国家收进菜单 chip~~ —— 7/17 定：生活场景保留现有国家 chips 原样，不加子 chips，子分类 chips 只有日常词汇区有
