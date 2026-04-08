# LangPod Project — Claude Instructions

## 项目简介

LangPod 是一个 AI 英语播客电台 app，像 BBC 一样每天推送预生成的英语对话播客。用户零输入，被动吸收。核心玩法：每集播放 3 遍英语原音 → 1 遍母语翻译 → 1 遍英语原音 → 展示生词卡片。

**产品文档：** `~/Desktop/LangPod产品文档.md`（完整产品设计、交互流程、技术架构、成本模型）

## 项目基本信息

- **开发者**: Amy Huang (amyhuang13506@gmail.com)
- **Bundle ID**: com.amyhuang.langpod
- **Deployment Target**: iOS 17.0
- **开发语言 (Base)**: English（面向全球市场）
- **支持语言**: en, zh-Hans, ja
- **技术栈**: SwiftUI + Observable + StoreKit 2
- **服务器**: 阿里云（47.84.141.119，新加坡），与 BlackHole 共用

## 与 BlackHole 的关系

LangPod 从 BlackHole 复用以下模块（复制后按需修改，不是直接引用）：

- `SubscriptionManager.swift` → 改 Product ID 和用量规则
- `MusicPlayer.swift` → 改为支持 5 遍循环播放逻辑
- `PaywallView.swift` → 改文案和功能列表
- `OnboardingView.swift` → 改为选级别 + 选母语
- `DataStore.swift` → 改数据模型
- `Theme.swift` → 全新配色

**BlackHole 项目路径：** `~/Desktop/BlackHole/`

## Git 提交规则

- 每完成一个功能模块或修复，主动 commit + push 到 GitHub
- 每天工作结束前，确保所有改动已提交，不要留未提交的代码过夜
- Commit message 用英文，简洁描述改动内容
- 大量改动拆分提交：代码和媒体资源分开 commit
- 不要提交包含 API key、密码等敏感信息的文件

## 工作流程规则

1. **用户说"先做方案"时**：必须先写方案文件，等用户确认方案后再开始改代码。不要自动改代码。
2. **每次改完代码后**：自动编译并部署到真机运行，不需要等用户要求。

## 每次修改代码后必须编译并部署到真机

每次改完代码，必须：
1. 编译真机版本
2. 部署到真机运行（不要卸载重装）

```bash
# 1. 编译真机版本
xcodebuild -project LangPod.xcodeproj -scheme LangPod \
  -destination 'id=00008130-00046C3E3E90001C' \
  -allowProvisioningUpdates build \
  2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"

# 2. 部署到真机（巧玲 iPhone 15 Pro Max）
xcrun devicectl device install app \
  --device 00008130-00046C3E3E90001C \
  ~/Library/Developer/Xcode/DerivedData/LangPod-*/Build/Products/Debug-iphoneos/LangPod.app && \
xcrun devicectl device process launch \
  --device 00008130-00046C3E3E90001C com.amyhuang.castlingo
```

## UI 语言规则（关键）

**播客内容 = 英文，操作界面 = 中文（MVP）**

- 播客对话音频、字幕文本、生词英文部分 → 全部英文（这是学习内容）
- 所有按钮、标签、提示文字、导航 → 中文（这是操作界面）
- 生词释义、翻译 → 中文
- 举例：
  - 播客标题 "Coffee Culture" → 英文
  - "正在播放"、"第 2/5 遍"、"今日播客" → 中文
  - 生词卡片：英文单词 + 音标 → 英文，释义 → 中文
  - Tab Bar："首页"、"词汇"、"统计"、"我的" → 中文

## 本地化规则

- MVP 先做中文版，验证后再加多语言
- 静态字符串：`Text("中文")` 自动走 `LocalizedStringKey`
- 动态字符串：用 `NSLocalizedString(variable, comment: "")`
- Base language 设为中文（zh-Hans），后续加 en、ja

## 开发原则

1. **先用假数据开发 UI，最后接真实 API**
2. **不要硬编码内容** — 频道列表、定价等从服务器拉取
3. **每个功能一个 Git 分支**，做完合并到 main
4. **不要一次做太多** — 按启动顺序逐步推进
5. **UI 和代码同步进行** — 先在 Pencil 设计，确认后再写代码

