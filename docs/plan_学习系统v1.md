# 实施文档：每日任务弹窗 + 火苗战绩系统 v2

> 状态：方案已定稿（2026-07-04，三个关键决策已拍板），本文档为**自包含实施手册**——新 session 无需追溯历史对话，按本文档施工即可。
> 所有 `文件:行号` 均已对着当前工作区代码核实（AudioPlayer.swift 含用户未提交的本地改动，**不要 checkout/stash 该文件**，行号以工作区为准）。
> 开工前通读一遍「陷阱清单」章节。

---

## 一、产品形态（一段话）

**不改现有首页 UI**。每天用户首次进 app 弹一次「今日任务」弹窗（4 格任务清单 + 本周 7 格进度条 + 火苗天数）；任务完成靠**被动事件记账**（锁屏听完的回前台自动补勾）；中途每完成一格出**顶部横条**「✓ 已完成：xx · 下一个：yy →」（像切歌预告，可点直达下一任务）；**完成任意 1 格点亮火苗**；4 格全完成弹**点火大庆祝**（真实数字文案）。火苗/周进度/统计搬到「我的」页，Streak 卡带 2/4 进度环 = 随时重开弹窗的二次入口。

### 已拍板的三个决策

1. **火苗门槛**：完成任意 1 个任务即点亮；4 个全完成 =「完美一天」大庆祝。**且保留现行"开始播放即点火"作为兜底**（任务系统只做加法），确保老用户零断火。
2. **中途反馈**：顶部轻量横条 + **下一个任务预告**，可点直达。全屏弹窗全天只出 2 次（首次进 app 的清单 + 4/4 的庆祝）。
3. **免费任务池**：直接剔除 Pro 任务（「学一篇单词」只进 Pro 用户的池子）；付费墙现状不动。

### 明确不做（这版）

- ❌ 补签卡 / streak freeze（下一版配合 RevenueCat 做付费点）
- ❌ 4/4 可变奖励宝箱（下一版可选）
- ❌ video 类型真实播客的收听统计（YouTube iframe 拿不到进度）
- ❌ 任务池服务器下发（v1 客户端硬编码 + 资格过滤兜底）
- ❌ 首页任何布局改动
- ❌ 鼓励语禁用「流利说英语」类文案（撞竞品名"英语流利说"+ 过度承诺），用真实数字

---

## 二、任务规格

### 每日 4 格（配额制，不是纯随机）

| 格 | 任务 | 达标判定 | 资格过滤 |
|---|---|---|---|
| ① 听力（每日固定） | 听一集学习播客 | **任 1 集第 1 遍英语原音播完**（不是 5 遍！免费用户没有第 5 遍） | 永远合格（有 bundle fallback 内容） |
| ② 句型 | 学一个句型 | 完整听完任 1 个句型讲解音频 | 当天 cron 无产出 → 本格替换为练习类 |
| ③ 练习 | 词义配对 / 连词成句 / 场景模拟 三选一 | 完成一轮 | 词库不够一局配对 / 无可练例句 → **场景模拟保底**（免费无限、无前置，永远合格） |
| ④ 机动 | 从剩余合格池抽 1 | 见下 | Pro 池：{学一篇场景课堂、模拟现场对话、听 10 分钟真实播客(仅 audio 类型且当日有更新)、第二种练习}；**免费池剔除课堂类** |

- 抽取用 `LessonStore.dailyShuffleSeed()` + `stableHash()`（现成，见锚点表），**抽一次立刻整体持久化**，当天绝不重抽——即使用户中途买 Pro / 存词跨过门槛，今日任务不变，明天生效
- 「听一个句型解析」和「学一个句型」是同一个动作，**只保留一个**任务类型
- **一次动作最多消费一个任务格**（按格序 ①→④ 匹配第一个未完成的同类格）
- 合格任务不足 4 个 → 当天出 3 个，不硬凑

### 持久化结构（单一 UserDefaults key，每次变更整体写盘）

