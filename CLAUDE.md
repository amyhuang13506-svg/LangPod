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

## 每次修改代码后必须编译并部署

每次改完代码，必须：
1. 编译检查零错误
2. 部署到模拟器运行
3. 部署到真机运行（不要卸载重装）

```bash
# 1. 编译（模拟器 + 真机同时）
xcodebuild -project LangPod.xcodeproj -scheme LangPod \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build \
  2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"

xcodebuild -project LangPod.xcodeproj -scheme LangPod \
  -destination 'id=00008130-00046C3E3E90001C' \
  -allowProvisioningUpdates build \
  2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"

# 2. 部署到模拟器
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; \
xcrun simctl install "iPhone 17 Pro" ~/Library/Developer/Xcode/DerivedData/LangPod-*/Build/Products/Debug-iphonesimulator/LangPod.app && \
xcrun simctl launch "iPhone 17 Pro" com.amyhuang.langpod

# 3. 部署到真机（巧玲 iPhone 15 Pro Max）
xcrun devicectl device install app \
  --device 00008130-00046C3E3E90001C \
  ~/Library/Developer/Xcode/DerivedData/LangPod-*/Build/Products/Debug-iphoneos/LangPod.app && \
xcrun devicectl device process launch \
  --device 00008130-00046C3E3E90001C com.amyhuang.langpod
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

### 明日待办（2026-03-28）

**优先级 1 — 内容生成：**
- [ ] 拿到 MiniMax API key + GPT API key
- [ ] pipeline/config.py 填入 key，改 generate_audio.py 为 MiniMax
- [ ] 测试生成 1 集 Easy 内容（脚本+音频+上传）
- [ ] 批量生成首批内容：每级 10 集

**优先级 2 — 服务器部署：**
- [ ] 阿里云创建 OSS bucket "langpod"
- [ ] Nginx 配置 /langpod/api/ 代理到 OSS
- [ ] 部署 pipeline 到服务器，配置 cron

**优先级 3 — 上架准备：**
- [ ] App Icon 设计
- [ ] 隐私政策 + 用户协议网页（放阿里云或 GitHub Pages）
- [ ] App Store 截图（5 张关键页面）
- [ ] App Store 描述文案

**优先级 4 — 后续优化（可延后）：**
- [ ] iCloud 同步（CloudKit）
- [ ] StoreKit 2 接入真实订阅
- [ ] 单词配对/连词成句难度层级
- [ ] 每日提醒通知