## 启动顺序

```
✅ 第 1 步：创建项目目录 + CLAUDE.md
✅ 第 2 步：UI 设计（14 页，Pencil 文件：LangPod-UI.pen）
✅ 第 3 步：创建 Xcode 项目（新项目，不是复制 BlackHole）
✅ 第 4 步：准备假数据（3个级别各3集的 JSON，放在项目 Resources 里）
✅ 第 5 步：搭 app 骨架 + Onboarding（选级别页）
✅ 第 6 步：首页 UI（内容列表 + 正在播放卡片 + Tab Bar）
✅ 第 7 步：播放引擎（5遍自动播放 + 后台播放 + 自动缓存）
✅ 第 8 步：字幕模式 + 生词卡片 + 本集完成页
✅ 第 9 步：词汇本 + 记忆状态追踪（遗忘曲线）
✅ 第 10 步：学习统计页（费曼四层 + 记忆状态 + 详情页）
✅ 第 11 步：词义配对游戏
✅ 第 12 步：费曼挑战（造句 + AI 评分）
✅ 第 13 步：听力等级系统 + 解锁逻辑 + 升级庆祝动画
✅ 第 14 步：分享卡片 + Streak 系统
✅ 第 15 步：Paywall + 订阅管理 + 我的页面
✅ 第 16 步：后台 Pipeline（Python 脚本，跑在阿里云）← 可与 app 开发并行
□ 第 17 步：预生成首批内容（每级 10 集）← 需要填 API key 后运行 pipeline
✅ 第 18 步：接真实数据替换假数据
□ 第 19 步：测试 + 截图 + 提交审核
```

## 开发注意事项

- **新建 Xcode 项目**，不要复制 BlackHole。从 BlackHole 复用的代码单独复制过来
- **用假数据开发所有 UI**，最后再接真实 API（第 18 步）
- **后台 Pipeline 可以和 app 开发并行**，白天写 app，晚上调 Pipeline
- **UI 设计稿在 Pencil 里**：`LangPod-UI.pen`，开发时对照
- **产品文档**：`LangPod产品文档.md` 有完整的功能定义和数据结构

## 核心技术架构

```
后台 Pipeline（阿里云 cron）
  → GPT API 生成对话脚本 + 翻译 + 生词
  → ElevenLabs TTS 合成双人英语音频 + 母语翻译音频
  → 上传阿里云 OSS（.mp3 + .json）

iOS App
  → 请求内容列表 API（Nginx）
  → 流式播放 OSS 音频
  → 本地缓存已下载内容
```

## 音频缓存策略

- 播放过的音频自动缓存到 app 沙盒，用户无感知
- 无需"下载"按钮，无需下载管理界面
- 缓存上限：最近 50 集（约 250MB）
- 超出上限自动清理最早的缓存
- 未缓存的集数在线流式播放

## 播放引擎核心逻辑

```
每集播放流程：
1. 提示音
2. 英语原音 × 3 遍（每遍间隔 1 秒）
3. 提示音 "Now in your language"
4. 母语翻译音频 × 1 遍
5. 提示音 "One more time"
6. 英语原音 × 1 遍（最终）
7. 展示生词卡片（5-8 个核心词）
8. 自动播放下一集
```

## 三个难度频道

- 🟢 Easy：1000 词以内，慢速，3-5 分钟，日常对话
- 🟡 Medium：3000 词以内，中速，5-8 分钟，生活/文化话题
- 🔴 Hard：无限制，自然语速，8-12 分钟，新闻/商务

## MVP 策略

- 母语翻译先只做中文，验证后再加日韩西葡
- 先预生成每个级别 10 集内容，够用户听 2 周
- 先做纯听模式，学习模式（字幕）第二优先

## 开发日志

### 2026-03-26
- 创建项目目录和 CLAUDE.md
- 产品文档完成：~/Desktop/LangPod产品文档.md
- UI 设计完成：LangPod-UI.pen