```swift
struct DailyTaskRecord: Codable {
    var dateKey: String        // 本地时区 yyyy-MM-dd（复用 dailyShuffleSeed()）
    var taskIds: [String]      // 抽中的任务类型 id，3-4 个
    var doneFlags: [Bool]
    var popupShownToday: Bool  // 当日清单弹窗是否已展示
    var rewardGranted: Bool    // 4/4 庆祝是否已发（幂等闸门）
    var rawListenSeconds: Double  // 10分钟播客的累计收听秒数
}
```

- 日界统一 **Calendar.current 本地时区**（项目曾因 UTC 日期字符串前缀踩过坑，commit 65113a7）
- 跨 0 点：事件按发生时刻的本地日期入账；检测到 dateKey != 今天 → 整体作废重抽
- 发奖统一收敛到 `grantIfNeeded()`：检查 `rewardGranted` 后**先置位再执行副作用**（防事件重放重复弹庆祝）

---

## 三、工程架构：TaskEngine 单例 + NotificationCenter 事件

**为什么必须是单例 + 广播、不能走 @Environment**：SceneQuizView 明确自包含不依赖环境注入（SentencePracticeViews.swift:554-556 有注释）；AudioPlayer 是 @State 实例非单例（LangPodApp.swift:19）；事件源分散在 Services 和 Views 两层。

```
各挂点 NotificationCenter.post(事件)  ──►  TaskEngine.shared（订阅、按日去重、写 DailyTaskRecord）
                                              │
                     ┌────────────────────────┼──────────────────────┐
                 点火苗（调 DataStore 包装）   横条/弹窗状态（AppState）   推送 context 提供进度
```

TaskEngine 若从后台线程收到事件（AVAudioPlayer delegate 链），修改 @Observable 状态前回主线程（范例：DataStore.swift:181 的 `MainActor.run`）。

### 事件挂点表（核心！每个挂点都验证过）

| 事件 | 挂点 | 去重要求 |
|---|---|---|
| **①第 1 遍原音播完** | `AudioPlayer.swift:348` — `advancePhase()` 的 `case .englishRound(1)` 分支内 post，带 `currentEpisode?.id` | 按 episodeId+日 去重。注意 skipCurrentRound(:720-725)/播放失败 catch(:432-435)/mock(:537) 也会走到这个 case，接受误差 |
| **完成一整集**（完美日统计用，可选） | `DataStore.swift:301-320` — `completeEpisode` **方法体内** post。绝不能挂 onEpisodeFinished 闭包（见陷阱#1） | completeEpisode 无同日去重，TaskEngine 侧按日去重 |
| **②句型听完** | `AudioPlayer.swift:557-560` — `handleItemFinished()` 的 `.pattern` 分支，`Analytics.track(.patternListenComplete)` 旁 post | repeatOne 循环会反复 fire，按 pattern.id+日 去重 |
| **③词义配对完成** | `WordMatchView.swift:476` — `advanceRound()` 里 `Analytics.track(.wordMatchComplete)` 旁 | 按日去重 |
| **③连词成句完成** | `FeynmanChallengeView.swift:647` — `advanceWord()` 里 `.feynmanComplete` 旁 | 按日去重 |
| **③场景模拟完成** | `SentencePracticeViews.swift:736` — SceneQuizView `advance()` 里 `.sentenceQuizComplete` 旁 | 按日去重 |
| **③句子跟读完成**（若算练习） | `SentencePracticeViews.swift:539` — SentencePracticeView `advance()` | 按日去重 |
| **④课堂学完** | `LessonStore.swift:150-154` — `markCompleted(_:)` **方法体内**（自带 lessonId 去重）。不要挂 LessonDetailView.swift:97-98 的滚动哨兵 onAppear（会重复触发） | 方法自带去重 |
| **④模拟对话走完** | `LessonDetailView.swift:920-923` — LessonRolePlayView `advance()` 里 `finished = true` 首次置位处 | :914 guard 分支和「再来一遍」会二次触发，按日去重 |
| **④真实播客收听秒数** | `RawPodcastPlayerView.swift:924-935` — RawAudioController `addPeriodicObserver()` 闭包内：`if player.timeControlStatus == .playing { +0.5s }`。**必须用 timeControlStatus 过滤**（seek 也触发 observer），用固定增量 0.5s 而非 time 差值。挂 controller（RawPlaybackSession.shared 单例持有 :802-827，后台存活）而非 View 层 | 秒数落盘进 DailyTaskRecord.rawListenSeconds，≥600 达标；仅 audio 类型（mediaType 分支见 :619-621） |

