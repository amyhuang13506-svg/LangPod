import SwiftUI

/// 词汇小课堂详情页：纵向长页 —— 分区场景图（单词标注长在图里）依次滚动，
/// 像翻一本图解词典。点标注 → 单词卡；底部固定「全部加入单词本」。
struct LessonDetailView: View {
    let item: SceneLessonIndexItem
    let country: LessonCountry

    @Environment(\.dismiss) private var dismiss
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(LessonStore.self) private var lessonStore
    @Environment(SentenceStore.self) private var sentenceStore
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var lesson: SceneLesson?
    @State private var loadFailed = false
    @State private var selectedWord: SceneWord?
    @State private var toast: String?
    @State private var addedAll = false
    @State private var showRolePlay = false
    @State private var showPaywall = false

    /// 锁定课：仍可进详情看内容，只在动作按钮处拦。免费的前 2 张 / 今日课 / Pro 不锁。
    private var isLockedLesson: Bool {
        lessonStore.isLocked(item, isPro: subscriptionManager.isProUser)
    }

    /// 动作闸门：锁定时弹付费墙、拦下动作；否则照常执行。返回 true = 已拦截。
    @discardableResult
    private func gatedByPaywall() -> Bool {
        guard isLockedLesson else { return false }
        Analytics.track(.lessonPaywallView, params: ["lesson_id": item.id, "country": country.id])
        showPaywall = true
        return true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            if let lesson {
                content(lesson)
            } else if loadFailed {
                failedState
            } else {
                ProgressView().tint(Color.appPrimary)
            }

            bottomCTA

        }
        // 顶部小横条反馈（与首页视频字幕加词同款）
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.appPrimary.opacity(0.92), in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task { await loadLesson() }
        .fullScreenCover(isPresented: $showRolePlay) {
            if let lesson, let roleplay = lesson.roleplay {
                LessonRolePlayView(lesson: lesson, roleplay: roleplay)
            }
        }
        .sheet(item: $selectedWord) { word in
            LessonWordCard(
                word: word,
                accent: country.accent,
                lessonTitle: lesson?.titleZh ?? item.titleZh,
                locked: isLockedLesson,
                onGated: {
                    // 关掉单词卡再弹付费墙，避免 sheet 叠 sheet 的模态冲突
                    selectedWord = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        gatedByPaywall()
                    }
                }
            )
            .environment(vocabularyStore)
            .environment(sentenceStore)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscriptionManager)
        }
    }

    private func loadLesson() async {
        Analytics.track(.lessonOpen, params: [
            "lesson_id": item.id, "country": country.id, "is_free": "\(item.isFree)",
        ])
        loadFailed = false
        if let loaded = await lessonStore.lessonDetail(country: country.id, id: item.id) {
            lesson = loaded
            LessonAudioPlayer.shared.prefetch(loaded.allAudioUrls)
        } else {
            loadFailed = true
        }
    }

    // MARK: - Content

    private func content(_ lesson: SceneLesson) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header(lesson)

                ForEach(Array(lesson.zones.enumerated()), id: \.element.id) { index, zone in
                    zoneSection(zone, index: index)
                }

                if !lesson.sentences.isEmpty {
                    sentencesSection(lesson.sentences)
                }
                if let tips = lesson.cultureTipsZh, !tips.isEmpty {
                    cultureTipsSection(tips)
                }
                // 滚到最后 = 学完
                Color.clear.frame(height: 1)
                    .onAppear { lessonStore.markCompleted(lesson.id) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 130)
        }
    }

    private func header(_ lesson: SceneLesson) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white))
                }
                Spacer()
                Text("\(country.flag) \(country.nameZh)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white))
            }
            HStack(alignment: .center, spacing: 8) {
                Text(lesson.titleZh)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color.textPrimary)
                if isLockedLesson {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Color.warning)
                }
            }
            .padding(.top, 6)
            Text("\(lesson.titleEn) · \(lesson.wordCount) 词")
                .font(.system(size: 14))
                .foregroundColor(Color.textSecondary)
        }
    }

    // MARK: - Zone

    private func zoneSection(_ zone: SceneZone, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.appPrimary))
                Text(zone.nameZh)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                Text(zone.nameEn)
                    .font(.system(size: 13))
                    .foregroundColor(Color.textTertiary)
            }

            ZoneSceneImage(
                zone: zone,
                isAdded: { isAdded($0) },
                onTapWord: { tapWord($0) }
            )

            if !zone.extraWords.isEmpty {
                extraWordsList(zone.extraWords)
            }
        }
    }

    private func extraWordsList(_ words: [SceneWord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("更多表达")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.textTertiary)
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                ForEach(words) { word in
                    HStack(spacing: 10) {
                        // 行主体：打开单词卡
                        Button { tapWord(word) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.appPrimary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(word.word)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(Color.textPrimary)
                                    Text(word.translationZh)
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.textSecondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // 加号直接可点：立即加入单词本 + 顶部横条反馈
                        Button {
                            addSingleWord(word)
                        } label: {
                            Image(systemName: isAdded(word) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 20))
                                .foregroundColor(isAdded(word) ? Color.success : Color.textQuaternary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if word.id != words.last?.id {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        }
    }

    // MARK: - Sentences & Tips

    private func sentencesSection(_ sentences: [SceneSentence]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("💬 常用句型")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.textPrimary)
            VStack(spacing: 8) {
                ForEach(sentences) { sentence in
                    sentenceRow(sentence)
                }
            }
        }
    }

    private func sentenceRow(_ sentence: SceneSentence) -> some View {
        let saved = sentenceStore.isSaved(sentence.english)
        return HStack(alignment: .top, spacing: 10) {
            Button {
                if gatedByPaywall() { return }
                LessonAudioPlayer.shared.play(sentence.audio) {
                    WordSpeaker.shared.speakSentence(sentence.english, accent: country.accent)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sentence.english)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text(sentence.chinese)
                            .font(.system(size: 13))
                            .foregroundColor(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color.appPrimary)
                        .padding(.top, 3)
                }
            }
            .buttonStyle(.plain)

            // 加入我的句子（场景 = 课堂标题）
            Button {
                if gatedByPaywall() { return }
                guard !saved, let lesson else { return }
                let added = sentenceStore.add(SavedSentence(
                    english: sentence.english,
                    chinese: sentence.chinese,
                    scene: lesson.titleZh,
                    source: "lesson",
                    sourceLabel: lesson.titleZh,
                    audioUrl: sentence.audio,
                    audioStart: nil,
                    audioEnd: nil,
                    savedDate: Date()
                ))
                if added {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showToast("已加入句型库")
                }
            } label: {
                Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22))
                    .foregroundColor(saved ? Color.success : Color.textQuaternary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
    }

    private func cultureTipsSection(_ tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("💡 文化小贴士")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.textPrimary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Color.warning).frame(width: 5, height: 5).padding(.top, 7)
                        Text(tip)
                            .font(.system(size: 14))
                            .foregroundColor(Color.bodyText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.warningLight))
        }
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.appBackground.opacity(0), Color.appBackground],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 24)
            HStack(spacing: 10) {
                Button(action: addAllWords) {
                    Text(allWordsAdded ? "已全部加入 ✓" : "全部加入单词本")
                        .font(.system(size: hasRoleplay ? 14 : 16, weight: .semibold))
                        .foregroundColor(allWordsAdded ? Color.textSecondary : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(allWordsAdded ? Color.border : Color.appPrimary)
                        )
                }
                .disabled(allWordsAdded || lesson == nil)

                if hasRoleplay {
                    Button {
                        if gatedByPaywall() { return }
                        showRolePlay = true
                    } label: {
                        Text("模拟现场对话")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 25).fill(Color.hardOrange))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Color.appBackground)
        }
    }

    private var hasRoleplay: Bool {
        !(lesson?.roleplay?.dialogue.isEmpty ?? true)
    }

    private var failedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 34))
                .foregroundColor(Color.textTertiary)
            Text("加载失败，请检查网络")
                .font(.system(size: 15))
                .foregroundColor(Color.textSecondary)
            Button("重试") { Task { await loadLesson() } }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.appPrimary)
            Button("关闭") { dismiss() }
                .font(.system(size: 14))
                .foregroundColor(Color.textTertiary)
        }
    }

    // MARK: - Actions

    private func isAdded(_ word: SceneWord) -> Bool {
        vocabularyStore.words.contains { $0.word.lowercased() == word.word.lowercased() }
    }

    private var allWordsAdded: Bool {
        addedAll || (lesson.map { l in l.allWords.allSatisfy { isAdded($0) } } ?? false)
    }

    private func tapWord(_ word: SceneWord) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedWord = word  // 发音由单词卡 onAppear 触发，避免和卡片自动朗读重复
    }

    private func addAllWords() {
        if gatedByPaywall() { return }
        guard let lesson else { return }
        var added = 0
        for word in lesson.allWords {
            if vocabularyStore.addWord(word.asVocabularyItem, sourceLabel: "scene_lesson") {
                added += 1
            }
        }
        addedAll = true
        Analytics.track(.lessonAddAll, params: [
            "lesson_id": lesson.id, "country": country.id, "added": "\(added)",
        ])
        showToast(added > 0 ? "已加入 \(added) 个新词" : "这些词都已在单词本里")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 加号直接加词（不开单词卡），带顶部横条反馈
    private func addSingleWord(_ word: SceneWord) {
        if gatedByPaywall() { return }
        guard !isAdded(word) else { return }
        let added = vocabularyStore.addWord(word.asVocabularyItem, sourceLabel: "scene_lesson")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showToast(added ? "「\(word.word)」已加入单词本" : "「\(word.word)」已在单词本")
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - 场景图 + 单词标注叠加层

/// 核心技巧：ImageCache 拿 UIImage → scaledToFit 之后挂 overlay，
/// GeometryReader 报告的就是渲染出的图片实际尺寸，归一化坐标直接乘宽高，零 letterbox 换算。
struct ZoneSceneImage: View {
    let zone: SceneZone
    let isAdded: (SceneWord) -> Bool
    let onTapWord: (SceneWord) -> Void

    @State private var uiImage: UIImage?
    @State private var revealed = false

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        GeometryReader { geo in
                            ForEach(Array(zone.hotspots.enumerated()), id: \.element.id) { index, spot in
                                HotspotChip(word: spot, added: isAdded(spot)) {
                                    onTapWord(spot)
                                }
                                .position(clampedPosition(spot, in: geo.size))
                                .opacity(revealed ? 1 : 0)
                                .animation(
                                    .spring(duration: 0.35).delay(Double(index) * 0.08),
                                    value: revealed
                                )
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onAppear { revealed = true }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primaryLight)
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .overlay { ProgressView().tint(Color.appPrimary) }
            }
        }
        .task(id: zone.image) {
            uiImage = await ImageCache.shared.image(for: zone.image)
        }
    }

    /// 长单词标签（ticket number machine 等）按实测文字宽度钳制在图内，不再溢出屏幕
    private func clampedPosition(_ spot: SceneWord, in size: CGSize) -> CGPoint {
        let textWidth = (spot.word as NSString).size(
            withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)]
        ).width
        let halfChip = (textWidth + 16) / 2 + 4  // 文字 + 内边距 + 安全边距
        let rawX = (spot.x ?? 0.5) * size.width
        let rawY = (spot.y ?? 0.5) * size.height
        return CGPoint(
            x: min(max(rawX, halfChip), size.width - halfChip),
            y: min(max(rawY, 18), size.height - 14)
        )
    }
}