### 2026-03-27
- 创建 Xcode 项目（iOS 17.0, SwiftUI, Bundle ID: com.amyhuang.langpod）
- 项目骨架：LangPodApp + ContentView(4 Tab) + 4 个 View 占位
- 数据模型：Episode, ScriptLine, VocabularyItem, PodcastLevel
- 假数据：3 级别 × 3 集 = 9 集 JSON（Resources/）
- MockDataLoader 加载器
- Onboarding 两页流程：Welcome → Level Select
- ContentView 根据 onboarding 状态切换显示
- DataStore 用 UserDefaults 持久化 onboarding 状态和选择的级别
- Theme.swift: Color(hex:) 扩展
- 首页 UI：问候语 + Streak 徽章 + 级别 Tab 切换 + 正在播放卡片 + 今日播客列表
- DataStore 扩展：episodes 加载、currentEpisode、streakDays
- AudioPlayer 引擎：5 遍自动播放（英×3 → 中×1 → 英×1），后台播放，锁屏控制
- PlayerView 全屏播放页：封面 + 遍数标签 + 进度条 + 控制按钮 + 字幕/速度
- HomeView 连接播放：点击播放/暂停，进度实时同步，点卡片打开全屏播放页
- Mock 模式：假数据 URL 用 simulatePlayback 模拟，接真实音频后无缝切换
- SubtitleOverlay：实时字幕浮层，按 script 时间戳匹配当前对话行，显示说话人+英文+中文翻译
- EpisodeCompleteView：本集完成页（统计行 + 生词卡片列表 + 下一集/保存词汇按钮）
- PlayerView 集成：5 遍播完自动切到完成页，点下一集继续播放
- SavedWord 模型：遗忘曲线（MemoryState: strong/fading/forgetting）+ 费曼四层（MasteryLevel: heard/recognized/canUse/canTeach）
- VocabularyStore：词汇持久化（UserDefaults）、间隔复习计算、按状态/掌握度筛选
- VocabularyView：已掌握/复习中/新词三色统计卡 + 今日新词列表 + 快速复习入口
- EpisodeComplete → 保存词汇流程打通
- StatsView：总时长/总词汇/已听集数 + 记忆状态卡片（进度条）+ 费曼四层卡片 + 复习/挑战 CTA
- MemoryDetailView：牢固/衰减中/即将遗忘 Tab 切换 + 词汇列表（含记忆百分比进度条）
- MasteryDetailView：听懂/认出/会用/能教 Tab 切换 + 层级说明 + 词汇列表
- WordMatchView：4词×2列配对游戏，多轮制，计时，配对成功变绿消失，错误红色闪烁
- 配对成功自动 markReviewed + 升级到 recognized
- 统计页/词汇本的"复习"CTA 均连接到词义配对
- FeynmanChallengeView：单词卡片 + 造句输入 + 本地评分 + 反馈卡片 + 多词挑战
- MVP 本地评分（检查包含目标词+句子长度），后续接 AI API
- 造句成功自动升级掌握度到"会用"
- 统计页"费曼挑战"CTA 连接
- ListeningLevel 模型：Lv.1~5，升级条件（集数+词汇），频道解锁映射
- LevelUpView：庆祝动画（弹性缩放+淡入）+ 解锁提示 + 炫耀/继续按钮
- DataStore 扩展：completeEpisode 自动检测升级，pendingLevelUp 触发庆祝页
- PlayerView 集成：播完→记录完成→检测升级→显示庆祝页→再显示完成页
- ShareCardView：渐变卡片（引言+大数字+徽章）+ 保存相册 + 系统分享
- Streak 系统：连续天数持久化，每日首次完成+1，断连重置，7/30/100天里程碑检测
- 升级后"炫耀一下"→ 打开分享卡片
- ProfileView 我的页面：用户卡片（头像+等级+Pro标签）+ 学习设置 + 功能入口 + 法律条款 + 清除数据
- PaywallView 付费墙：功能列表 + 三档价格（月/年/终身）+ 订阅按钮 + 恢复购买
- 所有 15 步 app UI 开发完成
- Pipeline 脚本（pipeline/ 目录）：generate_script → generate_audio → upload_oss → generate_daily
- 填入 API key 后运行 `python3 generate_daily.py easy` 即可生成第一批内容
- APIService：从阿里云拉取集列表+详情，三层 fallback（服务器→本地缓存→mock 数据）
- DataStore 改为异步加载：先显示 mock 数据，后台拉服务器数据无缝替换
- AudioPlayer 支持真实 URL：下载→缓存→播放，mock URL 仍走模拟播放
- Info.plist 配置 ATS 允许 HTTP 访问服务器 IP
- 下一步：第 17 步填 API key 运行 pipeline 生成内容，第 19 步测试+提交

