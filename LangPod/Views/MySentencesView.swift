import SwiftUI

/// 我的句子收藏页（从句型 tab 右上角进入）：
/// 收藏列表（场景 tag + 发音 + 左滑删除）+ 底部双练习 CTA（连词成句 / 场景模拟）。
struct MySentencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SentenceStore.self) private var sentenceStore

    @State private var showPractice = false
    @State private var showQuiz = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if sentenceStore.sentences.isEmpty {
                    emptyState
                } else {
                    sentenceList
                }
            }

            if !sentenceStore.sentences.isEmpty {
                bottomCTAs
            }
        }
        .fullScreenCover(isPresented: $showPractice) {
            SentencePracticeView()
                .environment(sentenceStore)
        }
        .fullScreenCover(isPresented: $showQuiz) {
            SceneQuizView()
                .environment(sentenceStore)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("我的句子")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white))
                }
                Spacer()
                Text("\(sentenceStore.totalCount) 句")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primaryLight, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - List（左滑删除）

    private var sentenceList: some View {
        List {
            ForEach(sentenceStore.sentences) { sentence in
                sentenceRow(sentence)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            withAnimation { sentenceStore.remove(sentence) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
            // 给底部固定 CTA 留空间
            Color.clear.frame(height: 90)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func sentenceRow(_ sentence: SavedSentence) -> some View {
        Button {
            LessonAudioPlayer.shared.play(sentence.audioUrl, from: sentence.audioStart, to: sentence.audioEnd) {
                WordSpeaker.shared.speakSentence(sentence.english)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(sentence.english)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appPrimary)
                        .padding(.top, 3)
                }
                Text(sentence.chinese)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(sentence.scene)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.gold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.warningLight))
                        .lineLimit(1)
                    Text("来自：\(sentence.sourceLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textQuaternary)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 双练习 CTA（仿词汇页蓝橙并排）

    private var bottomCTAs: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.appBackground.opacity(0), Color.appBackground],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 16)

            HStack(spacing: 12) {
                Button { showPractice = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.word.spacing")
                            .font(.system(size: 15))
                        Text("连词成句")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        sentenceStore.practiceableSentences.isEmpty ? Color.textTertiary : Color.appPrimary,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .disabled(sentenceStore.practiceableSentences.isEmpty)

                Button { showQuiz = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "theatermasks.fill")
                            .font(.system(size: 15))
                        Text("场景模拟")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.warning, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .background(Color.appBackground)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("还没有收藏句子")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text("在句型详情和小课堂的常用句型里\n点 ＋ 把句子收进来")
                .font(.system(size: 13))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}