### 火苗改造（严格做加法）

现状：`updateStreak()` 是 **private**（DataStore.swift:328-357），由 `recordPlayStart`（:272-274，**开播即点火**）和 `recordRawPodcastPlayStart`（:432-433）触发；`recordPatternPlayed`（:229-233）**不**触发 streak。

改法：
1. DataStore 加 public 包装 `func markStreakActivity() { updateStreak() }`
2. TaskEngine 每次任务达成时调用它——非听力任务（练习/课堂/句型）也能点火，且 `lastListenDate` 被更新，推送仲裁不会误报断连
3. **不动** recordPlayStart 里的现有调用（兜底保留，老用户行为零变化）
4. 「今日火苗是否已点亮」的 UI 判定：**绝不能用 `streakDays > 0`**（init :110 有 ==0 置 1 的 hack，checkStreakContinuity :495-505 断连也重置为 1 不是 0，此值永远 ≥1）。用 `Calendar.current.isDateInToday(dataStore.lastListenDate)` 或 TaskEngine 的今日完成数

---

## 四、UI 实现

### 挂载点：LangPodApp 根部（不要挂 HomeView！）

HomeView 已挂 4 个 fullScreenCover + 1 个 sheet（HomeView.swift:79-94）且只覆盖首页 tab。正确位置是 **LangPodApp.swift 的 WindowGroup 根 ZStack（:54-77）**——那里已有全局 EpisodeToast 先例（:64-76，`if appState.showToast {...}` 条件渲染 + transition）和根级 `.fullScreenCover($appState.showCompletePage)`（:78-104）。

给 `AppState`（@Observable class，LangPodApp.swift:6-13）加字段：`showDailyTasks`（清单弹窗）、`showTaskCelebration`（4/4 庆祝）、`taskToast`（横条数据：完成的任务名 + 下一个任务）。

### 1. 任务清单弹窗（全天最多 1 次自动弹）

- 内容：火苗天数 + **本周 7 格进度条**（从旧 StatsView 恢复，见下）+ 4 格任务（图标/名称/预计耗时/完成态✓）+ 点格 deep link + 关闭按钮
- 自动弹时机：冷启动 `.task {}`（LangPodApp.swift:105-121）和回前台 `.onReceive(willEnterForegroundNotification)`（:122-128）里判断——**注意项目没用 scenePhase，全是 onReceive**；别误挂 didEnterBackground（:129-134）
- 弹出条件（全部满足）：`!popupShownToday` && 非 onboarding 当天 && `audioPlayer` 未在播 && `appState.showCompletePage == false` && 无付费墙/深链在展示 && 首页渲染后延迟 1-2 秒
- 弹之前先「对账」：用当天已落盘的事件记录预勾选（锁屏听完的自动带✓）
- deep link：复用 `.openEpisodeFromPush` 深链模式（Name 定义 PushService.swift:7，ContentView.swift:43-48 接收后切 tab/拉起播放）——新增几个 Notification.Name：听力→播今日第一集（走 playGate）；句型→playPattern 今日第一个；练习→切词汇 tab 并 present 对应练习页；课堂→切词汇 tab 开今日课

### 2. 中途横条 TaskToast（完全照抄 EpisodeToast 模式）

