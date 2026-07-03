# 方案：句型 Tab 改版 + 我的句子 + 小课堂细节优化

> 项目内同步版本：docs/plan_句型页改版与小课堂优化.md（批准后同步更新）

## Context

词汇小课堂（场景图解词汇 + ElevenLabs 发音）已上线真机。用户体验后提出一批迭代：
- 小课堂单词卡两处排版/交互问题 + 词汇页图标位置
- 把「记录」tab 整个换成「句型」tab：每日生成的句型讲解以**文本形式**集中展现（页面结构仿词汇 tab：居中标题 + 右上「我的」）
- 新增「我的句子」收藏系统：带**使用场景**字段，收藏夹内置**连词成句**练习
- 句型例句发音：**不需要任何回溯/新合成**——例句本来就在讲解音频里被完整朗读过（explainer_script 的 example1/2/3 段有独立时间戳、纯英文），App 直接截段播放即可。老句型是 MiniMax 音色、4-22 起是 ElevenLabs v3，都能截段，零成本全覆盖
- 连词成句句长控制：**≤ 12 个单词**（用户已确认）
- 「我的句子」除连词成句外，再加**场景模拟**练习（场景选择题：给定场景，选出该说哪句）
- 右上角「我的」入口图标：**对称图标**（词汇页用展开的书 `book.fill`），**不要**课堂详情页那种白圆底按钮样式，句型页同理

用户问"重做一个跟单词一样的页面 vs 沿用现在的句型页面"——本方案采用**重做同构页面**：和词汇 tab 结构一致（居中标题 + 右上我的收藏），信息架构统一；现有 PatternHistoryView 是为音频播放列表设计的，新定位是文本学习，只复用其日期分组和 gating 逻辑，页面骨架新写。首页的今日句型区块和播放器不动。

## 批次一：小修（~1 小时）

### 1. 单词卡排版（LessonDetailView.swift 的 LessonWordCard）
单词独占第一行（`lineLimit(1)` + `minimumScaleFactor(0.6)`，超长自动缩字号），音标移到第二行与中文释义、难度标签同排。

### 2. 单词卡弹窗高度自适应（LessonDetailView.swift）
现在固定 `.presentationDetents([.medium])` 永远半屏。改为 PreferenceKey 实测内容高度 → `.presentationDetents([.height(实测)])`，上限 0.75 屏。

### 3. 词汇页「我的」图标（VocabularyView.swift header）
图标换成**对称的展开书本** `book.fill`（books.vertical.fill 不对称），下面「我的」两字不变；**不加**白圆底（用户明确不要课堂详情页那种按钮样式）；右边距 20→24 不再贴边。句型页右上角「我的」同样用对称图标（`bookmark.fill`）。

## 批次二：句型 Tab + 我的句子（~4 小时）

### 4. 数据层：SavedSentence + SentenceStore（新文件）
- `SavedSentence`：english / chinese / **scene（使用场景）** / source（"lesson"|"pattern"）/ sourceLabel（课堂名或句型 template）/ audioUrl（可选）/ **audioStart / audioEnd（可选，pattern 例句 = 讲解音频截段区间）** / savedDate，id = english
  - scene 来源：小课堂句型 → 课堂标题（"在 CVS 买非处方药"）；句型例句 → pattern.scene（"日常请求 / 寻求许可"）
  - 音频来源：小课堂句型 → 独立 mp3 URL；句型例句 → 讲解音频 URL + start/end 截段；都取不到 → WordSpeaker TTS 兜底
- `SentenceStore`：@Observable + UserDefaults 持久化（仿 VocabularyStore），add/remove/isSaved
- 埋点：Analytics 加 `sentence_save` / `sentence_practice_complete`
- 注册到 LangPodApp 环境（同 VocabularyStore 的注入方式）

### 5. Tab 替换（ContentView.swift）
- 第三个 tab：`StatsView`（记录）→ `PatternsTabView`（句型，图标 `quote.bubble`）
- **删除** StatsView.swift；MemoryDetailView.swift / MasteryDetailView.swift 先 grep 确认只被 StatsView 引用后一并删除，pbxproj 同步移除
- Streak 数据/completeEpisode 逻辑保留（首页徽章、分享卡在用），只删页面