**UI 优化轮（同日）：**
- 首页问候语去掉 👋 手势 emoji
- 首页新增"本周播客精选"区块（其他级别推荐，带级别标签+时长+生词数）
- 播放页倍速改为横条式选择器（点击弹出/收起，选中蓝底白字）
- 词汇页三个统计框改为可点击筛选器（已掌握/复习中/新词）+ 选中态边框
- 词汇页单词行：加音标 + 播放喇叭图标，去掉颜色圆点
- 词汇页"已掌握"筛选下加清零按钮（红色圆点→清完变绿色对勾）
- 费曼挑战改为"连词成句"（拖拽排列单词块，去掉打字输入）
- 两个练习 CTA（单词配对+连词成句）从统计页移到词汇页底部固定
- CTA 改为并排实心按钮（蓝+橙）
- 统计页改为"记录"页：学习日历（绿格子）+ 播放历史（按日分组）
- 播放历史：15天保留 + 收藏星标 + 收藏筛选 + 播放全部（Pro）
- 播放页底部加收藏按钮（字幕/速度/收藏一排）
- 所有一级页面 top padding 62→16
- 进度条支持拖动（播放页+首页卡片）
- 播放完成用 callback 替代 onChange 解决完成页不弹出问题
- 真机部署自动化（devicectl install + launch）

**Bug 修复轮（同日）：**
- 完成页累计词汇/升级进度从写死改为动态计算
- 分享卡片时长从写死改为真实数据
- 首页+播放页集数从"第 1 集"改为动态
- Streak 断连重置 0→1
- 记忆百分比从随机数改为真实遗忘曲线计算
- 删掉 Onboarding "我已有账号"空按钮
- 设置项去掉不可点的箭头
- 连词成句去掉标点干扰判定
- 隐私政策/用户协议改为 Link 跳转
- 个人资料卡片去掉箭头

### 2026-03-28 — Pipeline 完善 + 内容生成

**Pipeline 调通：**
- [x] GPT API（api.v3.cm 代理）+ MiniMax API 接入并测试通过
- [x] 修复 MiniMax 音频解码（hex 编码，非 base64）
- [x] 逐句生成音频（男女声交替）+ 真实时间戳计算
- [x] 修复长句触发 MiniMax 限制：自动拆分 >150 字符的句子
- [x] emotion 标签：GPT 为每句标注情感 → MiniMax 用对应语调
- [x] 非法 emotion 自动映射 + 失败后 neutral 重试
- [x] DALL-E 封面生成（新闻摄影风格，URL 模式下载）

**提示词优化：**
- [x] 三级别详细提示词（初级简单短句 / 中级朋友聊天 / 高级新闻播客）
- [x] 加入单人播报格式（Host）+ 双人对话混合
- [x] 禁止政治/军事/宗教等敏感话题
- [x] 限定 emotion 只能用 5 个合法值

**音色选定：**
- [x] 英语男声：English_DecentYoungMan
- [x] 英语女声：English_Upbeat_Woman
- [x] 中文男声翻译：male-qn-daxuesheng（大学生）
- [x] 中文女声翻译：presenter_female（主持人女）+ emotion 跟随内容

**UI 更新：**
- [x] EpisodeThumbnail 组件：支持 AI 封面 / bundle 图片 / 渐变色 fallback
- [x] 首页/播放页/历史所有列表统一缩略图排版
- [x] 播放页大封面替换蓝色耳机
- [x] 往期回顾区域 + 查看全部页面（搜索 + 按日期分组）
- [x] 锁屏/通知栏媒体控制：封面 + 标题 + 进度 + 播放速度
- [x] 正在播放卡片全局同步（跨级别显示当前播放内容）
- [x] ScriptLine 的 start/end 改为 Optional，避免缺失时间戳导致解码失败
- [x] 产品文档更新（封面缩略图 + 内容展示方案 + 页面清单）

