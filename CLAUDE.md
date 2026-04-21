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

### 2026-04-19 — 友盟接入 + 推送系统重构 + 抖音投放素材

**App Store 已过审**（此前达成，今日起正式可下载）

**抖音投放策略 & 素材：**
- 讨论 100 素人号"图文求推荐"方案，评估风险并给了 A/B/C 三种执行路径
- 用户选定：不同设备/IP 的 100 真实素人号 + 矩阵化求推荐文案
- 生成 9 张抖音图文卡片 HTML 预览（`docs/douyin_cards_preview.html`），用户后来自改成 5 种样式（紫色提问/蓝色边框/黄色便签/iOS备忘录/粉色问号）
- 评论区马甲号引导话术 × 6 套

**友盟（Umeng）集成完成：**
- 创建 `Services/Analytics.swift` 包装层（`#if canImport(UMCommon)` 条件编译，没 SDK 也能过编）
- 10 个核心漏斗事件：`app_launch` / `onboarding_complete`（带 level+source）/ `episode_play_start` / `episode_complete` / `vocabulary_save` / `word_match_complete` / `feynman_complete` / `paywall_view` / `purchase_attempt/success/fail` / `push_opened`
- AppKey: `69e359319a7f376488c57f94`（Info.plist 的 `UMAppKey` 字段）
- 手动集成 SDK：UMCommon 7.5.10 + UMDevice + UYuMao + UTDID + UMCommonLog，共 5 个 framework + 1 个 bundle，通过 pbxproj 直接加
- 配置 `FRAMEWORK_SEARCH_PATHS` + `-ObjC` 链接器标志
- `PrivacyInfo.xcprivacy` 按友盟合规声明 DeviceID / ProductInteraction / CrashData（都是 Analytics 用途，未链接身份、不跟踪）
- **说明**：新版 UMCommon 7.5+ 已合并 MobClick（分析模块），不需要单独 UMAnalytics
- **说明**：友盟官方不提供 SPM 包，只支持 CocoaPods 或手动 XCFramework。走了 XCFramework 路线（轻量、不引入 Podfile）

**隐私同意弹窗**：做完又撤回，用户决定先不做，待有需要时再加

**本地推送系统彻底重构：**
- 排查：原有 `scheduleEncounterReminder` 有 bug（`EpisodeCompleteView` 新建 `NotificationManager()` 实例，`isAuthorized` 异步还没刷就 `guard` 被挡，实际发不出去）
- 核心改动：从"多条独立推送叠加"改为"**每日单条优先级仲裁**"
- 5 层优先级（从高到低）：
  1. Streak 要断（≥2 天没听 + streak ≥ 2）
  2. 今天新集 + 当天没听
  3. 旧词复现（2 天内有 encountered 词）
  4. 词汇快忘（≥3 个词超过 30 天没练）
  5. 朴素提醒（当天没听）
- 单一稳定 ID `castlingo.daily`，重排自动覆盖
- 5 个触发时机自动刷新：app 启动 / 回前台 / **进后台（最关键）** / 完播 / 用户改提醒时间（通过 `Notification.Name.reminderTimeChanged` 广播）
- `EpisodeCompleteView` 的手动调用删掉，由仲裁器统一处理
- 最终保证：每个用户每天最多 **1 条** 推送，且只在"值得发"时才发

**推送漏斗埋点（方案 A 后续）：**
- `NotificationManager` 实现 `UNUserNotificationCenterDelegate`
- 用户点推送 → 触发 `push_opened` 事件带 `intent` 参数（5 种值之一）
- 加 `willPresent` handler：前台时推送也显示，不被 iOS 抑制
- 友盟后台可按 intent 分组，看"哪种文案点击率最高→哪种转化最终付费最好"
- **iOS 限制**：本地推送不经服务器，友盟看不到"发出了几条"，只能算点击基数

**今日完成清单：**
- [x] Analytics.swift 包装层 + 10 事件埋点
- [x] Info.plist UMAppKey 填入
- [x] 5 Umeng XCFramework + 1 bundle 集成（pbxproj 改）
- [x] PrivacyInfo.xcprivacy 补齐合规声明
- [x] NotificationManager 优先级仲裁重写
- [x] 5 个生命周期触发点接入
- [x] EpisodeCompleteView bug 修复
- [x] push_opened 漏斗埋点 + UNUserNotificationCenterDelegate
- [x] 抖音 9 张图文卡片 HTML 预览
- [x] 真机部署验证编译通过

