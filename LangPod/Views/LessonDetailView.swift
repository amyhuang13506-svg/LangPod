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

    @State private var lesson: SceneLesson?
    @State private var loadFailed = false
    @State private var selectedWord: SceneWord?
    @State private var toast: String?
    @State private var addedAll = false

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

            if let toast {
                Text(toast)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 110)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .task { await loadLesson() }
        .sheet(item: $selectedWord) { word in
            LessonWordCard(word: word, accent: country.accent)
                .environment(vocabularyStore)
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
            Text(lesson.titleZh)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color.textPrimary)
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
                            Image(systemName: isAdded(word) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 20))
                                .foregroundColor(isAdded(word) ? Color.success : Color.textQuaternary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
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
            Button(action: addAllWords) {
                Text(allWordsAdded ? "已全部加入 ✓" : "全部加入单词本 (\(lesson?.allWords.count ?? item.wordCount))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(allWordsAdded ? Color.textSecondary : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(allWordsAdded ? Color.border : Color.appPrimary)
                    )
            }
            .disabled(allWordsAdded || lesson == nil)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Color.appBackground)
        }
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
                                .position(
                                    x: (spot.x ?? 0.5) * geo.size.width,
                                    y: (spot.y ?? 0.5) * geo.size.height
                                )
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

    @Environment(VocabularyStore.self) private var vocabularyStore
    @State private var justAdded = false
    @State private var contentHeight: CGFloat = 340

    private var isAdded: Bool {
        justAdded || vocabularyStore.words.contains { $0.word.lowercased() == word.word.lowercased() }
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

            Button {
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
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.appBackground))
            }

            Button {
                guard !isAdded else { return }
                if vocabularyStore.addWord(word.asVocabularyItem, sourceLabel: "scene_lesson") {
                    justAdded = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Analytics.track(.lessonWordAdd, params: ["word": word.word])
                }
            } label: {
                Text(isAdded ? "已在单词本 ✓" : "加入单词本")
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
        .onAppear { playWord() }
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