**首批内容生成：**
- [x] batch_generate.py 批量生成脚本
- [x] 30 集全部生成（Easy/Medium/Hard 各 10 集）
- [x] 21 集完好，5 集部分可用，4 集因 MiniMax 限流不可用
- [x] 代码提交 GitHub（私有仓库，API key 已排除）

### 2026-03-29 — 词汇系统重构 + 记录页改版 + 音频修复

**词汇系统重构：**
- [x] 分类逻辑从时间衰减改为行为驱动（配对次数+造句次数）
- [x] 新词=配对0次 / 复习中=配对1-2次 / 已掌握=配对≥3次或造句≥1次
- [x] 30天不练习自动退回复习中
- [x] SavedWord 新字段：matchCorrectCount、sentenceCorrectCount
- [x] WordMatchView/FeynmanChallengeView 改用 recordMatchCorrect/recordSentenceCorrect
- [x] "新词"颜色从红色改为蓝色

**单词发音功能：**
- [x] WordSpeaker 服务（AVSpeechSynthesizer，离线可用，美式英语慢速）
- [x] 词汇本喇叭按钮点击发音
- [x] 连词成句单词卡片加发音按钮
- [x] 答对后显示英文句子（带播放）+ 中文翻译

**例句翻译补全：**
- [x] VocabularyItem/SavedWord 加 exampleZh 字段
- [x] Pipeline 提示词加 example_zh
- [x] 批量脚本用 GPT 翻译已有 30 集的 149 个例句
- [x] VocabularyStore 启动时自动迁移补全旧数据的 exampleZh

**词义配对优化：**
- [x] 音效开关按钮（@AppStorage 记住选择）
- [x] 点击英文单词自动播放发音
- [x] 配对正确/错误震动反馈（UIImpactFeedbackGenerator）
- [x] 优先抽新词 → 复习中 → 已掌握，每次随机

**连词成句优化：**
- [x] 优先抽复习中的词，每次随机
- [x] 完成页庆祝动效（星星弹性放大+彩色粒子散射+双重震动）
- [x] 每题答对/答错震动反馈
- [x] 词块去掉标点
- [x] 命名统一：词义配对 + 连词成句（全局一致）

**记录页改版：**
- [x] Streak 卡片替代旧三格统计（大火苗+连续天数+状态文案）
- [x] 三种状态文案：已完成(绿)/还没听(橙)/即将清零(红)
- [x] 连续5天没听显示降级警告
- [x] 本周7天进度条替代35天日历（🟢完成/🟡进行中/⚫未来）
- [x] 统计行改为：总时长/已听集数/已掌握词汇
- [x] 清掉 mock 历史数据，只显示真实播放记录
- [x] 播放历史去重（同一集只保留最近一次）
- [x] "顺序播放"轻量按钮（收藏模式下只播收藏）
- [x] completeEpisode 改为传入实际播放的 episode，修复历史不更新 bug

**音频问题修复：**
- [x] 重跑 Easy 3 集（全部修好）
- [x] Medium/Hard 部分中文音频偏短（MiniMax 限流，需后续分批补）
- [x] 音频时长显示修复（秒数 < 60 显示"X秒"，≥60 显示"X分X秒"）

**播放流程修复：**
- [x] 锁屏自动下一集（去掉 asyncAfter，直接在 AVAudioPlayer delegate 链里调用）
- [x] 遍间延迟去掉（直接播放下一遍，后台不中断）
- [x] 周精选播放传入队列，跳过按钮正常工作
- [x] 空队列 fallback 为当前 episode

### 2026-03-30 — Paywall 重构 + 内容生成 + 播放修复

**今日新内容生成（6集）：**
- [x] Easy 2 集（Our Favorite Foods / Doctor Visit）
- [x] Medium 2 集（Bubble Tea Craze / Working from Home）
- [x] Hard 2 集（AI in Education / Renewable Energy）
- [x] 全部音频完整、封面生成、例句翻译补全
- [x] 部署到 app，每级现有 12 集

**播放流程修复：**
- [x] 首页正在播放改为显示最新内容（episodes.last）
- [x] Toast 进完成页保存词汇不再多跳一集
- [x] 首页下一集按钮修复（queue 为空时自动初始化）
- [x] 最后一集下一集循环回第一集