/// 图上的单词标注：小圆点 + 白底词标签，已加入变绿 ✓
struct HotspotChip: View {
    let word: SceneWord
    let added: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    if added {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.success)
                    }
                    Text(word.word)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(added ? Color.success : Color.navyTitle)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(added ? Color.successLight : Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                )
                Circle()
                    .fill(added ? Color.success : Color.appPrimary)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .fixedSize()
    }
}

// MARK: - 单词卡 bottom sheet

struct LessonWordCard: View {
    let word: SceneWord
    let accent: String
    let lessonTitle: String
    /// 锁定课的单词卡：内容照常显示，发音/收藏按钮触发 onGated（弹付费墙），且不自动朗读。
    var locked: Bool = false
    var onGated: () -> Void = {}

    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(SentenceStore.self) private var sentenceStore
    @State private var justAdded = false
    @State private var contentHeight: CGFloat = 340

    private var isAdded: Bool {
        justAdded || vocabularyStore.words.contains { $0.word.lowercased() == word.word.lowercased() }
    }

    private var exampleSaved: Bool {
        sentenceStore.isSaved(word.example)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 单词独占一行（超长自动缩小字号，不换行拆分）
            HStack(alignment: .center, spacing: 10) {
                Text(word.word)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                Button {
                    if locked { onGated(); return }
                    playWord()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 17))
                        .foregroundColor(Color.appPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.primaryLight))
                }
            }

            // 第二行：音标 + 释义 + 难度
            HStack(spacing: 8) {
                Text(word.phonetic)
                    .font(.system(size: 14))
                    .foregroundColor(Color.textTertiary)
                Text(word.translationZh)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color.textPrimary)
                if !word.difficultyLabel.isEmpty {
                    Text(word.difficultyLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.appPrimary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primaryLight))
                }
            }

            // 例句：点击发音，右侧 ＋ 收进我的句子
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        if locked { onGated(); return }
                        LessonAudioPlayer.shared.play(word.exampleAudio) {
                            WordSpeaker.shared.speakSentence(word.example, accent: accent)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .top) {
                                Text(word.example)
                                    .font(.system(size: 15))
                                    .foregroundColor(Color.bodyText)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.appPrimary)
                            }
                            if let zh = word.exampleZh {
                                Text(zh)
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        if locked { onGated(); return }
                        guard !exampleSaved else { return }
                        let added = sentenceStore.add(SavedSentence(
                            english: word.example,
                            chinese: word.exampleZh ?? "",
                            scene: lessonTitle,
                            source: "lesson",
                            sourceLabel: lessonTitle,
                            audioUrl: word.exampleAudio,
                            audioStart: nil,
                            audioEnd: nil,
                            savedDate: Date()
                        ))
                        if added {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    } label: {
                        Image(systemName: exampleSaved ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 22))
                            .foregroundColor(exampleSaved ? Color.success : Color.textQuaternary)
                    }
                }
                if exampleSaved {
                    Text("✓ 已加入我的句子")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.success)
                        .transition(.opacity)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.appBackground))

            Button {
                if locked { onGated(); return }
                guard !isAdded else { return }
                if vocabularyStore.addWord(word.asVocabularyItem, sourceLabel: "scene_lesson") {
                    justAdded = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Analytics.track(.lessonWordAdd, params: ["word": word.word])
                }
            } label: {
                Text(isAdded ? "已加入我的单词 ✓" : "加入单词本")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isAdded ? Color.textSecondary : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(isAdded ? Color.border : Color.appPrimary)
                    )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: LessonWordCardHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(LessonWordCardHeightKey.self) { height in
            // 内容多高弹多高（去掉半屏固定高度的空白），上限 3/4 屏
            contentHeight = min(height + 12, UIScreen.main.bounds.height * 0.75)
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .onAppear { if !locked { playWord() } }   // 锁定课不自动朗读（发音是被拦的动作）
    }

    private func playWord() {
        LessonAudioPlayer.shared.play(word.audio) {
            WordSpeaker.shared.speak(word.word, accent: accent)
        }
    }
}