### 明日待办（2026-04-20）

**优先级 1 — 抖音投放启动：**
- [ ] 100 素人号分批次发图文（每天 10-15 个，别集中发）
- [ ] 评论区马甲号引导按话术分散执行
- [ ] 24 小时后回数据：点赞/评论/引流转化初判

**优先级 2 — 数据验证（让数据跑）：**
- [ ] 手机走一遍完整漏斗（onboarding → 播一集 → 完播 → 保存词汇 → 词义配对 → 连词成句 → 打开付费墙）
- [ ] 15-30 分钟后去友盟后台看实时统计 + 自定义事件是否接收
- [ ] 推送实测：设提醒时间到 2 分钟后，杀进程验证文案命中哪种 intent
- [ ] 让推送系统跑 3-5 天，积累 `push_opened` 分 intent 的点击率数据

**优先级 3 — 历史遗留：**
- [ ] Hard 级别部分中文音频偏短的集重跑（MiniMax 分批）
- [ ] GPT 提示词更新（混合单人播报 + 时事新闻）
- [ ] iCloud 同步（CloudKit）
- [ ] 多语言翻译（日韩西法）

**决策记录（不做）：**
- ~~"不要打扰我"推送总开关~~ —— 4/19 决定不做，iOS 系统设置已覆盖
- ~~隐私同意弹窗~~ —— 4/19 决定暂缓

### 2026-04-20 — 句型讲解模块端到端落地 + 包体瘦身

**一整天 focus**：从零开发「句型讲解」整条链路 —— 产品设计 → pipeline → App UI → 真机联调。核心理念是**语感不是翻译**：母语者用句型是条件反射，由场景/情绪直接触发，绕过"中文→英文"的中间层。

**产品设计（多轮迭代后定稿）：**
- 句型 100% 来自每日播客 Pipeline 自动提取（砍掉最初想的 60 手工固定库方案）
- 入口：首页「今日句型讲解」横滑小卡片 158×158 + 标题右侧「往期回顾→」紧凑入口
- 混播逻辑：默认播客 5 遍后自动接这集的 2-3 个句型（设置可关），shuffle 以「播客+句型」为单元，repeatOne 包含 pattern
- 付费：今日免费 + 历史 Pro Only
- 6 段式讲解结构：读音 / 跟我念 3 次 / 字面意思 / 场景与感觉（核心 · VS 对比强制）/ 例句 ×3

**Pipeline（extract_patterns.py）迭代 6 版：**
- v1：初版用 `dot dot dot` 描述空缺、drill 用核心音节 → 被 TTS 字面读出来，被拒
- v2：prompt 禁止 `dot dot dot`、drill 改完整短句、强化 VS 对比（"它和 X 不一样"必须出现）
- v3：中文女声 `presenter_female` 太"主持人" → 换 `female-shaonv`（少女）；英文换用户提供的 `English_radiant_girl`
- v4：例句顺序改「中文场景前缀 → 英文例句」
- v5：drill 语速 0.7 → 0.85 → 0.9 都仍然不连读（MiniMax 在慢速下分词）
- **v6（关键突破）**：drill 不单独调 TTS，而是**把 pronunciation_demo_en 的正常速度音频用 ffmpeg atempo 慢放到 0.7x**，保留连读/音调/节奏
- 规则：`pronunciation_demo_en` 和 `example1.en_text` 必须是原文原句（"耳熟嘴熟"闭环）；3 个 template 类型必须多样（禁止全问句）；Hard 级别字面陷阱必须警告

**字幕细粒度（今天最后补的 pipeline 改进）：**
- 旧：每 section 一整段 TTS + 整段时间戳 → 字幕 300 字被 App 5 行截断
- 新：`split_into_subtitles()` 按句号/分号/逗号拆成 ≤60 字子句 → 逐子句独立 TTS + 独立时间戳 → App 字幕按子句自动翻页
- `synthesize_pattern_audio` 返回 `script_lines: List[Dict]` 替代 `timestamps: Dict`；`build_pattern_object` 简化为直接使用 script_lines
- **不重跑老 13 集**（用户确认），明天 cron 跑的自动用新逻辑

