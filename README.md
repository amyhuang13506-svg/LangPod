# Castlingo

Castlingo 是一款 iOS 英语学习 App，主打「零输入、被动吸收」的沉浸式学习：像电台一样每天推送预生成的英语内容，用户打开就能听、能学、能练，不需要主动检索或编排学习计划。

> 品牌前身为 LangPod，仓库与部分内部标识仍沿用 `langpod` 命名。

## 核心功能

- **每日英语播客电台**　按 Easy / Medium / Hard 三个难度每天推送预生成的英语对话，独特的「三遍原音 → 一遍母语翻译 → 一遍原音」循环播放引擎，支持后台播放、锁屏控制与自动缓存。
- **场景词汇小课堂**　把单词标注在 AI 生成的真实生活场景插画里（在便利店买药、逛超市、机场值机……），按国家分类（美 / 英 / 澳 / 加 / 新西兰 / 新加坡），一图一场景，点标注即可查词、发音、加入单词本。
- **模拟现场对话**　每个课堂配一段角色扮演对话（你 = 顾客，对方 = 店员/柜员等），聊天式逐句推进、双声发音，把学过的词句在真实语境里用出来。
- **口语表达库**　按功能分类（日常反应 / 表达自己 / 会话技能 / 进阶地道）整理数百条地道口语表达，每条含语感注释、国家差异、例句与场景对话。
- **主动练习**　词义配对、连词成句、场景模拟（对话填空）等练习模式，配合遗忘曲线与掌握度追踪，把「听懂」推进到「会用」。
- **成长系统**　听力等级、连续打卡（Streak）、成就徽章、学习统计与分享卡片。

## 技术栈

- **App**：SwiftUI · iOS 17+ · Observable · AVFoundation（播放引擎）· StoreKit / RevenueCat（订阅）
- **内容后台**：Python 内容生产管线（大语言模型生成脚本与讲解、TTS 合成语音、文生图生成封面与场景插画）
- **分发**：对象存储（OSS）+ CDN，App 端网络优先、本地缓存兜底

## 架构概览

```
内容生产管线（服务器 · 定时任务）
   ├─ 生成脚本 / 对话 / 讲解文本
   ├─ 合成语音（多角色、多口音）
   ├─ 生成封面与场景插画
   └─ 上传对象存储（音频 .mp3 + 结构化 .json + 图片）

          │  (HTTP / CDN)
          ▼

iOS App
   ├─ 拉取内容索引与详情（网络优先，缓存兜底）
   ├─ 流式播放 + 本地缓存已听内容
   └─ 本地记录学习进度、词汇、练习数据
```

**内容全部通过对象存储分发，不打包进 App。** 新增/更新内容无需发版，安装包体积也不随内容增长。

## 项目结构

```
LangPod/                    # iOS App（SwiftUI）
├─ LangPodApp.swift         # 入口，注入全局状态
├─ ContentView.swift        # 四个主 Tab：首页 / 词汇 / 句型 / 我的
├─ Models/                  # 数据模型（Episode / SceneLesson / Expression / SavedWord …）
├─ Views/                   # 页面与组件
├─ Services/                # 数据层与服务
│  ├─ APIService            # 内容拉取（索引 / 详情，网络优先 + 缓存）
│  ├─ AudioPlayer           # 播客播放引擎（多遍循环 / 后台 / 锁屏）
│  ├─ LessonStore / ExpressionStore / VocabularyStore / SentenceStore
│  ├─ LessonAudioPlayer     # 发音音频播放（磁盘缓存 + 分段播放）
│  └─ SubscriptionManager / Analytics / NotificationManager
├─ Resources/               # 少量兜底资源（onboarding 演示音频等）
└─ Assets.xcassets, Theme.swift, 本地化 …

pipeline/                   # 内容生产管线（Python）
├─ 播客：脚本 → 音频 → 封面 → 上传
├─ 场景课堂：目录 → 内容 → 场景插画（含图上单词标注）→ 发音 → 角色扮演对话 → 上传
├─ 口语表达库：目录 → 表达内容 → 场景插画 → 发音 → 上传
└─ 校验与运维脚本（音频/文本一致性核对、批量重跑等）

docs/                       # 内容生产标准文档、方案记录
```

> 内容生产管线依赖一份本地配置文件存放各类密钥与服务参数，该文件不纳入版本控制。

## 开发

**环境**：Xcode（iOS 17 SDK）· 真机或模拟器

编译并部署到真机：

```bash
xcodebuild -project LangPod.xcodeproj -scheme LangPod \
  -destination 'id=<YOUR_DEVICE_ID>' \
  -allowProvisioningUpdates build

xcrun devicectl device install app \
  --device <YOUR_DEVICE_ID> \
  ~/Library/Developer/Xcode/DerivedData/LangPod-*/Build/Products/Debug-iphoneos/LangPod.app
```

App 首次启动即从内容服务器拉取最新内容；无网络时回落到本地缓存与内置兜底数据。

## 本地化

- 学习内容（对话音频、字幕、生词英文）全部为英文——这是学习材料本身。
- 操作界面、释义、翻译为中文（MVP 阶段）。
- 支持语言：简体中文 / 英文 / 日文（界面本地化按 MVP 策略逐步开放）。

## 隐私

App 的学习数据（进度、词汇、练习记录）默认存储在设备本地。隐私政策与用户协议随 App 内链接提供。