**Paywall 完全重构（多轮迭代）：**
- [x] 参考 Learna Pro 设计，全屏蓝色渐变背景
- [x] 耳机图标浮动动效 + Castlingo Pro 深蓝标题
- [x] 金字塔文案布局（Castlingo Pro / 坚持30天 / 坚持一整年）
- [x] 功能竖排列表 + 逐行滑入荡漾动效
- [x] 底部价格行：3天免费试用(绿) · 年付平均¥0.8/天(蓝)
- [x] 年付/月付切换：选中变"开启免费试用"蓝框，未选中变灰框
- [x] 试用详情跟随方案变化：今日¥0 + 具体日期后扣费
- [x] CTA 呼吸光效固定底部
- [x] 苹果订阅审核合规（条款+恢复购买+隐私链接）

**我的页面优化：**
- [x] 级别/语言/提醒改为 push 导航子页面（非弹窗）
- [x] 右侧 > 箭头
- [x] 级别选择页（带颜色圆点+勾选）
- [x] 语言选择页（中文可选，日韩西法"即将推出"）
- [x] 提醒时间页（滚轮选择器+保存按钮）

**成就徽章系统：**
- [x] 12 个徽章，3列网格
- [x] 每个徽章独立配色（天蓝/橙/金/紫/绿/玫红/靛蓝/红/金色）
- [x] 已解锁：渐变色底+金色边框+内圈白线+彩色投影
- [x] 未解锁：灰色底+虚线边框+🔒
- [x] 基于真实数据自动解锁（streak/词汇/配对/造句/集数）

### 2026-03-31 — 上架准备 + 品牌改名

**品牌改名 LangPod → Castlingo：**
- [x] 全局文案替换（Onboarding/Profile/ShareCard/AudioPlayer/DataStore）
- [x] 用户昵称"英语学习者" → "Explorer"
- [x] Bundle ID: com.amyhuang.langpod → com.amyhuang.castlingo
- [x] Display Name: LangPod → Castlingo（Info.plist + pbxproj）

**上架配置：**
- [x] App Icon 设置（Pencil V6 声波图标，1024x1024）
- [x] 强制浅色模式（UIUserInterfaceStyle = Light）
- [x] iPhone Only（TARGETED_DEVICE_FAMILY = 1）
- [x] PrivacyInfo.xcprivacy 已声明 UserDefaults

**隐私政策 + 用户协议（完整版）：**
- [x] 隐私政策 14 节（数据收集清单/存储/安全/共享/第三方/Cookie/跨境/用户权利/儿童/订阅/法律）
- [x] 用户协议 12 节（服务说明/订阅条款/试用/续费/取消/退款/行为规范/知识产权/免责/责任限制/争议）
- [x] GitHub Pages 托管（仓库已公开）
- [x] App 内链接指向 GitHub Pages URL

### 明日待办（2026-04-01）

**优先级 1 — 上架阻塞项：**
- [ ] 等苹果开发者账号
- [ ] StoreKit 2 接入真实订阅（账号到了立即做）
- [ ] App Store 截图（5.5寸 + 6.7寸，至少 5 张）
- [ ] App Store 描述文案（标题/副标题/关键词/描述）

**优先级 2 — 服务器部署：**
- [ ] 阿里云 OSS 创建 bucket + 上传现有内容
- [ ] Nginx 配置 API 代理
- [ ] App 数据源从 bundle 切到 API
- [ ] Pipeline 部署到服务器 + cron 每日自动生成

**优先级 3 — 内容质量：**
- [ ] 分批重跑 Hard 级别中文音频偏短的集
- [ ] GPT 提示词更新（混合单人播报+双人对话+时事新闻）
- [ ] MiniMax 长句自动拆分优化

**优先级 4 — 后续迭代：**
- [ ] Firebase Analytics 埋点（关键用户行为追踪）
- [ ] iCloud 同步（CloudKit）
- [ ] 每日提醒本地通知注册
- [ ] 连词成句拖拽排序（自定义手势）
- [ ] 单词配对/连词成句难度层级细化
- [ ] NewsAPI 接入获取真实每日新闻标题
- [ ] 多语言翻译（日韩西法）