**播客字幕同等约束（generate_script.py prompt）：**
- script 示例改成 "EXACTLY ONE English sentence — max 20 words"
- Checklist 第 5 条新增 SUBTITLE RULE：每 script line 单句 + 英 ≤20 词 + 中 ≤30 字
- 长对话强制 GPT 拆多行，避免单 line 多句被字幕截断

**数据模型：**
- `Pattern.swift`：id / episodeId / template / translationZh / scene / audioUrl / duration / explainerScript / exampleSentences(3) / thumbnailColor
- `PatternSection` enum（7 种）+ `PatternScriptLine` / `PatternExample`
- `PlayItem` enum：`.episode(Episode)` / `.pattern(Pattern, parentEpisode: Episode)` — 统一队列项
- `PatternAccessGate`：静态方法判断"今日免费 / 历史 Pro"

**AudioPlayer 重构：**
- 新增 `currentPlayItem: PlayItem?` / `playQueue: [PlayItem]` / `playPatternsAlongside: Bool`
- `playEpisode(in:)` 内部构造混播 PlayItem 队列（episode 后插入其 patterns）
- 新增 `playPattern` / `playItem` / `handleItemFinished` / `skipToNext` / `skipToPrevious`
- 保留 legacy alias（`skipToNextEpisode` / `currentEpisode`）不破坏现有调用点
- Pattern 单次播放（无 5 遍循环），repeatOne 重放同一 pattern
- Shuffle 以"episode + its patterns"为单元
- 锁屏按 PlayItem 类型切换：episode → 封面 + "第 X/5 遍"；pattern → 米色卡片 + 模板文字

**Bug 修复：**
- **PatternSection Codable bug**（最坑）：String raw enum 的 Codable 用 rawValue 解码（不看 CodingKeys），默认驼峰 rawValue 和 snake_case JSON 不匹配 → 整个 episode JSON 解码抛异常 → `dataStore.episodes` 为空 → Medium/Hard tab 空白 + 混播完全不工作。修：直接给 case 设置 snake_case rawValue
- **Pattern ID 冲突**：同日同级两集的 pattern_id 相同（date+idx）→ easy-002 覆盖 easy-001 的 mp3。修：加 episode suffix（`pattern_easy_20260330_001_1`）
- **混播不接句型**：PlayerView.onDisappear 恢复的默认 handler 忘了 `skipToNextEpisode()` → 一旦打开过 PlayerView 再关，播完就停
- **index.json 没带 patterns**：App 启动拉 lightweight index 没 patterns 字段 → 首页今日句型和混播都不工作。修：upload_oss 的 `update_episode_list` 加 patterns 字段；App 的 EpisodeIndexItem + Episode.init(from:) 带上 patterns

**UI（多轮微调）：**
- `PatternPlayerContent`：米色大字 serif 模板卡（260×260）+ scene tag + 7 段进度圆点 + 当前章节 label（固定高度防止跳动）
- `PlayerView` 顶部 switch：episode → 原封面 + 集名 + phase badge；pattern → PatternPlayerContent
- `HomeView`：今日句型小卡片（158×158 横滑）+ 紧凑"往期回顾"入口（今日空时显示）；nowPlayingCard 播 pattern 时显示 template + scene
- `PatternHistoryView`：按日期倒序 + 锁图标 + 右上角蓝色圆形「播放全部」按钮
- `ProfileView`：学习设置加「句型混播」Toggle
- `EpisodeCompleteView`：加「今日句型」列表 row（无小播放按钮）+ 底部固定 CTA（播放句型 / 下一集 横排 + 保存词汇 全宽按钮）
- 字幕演进：独立字幕卡 → 底部 overlay 不影响主布局 → 中英同字体（英文不再 serif italic，像自然穿插）

**包体瘦身：**
- `LangPod/Resources/*.mp3`：66 个 ep-*.mp3（33MB）全部删除（内容走 OSS 流式 + 缓存）
- 用 Python 脚本批量从 pbxproj 删 264 条 mp3 引用
- 保留 5 个 onboarding mp3 + 3 个 episodes_*.json fallback
- **.app 从 55MB → 21MB**，Resources 42MB → 10MB
- 今后新内容 100% 走 OSS，包体永远不涨