- EpisodeToast.swift:3-35 是纯展示 view，由 AppState.showToast 驱动、挂根 ZStack（LangPodApp.swift:64-76）+ `.transition(.move(edge:.bottom).combined(with:.opacity))`。TaskToast 同款：**顶部**滑入、「✓ 已完成：听一集 · 下一个：单词配对 →」+ 轻震动（UIImpactFeedbackGenerator，项目已有使用习惯）
- 点横条 → deep link 直达下一个任务（同上），**永不打断进行中的音频队列**
- 同刻多任务达成合并为一条；3-4 秒自动消失
- 正在播放时任务达成 → 只出横条不弹窗

### 3. 点火大庆祝（4/4 时）

- 视觉复用 LevelUpView 风格（弹性缩放 + 粒子）。**注意 LevelUpView 不是 modal**，是 PlayerView 内嵌 ZStack 分支（PlayerView.swift:24-40，由 dataStore.pendingLevelUp + @State showLevelUp 双开关驱动）——庆祝页挂 LangPodApp 根部，弹出前必须 `appState.showCompletePage == false`，被占用就排队等 dismiss。优先级：完成页/LevelUp > 任务庆祝
- 文案用真实数字：「🔥 连续 X 天 · 累计听 Y 分钟 · 掌握 Z 个词」+ 下一里程碑预告（「再坚持 2 天点亮 7 天徽章」）。数据源全现成：`dataStore.streakDays` / `totalListeningTimeDisplay`（DataStore.swift:476-481）/ `vocabularyStore.strongWords.count`
- 7/30/100 里程碑日与现有分享海报（ShareCardView）合并展示，不出两个庆祝。注：`streakMilestone` 字段（DataStore.swift:41）目前是僵尸字段没有 UI 消费，可借用
- `grantIfNeeded()` 幂等，只弹一次

### 4. 「我的」页战绩区（恢复旧记录页组件）

被删的 StatsView 在 git 历史里：`git show cb36b24^:LangPod/Views/StatsView.swift`。**只恢复三块**（历史列表 :375+ 不要恢复）：

| 组件 | git blob 行号 | 说明 |
|---|---|---|
| streakCard | 65-138 | 🔥+连续天数大字卡 + 辅助计算属性（daysSinceLastListen/streakMessage/streakColor 等），数据源 streakDays/lastListenDate |
| statsRow + statCard | 142-166 | 三格：totalListeningTimeDisplay / episodesCompleted / vocabularyStore.strongWords.count |
| weekProgress + WeekDay | 170-249 | 本周一到日 7 格圆点，count 来自 listenHistory 按天过滤 |

- 插入位置：ProfileView.swift:41-43 之间（profileCard 之后、settingsSection 之前），页内顺序变为：标题 → 用户卡 → **战绩区** → 设置 → 其他(徽章) → 法律 → 版本
- 依赖的 Color 扩展（success/warning/danger/border 等）和 DataStore 字段已验证全部仍在，可直接编译；删掉旧 #Preview
- **streakCard 加 2/4 任务进度环，点击 → `appState.showDailyTasks = true`**（二次入口，解决"关掉弹窗后任务无处可看"）
- weekProgress 组件同时复用进任务清单弹窗顶部

---

## 五、推送联动（复用现有仲裁器，不另发推送）

架构：每日单条仲裁 `pickIntent`（NotificationManager.swift:147-198，5 档），排程入口 `refreshDailyNotification`（:104-132），稳定 ID `castlingo.daily`（:29）。**不要为任务系统另起 UNNotificationRequest**（破坏每天最多 1 条的保证）；TaskEngine 也不要自己调 UNUserNotificationCenter（isAuthorized 异步刷新有时序坑，:90-96，4/19 踩过）。