### 6. 句型页 PatternsTabView（新文件，结构仿词汇 tab）
- 居中标题「句型」+ 右上角「我的」（图标+文字，白圆底，同词汇页新样式）
- 数据：`dataStore.episodes`（三级别合并）的 patterns，按日期倒序分组（"7月3日 / 昨天 / …"）
- 卡片：template 大字（serif 同 PatternPlayerContent 风格）+ translation_zh + scene tag + 级别小标 + 锁标
- 付费：复用 `PatternAccessGate.canAccess`（今日免费 + 历史 Pro）→ PaywallView
- 点卡片 → 文本详情 sheet（PatternTextDetailView，新）：
  - 顶部：template + 中文 + 一个小「播放讲解」按钮（现有讲解音频，文本为主音频为辅）
  - 讲解正文：explainer_script 按 section 分段渲染 text_zh（跟读/例句段附 text_en）
  - 3 个例句：从 explainer_script 的 example1/2/3 段取（text_en + 同段 text_zh 前缀行；老数据回落 example_sentences 数组）；每句 🔊 = **讲解音频按 start/end 截段播放**（LessonAudioPlayer 扩展 `play(url:from:to:)`：seek 到 start、到 end 停），无时间戳的老数据 → WordSpeaker 兜底；+「加入我的句子」＋按钮（已加变 ✓）

### 7. 我的句子页 MySentencesView（新文件，仿 MyVocabularyView）
- 关闭按钮 + 居中标题「我的句子」+ 句数
- 列表行：英文 + 中文 + **场景 tag** + 🔊（截段/mp3/TTS 三级）+ 左滑删除；来源小标（"来自：机场课堂"）
- 底部固定双 CTA（仿词汇页配对+连词成句的蓝橙并排样式）：「连词成句」→ SentencePracticeView；「场景模拟」→ SceneQuizView
- 空态："在句型和小课堂里点 ＋ 收藏句子"

### 8. 收藏入口（两处改动）
- LessonDetailView 常用句型行尾加 ＋（已加 ✓ 绿色），scene = 课堂标题
- PatternTextDetailView 例句行 ＋，scene = pattern.scene

### 9. 我的句子·连词成句 SentencePracticeView（新文件）
现有 FeynmanChallengeView 与 SavedWord 记忆体系深耦合，不改造它；新写轻量版：
- 复用 WordToken 词块交互模式（打散 → 点选拼句 → 对错反馈 + 震动），题源 = 收藏句子（shuffle）
- 完成页简单庆祝（复用星星动效思路），不进 SavedWord 记忆体系，无每日次数限制（自己收藏的内容随便练）
- 超过 12 词的收藏句不出题（过滤）

### 10. 我的句子·场景模拟 SceneQuizView（新文件，场景选择题）
- 题型：给定使用场景（题干 = scene tag + 中文意思，"在美国药店，你想问有没有治嗓子疼的药，该说哪句？"）→ 4 个英文句子选项单选（1 个正确 + 3 个从其他收藏句随机抽的干扰项）
- 对错反馈：选对绿色 + 震动 + 自动播放该句发音；选错红闪显示正确答案
- 需要 ≥ 4 个收藏句才可玩，不足时按钮置灰提示"再收藏几句解锁"
- 多轮制（每轮 5 题或收藏数上限），完成页同连词成句
- 埋点：`sentence_quiz_complete`

### 11. 连词成句句长 ≤ 12 个单词
- FeynmanChallengeView 选题过滤：`example.split(separator: " ").count <= 12`（超长词直接不进题池）
- SentencePracticeView 同一规则
- pipeline 未来内容约束：generate_lessons.py 和 extract_patterns.py 的 prompt 加 "example sentences must be ≤ 12 words"（仅这一处 pipeline 改动，随下次部署服务器带上，不阻塞本期）

## 实施顺序

```
批次一（1-3）→ 编译部署 → 用户验收一次
批次二（4-11）→ 编译部署 → 用户验收
全部完成后同步 docs/plan 文件 + commit push
（无跑批、无服务器部署——例句音频靠截段播放，零 pipeline 工作）
```

## 真机验证清单
- [ ] 长单词一行显示 + 音标第二行；短词弹窗矮、长例句弹窗高（不再固定半屏）
- [ ] 词汇页「我的」= 对称书本图标（无圆底、不贴边）；句型页「我的」= 对称图标
- [ ] 句型 tab：日期分组文本卡、今日免费可开、历史句型锁 Pro 弹 paywall
- [ ] 句型详情：讲解文本分段展示、播放讲解按钮可用、**例句 🔊 截段播放干净（起止不吞字、不带到下一句）**
- [ ] 收藏：小课堂常用句型 ＋ / 句型例句 ＋ → 我的句子出现（带场景 tag）、可发音、左滑删、重启不丢
- [ ] 我的句子连词成句：只出 ≤12 词的句子、对错反馈正常、无次数限制
- [ ] 场景模拟：<4 句时置灰提示；答对播发音、答错显示正确答案
- [ ] 词汇本连词成句不再出现 >12 词的长句
- [ ] 记录页消失、首页 streak 徽章和分享卡正常

## 明确不做
- 首页句型区块/播放器调整（不动）
- 例句音频回溯/新合成（用户确认不需要——讲解音频截段播放已覆盖）
- 我的句子的记忆曲线/复习调度（先积累使用数据）