**Analytics 事件（3 个新增）：**
- `pattern_open`（source: home_today / home_today_paging / history / history_play_all）
- `pattern_listen_complete`
- `pattern_paywall_view`

**OSS 数据：**
- 13 集有 patterns（样本 + 回溯 6 + 今日 cron 6 补 patterns）
- 每 pattern 讲解音频 ~100 秒、~1.5MB
- 老集 patterns 保持整段字幕（不重跑），新集用子句字幕

**产品决策（记录）：**
- ~~手工 60 固定句型库~~ —— 放弃，全走 Pipeline 自动提取
- ~~Tab Bar 加「句型」Tab~~ —— 放弃，5 个 Tab 太挤，用首页区块入口
- ~~今日句型全宽 paging 大卡~~ —— 放弃，恢复小卡横滑
- ~~老 13 集 patterns 重跑子句字幕~~ —— 放弃，只要 pipeline 改了，新集自动生效

### 明日待办（2026-04-21）

**优先级 1 — 服务器部署：**
- [ ] 同步 extract_patterns.py + generate_script.py（改了 prompt + 拆子句）到阿里云
- [ ] daily cron 串入 extract_patterns.py 步骤（目前只跑 script + audio）
- [ ] 验证 4-21 新跑的集自带 patterns + 子句字幕 ≤5 行

**优先级 2 — 验证：**
- [ ] 真机全流程测试：今日句型卡片 → 播放页 → 字幕 → 混播接下一集
- [ ] 免费 vs Pro 权限测试：历史句型付费墙触发
- [ ] 完成页 CTA 测试：播放句型 → 进入 pattern 播放 → 跟回下一集

### 2026-04-21 — 句型 TTS 换 ElevenLabs V3 + pipeline 部署上服务器

**今日 focus**：把句型讲解的 TTS 从 MiniMax 换成 ElevenLabs v3（音质 + 多语言连贯度），反复打磨 prompt + 清洗逻辑直到音频质量过关，然后部署到阿里云服务器。明日凌晨 3 点 cron 将第一次自动产出带 patterns 的新集。

**TTS 切换 ElevenLabs v3：**
- 接入 `eleven_v3` multilingual 模型，一个 voice 读中英无切换
- 5 个 voice 轮转（用户提供的：`XfNU2rGpBa01ckF309OY` / `lxYfHSkYm1EzQzGhdbfc` / `54Cze5LrTSyLgbO6Fhlc` / `9KsetBCT7UMILPg6Ksvu` / `1IKfgBmzdwnmAUPnryb3`）
- `pick_voice_for_pattern(pattern_id)`：md5 hash % 5，稳定可复现（重跑同一 pattern 音色不变）
- 只换句型模块 TTS，播客 podcast 继续用 MiniMax 双人对白（便宜且双人切换已 OK）
- 中途试过 Rachel（英文母语 voice）读中文 — 中文腔调不自然，弃用；用户提供 5 个 V3 voice 后问题解决

**Prompt 多轮迭代（规则 1-12）：**
- 规则 1：禁止 `dot dot dot` / `...`（MiniMax 时代旧约束继承）
- 规则 2：`pronunciation_demo_en` + `example1.en_text` 必须 script 原文原句（耳熟嘴熟闭环）
- 规则 3：3 个 template 类型多样（问句/陈述/请求/感叹），script 简单时允许只输出 2 个
- 规则 4：`scene_and_feeling_zh` 必须含具象画面 + 感觉关键词 + VS 对比 + 固定结尾
- 规则 5：example `scene_prefix_zh` 带场景前缀
- 规则 6：Hard 级别字面陷阱必须警告
- 规则 7：`thumbnail_color` 限定 5 个候选
- **规则 8（本轮核心）**：错误发音示范 = "英文原词 + 句号强制断开"，不用汉字拟音
  - ❌ "不要念成 cǎo·dé·ài" / "库德·爱"（TTS 读中文拟音没有对比效果）
  - ✅ "不要分开念成 Could. I."（TTS 自然停顿，模拟"不连读"的错误）