/// 单词卡内容实测高度（驱动弹窗高度自适应）
private struct LessonWordCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - 模拟现场对话（角色扮演：一句句推进，对方有声、你的台词跟着念）

struct LessonRolePlayView: View {
    let lesson: SceneLesson
    let roleplay: LessonRoleplay

    @Environment(\.dismiss) private var dismiss
    @State private var revealed = 0
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                setupCard
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(Array(roleplay.dialogue.prefix(revealed).enumerated()), id: \.element.id) { index, line in
                                bubble(line)
                                    .id(index)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            if finished {
                                completionCard
                                    .id("done")
                                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 20)
                    }
                    .onChange(of: revealed) { _, newValue in
                        withAnimation(.spring(duration: 0.35)) {
                            proxy.scrollTo(finished ? AnyHashable("done") : AnyHashable(newValue - 1), anchor: .bottom)
                        }
                    }
                }

                bottomButton
            }
        }
        .onAppear { advance() }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("模拟现场对话")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(lesson.titleZh)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("🎬")
                Text(roleplay.setupZh)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                roleTag("你", roleplay.yourRoleZh, color: Color.appPrimary)
                roleTag("对方", roleplay.otherRoleZh, color: Color.hardOrange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.warningLight.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func roleTag(_ label: String, _ role: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(color))
            Text(role)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - 气泡

    @ViewBuilder
    private func bubble(_ line: RoleplayLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if line.isYou {
                Spacer(minLength: 34)
            } else {
                avatar(isYou: false)
            }
            Button {
                play(line)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    // 喇叭内联在英文句子末尾（点击气泡重听）
                    (Text(line.en + " ")
                        + Text(Image(systemName: "speaker.wave.2.fill"))
                            .font(.system(size: 11)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(line.isYou ? .white : Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(line.zh)
                        .font(.system(size: 12))
                        .foregroundStyle(line.isYou ? .white.opacity(0.85) : Color.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(line.isYou ? Color.appPrimary : Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                )
            }
            .buttonStyle(.plain)
            if line.isYou {
                avatar(isYou: true)
            } else {
                Spacer(minLength: 34)
            }
        }
    }

    /// 双方头像：gpt-image-1 生成的人物画像（缺失回落 person 圆形图标）
    private func avatar(isYou: Bool) -> some View {
        CachedAsyncImage(url: (isYou ? roleplay.youAvatar : roleplay.otherAvatar) ?? "") {
            Image(systemName: "person.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isYou ? Color.appPrimary : Color.hardOrange))
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay(Circle().stroke(isYou ? Color.appPrimary : Color.hardOrange, lineWidth: 1.5))
    }

    private var completionCard: some View {
        VStack(spacing: 8) {
            Text("🎉")
                .font(.system(size: 34))
            Text("对话完成！")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text("下次走进这个场景，这些话就是条件反射")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.successLight.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var bottomButton: some View {
        HStack(spacing: 10) {
            if finished {
                Button {
                    withAnimation { revealed = 0; finished = false }
                    advance()
                } label: {
                    Text("再来一遍")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.appPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Color.primaryLight))
                }
                Button { dismiss() } label: {
                    Text("完成")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Color.appPrimary))
                }
            } else {
                Button { advance() } label: {
                    Text(revealed == 0 ? "开始对话" : "下一句")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Color.appPrimary))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appBackground)
    }

    // MARK: - 推进

    private func advance() {
        guard revealed < roleplay.dialogue.count else {
            withAnimation(.spring(duration: 0.35)) { finished = true }
            return
        }
        withAnimation(.spring(duration: 0.35)) { revealed += 1 }
        let line = roleplay.dialogue[revealed - 1]
        play(line)
        if revealed == roleplay.dialogue.count {
            // 每日任务：模拟对话首次走完（guard 分支和「再来一遍」会二次触发，TaskEngine 按日去重）
            NotificationCenter.default.post(name: .taskEventRoleplayFinished, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(duration: 0.35)) { finished = true }
            }
        }
    }

    private func play(_ line: RoleplayLine) {
        LessonAudioPlayer.shared.play(line.audio) {
            WordSpeaker.shared.speakSentence(line.en)
        }
    }
}