1. **加一档「今日任务只差 1 个」**：插在 streak_risk 闭括号（:158）之后、new_episode（:160）之前，作为第 2 优先级。`NotificationContext`（:12-22）加 `tasksCompletedToday`/`tasksTotalToday: Int`，在 `buildNotificationContext`（LangPodApp.swift:216-251）从 TaskEngine.shared 填充。判定 `completedToday == totalToday - 1 && totalToday > 0`，type = `"task_almost_done"`（自动进 push_opened 的 intent 漏斗，无需改埋点）
2. **顺手修 streak_risk 双重 bug**（:149-158）：(a) 条件 `days >= 2` 但火苗隔 1 天就重置（DataStore.swift:342-344），发出时火苗已死——改为 `days == 1`；(b) 更深的坑：排程只在 app 活跃时发生，「昨天听了今天没开 app」这个最该救的场景排不出去——修法：listenedToday==true 且 streak 存活时**预排明天**的 streak_risk（trigger 定次日 reminderHour，fire 时 days 恰为 1）
3. TaskEngine 状态变化触发重排：仿 `.reminderTimeChanged` 广播模式（定义 NotificationManager.swift:7、post ProfileView.swift:472、监听 LangPodApp.swift:135-137）——notificationManager 是 LangPodApp 私有 @State（:24）未注入 environment，拿不到实例，只能广播

---

## 六、Analytics（友盟）

`Analytics.Event` enum（Analytics.swift:23-48）加 case，`Analytics.track(_:params:)`（:79，params 只接受 `[String: String]`）：

```
daily_task_popup_view / daily_task_popup_dismiss(done_count)
daily_task_complete(type) / daily_task_all_complete
daily_task_entry_tap(source: popup|profile_card|toast)
```

---

## 七、新文件与 pbxproj（老格式，必须手改 4 处）

pbxproj 是 objectVersion=60 老格式，新 .swift 文件**不会自动编译**。每个新文件照 commit cb36b24 的 diff 模式改 4 处：① PBXBuildFile（:35 附近）② PBXFileReference（:159 附近）③ Views/Services group children（Views 在 :361 附近）④ PBXSourcesBuildPhase files。ID 约定 BuildFile=A199110x / FileRef=A299110x 递增，**A1991107/A2991107 起已验证空闲**，加前 grep 防冲突。

建议只加 2 个新文件（最少 pbxproj 改动）：
- `LangPod/Services/TaskEngine.swift` — TaskEngine 单例 + DailyTaskRecord + 任务定义/抽取/资格过滤
- `LangPod/Views/DailyTaskViews.swift` — 清单弹窗 + TaskToast + 庆祝页（三个 view 一个文件）

战绩区组件直接写进 ProfileView.swift（不新增文件）。

---

## 八、陷阱清单（每条都是真实验证过的坑）