- **规则 9**：IPA 音标前后加空格（`/kʊdaɪ/` 前后必须有空格，防粘连）
- **规则 10**：`pronunciation_intro_zh` 不嵌入完整英文句子，结尾禁止破折号 ——（TTS 会读成吸气杂音）
- **规则 11**：`meaning_zh` 严格短（≤50 字），只讲字面意思，不讲语气/场景/VS 对比
- **规则 12**：`scene_prefix_zh` 必须"XXX——YYY。"双段（场景+情绪），禁止纯名词或英文翻译

**字幕子句拆分逻辑完善（split_into_subtitles）：**
- 合并 `X. Y.` 片段：规则 8 的错误示范被按句号切成两行 → 识别合并（`Can.` + `I.` → `Can. I.`）
- 过滤孤立标点子句：GPT 偶尔在英文问号后写中文句号产生孤立 `'。'` 行，filter 掉只含标点的子句

**TTS 尾部 artifact 清洗：**
- `clean_for_tts` 去掉文本末尾的 `——` / `—`（ElevenLabs V3 处理破折号会生成短促含糊元音）
- `trim_tts_tail`：用 `detect_leading_silence(reversed_seg)` 精准检测末尾 30-500ms 窗口的低能量区（-30dB 阈值）
  - 第一版 `detect_silence()` 方法误杀中段（取最后一段静音可能错位到中间） → 替换为反转段 + leading silence 检测，窗口限死，绝不触及中段
- 两重保险（GPT 不产破折号 + 代码补漏 trim），效果彻底

**跟读 drill 方案保留 atempo 慢放：**
- 试过把 drill 速度控制移到 App 端（动态 player.rate = 0.6） → 发现时间戳错位（实际时长变 1.67 倍，后续段 start/end 全错）
- 最终决定保持 pipeline 里 ffmpeg atempo 慢放（质量损失极小，工程复杂度最低）
- DRILL_SPEED 从 0.7 调到 0.6（用户希望更慢）

**generate_daily.py 加入 extract_patterns 步骤：**
- 原流程：script → audio → cover → upload_oss（4 步）
- 新流程：script → audio → cover → **extract_patterns** → upload_oss（5 步）
- 失败非致命（try/except 包住，句型生成失败不影响播客本身上传）

**服务器部署：**
- scp 5 个文件到 `/opt/langpod/pipeline/`：config.py / extract_patterns.py / generate_script.py / generate_daily.py / upload_oss.py
- 服务器验证：ffmpeg 已装（`/usr/bin/ffmpeg`）、Python 依赖齐全、cron `0 3 * * *` 已配置
- dry-run ElevenLabs 从服务器调用成功（3.8 秒测试音频）
- 明日 04-22 凌晨 3 点 CST 首次自动产出带 patterns 的新集

**生产数据状态：**
- OSS 上 13 集有 patterns（3-19 sample + 3-30 回溯 6 + 4-20 cron 6）
- 老 13 集继续用 MiniMax 音色（不重跑），4-22 起新集用 ElevenLabs V3
- 可接受音色混搭（老 vs 新）—— 用户听感明显改善的新集会逐日累积

**失败的路径（决策记录）：**
- ~~Rachel 音色读中文~~ —— 英文母语 voice 硬读中文腔调别扭，弃用
- ~~汉字拟音（cǎo·dé·ài）~~ —— 自己构造的汉字 TTS 读不出"错误示范"感，改英文+句号
- ~~App 端动态 rate=0.6~~ —— 时间戳会错位 67%，放弃
- ~~detect_silence 全段扫描 trim~~ —— 误杀中间内容（取最后一段静音可能错位到中间长停顿），改 detect_leading_silence(reversed)

### 明日待办（2026-04-22）

**优先级 1 — 监控 cron 产出：**
- [ ] 早起看 `/opt/langpod/pipeline/logs/cron.log` 无 fatal error
- [ ] 真机 app 首页今日句型区块有 6-9 张卡片（每级 2 集 × 2-3 patterns）
- [ ] 抽样听一集新 patterns：音色/连读/字幕同步/跟读 0.6 速度

**优先级 2 — 如果有问题：**
- [ ] ElevenLabs 配额 / 网络超时导致失败 → 分析 log 判断
- [ ] 字幕拆分在 hard 级别长段上有新 edge case？
- [ ] 跑批量回溯给老 13 集换 ElevenLabs 音色？（用户决定，成本 ~¥50 + 20 分钟）