1. **onEpisodeFinished 有 3 份副本互相覆盖**：LangPodApp.swift:194-206（默认）、PlayerView.swift:72-86（onAppear 覆盖）、PlayerView.swift:92-101（onDisappear「恢复」——但它 inline 又写了第三份，不是调 setupDefaultFinishedHandler，还缺 refreshDailyNotification）。它是单闭包 last-writer-wins（AudioPlayer.swift:156）。**任务事件绝不能挂进任何一份闭包**，只能挂 AudioPlayer 内部 fire 点（:385 Pro 路径 / :400 免费 proUpsell 路径，两处都要）或三份闭包共同调用的 DataStore.completeEpisode 方法体内。
2. **repeatOne 模式**：单集循环下 onEpisodeFinished 永不触发（:377-380/:392-395），「第 1 遍播完」和 pattern 完成事件却反复触发——一切事件按 id+日 去重。
3. **免费用户没有第 5 遍**（phase 走 .proUpsell，AudioPlayer.swift:357-371）——任务达标线绝不能定义为「听满 5 遍」。
4. **streakDays 永远 ≥1**（init hack + 断连重置为 1）——「今日已点亮」判定用 lastListenDate isDateInToday，不用 streakDays。
5. **completeEpisode 无同日去重**（重听同集会重复 +1 / 重复累加时长）——任务记账在 TaskEngine 侧独立按日去重，别数 episodesCompleted 增量。
6. **同一 view 多个 fullScreenCover(isPresented:) 同时置 true 会静默丢一个**——庆祝页弹出前查 `appState.showCompletePage == false`，被占用就排队。
7. **periodic observer 在 seek/暂停时间跳变时也 fire**——收听秒数必须 `timeControlStatus == .playing` 过滤 + 固定 0.5s 增量。
8. **项目没有 scenePhase**，前后台全靠 onReceive（LangPodApp.swift:122-134）；跨天重置/弹窗判断挂 willEnterForeground，别挂 didEnterBackground。
9. **日期判断项目里混用两套**（DateFormatter.episodeDate 字符串 vs Calendar.startOfDay）——TaskEngine 统一用 Calendar.current 本地时区。
10. **AudioPlayer.swift 有用户未提交的本地改动**（proUpsell/onPatternStarted 等都是未提交内容）——不要 checkout/stash/revert 该文件；**commit 时不要把它和 AppIcon.png 的既有改动、IMG_*.png 等杂项一起提交**（只提交本功能的文件；若必须改 AudioPlayer.swift 加事件 post，提交前告知用户该文件含其之前的未提交改动，由用户确认）。
11. **每次改完代码必须真机编译部署**（命令见 CLAUDE.md，设备 00008130-00046C3E3E90001C；launch 加 `--terminate-existing` 否则看不到新包）。
12. 词义配对/连词成句完成点已有 `markDailyMatchPlayed()/markDailySentencePlayed()`（VocabularyStore 每日标记，免费限次用）——TaskEngine 独立记账，别复用这两个标记（语义不同：那是限额，这是达成）。

---

## 九、实施顺序

1. **TaskEngine + 事件接线**：TaskEngine.swift（任务定义/资格过滤/抽取持久化/去重记账/markStreakActivity）+ 按挂点表逐个 post 事件 + DataStore 加 public 包装 → 编译部署，console 验证事件流
2. **UI**：DailyTaskViews.swift（弹窗/横条/庆祝）+ AppState 字段 + LangPodApp 根部挂载 + deep link → 部署验收
3. **「我的」页战绩区**：git show 恢复三组件进 ProfileView + streakCard 进度环入口 → 部署验收
4. **推送**：新档 + streak_risk bug 修复 + buildNotificationContext 填充
5. **埋点 + 全流程真机验证** → 分批 commit（TaskEngine / UI / ProfileView / 推送 各自成 commit）+ push

## 十、真机验证清单

- [ ] 新用户 Day1（无保存词）：格③ 落到场景模拟，无不可完成任务
- [ ] 免费用户：任务池无课堂类；听一集(1遍)/句型/练习全部可达成
- [ ] 锁屏听完一集 → 解锁进 app → 弹窗里格① 已自动带 ✓（对账生效）
- [ ] 前台正在播放时完成任务 → 只出横条不弹窗，音频不断
- [ ] 完成第 1 格 → 火苗 +1（「我的」页 Streak 卡同步），横条显示下一任务且可点直达
- [ ] 完成 4/4 → 大庆祝弹出（若完成页正在展示则等其关闭后弹），当天重复动作不再弹
- [ ] 杀进程重启 → 任务清单不变（不重抽）、已完成状态不丢、弹窗不重复弹
- [ ] 跨 0 点（改系统时间模拟）→ 任务整体重置重抽，昨天进度不串账
- [ ] 中途买 Pro → 今日任务不变，明天池子含课堂类
- [ ] 10 分钟播客：拖进度条不累计、暂停不累计、后台播放累计、杀进程秒数不清零
- [ ] 推送：设提醒到 2 分钟后 + 3/4 状态 → 收到「只差 1 个」文案；点开 push_opened 带 intent=task_almost_done
- [ ] 「我的」页战绩区三组件数据正确；点 Streak 卡重开任务弹窗
