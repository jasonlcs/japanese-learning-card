#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
import JapaneseLearningCardCore
import SwiftUI
import AVFoundation
import CryptoKit

// MARK: - Platform-adaptive Color helpers

extension Color {
    /// Window / page background (macOS: windowBackgroundColor, iOS: systemBackground).
    static var platformWindowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }
    /// Text-field / editor background (macOS: textBackgroundColor, iOS: secondarySystemBackground).
    static var platformTextBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
    /// Hairline separator (macOS: separatorColor, iOS: separator).
    static var platformSeparator: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(.separator)
        #endif
    }
}

public struct RootView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DesignTabBar(selectedTab: $viewModel.selectedTab)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                AutoDisplayPauseToggle(viewModel: viewModel)
                #if os(macOS)
                PresentationModeToggle(viewModel: viewModel)
                #endif
                if viewModel.selectedTab == 0 {
                    QuickReviewControls(viewModel: viewModel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 9)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            Divider()

            // 內容區以卡片頁當唯一的高度基準，其他頁籤用 overlay 蓋在上面
            // 吃滿同樣的高度。overlay 不參與 layout，所以 popover 的理想高度
            // 永遠跟著卡片內容走，切換頁籤或內容變長都不會高度亂跳。
            CardView(viewModel: viewModel)
                .opacity(viewModel.selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(viewModel.selectedTab == 0)
                .accessibilityHidden(viewModel.selectedTab != 0)
                .overlay(alignment: .topLeading) {
                    if viewModel.selectedTab != 0 {
                        Group {
                            switch viewModel.selectedTab {
                            #if os(macOS)
                            case 1:
                                CardMakerView(viewModel: viewModel)
                            #endif
                            case 2:
                                QuizView(viewModel: viewModel)
                            case 4:
                                SettingsView(viewModel: viewModel)
                            case 5:
                                HistoryView(viewModel: viewModel)
                            default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.designCanvas)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 550)
        .background(Color.designCanvas)
        .scrollContentBackground(.hidden)
        .onHover { inside in
            if inside {
                viewModel.pauseAutoCloseForInteraction()
            } else {
                viewModel.resumeAutoCloseAfterInteraction()
            }
        }
        #else
        .background(Color.designCanvas)
        .scrollContentBackground(.hidden)
        #endif
        .tint(.cardBlue)
        .environmentObject(viewModel)
    }
}

/// Open Design 的緊湊分頁列：選取頁籤使用白色浮起面，其餘維持冷灰底。
private struct DesignTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(title: String, value: Int)] = [
        ("卡片", 0),
        ("考題", 2),
        ("造卡", 1),
        ("設定", 4),
        ("歷史", 5)
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.value) { tab in
                #if os(iOS)
                if tab.value != 1 {
                    tabButton(tab)
                }
                #else
                tabButton(tab)
                #endif
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: (title: String, value: Int)) -> some View {
        Button {
            selectedTab = tab.value
        } label: {
            Text(tab.title)
                .font(.system(size: 14, weight: selectedTab == tab.value ? .bold : .semibold))
                .foregroundStyle(selectedTab == tab.value ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 31)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if selectedTab == tab.value {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.designSurface)
                    .shadow(color: Color.black.opacity(0.13), radius: 3, y: 1)
            }
        }
        .accessibilityAddTraits(selectedTab == tab.value ? .isSelected : [])
    }
}

/// 暫停／繼續「依顯示頻率自動彈出單字卡」。按一下開啟選單挑暫停多久。
struct AutoDisplayPauseToggle: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Menu {
            if viewModel.autoDisplayPaused {
                Button("繼續") { viewModel.resumeAutoDisplay() }
                Divider()
            }
            Button("暫停 1 小時") { viewModel.pauseAutoDisplay(until: Date().addingTimeInterval(3600)) }
            Button("暫停 4 小時") { viewModel.pauseAutoDisplay(until: Date().addingTimeInterval(4 * 3600)) }
            Button("暫停到今天晚上 11:59") { viewModel.pauseAutoDisplay(until: Self.tonightElevenFiftyNine()) }
            Button("一直暫停") { viewModel.pauseAutoDisplay(until: nil) }
        } label: {
            Image(systemName: viewModel.autoDisplayPaused ? "play.circle.fill" : "pause.circle")
                .font(.system(size: 16))
                .foregroundStyle(viewModel.autoDisplayPaused ? Color.cardOrange : .secondary)
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .fixedSize()
        .help(helpText)
        .accessibilityLabel("暫停自動顯示")
    }

    private var helpText: String {
        guard viewModel.autoDisplayPaused else { return "暫停自動顯示單字卡" }
        if let until = viewModel.autoDisplayPauseUntil {
            return "已暫停自動顯示單字卡到 \(until.formatted(date: .omitted, time: .shortened))"
        }
        return "已暫停自動顯示單字卡，點一下選擇繼續或改暫停時間"
    }

    private static func tonightElevenFiftyNine() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 23
        components.minute = 59
        components.second = 0
        let tonight = calendar.date(from: components) ?? now
        // 如果已經過了今晚 11:59（例如半夜使用），改成明天晚上 11:59。
        return tonight > now ? tonight : (calendar.date(byAdding: .day, value: 1, to: tonight) ?? tonight)
    }
}

/// 簡報模式開關：按一下暫停卡片自動彈出（手動）。偵測到投影／全螢幕時也會亮起。
struct PresentationModeToggle: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Button {
            viewModel.presentationModeEnabled.toggle()
        } label: {
            Image(systemName: viewModel.isPresentationPaused ? "moon.zzz.fill" : "moon.zzz")
                .font(.system(size: 16))
                .foregroundStyle(viewModel.isPresentationPaused ? Color.cardOrange : .secondary)
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .accessibilityLabel("簡報模式")
    }

    private var helpText: String {
        if viewModel.presentationAutoDetected && !viewModel.presentationModeEnabled {
            return "偵測到簡報／投影中，已暫停自動彈出（結束後自動恢復）"
        }
        return viewModel.presentationModeEnabled
            ? "簡報模式開啟中：已暫停自動彈出，點一下恢復"
            : "簡報模式：暫停卡片自動彈出"
    }
}

enum DatabaseFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case cards = "卡片"
    case sources = "來源"
    case documents = "文件"
    case quizzes = "考題"

    var id: String { rawValue }
}

struct DatabaseView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var filter: DatabaseFilter = .all
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("篩選文字", text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $filter) {
                    ForEach(DatabaseFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 96)
            }

            List {
                if shouldShow(.sources) {
                    Section("來源 \(filteredSources.count)") {
                        ForEach(filteredSources) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.url.absoluteString).font(.headline).lineLimit(1)
                                HStack {
                                    Text(source.isEnabled ? "啟用" : "停用")
                                    if let lastFetchedAt = source.lastFetchedAt {
                                        Text("更新：\(lastFetchedAt.formatted())")
                                    } else {
                                        Text("尚未更新")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if let error = source.lastError {
                                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if shouldShow(.cards) {
                    Section("卡片 \(filteredCards.count)") {
                        ForEach(filteredCards) { card in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(card.word).font(.headline)
                                    Text(card.reading).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(card.status.rawValue)
                                }
                                HStack {
                                    Text("加入：\(card.createdAt.formatted())")
                                    if card.jlptLevel != .unknown {
                                        Text(card.jlptLevel.rawValue)
                                    }
                                    if card.verbFormType != .notVerb && card.verbFormType != .unknown {
                                        Text(card.verbFormType.rawValue)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Text(card.meaningZh).lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if shouldShow(.documents) {
                    Section("文件 \(filteredDocuments.count)") {
                        ForEach(filteredDocuments) { document in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(document.title.isEmpty ? document.url.absoluteString : document.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("抓取：\(document.fetchedAt.formatted())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(document.plainText).font(.caption).lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if shouldShow(.quizzes) {
                    Section("考題 \(filteredQuizzes.count)") {
                        ForEach(filteredQuizzes) { quiz in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(quiz.sourceWord).font(.headline)
                                    Spacer()
                                    Text(quiz.status.rawValue)
                                }
                                Text(quiz.question).lineLimit(2)
                                Text("加入：\(quiz.createdAt.formatted())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if isEmpty {
                    ContentUnavailableView("沒有符合條件的資料", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .padding()
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredSources: [Source] {
        viewModel.snapshot.sources.filter { source in
            normalizedQuery.isEmpty ||
            source.url.absoluteString.lowercased().contains(normalizedQuery) ||
            source.extractionPrompt.lowercased().contains(normalizedQuery) ||
            (source.lastError?.lowercased().contains(normalizedQuery) ?? false)
        }
    }

    private var filteredCards: [LearningCard] {
        viewModel.snapshot.cards.filter { card in
            normalizedQuery.isEmpty ||
            card.word.lowercased().contains(normalizedQuery) ||
            card.reading.lowercased().contains(normalizedQuery) ||
            card.meaningZh.lowercased().contains(normalizedQuery) ||
            card.exampleJa.lowercased().contains(normalizedQuery) ||
            card.status.rawValue.lowercased().contains(normalizedQuery) ||
            card.jlptLevel.rawValue.lowercased().contains(normalizedQuery)
        }
    }

    private var filteredDocuments: [CrawledDocument] {
        viewModel.snapshot.documents.filter { document in
            normalizedQuery.isEmpty ||
            document.title.lowercased().contains(normalizedQuery) ||
            document.url.absoluteString.lowercased().contains(normalizedQuery) ||
            document.plainText.lowercased().contains(normalizedQuery)
        }
    }

    private var filteredQuizzes: [QuizQuestion] {
        viewModel.snapshot.quizzes.filter { quiz in
            normalizedQuery.isEmpty ||
            quiz.sourceWord.lowercased().contains(normalizedQuery) ||
            quiz.question.lowercased().contains(normalizedQuery) ||
            quiz.explanationZh.lowercased().contains(normalizedQuery) ||
            quiz.status.rawValue.lowercased().contains(normalizedQuery)
        }
    }

    private var isEmpty: Bool {
        (!shouldShow(.sources) || filteredSources.isEmpty) &&
        (!shouldShow(.cards) || filteredCards.isEmpty) &&
        (!shouldShow(.documents) || filteredDocuments.isEmpty) &&
        (!shouldShow(.quizzes) || filteredQuizzes.isEmpty)
    }

    private func shouldShow(_ item: DatabaseFilter) -> Bool {
        filter == .all || filter == item
    }
}

struct QuizView: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage("japaneseDisplayScale") private var japaneseDisplayScale = 1.18

    // 高度由卡片頁決定(見 RootView),考題內容比卡片高時改用捲動。
    var body: some View {
        ScrollView {
            quizContent
        }
        .background(Color.designCanvas)
    }

    private var quizContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("考題")
                        .font(.title2.weight(.semibold))
                    #if os(macOS)
                    Text("由 AI 根據已產生的學習卡出題，作答後顯示解析。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #else
                    Text("考題在 Mac 版產生，透過 iCloud 同步到這裡作答。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #endif
                }
                Spacer()
                // AI 出題屬於內容產生，只在 macOS 提供。
                #if os(macOS)
                Button {
                    viewModel.generateQuiz()
                } label: {
                    Label(viewModel.isGeneratingQuiz ? "出題中..." : "AI 出題", systemImage: "sparkles")
                }
                .disabled(viewModel.isGeneratingQuiz)
                #endif
            }

            if let quiz = viewModel.currentQuiz {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(quiz.sourceWord)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(quiz.question)
                            .font(.system(size: 17 * japaneseDisplayScale, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(Array(quiz.choices.enumerated()), id: \.offset) { index, choice in
                            Button {
                                if quiz.status == .pending {
                                    viewModel.submitQuizAnswer(choice)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(optionLabel(index))
                                        .font(.body.weight(.bold))
                                        .frame(width: 30, height: 30)
                                        .foregroundStyle(labelColor(choice: choice, quiz: quiz, index: index))
                                        .background(labelBgColor(choice: choice, quiz: quiz, index: index))
                                        .clipShape(Circle())
                                    
                                    Text(choice)
                                        .font(.system(size: 15 * japaneseDisplayScale, weight: .semibold))
                                        .foregroundStyle(textColor(choice: choice, quiz: quiz))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    if quiz.status != .pending {
                                        if choice == quiz.correctAnswer {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundStyle(Color.quizCorrect)
                                        } else if choice == quiz.selectedAnswer {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundStyle(Color.quizIncorrect)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(
                                QuizChoiceButtonStyle(
                                    bgColor: choiceBgColor(choice: choice, quiz: quiz, index: index),
                                    borderColor: choiceBorderColor(choice: choice, quiz: quiz, index: index),
                                    borderLineWidth: choiceBorderLineWidth(choice: choice, quiz: quiz)
                                )
                            )
                        }

                        if quiz.status != .pending {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Label(
                                    quiz.status == .correct ? "答對了" : "正解：\(quiz.correctAnswer)",
                                    systemImage: quiz.status == .correct ? "checkmark.seal" : "lightbulb"
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(quiz.status == .correct ? Color.quizCorrect : Color.quizIncorrect)
                                Text(quiz.explanationZh)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button("略過") {
                        viewModel.skipCurrentQuiz()
                    }
                    .disabled(quiz.status != .pending)
                    Spacer()
                    Button {
                        viewModel.showNextQuiz()
                    } label: {
                        Label("下一題", systemImage: "arrow.right")
                    }
                }
            } else {
                ContentUnavailableView(
                    "還沒有待作答考題",
                    systemImage: "checklist",
                    description: quizEmptyDescription
                )
                Spacer()
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var quizEmptyDescription: Text {
        #if os(macOS)
        return Text("先按 AI 出題，系統會從已儲存的學習卡產生選擇題。")
        #else
        return Text("在 Mac 版按 AI 出題產生考題，同步後就會出現在這裡。")
        #endif
    }

    private func optionLabel(_ index: Int) -> String {
        ["A", "B", "C", "D"][safe: index] ?? "\(index + 1)"
    }

    private func optionAccent(_ index: Int) -> Color {
        [.blue, .purple, .orange, .teal][safe: index] ?? .accentColor
    }

    private func labelColor(choice: String, quiz: QuizQuestion, index: Int) -> Color {
        if quiz.status == .pending {
            return optionAccent(index)
        }
        if choice == quiz.correctAnswer || choice == quiz.selectedAnswer {
            return .white
        }
        return .secondary
    }

    private func labelBgColor(choice: String, quiz: QuizQuestion, index: Int) -> Color {
        if quiz.status == .pending {
            return optionAccent(index).opacity(0.16)
        }
        if choice == quiz.correctAnswer {
            return .quizCorrect
        }
        if choice == quiz.selectedAnswer {
            return .quizIncorrect
        }
        return Color.gray.opacity(0.12)
    }

    private func textColor(choice: String, quiz: QuizQuestion) -> Color {
        if quiz.status == .pending {
            return .primary
        }
        if choice == quiz.correctAnswer || choice == quiz.selectedAnswer {
            return .primary
        }
        return .secondary
    }

    private func choiceBgColor(choice: String, quiz: QuizQuestion, index: Int) -> Color {
        if quiz.status == .pending {
            return Color.platformTextBackground
        }
        if choice == quiz.correctAnswer {
            return .quizCorrectBg
        }
        if choice == quiz.selectedAnswer {
            return .quizIncorrectBg
        }
        return Color.platformTextBackground.opacity(0.5)
    }

    private func choiceBorderColor(choice: String, quiz: QuizQuestion, index: Int) -> Color {
        if quiz.status == .pending {
            return optionAccent(index).opacity(0.4)
        }
        if choice == quiz.correctAnswer {
            return .quizCorrect
        }
        if choice == quiz.selectedAnswer {
            return .quizIncorrect
        }
        return Color.gray.opacity(0.15)
    }

    private func choiceBorderLineWidth(choice: String, quiz: QuizQuestion) -> CGFloat {
        if quiz.status == .pending {
            return 1.5
        }
        if choice == quiz.correctAnswer || choice == quiz.selectedAnswer {
            return 2.5
        }
        return 1.0
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct CardView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let card = viewModel.currentCard {
                // 卡片放進 ScrollView：popover 高度不足（螢幕上限、量測誤差）時
                // 內容改為捲動，絕不被裁切；進度條與頁籤列因此永遠可見。
                ScrollView(.vertical) {
                    StyledLearningCard(
                        card: card,
                        isGeneratingExampleReading: viewModel.isGeneratingExampleReading,
                        fillExampleReading: viewModel.fillCurrentExampleReading,
                        skipCard: { viewModel.markCurrentCard(.skipped) },
                        learnCard: { viewModel.markCurrentCard(.learned) },
                        nextCard: viewModel.showNextCard
                    )
                    .id(card.id)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            } else {
                #if os(macOS)
                ContentUnavailableView(
                    "還沒有學習卡",
                    systemImage: "sparkles",
                    description: Text("新增網址與 API key 後，按立即更新產生第一批卡片。")
                )
                Button {
                    viewModel.refreshNow()
                } label: {
                    Label(viewModel.isRefreshing ? "更新中..." : "立即更新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)
                #else
                // iOS 不產生內容：卡片由 Mac 版產生，這裡只做 CloudKit 同步。
                ContentUnavailableView(
                    "還沒有學習卡",
                    systemImage: "icloud.and.arrow.down",
                    description: Text("在 Mac 版產生卡片後，透過 iCloud 同步到這裡。")
                )
                Button {
                    Task { await viewModel.performPull() }
                } label: {
                    Label(viewModel.iCloudIsSyncing ? "同步中..." : "立即同步", systemImage: "arrow.clockwise.icloud")
                }
                .disabled(viewModel.iCloudIsSyncing || !viewModel.isICloudSyncAvailable)
                #endif
                Spacer()
            }
        }
        .padding(16)
        .padding(.bottom, viewModel.currentCard == nil ? 0 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if viewModel.currentCard != nil {
                CardTimerLightBar(timerState: viewModel.visibleCardTimerState)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 3)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct QuickReviewControls: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.isQuickReviewActive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.durationText(viewModel.quickReviewSessionState.remainingSeconds(at: context.date)))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.cardBlue)
                        .frame(minWidth: 48, alignment: .trailing)
                }

                Button {
                    viewModel.stopQuickReview()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .controlSize(.small)
            } else {
                Button {
                    viewModel.startQuickReview()
                } label: {
                    Label("快速複習", systemImage: "timer")
                }
                .controlSize(.small)
            }
        }
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private enum LearningCardLayoutKind {
    case vocabulary
    case grammar

    init(card: LearningCard) {
        let word = card.word.trimmingCharacters(in: .whitespacesAndNewlines)
        let partOfSpeech = card.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        if word.contains("〜") || word.contains("~") || partOfSpeech.contains("文法") || partOfSpeech.contains("句型") {
            self = .grammar
        } else {
            self = .vocabulary
        }
    }

    var title: String {
        switch self {
        case .vocabulary: "單字卡"
        case .grammar: "文法卡"
        }
    }

    var icon: String { "book" }
}

private struct StyledLearningCard: View {
    var card: LearningCard
    var isGeneratingExampleReading: Bool
    var fillExampleReading: () -> Void
    var skipCard: () -> Void
    var learnCard: () -> Void
    var nextCard: () -> Void

    @State private var isMeaningShown = false
    @State private var isExampleTranslationShown = false
    @State private var cardLoadTime = Date()
    @AppStorage("japaneseDisplayScale") private var japaneseDisplayScale = 1.18

    private var kind: LearningCardLayoutKind { LearningCardLayoutKind(card: card) }
    private var noteSections: CardNoteSections { CardNoteSections(note: card.grammarNoteZh) }
    private var cardCopyText: String {
        clipboardText(base: card.word, reading: card.reading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            cardHeader

            switch kind {
            case .vocabulary:
                vocabularyLayout
            case .grammar:
                grammarLayout
            }

            cardFooter
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.designSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.cardBlue.opacity(0.48), lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
        .task {
            cardLoadTime = Date()
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeInOut(duration: 0.8)) {
                isMeaningShown = true
            }
        }
    }

    private var cardHeader: some View {
        HStack(spacing: 0) {
            Text(card.jlptLevel == .unknown ? "JLPT" : "JLPT \(card.jlptLevel.rawValue)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 10,
                        bottomLeadingRadius: 10,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(Color.cardBlue)
                )

            Label(kind.title, systemImage: kind.icon)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.cardBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 10,
                        topTrailingRadius: 10
                    )
                    .fill(Color.white)
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 10,
                        topTrailingRadius: 10
                    )
                    .stroke(Color.cardBlue, lineWidth: 1.5)
                )

            Spacer()

            SpeechModeToggleButton()
                .padding(.leading, 8)

            SpeakButton(text: card.word, speechText: card.reading, isProminent: true)
                .padding(.leading, 8)

            CopyButton(text: cardCopyText, isProminent: true)
                .padding(.leading, 8)
        }
    }

    private var vocabularyLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                wordHero
                    .frame(maxWidth: .infinity, minHeight: 96)

                Divider()
                    .frame(height: 92)

                VStack(alignment: .leading, spacing: 8) {
                    CardInfoPanel(title: "意味", systemImage: "lightbulb", tint: .cardOrange) {
                        ZStack(alignment: .leading) {
                            Text(card.meaningZh)
                                .font(.body.weight(.semibold))
                                .lineLimit(2)
                                .opacity(isMeaningShown ? 1.0 : 0.0)
                                .scaleEffect(isMeaningShown ? 1.0 : 0.96)
                                .offset(y: isMeaningShown ? 0 : 2)
                            
                            if !isMeaningShown {
                                TimelineView(.animation(minimumInterval: 0.03)) { context in
                                    let elapsed = context.date.timeIntervalSince(cardLoadTime)
                                    let remaining = max(0.0, 5.0 - elapsed)
                                    
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.8)) {
                                            isMeaningShown = true
                                        }
                                    } label: {
                                        SegmentedCountdownView(remaining: remaining)
                                            .padding(.vertical, 6)
                                            .padding(.trailing, 12)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.opacity)
                                }
                            }
                        }
                        if let point = noteSections.point {
                            Divider().overlay(Color.cardOrange.opacity(0.45))
                            Text(point)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    CardInfoPanel(title: "品詞", systemImage: "tag.fill", tint: .cardGreen) {
                        Text(card.partOfSpeech.isEmpty ? "未分類" : card.partOfSpeech)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            examplePanel(tint: .cardPink, title: "例文")

            HStack(alignment: .top, spacing: 8) {
                CardInfoPanel(title: "よく使う形", systemImage: "checkmark.circle.fill", tint: .cardBlue) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(commonForms.prefix(3), id: \.self) { form in
                            UsageLine(text: form)
                        }
                    }
                }

                CardInfoPanel(title: "関連語", systemImage: "star.fill", tint: .cardGreen) {
                    Text(noteSections.relatedWords ?? "例文與解說中延伸記憶")
                        .font(.callout)
                        .lineLimit(2)
                }
            }
        }
    }

    private var grammarLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                wordHero
                    .frame(maxWidth: .infinity, minHeight: 94)

                CardInfoPanel(title: "意味", systemImage: "lightbulb", tint: .cardOrange) {
                    ZStack(alignment: .leading) {
                        Text(card.meaningZh)
                            .font(.body.weight(.semibold))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(isMeaningShown ? 1.0 : 0.0)
                            .scaleEffect(isMeaningShown ? 1.0 : 0.96)
                            .offset(y: isMeaningShown ? 0 : 2)
                        
                        if !isMeaningShown {
                            TimelineView(.animation(minimumInterval: 0.03)) { context in
                                let elapsed = context.date.timeIntervalSince(cardLoadTime)
                                let remaining = max(0.0, 5.0 - elapsed)
                                
                                Button {
                                    withAnimation(.easeInOut(duration: 0.8)) {
                                        isMeaningShown = true
                                    }
                                } label: {
                                    SegmentedCountdownView(remaining: remaining)
                                        .padding(.vertical, 6)
                                        .padding(.trailing, 12)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .transition(.opacity)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 7) {
                CardInfoPanel(title: "接続", systemImage: "gearshape.fill", tint: .cardPink) {
                    Text(connectionText)
                        .font(.body.weight(.semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CardInfoPanel(title: "ポイント", systemImage: "exclamationmark.circle.fill", tint: .cardPink) {
                    Text(noteSections.point ?? "注意句型前後的接續與語氣。")
                        .font(.callout)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            examplePanel(tint: .cardBlue, title: "例文")

            HStack(alignment: .top, spacing: 8) {
                CardInfoPanel(title: "よく使う場面", systemImage: "checkmark.circle.fill", tint: .cardGreen) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(usageScenes.prefix(2), id: \.self) { scene in
                            UsageLine(text: scene)
                        }
                    }
                }

                CardInfoPanel(title: "類似表現との差", systemImage: "star.fill", tint: .cardOrange) {
                    Text(noteSections.similarExpressions ?? "和近義句型比較時，先看接續與語氣差異。")
                        .font(.callout)
                        .lineLimit(2)
                }
            }
        }
    }

    private var wordHero: some View {
        let trimmedReading = card.reading.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWord = card.word.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only show the reading when it adds information beyond the headword
        // (e.g. kanji words). For kana grammar patterns reading == word.
        let showReading = !trimmedReading.isEmpty && trimmedReading != trimmedWord
        let romanized = card.reading.romanizedJapaneseFallback
        // The romaji fallback leaves kana untouched, so only render it when it
        // actually differs from the reading we already displayed.
        let showRomanized = showReading && !romanized.isEmpty && romanized != trimmedReading
        let usesRuby = RubySupport.isUsable(card.wordRuby, for: trimmedWord)
        let wordLength = trimmedWord.count
        let baseSize = Self.wordFontSize(forLength: wordLength, isGrammar: kind == .grammar) * japaneseDisplayScale
        let rubySize = Self.rubyFontSize(forLength: wordLength) * japaneseDisplayScale
        return VStack(spacing: 6) {
            if usesRuby {
                RubyText(
                    segments: card.wordRuby,
                    fallback: trimmedWord,
                    baseFont: .system(size: baseSize, weight: .black, design: .rounded),
                    rubyFont: .system(size: rubySize, weight: .bold, design: .rounded),
                    baseColor: kind == .grammar ? Color.cardBlue : .primary,
                    rubyColor: Color.cardBlue,
                    horizontalSpacing: 0,
                    verticalSpacing: 1
                )
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            } else if showReading {
                Text(card.reading)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.cardBlue)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if !usesRuby {
                Text(card.word)
                    .font(.system(size: baseSize + 7, weight: .black, design: .rounded))
                    .foregroundStyle(kind == .grammar ? Color.cardBlue : .primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 24)
            }
            if showRomanized && !usesRuby {
                Text(romanized)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    /// 依字數縮放單字字級，字數愈多字級愈小，盡量讓卡片維持單行不折行。
    private static func wordFontSize(forLength length: Int, isGrammar: Bool) -> CGFloat {
        let base: CGFloat = isGrammar ? 30 : 38
        switch length {
        case 0...2: return base
        case 3...4: return base - 5
        case 5...6: return base - 11
        case 7...8: return base - 16
        default: return base - 20
        }
    }

    /// 假名 ruby 字級同樣依字數縮放，但維持比基礎字級更大的比例。
    private static func rubyFontSize(forLength length: Int) -> CGFloat {
        switch length {
        case 0...2: return 17
        case 3...4: return 15
        case 5...6: return 13
        case 7...8: return 12
        default: return 11
        }
    }

    private var cardFooter: some View {
        HStack(spacing: 8) {
            Link(destination: card.sourceUrl) {
                Label(card.sourceUrl.host() ?? card.sourceUrl.absoluteString, systemImage: "link")
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)

            Text("出現 \(card.shownCount) 次")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button {
                skipCard()
            } label: {
                Label("略過", systemImage: "forward")
            }
            .controlSize(.small)

            Button {
                learnCard()
            } label: {
                Label("已學會", systemImage: "checkmark")
            }
            .controlSize(.small)

            Button {
                nextCard()
            } label: {
                Label("下一張", systemImage: "arrow.right")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(.cardGreen)
            .controlSize(.regular)
        }
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private var connectionText: String {
        if let connection = noteSections.connection {
            return connection
        }
        if card.word.contains("〜") || card.word.contains("~") {
            return "\(card.word) の前後の接続"
        } else if card.verbFormType != .notVerb && card.verbFormType != .unknown {
            return "\(card.verbFormType.rawValue) + \(card.word)"
        } else {
            return "\(card.partOfSpeech.isEmpty ? "語句" : card.partOfSpeech) + \(card.word)"
        }
    }

    private var commonForms: [String] {
        if let commonForms = noteSections.commonForms {
            return commonForms.cardListItems
        }
        var forms = [card.word]
        if card.verbFormType != .notVerb && card.verbFormType != .unknown {
            forms.append(card.verbFormType.rawValue)
        }
        if !card.reading.isEmpty {
            forms.append(card.reading)
        }
        return forms
    }

    private var usageScenes: [String] {
        noteSections.usageScenes?.cardListItems ?? [
            "文章、會話或考題中辨認句型",
            "搭配例句一起記憶語氣"
        ]
    }

    private func examplePanel(tint: Color, title: String) -> some View {
        CardInfoPanel(title: title, systemImage: "pencil", tint: tint) {
            VStack(alignment: .leading, spacing: 8) {
                if RubySupport.isUsable(card.exampleRuby, for: card.exampleJa) {
                    ZStack(alignment: .topTrailing) {
                            RubyText(
                                segments: card.exampleRuby,
                                fallback: card.exampleJa,
                                baseFont: .system(size: 18 * japaneseDisplayScale, weight: .semibold),
                                rubyFont: .system(size: 12 * japaneseDisplayScale, weight: .medium),
                            baseColor: .primary,
                            rubyColor: .secondary,
                            horizontalSpacing: 1,
                            verticalSpacing: 3
                        )
                        .padding(.trailing, 48)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 6) {
                            SpeakButton(text: card.exampleJa)
                            CopyButton(text: clipboardText(base: card.exampleJa, reading: card.exampleReading))
                        }
                    }
                } else {
                    CopyableTextRow(
                        text: card.exampleJa,
                        font: .system(size: 18 * japaneseDisplayScale, weight: .semibold),
                        copyText: clipboardText(base: card.exampleJa, reading: card.exampleReading),
                        showSpeakButton: true
                    )
                    .lineLimit(3)
                }
                if !card.exampleReading.isEmpty && !RubySupport.isUsable(card.exampleRuby, for: card.exampleJa) {
                    CopyableTextRow(
                        text: card.exampleReading,
                        font: .system(size: 14 * japaneseDisplayScale, weight: .medium),
                        color: .secondary
                    )
                        .lineLimit(2)
                } else if card.exampleReading.isEmpty && !RubySupport.isUsable(card.exampleRuby, for: card.exampleJa) {
                    Button {
                        fillExampleReading()
                    } label: {
                        Label(isGeneratingExampleReading ? "補平假名中..." : "補平假名", systemImage: "wand.and.stars")
                    }
                    .disabled(isGeneratingExampleReading)
                }
                ZStack(alignment: .topLeading) {
                    Text(card.exampleZh)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(isExampleTranslationShown ? 1.0 : 0.0)

                    if !isExampleTranslationShown {
                        Button {
                            withAnimation(.easeInOut(duration: 0.8)) {
                                isExampleTranslationShown = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                Text("顯示中文翻譯")
                            }
                            .font(.caption)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(tint.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func clipboardText(base: String, reading: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReading = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReading.isEmpty, trimmedReading != trimmedBase else { return trimmedBase }
        return "\(trimmedBase)\n\(trimmedReading)"
    }
}

private struct CardNoteSections {
    var connection: String?
    var point: String?
    var usageScenes: String?
    var similarExpressions: String?
    var commonForms: String?
    var relatedWords: String?

    init(note: String) {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return }

        var activeKey: WritableKeyPath<CardNoteSections, String?>?
        for rawLine in trimmedNote.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let match = Self.match(line: line) {
                activeKey = match.keyPath
                append(match.value, to: match.keyPath)
            } else if let activeKey {
                append(line, to: activeKey)
            } else {
                append(line, to: \.point)
            }
        }
    }

    private static func match(line: String) -> (keyPath: WritableKeyPath<CardNoteSections, String?>, value: String)? {
        let labels: [(String, WritableKeyPath<CardNoteSections, String?>)] = [
            ("接續", \.connection),
            ("接続", \.connection),
            ("重點", \.point),
            ("ポイント", \.point),
            ("使用場景", \.usageScenes),
            ("よく使う場面", \.usageScenes),
            ("類似表現", \.similarExpressions),
            ("類似表現との差", \.similarExpressions),
            ("常用形", \.commonForms),
            ("よく使う形", \.commonForms),
            ("よく使う", \.commonForms),
            ("相關語", \.relatedWords),
            ("関連語", \.relatedWords)
        ]

        for (label, keyPath) in labels {
            for separator in ["：", ":"] {
                let prefix = "\(label)\(separator)"
                if line.hasPrefix(prefix) {
                    let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (keyPath, value)
                }
            }
        }
        return nil
    }

    private mutating func append(_ value: String, to keyPath: WritableKeyPath<CardNoteSections, String?>) {
        guard !value.isEmpty else { return }
        if let existing = self[keyPath: keyPath], !existing.isEmpty {
            self[keyPath: keyPath] = "\(existing)\n\(value)"
        } else {
            self[keyPath: keyPath] = value
        }
    }
}

private struct CardInfoPanel<Content: View>: View {
    var title: String
    var systemImage: String
    var tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(tint.gradient, in: Capsule())

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct UsageLine: View {
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Color.cardBlue)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CardTimerLightBar: View {
    var timerState: VisibleCardTimerState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { proxy in
                let fraction = timerState.remainingFraction(at: context.date)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.cardBlue.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cardGreen, .cardOrange, .cardPink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * fraction)
                        .shadow(color: Color.cardOrange.opacity(timerState.isActive ? 0.45 : 0.15), radius: 5)
                }
            }
            .opacity(timerState.isActive ? 1 : 0.35)
            .accessibilityLabel("卡片停留時間")
            .accessibilityValue("\(Int(timerState.duration * timerState.remainingFraction(at: context.date))) 秒")
        }
        .frame(height: 5)
    }
}

private struct SegmentedCountdownView: View {
    var remaining: Double
    var color: Color = .cardOrange
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                let threshold = Double(index)
                let isActive = remaining > threshold
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .opacity(isActive ? 1.0 : 0.18)
                    .frame(width: 14, height: 14)
                    .animation(.easeInOut(duration: 0.2), value: isActive)
            }
        }
    }
}

struct CardBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.blue.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private extension Color {
    // Open Design brand tokens: cool blue chrome, white content surfaces,
    // and semantic accents reserved for learning states.
    static let designCanvas = Color(red: 0.843, green: 0.871, blue: 0.91)
    static let designSurface = Color.white
    static let designBorder = Color(red: 0.62, green: 0.75, blue: 0.91)
    static let cardBlue = Color(red: 0.071, green: 0.369, blue: 0.710)
    static let cardOrange = Color(red: 0.94, green: 0.58, blue: 0.05)
    static let cardPink = Color(red: 0.93, green: 0.25, blue: 0.43)
    static let cardGreen = Color(red: 0.35, green: 0.68, blue: 0.16)

    static let quizCorrect = Color(red: 0.18, green: 0.80, blue: 0.44)
    static let quizIncorrect = Color(red: 0.91, green: 0.30, blue: 0.24)
    static let quizCorrectBg = Color(red: 0.18, green: 0.80, blue: 0.44).opacity(0.12)
    static let quizIncorrectBg = Color(red: 0.91, green: 0.30, blue: 0.24).opacity(0.12)
}

private extension String {
    var romanizedJapaneseFallback: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        return value
            .replacingOccurrences(of: "ー", with: "-")
            .replacingOccurrences(of: " ", with: " ")
    }

    var cardListItems: [String] {
        split(whereSeparator: { character in
            character == "\n" || character == "、" || character == "，" || character == ";"
        })
        .map { item in
            item.trimmingCharacters(in: CharacterSet(charactersIn: " -•・\t"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }
}

struct CopyableTextRow: View {
    var text: String
    var font: Font
    var color: Color = .primary
    var copyText: String? = nil
    var showSpeakButton = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if showSpeakButton {
                SpeakButton(text: copyText ?? text)
            }
            CopyButton(text: copyText ?? text)
        }
    }
}

/// 統一的「複製到剪貼簿」按鈕，整張卡只保留一顆。
struct CopyButton: View {
    var text: String
    var isProminent = false
    @State private var didCopy = false
    @State private var feedbackToken = 0

    var body: some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #else
            UIPasteboard.general.string = text
            #endif
            showCopyFeedback()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: isProminent ? 13 : 12, weight: .bold))
                    .symbolEffect(.bounce, value: didCopy)

                if isProminent {
                    Text(didCopy ? "已複製" : "複製")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(didCopy ? Color.cardGreen : Color.cardBlue)
            .frame(width: isProminent ? 68 : 18, height: isProminent ? 30 : 18)
            .background {
                if isProminent {
                    RoundedRectangle(cornerRadius: 7)
                        .fill((didCopy ? Color.cardGreen : Color.cardBlue).opacity(didCopy ? 0.14 : 0.09))
                }
            }
            .overlay {
                if isProminent {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke((didCopy ? Color.cardGreen : Color.cardBlue).opacity(didCopy ? 0.38 : 0.28), lineWidth: 1)
                }
            }
            .scaleEffect(didCopy ? 1.04 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: didCopy)
        }
        .buttonStyle(.borderless)
        .contentShape(RoundedRectangle(cornerRadius: isProminent ? 7 : 4))
        .help(didCopy ? "已複製" : "複製")
    }

    private func showCopyFeedback() {
        feedbackToken += 1
        let token = feedbackToken
        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
            didCopy = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            guard feedbackToken == token else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                didCopy = false
            }
        }
    }
}

struct SpeakButton: View {
    var text: String
    var speechText: String?
    var isProminent = false
    @State private var isSpeaking = false
    @State private var isWaitingForRemoteAudio = false
    @State private var speakToken = 0
    @EnvironmentObject var viewModel: AppViewModel
    
    var body: some View {
        Button {
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanSpeechText = speechText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let settings = viewModel.snapshot.settings
            let usesRemoteTTS = settings.openAITtsEnabled

            speakToken += 1
            let token = speakToken
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                isSpeaking = true
                isWaitingForRemoteAudio = usesRemoteTTS
            }

            SpeechSynthesizerManager.shared.speak(cleanText, remoteText: cleanSpeechText, settings: settings) { status in
                viewModel.statusMessage = status
                if usesRemoteTTS && Self.shouldKeepWaiting(for: status) {
                    return
                }
                finishSpeakingFeedback(token: token, delay: usesRemoteTTS ? 1.4 : 1.2)
            }

            if !usesRemoteTTS {
                finishSpeakingFeedback(token: token, delay: 1.2)
            }
        } label: {
            HStack(spacing: 5) {
                if isWaitingForRemoteAudio {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: isProminent ? 13 : 12, height: isProminent ? 13 : 12)
                } else {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: isProminent ? 13 : 12, weight: .bold))
                        .symbolEffect(.bounce, value: isSpeaking)
                }
                
                if isProminent {
                    Text(isWaitingForRemoteAudio ? "準備中" : "發音")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Color.cardBlue)
            .frame(width: isProminent ? 68 : 18, height: isProminent ? 30 : 18)
            .background {
                if isProminent {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.cardBlue.opacity(0.09))
                }
            }
            .overlay {
                if isProminent {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.cardBlue.opacity(0.28), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.borderless)
        .contentShape(RoundedRectangle(cornerRadius: isProminent ? 7 : 4))
        .disabled(isWaitingForRemoteAudio)
        .help(isWaitingForRemoteAudio ? "正在等待 AI 語音" : "發音")
    }

    private static func shouldKeepWaiting(for status: String) -> Bool {
        status.hasPrefix("正在透過") || status.hasPrefix("正在測試")
    }

    private func finishSpeakingFeedback(token: Int, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard speakToken == token else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isSpeaking = false
                isWaitingForRemoteAudio = false
            }
        }
    }
}

struct SpeechModeToggleButton: View {
    @EnvironmentObject var viewModel: AppViewModel

    private var useAI: Bool {
        viewModel.snapshot.settings.openAITtsEnabled
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                viewModel.setTTSMode(useAI: !useAI)
            }
        } label: {
            ZStack(alignment: useAI ? .trailing : .leading) {
                Capsule()
                    .fill((useAI ? Color.cardPink : Color.cardGreen).opacity(0.14))
                    .overlay {
                        Capsule()
                            .stroke((useAI ? Color.cardPink : Color.cardGreen).opacity(0.34), lineWidth: 1)
                    }

                HStack(spacing: 0) {
                    Text("內建")
                        .frame(maxWidth: .infinity)
                    Text("AI")
                        .frame(maxWidth: .infinity)
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)

                Capsule()
                    .fill(useAI ? Color.cardPink : Color.cardGreen)
                    .frame(width: 31, height: 24)
                    .overlay {
                        Image(systemName: useAI ? "sparkles" : "speaker.wave.1")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(3)
            }
            .frame(width: 76, height: 30)
        }
        .buttonStyle(.borderless)
        .contentShape(Capsule())
        .accessibilityLabel("發音模式")
        .accessibilityValue(useAI ? "AI 發音" : "內建發音")
        .help(useAI ? "目前使用 AI 發音，點擊切換為內建發音" : "目前使用內建發音，點擊切換為 AI 發音")
    }
}

@MainActor
private final class SpeechSynthesizerManager {
    static let shared = SpeechSynthesizerManager()
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var downloadTask: URLSessionDataTask?
    private let secretStore = KeychainStore()
    private let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("JapaneseLearningCard", isDirectory: true)
            .appendingPathComponent("TTSCache", isDirectory: true)
    }()
    
    func speak(
        _ text: String,
        remoteText: String? = nil,
        settings: AppSettings,
        language: String = "ja-JP",
        onStatus: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        downloadTask?.cancel()
        downloadTask = nil
        audioPlayer?.stop()
        audioPlayer = nil

        if settings.openAITtsEnabled {
            if let apiKey = try? secretStore.apiKey(reference: settings.ttsKeychainReference), !apiKey.isEmpty {
                onStatus("正在透過 \(settings.openAITtsProviderPreset.displayName) TTS 發音 (\(settings.openAITtsVoice))...")
                let ttsText = remoteText?.isEmpty == false ? remoteText! : text
                speakRemoteTTS(ttsText, settings: settings, apiKey: apiKey, fallbackToNativeOnFailure: true, onStatus: onStatus)
                return
            } else {
                onStatus("尚未儲存 API Key，已 Fallback 至系統原生語音發音")
            }
        } else {
            onStatus("正在使用系統原生語音發音...")
        }

        speakNative(text, language: language)
    }

    func testConfiguredTTS(settings: AppSettings, onStatus: @escaping @MainActor (String) -> Void) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        downloadTask?.cancel()
        downloadTask = nil
        audioPlayer?.stop()
        audioPlayer = nil

        guard let apiKey = try? secretStore.apiKey(reference: settings.ttsKeychainReference), !apiKey.isEmpty else {
            onStatus("請先儲存 TTS API Key，才能測試模型發音。")
            return
        }
        guard !settings.openAITtsModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onStatus("請先選擇或輸入 TTS 模型。")
            return
        }

        onStatus("正在測試 \(settings.openAITtsProviderPreset.displayName) TTS 模型：\(settings.openAITtsModel)")
        speakRemoteTTS(
            "これは日本語の発音テストです。",
            settings: settings,
            apiKey: apiKey,
            fallbackToNativeOnFailure: false,
            onStatus: onStatus
        )
    }

    private func speakNative(_ text: String, language: String) {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
        #endif
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        
        synthesizer.speak(utterance)
    }

    private func speakRemoteTTS(
        _ text: String,
        settings: AppSettings,
        apiKey: String,
        fallbackToNativeOnFailure: Bool,
        onStatus: @escaping @MainActor (String) -> Void
    ) {
        if settings.openAITtsProviderPreset == .elevenLabs {
            speakElevenLabs(text, settings: settings, apiKey: apiKey, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
            return
        }
        if settings.openAITtsProviderPreset == .gemini {
            speakGemini(text, settings: settings, apiKey: apiKey, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
            return
        }

        var baseString = settings.openAITtsProviderPreset == .openAI
            ? TTSProviderPreset.openAI.defaultBaseURL
            : settings.openAITtsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseString.hasSuffix("/") {
            baseString.removeLast()
        }
        guard let url = URL(string: "\(baseString)/audio/speech") else {
            handleTTSFailure("API Base URL 格式錯誤", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
            return
        }
        let speechInput = remoteSpeechInput(text)
        let cacheURL = ttsCacheURL(settings: settings, text: text, speechInput: speechInput, fileExtension: "mp3")
        if playCachedAudioIfAvailable(cacheURL, providerName: settings.openAITtsProviderPreset.displayName, voice: settings.openAITtsVoice, onStatus: onStatus) {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": settings.openAITtsModel,
            "input": speechInput,
            "voice": settings.openAITtsVoice
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            handleTTSFailure("序列化請求失敗", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
            return
        }
        request.httpBody = httpBody

        let requestURL = request.url?.absoluteString ?? ""
        let hasAuthorizationHeader = request.value(forHTTPHeaderField: "Authorization")?.isEmpty == false
        print("TTS request URL: \(requestURL)")
        print("TTS Authorization header present: \(hasAuthorizationHeader)")

        let session = URLSession.shared
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    print("TTS network error: \(error.localizedDescription)")
                    self.handleTTSFailure("網路請求失敗：\(error.localizedDescription)", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.handleTTSFailure("連線回應異常", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                    return
                }
                guard (200...299).contains(httpResponse.statusCode), let data = data else {
                    print("TTS HTTP status: \(httpResponse.statusCode)")
                    var details = ""
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("TTS error response: \(errorString)")
                        details = " (\(errorString.prefix(60)))"
                    }
                    if httpResponse.statusCode == 401 {
                        details += "；URL=\(requestURL)；Authorization header=\(hasAuthorizationHeader ? "present" : "missing")"
                    }
                    self.handleTTSFailure("API 回傳失敗 (\(httpResponse.statusCode))\(details)", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                    return
                }

                #if os(iOS)
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Failed to set audio session category: \(error)")
                }
                #endif

                do {
                    try self.storeAudioData(data, at: cacheURL)
                    try self.playAudioData(data, providerName: settings.openAITtsProviderPreset.displayName, voice: settings.openAITtsVoice, onStatus: onStatus)
                } catch {
                    print("Failed to play TTS audio data: \(error.localizedDescription)")
                    self.handleTTSFailure("播放音訊失敗：\(error.localizedDescription)", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                }
            }
        }
        self.downloadTask = task
        task.resume()
    }

    private func speakElevenLabs(
        _ text: String,
        settings: AppSettings,
        apiKey: String,
        fallbackToNativeOnFailure: Bool,
        onStatus: @escaping @MainActor (String) -> Void
    ) {
        var baseString = settings.openAITtsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseString.hasSuffix("/") {
            baseString.removeLast()
        }
        let voiceID = settings.openAITtsVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voiceID.isEmpty,
              let encodedVoiceID = voiceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseString)/text-to-speech/\(encodedVoiceID)") else {
            handleTTSFailure("ElevenLabs voice_id 或 Base URL 格式錯誤", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
            return
        }
        let speechInput = remoteSpeechInput(text)
        let cacheURL = ttsCacheURL(settings: settings, text: text, speechInput: speechInput, fileExtension: "mp3")
        if playCachedAudioIfAvailable(cacheURL, providerName: settings.openAITtsProviderPreset.displayName, voice: settings.openAITtsVoice, onStatus: onStatus) {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "text": speechInput,
            "model_id": settings.openAITtsModel
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            handleTTSFailure("ElevenLabs 請求序列化失敗", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
            return
        }
        request.httpBody = httpBody

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error {
                    print("TTS network error: \(error.localizedDescription)")
                    self.handleTTSFailure("網路請求失敗：\(error.localizedDescription)", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.handleTTSFailure("連線回應異常", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                    return
                }
                guard (200...299).contains(httpResponse.statusCode), let data else {
                    print("TTS HTTP status: \(httpResponse.statusCode)")
                    var details = ""
                    if let data, let errorString = String(data: data, encoding: .utf8) {
                        print("TTS error response: \(errorString)")
                        details = " (\(errorString.prefix(60)))"
                    }
                    self.handleTTSFailure("API 回傳失敗 (\(httpResponse.statusCode))\(details)", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                    return
                }

                #if os(iOS)
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Failed to set audio session category: \(error)")
                }
                #endif

                do {
                    try self.storeAudioData(data, at: cacheURL)
                    try self.playAudioData(data, providerName: settings.openAITtsProviderPreset.displayName, voice: settings.openAITtsVoice, onStatus: onStatus)
                } catch {
                    print("Failed to play TTS audio data: \(error.localizedDescription)")
                    self.handleTTSFailure("播放音訊失敗：\(error.localizedDescription)", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                }
            }
        }
        self.downloadTask = task
        task.resume()
    }

    private func speakGemini(
        _ text: String,
        settings: AppSettings,
        apiKey: String,
        fallbackToNativeOnFailure: Bool,
        onStatus: @escaping @MainActor (String) -> Void
    ) {
        let voice = settings.openAITtsVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voice.isEmpty else {
            handleTTSFailure("請先選擇 Gemini voice", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
            return
        }

        let speechInput = remoteSpeechInput(text)
        let cacheURL = ttsCacheURL(settings: settings, text: text, speechInput: speechInput, fileExtension: "wav")
        if playCachedAudioIfAvailable(cacheURL, providerName: settings.openAITtsProviderPreset.displayName, voice: voice, onStatus: onStatus) {
            return
        }

        var baseString = TTSProviderPreset.gemini.defaultBaseURL
        if baseString.hasSuffix("/") {
            baseString.removeLast()
        }
        guard let modelName = settings.openAITtsModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseString)/models/\(modelName):generateContent") else {
            handleTTSFailure("Gemini API Base URL 格式錯誤", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
            return
        }

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": speechInput]
                    ]
                ]
            ],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": [
                            "voiceName": voice
                        ]
                    ]
                ]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            handleTTSFailure("Gemini 請求序列化失敗", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        sendGeminiTTSRequest(
            request: request,
            retryCount: 0,
            maxRetries: 2,
            cacheURL: cacheURL,
            text: text,
            voice: voice,
            fallbackToNativeOnFailure: fallbackToNativeOnFailure,
            onStatus: onStatus
        )
    }

    private func sendGeminiTTSRequest(
        request: URLRequest,
        retryCount: Int,
        maxRetries: Int,
        cacheURL: URL,
        text: String,
        voice: String,
        fallbackToNativeOnFailure: Bool,
        onStatus: @escaping @MainActor (String) -> Void
    ) {
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    print("TTS network error: \(error.localizedDescription)")
                    self.handleTTSFailure("網路請求失敗：\(error.localizedDescription)", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.handleTTSFailure("連線回應異常", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                    return
                }
                guard (200...299).contains(httpResponse.statusCode), let data else {
                    print("TTS HTTP status: \(httpResponse.statusCode)")
                    var details = ""
                    if let data, let errorString = String(data: data, encoding: .utf8) {
                        print("TTS error response: \(errorString)")
                        details = " (\(errorString.prefix(60)))"
                    }
                    self.handleTTSFailure("Gemini API 回傳失敗 (\(httpResponse.statusCode))\(details)", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                    return
                }

                #if os(iOS)
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Failed to set audio session category: \(error)")
                }
                #endif

                do {
                    if let responseString = String(data: data, encoding: .utf8)?.prefix(500) {
                        print("Gemini TTS response: \(responseString)")
                    }
                    let audioData = try self.geminiPlayableAudioData(from: data)
                    try self.storeAudioData(audioData, at: cacheURL)
                    try self.playAudioData(audioData, providerName: TTSProviderPreset.gemini.displayName, voice: voice, onStatus: onStatus)
                } catch {
                    let errorMsg = error.localizedDescription
                    if errorMsg.contains("finish_reason") && retryCount < maxRetries {
                        print("Gemini TTS retry \(retryCount + 1)/\(maxRetries) due to: \(errorMsg)")
                        onStatus("Gemini TTS 重試中 (\(retryCount + 1)/\(maxRetries))...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self else { return }
                            self.sendGeminiTTSRequest(
                                request: request,
                                retryCount: retryCount + 1,
                                maxRetries: maxRetries,
                                cacheURL: cacheURL,
                                text: text,
                                voice: voice,
                                fallbackToNativeOnFailure: fallbackToNativeOnFailure,
                                onStatus: onStatus
                            )
                        }
                        return
                    }
                    if let responseString = String(data: data, encoding: .utf8)?.prefix(500) {
                        print("Gemini TTS response body (parse failed): \(responseString)")
                    }
                    print("Failed to play Gemini TTS audio data: \(errorMsg)")
                    self.handleTTSFailure("Gemini 音訊解析或播放失敗：\(errorMsg)", text: text, fallbackToNativeOnFailure: fallbackToNativeOnFailure, onStatus: onStatus)
                }
            }
        }
        self.downloadTask = task
        task.resume()
    }

    private struct GeminiTTSResponse: Decodable {
        var candidates: [Candidate]?

        struct Candidate: Decodable {
            var content: Content?
            var finishReason: String?

            struct Content: Decodable {
                var parts: [Part]?

                struct Part: Decodable {
                    var inlineData: InlineData?
                    var text: String?

                    struct InlineData: Decodable {
                        var data: String
                        var mimeType: String?

                        enum CodingKeys: String, CodingKey {
                            case data
                            case mimeType = "mime_type"
                            case mimeTypeCamel = "mimeType"
                        }

                        init(from decoder: Decoder) throws {
                            let container = try decoder.container(keyedBy: CodingKeys.self)
                            data = try container.decode(String.self, forKey: .data)
                            mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
                                ?? container.decodeIfPresent(String.self, forKey: .mimeTypeCamel)
                        }
                    }

                    enum CodingKeys: String, CodingKey {
                        case inlineData = "inline_data"
                        case inlineDataCamel = "inlineData"
                        case text
                    }

                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        inlineData = try container.decodeIfPresent(InlineData.self, forKey: .inlineData)
                            ?? container.decodeIfPresent(InlineData.self, forKey: .inlineDataCamel)
                        text = try container.decodeIfPresent(String.self, forKey: .text)
                    }
                }
            }

            enum CodingKeys: String, CodingKey {
                case content
                case finishReason = "finish_reason"
                case finishReasonCamel = "finishReason"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                content = try container.decodeIfPresent(Content.self, forKey: .content)
                finishReason = try container.decodeIfPresent(String.self, forKey: .finishReason)
                    ?? container.decodeIfPresent(String.self, forKey: .finishReasonCamel)
            }
        }
    }

    private func geminiPlayableAudioData(from responseData: Data) throws -> Data {
        let response = try JSONDecoder().decode(GeminiTTSResponse.self, from: responseData)
        let firstCandidate = response.candidates?.first
        if let finishReason = firstCandidate?.finishReason, firstCandidate?.content == nil {
            throw NSError(domain: "JapaneseLearningCard.GeminiTTS", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Gemini 未產生音訊 (finish_reason: \(finishReason))，請重試"
            ])
        }
        guard let inlineData = firstCandidate?.content?.parts?.first?.inlineData,
              let audioData = Data(base64Encoded: inlineData.data) else {
            throw NSError(domain: "JapaneseLearningCard.GeminiTTS", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Gemini 回應沒有可解析的 inline_data"
            ])
        }

        if audioData.starts(with: Data("RIFF".utf8)) {
            return audioData
        }
        return wavData(fromPCM: audioData, sampleRate: 24_000, channels: 1, bitsPerSample: 16)
    }

    private func wavData(fromPCM pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        var data = Data()

        func appendString(_ value: String) {
            data.append(contentsOf: value.utf8)
        }

        func appendUInt16LE(_ value: UInt16) {
            var littleEndian = value.littleEndian
            data.append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
        }

        func appendUInt32LE(_ value: UInt32) {
            var littleEndian = value.littleEndian
            data.append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
        }

        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)

        appendString("RIFF")
        appendUInt32LE(36 + dataSize)
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32LE(16)
        appendUInt16LE(1)
        appendUInt16LE(channels)
        appendUInt32LE(sampleRate)
        appendUInt32LE(byteRate)
        appendUInt16LE(blockAlign)
        appendUInt16LE(bitsPerSample)
        appendString("data")
        appendUInt32LE(dataSize)
        data.append(pcmData)
        return data
    }

    private func remoteSpeechInput(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        if let shortPattern = pronounceableShortPattern(trimmed) {
            return "読音は、\(shortPattern)。"
        }
        return "　\(trimmed)。"
    }

    private func pronounceableShortPattern(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: CharacterSet(charactersIn: "〜～~").union(.whitespacesAndNewlines))
        guard !normalized.isEmpty, normalized.count <= 6 else { return nil }
        guard normalized.range(of: #"[一-龯ぁ-んァ-ヶ]"#, options: .regularExpression) != nil else { return nil }
        let sentenceMarkers = CharacterSet(charactersIn: "。、！？!?，,；;：「」『』（）()[]\n")
        guard normalized.rangeOfCharacter(from: sentenceMarkers) == nil else { return nil }
        return normalized
    }

    private func ttsCacheURL(settings: AppSettings, text: String, speechInput: String, fileExtension: String) -> URL {
        let key = [
            settings.openAITtsProviderPreset.rawValue,
            settings.openAITtsBaseURL,
            settings.openAITtsModel,
            settings.openAITtsVoice,
            text.trimmingCharacters(in: .whitespacesAndNewlines),
            speechInput
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(key.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(hash).\(fileExtension)")
    }

    private func playCachedAudioIfAvailable(
        _ url: URL,
        providerName: String,
        voice: String,
        onStatus: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            let data = try Data(contentsOf: url)
            try playAudioData(data, providerName: providerName, voice: voice, onStatus: onStatus, source: "快取")
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            print("Failed to play cached TTS audio: \(error.localizedDescription)")
            return false
        }
    }

    private func storeAudioData(_ data: Data, at url: URL) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func playAudioData(
        _ data: Data,
        providerName: String,
        voice: String,
        onStatus: @escaping @MainActor (String) -> Void,
        source: String = "AI"
    ) throws {
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        self.audioPlayer = player
        onStatus("正在播放 \(providerName) TTS 語音 (\(voice)，\(source))")
        player.play()
    }

    private func handleTTSFailure(
        _ message: String,
        text: String,
        fallbackToNativeOnFailure: Bool,
        onStatus: @escaping @MainActor (String) -> Void
    ) {
        if fallbackToNativeOnFailure {
            onStatus("\(message)，已 Fallback 至系統原生語音")
            speakNative(text, language: "ja-JP")
        } else {
            onStatus("TTS 測試失敗：\(message)")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(UpdateChecker.autoCheckDefaultsKey) private var autoCheckUpdates = false
    @AppStorage("japaneseDisplayScale") private var japaneseDisplayScale = 1.18
    @FocusState private var isSourceURLFocused: Bool
    @FocusState private var focusedSettingsField: SettingsField?
    @State private var profileNameDraft = ""
    @State private var baseURLDraft = ""
    @State private var ttsProfileNameDraft = ""
    /// 既有來源網址的編輯緩衝區（key 為 Source.id），送出前不寫回資料。
    @State private var editingSourceURLs: [UUID: String] = [:]
    /// 設定分類：用上方分段直接切換，不再藏在「系統設定」子頁裡。
    @State private var section: SettingsSection = SettingsSection.initial

    enum SettingsSection: String, CaseIterable, Identifiable {
        case sources = "來源"
        case display = "顯示"
        case ai = "AI"
        case data = "資料"
        case system = "系統"
        var id: String { rawValue }

        /// 來源與 AI provider 只服務內容產生，iOS 版不顯示（產生內容留在 macOS）。
        static var visibleCases: [SettingsSection] {
            #if os(macOS)
            allCases
            #else
            [.display, .ai, .data, .system]
            #endif
        }

        static var initial: SettingsSection {
            #if os(macOS)
            .sources
            #else
            .display
            #endif
        }
    }

    private enum SettingsField: Hashable {
        case profileName
        case baseURL
        case apiKey
        case ttsProfileName
        case existingSource(UUID)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(SettingsSection.visibleCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !viewModel.statusMessage.isEmpty {
                        Label(viewModel.statusMessage, systemImage: viewModel.isValidatingProvider || viewModel.isRefreshing ? "hourglass" : "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    switch section {
                    case .sources: sourcesSection
                    case .display: displaySection
                    case .ai: aiSection
                    case .data: dataSection
                    case .system: systemSection
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            syncAIDraftsFromSettings()
        }
        .onChange(of: section) { _, _ in
            syncAIDraftsFromSettings()
        }
        .onChange(of: viewModel.snapshot.settings.providerConfig.baseURL) { _, _ in
            syncAIDraftsFromSettings()
        }
        .onChange(of: viewModel.snapshot.settings.activeProviderProfileId) { _, _ in
            syncAIDraftsFromSettings()
        }
        .onChange(of: viewModel.snapshot.settings.activeTTSProviderProfileId) { _, _ in
            syncAIDraftsFromSettings()
        }
        .onChange(of: focusedSettingsField) { oldValue, newValue in
            if oldValue == .profileName, newValue != .profileName {
                commitProfileNameDraft()
            }
            if oldValue == .baseURL, newValue != .baseURL {
                commitBaseURLDraft()
            }
            if oldValue == .ttsProfileName, newValue != .ttsProfileName {
                commitTTSProfileNameDraft()
            }
            if case .existingSource(let id) = oldValue, newValue != oldValue,
               let source = viewModel.snapshot.sources.first(where: { $0.id == id }) {
                commitSourceURL(source)
            }
        }
        .background(Color.designCanvas)
    }

    @ViewBuilder
    private var sourcesSection: some View {
        settingsBox("內容來源") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("卡片擷取指示")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: stringBinding(
                            get: { $0.defaultExtractionPrompt },
                            set: { $0.defaultExtractionPrompt = $1 }
                        ))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 96)
                        .background(Color.designSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.designBorder.opacity(0.7), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("新增網址")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("", text: $viewModel.newSourceURL)
                                .textFieldStyle(.roundedBorder)
                                .focused($isSourceURLFocused)
                                .frame(maxWidth: .infinity)
                                .onSubmit {
                                    if canAddSource {
                                        addSourceAndRefocus()
                                    }
                                }
                            if viewModel.validatingSourceIDs.contains(AppViewModel.newSourceDiagnosticID) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button {
                                    viewModel.validateNewSourceURL()
                                } label: {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }
                                .disabled(!canAddSource)
                                .help("驗證連線並測試 AI 解析;成功會把卡片加入資料庫(會消耗 API token)")
                            }
                            Button {
                                addSourceAndRefocus()
                            } label: {
                                Image(systemName: "plus")
                            }
                            .disabled(!canAddSource)
                            .help("新增網址")
                        }
                        if let diagnostic = viewModel.sourceDiagnostics[AppViewModel.newSourceDiagnosticID] {
                            diagnosticView(diagnostic)
                        }
                    }

                    ForEach(webSources) { source in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: toggleBinding(source))
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 3) {
                                TextField("", text: sourceURLBinding(source))
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedSettingsField, equals: .existingSource(source.id))
                                    .onSubmit { commitSourceURL(source) }
                                if let diagnostic = viewModel.sourceDiagnostics[source.id] {
                                    diagnosticView(diagnostic)
                                } else if let error = source.lastError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .lineLimit(3)
                                        .textSelection(.enabled)
                                } else if let date = source.lastFetchedAt {
                                    Text("上次更新：\(date.formatted())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                } else {
                                    Text("尚未更新")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if viewModel.validatingSourceIDs.contains(source.id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button {
                                    viewModel.validateSource(source)
                                } label: {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }
                                .buttonStyle(.borderless)
                                .help("驗證連線並測試 AI 解析;成功會把卡片加入資料庫(會消耗 API token)")
                            }
                            Button {
                                viewModel.removeSource(source)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("移除來源")
                        }
                        .padding(.vertical, 3)
                    }
                }

                HStack {
                    Button {
                        viewModel.refreshNow()
                    } label: {
                        Label(viewModel.isRefreshing ? "更新中..." : "手動更新", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isRefreshing)
                }
    }

    @ViewBuilder
    private var displaySection: some View {
                settingsBox("顯示") {
                    VStack(alignment: .leading, spacing: 7) {
                        Picker("日文顯示大小", selection: $japaneseDisplayScale) {
                            Text("標準").tag(1.0)
                            Text("大字").tag(1.18)
                            Text("特大").tag(1.35)
                        }
                        .pickerStyle(.segmented)

                        Text("會同步放大單字、片假名、讀音、例句與考題文字。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Stepper("顯示頻率：\(viewModel.snapshot.settings.displayIntervalMinutes) 分鐘", value: binding(\.displayIntervalMinutes), in: 1...1440)
                    Stepper("停留秒數：\(viewModel.snapshot.settings.visibleDurationSeconds) 秒", value: binding(\.visibleDurationSeconds), in: 3...300)
                    Stepper("快速複習時間：\(viewModel.snapshot.settings.quickReviewDurationMinutes) 分鐘", value: binding(\.quickReviewDurationMinutes), in: 1...30)
                    Stepper("快速換卡：\(viewModel.snapshot.settings.quickReviewCardIntervalSeconds) 秒", value: binding(\.quickReviewCardIntervalSeconds), in: 5...120)
                    #if os(macOS)
                    Stepper("爬文頻率：\(viewModel.snapshot.settings.crawlIntervalHours) 小時", value: binding(\.crawlIntervalHours), in: 1...168)
                    #endif
                }
    }

    @ViewBuilder
    private var aiSection: some View {
                #if os(macOS)
                settingsBox("AI Provider Profiles") {
                    Text("點一下列表即可切換預設 profile；AI 造卡、出題、驗證都會使用打勾的那一組。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        ForEach(viewModel.snapshot.settings.providerProfiles) { profile in
                            providerProfileRow(profile)
                            if profile.id != viewModel.snapshot.settings.providerProfiles.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(Color.platformTextBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.platformSeparator, lineWidth: 1)
                    )

                    HStack(spacing: 8) {
                        Button {
                            commitPendingProviderProfileDrafts()
                            viewModel.createProviderProfile()
                            syncAIDraftsFromSettings()
                        } label: {
                            Label("新增", systemImage: "plus")
                        }
                        Button {
                            commitPendingProviderProfileDrafts()
                            viewModel.duplicateActiveProviderProfile()
                            syncAIDraftsFromSettings()
                        } label: {
                            Label("複製", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            commitPendingProviderProfileDrafts()
                            viewModel.deleteActiveProviderProfile()
                            syncAIDraftsFromSettings()
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                        .disabled(viewModel.snapshot.settings.providerProfiles.count <= 1)
                        Button(role: .destructive) {
                            viewModel.clearActiveProviderProfileKey()
                        } label: {
                            Label("清空 Key", systemImage: "key.slash")
                        }
                    }
                    .buttonStyle(.borderless)
                }

                if let profile = viewModel.activeProviderProfile {
                    settingsBox("Profile 設定") {
                        providerProfileStatus(profile)

                        labeledRow("Profile name") {
                            TextField("", text: $profileNameDraft)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedSettingsField, equals: .profileName)
                                .onSubmit { commitProfileNameDraft() }
                        }

                        labeledRow("Provider") {
                            Picker("", selection: providerPresetBinding()) {
                                ForEach(ProviderPreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .labelsHidden()
                        }

                        labeledRow("Base URL") {
                            TextField("", text: $baseURLDraft)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedSettingsField, equals: .baseURL)
                            .onSubmit { commitBaseURLDraft() }
                        }

                        labeledRow("主要模型 (生卡片/文章)") {
                            Picker("", selection: activeProviderModelBinding()) {
                                ForEach(viewModel.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                        }

                        labeledRow("輕量模型 (標音/測驗)") {
                            Picker("", selection: activeProviderFastModelBinding()) {
                                ForEach(viewModel.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                        }

                        labeledRow("JSON 格式輸出") {
                            Picker("", selection: structuredOutputBinding()) {
                                ForEach(StructuredOutputMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .help("要求模型只輸出 JSON (response_format)。OpenAI 等支援的 provider 建議開啟；不支援的 endpoint 請關閉，否則可能回 400。關閉時仍會自動清洗 <think>、markdown 等雜訊。")
                        }

                        labeledRow("Keychain ID") {
                            HStack(spacing: 6) {
                                Text(profile.keychainReference)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                CopyButton(text: profile.keychainReference)
                            }
                            .help("自動產生，永遠等於 Profile ID，無法手動修改。")
                        }

                        labeledRow("API key") {
                            SecureField(
                                profile.config.preset.requiresAPIKey
                                    ? "貼上新 key；留空會沿用 Keychain 既有 key 驗證"
                                    : "此 provider 不需要 API key，留空即可",
                                text: $viewModel.apiKeyInput
                            )
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedSettingsField, equals: .apiKey)
                        }

                        Button {
                            viewModel.validateAndSaveProvider()
                        } label: {
                            Label(viewModel.isValidatingProvider ? "驗證中..." : "驗證並儲存", systemImage: "checkmark.seal")
                        }
                        .disabled(viewModel.isValidatingProvider)
                        .help("驗證成功才會把新的 API key 存入 Keychain；欄位留空時會用既有 key 驗證。")
                    }
                }
                #endif

                settingsBox("TTS 語音合成 (BYOK)") {
                    Toggle("啟用 TTS 語音合成", isOn: binding(\.openAITtsEnabled))
                        .help("開啟後，日文發音將會透過所設定的 TTS API 產生；若關閉、無 API Key 或網路異常，會自動 fallback 使用系統內建的日文語音。")

                    if viewModel.snapshot.settings.openAITtsEnabled && !viewModel.isOpenAITtsKeySaved {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("注意：尚未儲存 API Key，將自動 Fallback 使用系統原生語音發音。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if viewModel.snapshot.settings.openAITtsEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("每個 profile 各自持有一把 API key,切換 profile 不會互相覆蓋。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            VStack(spacing: 0) {
                                ForEach(viewModel.snapshot.settings.ttsProviderProfiles) { profile in
                                    ttsProviderProfileRow(profile)
                                    if profile.id != viewModel.snapshot.settings.ttsProviderProfiles.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .background(Color.platformTextBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.platformSeparator, lineWidth: 1)
                            )

                            HStack(spacing: 8) {
                                Button {
                                    commitTTSProfileNameDraft()
                                    viewModel.createTTSProviderProfile()
                                } label: {
                                    Label("新增", systemImage: "plus")
                                }
                                Button(role: .destructive) {
                                    commitTTSProfileNameDraft()
                                    viewModel.deleteActiveTTSProviderProfile()
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                                .disabled(viewModel.snapshot.settings.ttsProviderProfiles.count <= 1)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.bottom, 4)

                        labeledRow("Profile 名稱") {
                            TextField("", text: $ttsProfileNameDraft)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedSettingsField, equals: .ttsProfileName)
                                .onSubmit { commitTTSProfileNameDraft() }
                        }

                        labeledRow("服務商") {
                            Picker("", selection: ttsProviderPresetBinding()) {
                                ForEach(TTSProviderPreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .labelsHidden()
                        }

                        labeledRow("API Base URL") {
                            TextField("", text: ttsBaseURLBinding())
                                .textFieldStyle(.roundedBorder)
                                .disabled(viewModel.snapshot.settings.openAITtsProviderPreset != .custom)
                        }
                        .help("自定義模式下可手動修改。")

                        labeledRow("模型 (Model)") {
                            if viewModel.snapshot.settings.openAITtsProviderPreset == .openAI {
                                Picker("", selection: ttsModelBinding()) {
                                    Text("gpt-4o-mini-tts").tag("gpt-4o-mini-tts")
                                    Text("tts-1").tag("tts-1")
                                    Text("tts-1-hd").tag("tts-1-hd")
                                }
                                .labelsHidden()
                            } else if viewModel.snapshot.settings.openAITtsProviderPreset == .gemini {
                                Picker("", selection: ttsModelBinding()) {
                                    ForEach(GeminiTTSOptions.models, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .labelsHidden()
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        TextField(
                                            viewModel.snapshot.settings.openAITtsProviderPreset == .elevenLabs
                                                ? "輸入 ElevenLabs model_id，例如 eleven_multilingual_v2"
                                                : "輸入模型標識，例如 tts-1",
                                            text: ttsModelBinding()
                                        )
                                            .textFieldStyle(.roundedBorder)
                                        
                                        Button {
                                            viewModel.fetchAvailableTtsModels()
                                        } label: {
                                            if viewModel.isFetchingTtsModels {
                                                ProgressView()
                                                    .controlSize(.small)
                                            } else {
                                                Text("獲取清單")
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(viewModel.isFetchingTtsModels || !viewModel.isOpenAITtsKeySaved)
                                    }

                                    if !viewModel.availableTtsModels.isEmpty {
                                        Picker("選取已獲取的模型", selection: ttsModelBinding()) {
                                            ForEach(viewModel.availableTtsModels, id: \.self) { model in
                                                Text(model).tag(model)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                    }
                                }
                            }
                        }

                        if !viewModel.ttsStatusMessage.isEmpty {
                            localStatusRow(viewModel.ttsStatusMessage)
                        }

                        labeledRow("語音 (Voice)") {
                            if viewModel.snapshot.settings.openAITtsProviderPreset == .elevenLabs {
                                VStack(alignment: .leading, spacing: 6) {
                                    TextField("輸入 ElevenLabs voice_id", text: ttsVoiceBinding())
                                        .textFieldStyle(.roundedBorder)

                                    if !viewModel.availableTtsVoices.isEmpty {
                                        Picker("選取已獲取的 voice", selection: ttsVoiceBinding()) {
                                            ForEach(viewModel.availableTtsVoices) { voice in
                                                Text(voice.displayName).tag(voice.id)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                    }
                                }
                            } else if viewModel.snapshot.settings.openAITtsProviderPreset == .gemini {
                                Picker("", selection: ttsVoiceBinding()) {
                                    ForEach(GeminiTTSOptions.voices, id: \.self) { voice in
                                        Text(voice).tag(voice)
                                    }
                                }
                                .labelsHidden()
                            } else {
                                Picker("", selection: ttsVoiceBinding()) {
                                    Text("alloy").tag("alloy")
                                    Text("echo").tag("echo")
                                    Text("fable").tag("fable")
                                    Text("onyx").tag("onyx")
                                    Text("nova").tag("nova")
                                    Text("shimmer").tag("shimmer")
                                }
                                .labelsHidden()
                            }
                        }
                        .help("OpenAI/Gemini 使用 voice 名稱；ElevenLabs 使用 voice_id。")

                        labeledRow("測試") {
                            Button {
                                SpeechSynthesizerManager.shared.testConfiguredTTS(settings: viewModel.snapshot.settings) { message in
                                    viewModel.statusMessage = message
                                    viewModel.ttsStatusMessage = message
                                }
                            } label: {
                                Label("測試發音", systemImage: "speaker.wave.2")
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                !viewModel.isOpenAITtsKeySaved ||
                                viewModel.snapshot.settings.openAITtsModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                viewModel.snapshot.settings.openAITtsVoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                            .help("使用目前選擇的 TTS 模型與語音實際呼叫 API 並播放測試音訊。")
                        }

                        labeledRow("API Key") {
                            #if os(macOS)
                            HStack(spacing: 8) {
                                SecureField(
                                    viewModel.isOpenAITtsKeySaved
                                        ? "已儲存 API Key (輸入新 key 可覆蓋)"
                                        : "請貼上 API key",
                                    text: $viewModel.openAITtsKeyInput
                                )
                                .textFieldStyle(.roundedBorder)

                                Button {
                                    viewModel.saveOpenAITtsKey(viewModel.openAITtsKeyInput)
                                } label: {
                                    Text("儲存 Key")
                                }
                                .disabled(viewModel.openAITtsKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                if viewModel.isOpenAITtsKeySaved {
                                    Button(role: .destructive) {
                                        viewModel.clearOpenAITtsKey()
                                    } label: {
                                        Text("清除 Key")
                                    }
                                }
                            }
                            #else
                            VStack(alignment: .leading, spacing: 6) {
                                SecureField(
                                    viewModel.isOpenAITtsKeySaved
                                        ? "已儲存 API Key (輸入新 key 可覆蓋)"
                                        : "請貼上 API key",
                                    text: $viewModel.openAITtsKeyInput
                                )
                                .textFieldStyle(.roundedBorder)

                                HStack(spacing: 8) {
                                    Button {
                                        viewModel.saveOpenAITtsKey(viewModel.openAITtsKeyInput)
                                    } label: {
                                        Text("儲存 Key")
                                    }
                                    .disabled(viewModel.openAITtsKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    if viewModel.isOpenAITtsKeySaved {
                                        Button(role: .destructive) {
                                            viewModel.clearOpenAITtsKey()
                                        } label: {
                                            Text("清除 Key")
                                        }
                                    }
                                }
                            }
                            #endif
                        }
                    }
                }
    }

    /// Profile 清單的一列:點一下整列就把該 profile 設為預設(active)。
    private func providerProfileRow(_ profile: ProviderProfile) -> some View {
        let isActive = profile.id == viewModel.snapshot.settings.activeProviderProfileId
        return Button {
            guard !isActive else { return }
            commitPendingProviderProfileDrafts()
            viewModel.selectProviderProfile(profile.id)
            syncAIDraftsFromSettings()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.body.weight(isActive ? .semibold : .regular))
                            .lineLimit(1)
                        if isActive {
                            Text("預設")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(profile.config.preset.displayName) · \(profile.config.model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: providerVerificationIcon(profile.lastVerificationStatus))
                    .foregroundStyle(providerVerificationColor(profile.lastVerificationStatus))
                    .help(providerVerificationText(profile))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .accessibilityLabel("\(profile.name)\(isActive ? "，目前為預設" : "")")
        .accessibilityHint("點一下設為預設 profile")
    }

    private func ttsProviderProfileRow(_ profile: TTSProviderProfile) -> some View {
        let isActive = profile.id == viewModel.snapshot.settings.activeTTSProviderProfileId
        return Button {
            guard !isActive else { return }
            commitTTSProfileNameDraft()
            viewModel.selectTTSProviderProfile(profile.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.body.weight(isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Text("\(profile.config.preset.displayName) · \(profile.config.model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .accessibilityLabel("\(profile.name)\(isActive ? "，目前使用中" : "")")
        .accessibilityHint("點一下切換為目前使用的 TTS profile")
    }

    @ViewBuilder
    private var dataSection: some View {
                settingsBox("資料儲存模式") {
                    storageModeRow()
                    storageLocationRow()
                    storageHealthRow()
                    HStack {
                        Button {
                            viewModel.switchStorageMode(.localOnly)
                        } label: {
                            Label("改存本機", systemImage: "internaldrive")
                        }
                        .disabled(viewModel.isMigratingStorage || viewModel.storageSettings.mode == .localOnly)

                        Button {
                            viewModel.chooseICloudDriveFolderAndMigrate()
                        } label: {
                            Label("選 iCloud Drive 資料夾", systemImage: "folder.badge.gearshape")
                        }
                        .disabled(viewModel.isMigratingStorage)

                        Button {
                            viewModel.switchStorageMode(.cloudKit)
                        } label: {
                            Label("使用 CloudKit", systemImage: "icloud")
                        }
                        .disabled(viewModel.isMigratingStorage || viewModel.storageSettings.mode == .cloudKit)
                    }
                    .buttonStyle(.bordered)

                    if viewModel.storageSettings.mode == .iCloudDriveFolder,
                       let path = viewModel.storageSettings.iCloudDriveFolderPath,
                       !UserDataStoreFactory.appearsInsideICloudDrive(URL(fileURLWithPath: path, isDirectory: true)) {
                        Label("目前資料夾看起來不在 iCloud Drive 內，macOS 不會自動同步這個位置。", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                #if os(macOS)
                settingsBox("批次重生既有卡片") {
                    Text("使用已儲存的文章內容與目前 prompt 重新產生結構化欄位，只更新缺少新版欄位的舊卡，並保留既有複習狀態。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button {
                            viewModel.backfillExistingCards()
                        } label: {
                            Label(viewModel.isBackfillingCards ? "重生中..." : "批次重生舊卡", systemImage: "wand.and.stars")
                        }
                        .disabled(viewModel.isBackfillingCards)
                        Spacer()
                        Text("待補齊 \(viewModel.snapshot.cards.filter(\.needsStructuredBackfill).count) 張")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif

                settingsBox("資料庫") {
                    Button {
                        viewModel.exportDatabase()
                    } label: {
                        Label("匯出 SQLite DB", systemImage: "square.and.arrow.down")
                    }
                    #if !os(macOS)
                    .sheet(isPresented: Binding(
                        get: { viewModel.exportedDatabaseURL != nil },
                        set: { if !$0 { viewModel.exportedDatabaseURL = nil } }
                    )) {
                        if let url = viewModel.exportedDatabaseURL {
                            ShareLink(item: url, message: Text("Japanese Learning Card SQLite DB"))
                        }
                    }
                    #endif
                }

                settingsBox("iCloud 同步") {
                    icloudStatusRow()
                    icloudFingerprintRow()
                    icloudLastSyncRow()
                    icloudConflictRow()
                    if let err = viewModel.iCloudLastErrorMessage {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    if !viewModel.iCloudConflicts.isEmpty {
                        conflictListSection()
                    }
                    HStack {
                        Button {
                            Task { await viewModel.performPull() }
                        } label: {
                            Label(
                                viewModel.iCloudIsSyncing ? "同步中..." : "立即同步 (Pull)",
                                systemImage: "arrow.clockwise.icloud"
                            )
                        }
                        .disabled(viewModel.iCloudIsSyncing || !viewModel.isICloudSyncAvailable)
                        .help(viewModel.isICloudSyncAvailable
                            ? "從 iCloud 拉最新一份回來, 跟本機做 3-way merge"
                            : "目前建置或儲存模式未啟用 CloudKit 同步")
                        Spacer()
                    }
                }
    }

    @ViewBuilder
    private var systemSection: some View {
                // AI Log 只記錄內容產生的請求，iOS 版不做產生所以不顯示。
                #if os(macOS)
                settingsBox("AI Log") {
                    Button {
                        viewModel.openAIRequestLog()
                    } label: {
                        Label("在 Finder 顯示 AI Log", systemImage: "folder")
                    }
                    Text("完整紀錄：\(AIRequestLogStore.logFileURL.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("最新一次流程：\(AIRequestLogStore.latestLogFileURL.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                settingsBox("更新") {
                    if UpdateChecker.isLocalBuild {
                        HStack {
                            Label("本地建置版本，已停用自動更新", systemImage: "hammer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("目前版本 \(UpdateChecker.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } else {
                        Toggle("自動檢查更新", isOn: $autoCheckUpdates)
                            .help("背景定期檢查新版本，有更新時會提示你下載並安裝。")
                            .onChange(of: autoCheckUpdates) { _, newValue in
                                viewModel.setAutomaticUpdateChecks?(newValue)
                            }
                        HStack {
                            Button {
                                viewModel.requestCheckForUpdates?()
                            } label: {
                                Label("立即檢查更新", systemImage: "arrow.down.circle")
                            }
                            Spacer()
                            Text("目前版本 \(UpdateChecker.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Button(role: .destructive) {
                    viewModel.quitApp()
                } label: {
                    Label("結束程式", systemImage: "power")
                }
                #else
                settingsBox("關於") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(UpdateChecker.currentVersion)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif
    }

    private var canAddSource: Bool {
        !viewModel.newSourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var webSources: [Source] {
        viewModel.snapshot.sources.filter { !AISource.isSentinelSource($0) }
    }

    private func addSourceAndRefocus() {
        viewModel.addSource()
        isSourceURLFocused = true
    }

    private func sourceURLBinding(_ source: Source) -> Binding<String> {
        Binding(
            get: { editingSourceURLs[source.id] ?? source.url.absoluteString },
            set: { editingSourceURLs[source.id] = $0 }
        )
    }

    private func commitSourceURL(_ source: Source) {
        guard let edited = editingSourceURLs[source.id] else { return }
        if viewModel.updateSourceURL(source, to: edited) {
            editingSourceURLs[source.id] = nil
        }
    }

    /// 在切換 active profile(新增/複製/刪除/選擇)之前呼叫,把目前 focus 中欄位的
    /// 草稿值強制寫回「目前這個」profile,並釋放 focus。
    ///
    /// 沒有這一步的話,`syncAIDraftsFromSettings()` 會因為欄位仍在 focus 中而略過
    /// 同步,草稿值(例如 baseURLDraft)就會停留在切換前的內容;等到 focus 離開時
    /// 才觸發的 commit,會把這份「屬於舊 profile」的草稿寫進「切換後的新 active
    /// profile」,悄悄把它的 baseURL／name 改壞。
    private func commitPendingProviderProfileDrafts() {
        commitProfileNameDraft()
        commitBaseURLDraft()
        commitTTSProfileNameDraft()
        focusedSettingsField = nil
    }

    private func syncAIDraftsFromSettings() {
        if focusedSettingsField != .profileName, focusedSettingsField != .baseURL,
           let profile = viewModel.activeProviderProfile {
            profileNameDraft = profile.name
            baseURLDraft = profile.config.baseURL.absoluteString
        }
        if focusedSettingsField != .ttsProfileName,
           let ttsProfile = viewModel.activeTTSProviderProfile {
            ttsProfileNameDraft = ttsProfile.name
        }
    }

    private func commitTTSProfileNameDraft() {
        let trimmed = ttsProfileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            ttsProfileNameDraft = viewModel.activeTTSProviderProfile?.name ?? ""
            return
        }
        guard trimmed != viewModel.activeTTSProviderProfile?.name else { return }
        viewModel.updateActiveTTSProviderProfileName(trimmed)
    }

    private func commitProfileNameDraft() {
        let trimmed = profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            profileNameDraft = viewModel.activeProviderProfile?.name ?? ""
            return
        }
        guard trimmed != viewModel.activeProviderProfile?.name else { return }
        viewModel.updateActiveProviderProfileName(trimmed)
    }

    private func commitBaseURLDraft() {
        let trimmed = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            baseURLDraft = viewModel.activeProviderProfile?.config.baseURL.absoluteString ?? ""
            return
        }
        guard let url = URL(string: trimmed), url.scheme != nil else {
            viewModel.statusMessage = "Base URL 格式不正確"
            baseURLDraft = viewModel.activeProviderProfile?.config.baseURL.absoluteString ?? ""
            return
        }
        guard url != viewModel.activeProviderProfile?.config.baseURL else { return }
        viewModel.updateActiveProviderProfileConfig { config in
            config.baseURL = url
        }
    }

    @ViewBuilder
    private func providerProfileStatus(_ profile: ProviderProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(providerVerificationText(profile), systemImage: providerVerificationIcon(profile.lastVerificationStatus))
                .font(.caption)
                .foregroundStyle(providerVerificationColor(profile.lastVerificationStatus))
            Label(viewModel.activeProviderKeyStatus.displayText, systemImage: "key")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = profile.lastVerificationMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }

    private func providerVerificationText(_ profile: ProviderProfile) -> String {
        let status = switch profile.lastVerificationStatus {
        case .unverified:
            "尚未驗證"
        case .success:
            "驗證成功"
        case .failed:
            "驗證失敗"
        case .missingKey:
            "缺少 API key"
        }
        var details: [String] = []
        if let count = profile.verifiedModelCount {
            details.append("\(count) models")
        }
        if let date = profile.lastVerifiedAt {
            details.append(date.formatted())
        }
        return details.isEmpty ? status : "\(status) · \(details.joined(separator: " · "))"
    }

    private func providerVerificationIcon(_ status: ProviderVerificationStatus) -> String {
        switch status {
        case .unverified:
            "questionmark.circle"
        case .success:
            "checkmark.seal"
        case .failed:
            "xmark.octagon"
        case .missingKey:
            "key.slash"
        }
    }

    private func providerVerificationColor(_ status: ProviderVerificationStatus) -> Color {
        switch status {
        case .unverified:
            .secondary
        case .success:
            .green
        case .failed, .missingKey:
            .red
        }
    }

    @ViewBuilder
    private func diagnosticView(_ diagnostic: SourceDiagnostic) -> some View {
        let color: Color = diagnostic.outcome == .ok
            ? .green
            : (diagnostic.isReachable ? .orange : .red)
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(diagnostic.summary)
                    .font(.caption)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: diagnostic.isReachable
                    ? (diagnostic.outcome == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    : "xmark.octagon.fill")
                    .foregroundStyle(color)
            }
            if let aiSummary = diagnostic.aiParseSummary {
                let style: (color: Color, icon: String) = {
                    if diagnostic.aiParseError != nil { return (.red, "xmark.octagon.fill") }
                    if diagnostic.aiParseDuplicate { return (.secondary, "doc.on.doc") }
                    if (diagnostic.aiParsedCardCount ?? 0) > 0 { return (.green, "sparkles") }
                    return (.orange, "exclamationmark.triangle.fill")
                }()
                Label {
                    Text(aiSummary)
                        .font(.caption)
                        .foregroundStyle(style.color)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: style.icon)
                        .foregroundStyle(style.color)
                }
            }
            if let suggestion = diagnostic.suggestion {
                Text(suggestion)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = diagnostic.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .textSelection(.enabled)
    }

    private func settingsBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline.weight(.semibold))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.designSurface, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.designBorder.opacity(0.7), lineWidth: 1)
        }
    }

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func localStatusRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: viewModel.isFetchingTtsModels ? "hourglass" : "info.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding {
            viewModel.snapshot.settings[keyPath: keyPath]
        } set: { value in
            var settings = viewModel.snapshot.settings
            settings[keyPath: keyPath] = value
            viewModel.updateSettings(settings)
        }
    }

    // MARK: - iCloud status rows

    @ViewBuilder
    private func icloudStatusRow() -> some View {
        let (icon, color, text) = icloudStatusDisplay()
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.callout)
            Spacer()
        }
    }

    private func icloudStatusDisplay() -> (String, Color, String) {
        switch viewModel.iCloudStatus {
        case .available:
            return ("checkmark.icloud.fill", .green, "iCloud 已連線")
        case .noAccount:
            return ("icloud.slash", .orange, "未登入 iCloud (系統設定 → Apple ID)")
        case .restricted:
            return ("exclamationmark.icloud", .red, "iCloud 帳號被限制")
        case .unknown:
            return ("questionmark.circle", .secondary, CloudKitAccountChecker.displayMessage(for: viewModel.iCloudStatus))
        case .unexpected:
            return ("questionmark.circle", .secondary, CloudKitAccountChecker.displayMessage(for: viewModel.iCloudStatus))
        }
    }

    @ViewBuilder
    private func icloudFingerprintRow() -> some View {
        if let fp = viewModel.iCloudFingerprint {
            labeledRow("帳號") {
                Text("iCloud _\(fp)")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func icloudLastSyncRow() -> some View {
        labeledRow("上次同步") {
            VStack(alignment: .leading, spacing: 2) {
                if let push = viewModel.iCloudLastPushAt {
                    Text("Push: \(Self.relativeTimeString(from: push))")
                } else {
                    Text("Push: 尚未執行")
                        .foregroundStyle(.secondary)
                }
                if let pull = viewModel.iCloudLastPullAt {
                    Text("Pull: \(Self.relativeTimeString(from: pull))")
                } else {
                    Text("Pull: 尚未執行")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func icloudConflictRow() -> some View {
        if viewModel.iCloudConflictCount > 0 {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("有 \(viewModel.iCloudConflictCount) 筆 3-way merge 衝突, 已用 last-writer-wins 自動解決")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else {
            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                Text("無未解決衝突")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "zh_TW")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func storageModeRow() -> some View {
        labeledRow("目前模式") {
            HStack {
                Image(systemName: storageModeIcon(viewModel.storageSettings.mode))
                Text(viewModel.storageSettings.mode.displayName)
                if viewModel.isMigratingStorage {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func storageLocationRow() -> some View {
        labeledRow("資料位置") {
            Text(storageLocationText())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func storageHealthRow() -> some View {
        if let health = viewModel.storageHealth {
            labeledRow("狀態") {
                Label(health.message, systemImage: health.isWritable ? "checkmark.circle" : "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(health.isWritable ? .green : .red)
            }
        }
    }

    private func storageModeIcon(_ mode: StorageMode) -> String {
        switch mode {
        case .localOnly: return "internaldrive"
        case .iCloudDriveFolder: return "folder"
        case .cloudKit: return "icloud"
        }
    }

    private func storageLocationText() -> String {
        switch viewModel.storageSettings.mode {
        case .localOnly:
            return viewModel.storageSettings.localDataPath ?? UserDataStoreFactory.defaultLocalFolder().path
        case .iCloudDriveFolder:
            return viewModel.storageSettings.iCloudDriveFolderPath ?? UserDataStoreFactory.defaultICloudDriveFolder().path
        case .cloudKit:
            return AppStore.localDatabaseURL().path
        }
    }

    // MARK: - Conflict list

    @State private var expandedConflictIDs: Set<UUID> = []

    @ViewBuilder
    private func conflictListSection() -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("3-way merge 衝突")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.iCloudConflictCount) 筆未處理")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.iCloudConflicts) { conflict in
                conflictRow(conflict)
            }
        }
    }

    @ViewBuilder
    private func conflictRow(_ conflict: ConflictRecord) -> some View {
        let isExpanded = expandedConflictIDs.contains(conflict.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: conflict.isResolved ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(conflict.isResolved ? .green : .orange)
                Text("\(Self.tableDisplayName(conflict.table)) · \(conflict.recordId.prefix(8))…")
                    .font(.callout)
                Spacer()
                if !conflict.isResolved {
                    Text(conflict.resolution == .tookLocal ? "目前用 local" : "目前用 remote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("已手動處理")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Button {
                    if isExpanded { expandedConflictIDs.remove(conflict.id) }
                    else { expandedConflictIDs.insert(conflict.id) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }

            if isExpanded && !conflict.isResolved {
                conflictDetail(conflict)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func conflictDetail(_ conflict: ConflictRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("local 值 (本機):")
                .font(.caption).foregroundStyle(.secondary)
            Text(Self.prettyJSON(conflict.localValue))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)

            Text("remote 值 (雲端):")
                .font(.caption).foregroundStyle(.secondary)
            Text(Self.prettyJSON(conflict.remoteValue))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)

            HStack {
                Button {
                    Task { await viewModel.resolveConflict(conflict.id, useLocal: true) }
                } label: {
                    Label("用 local", systemImage: "mac")
                }
                Button {
                    Task { await viewModel.resolveConflict(conflict.id, useLocal: false) }
                } label: {
                    Label("用 remote", systemImage: "icloud")
                }
                Spacer()
            }
            .buttonStyle(.bordered)
        }
    }

    private static func tableDisplayName(_ table: ConflictRecord.Table) -> String {
        switch table {
        case .settings: return "設定"
        case .sources: return "來源"
        case .crawledDocuments: return "爬文文件"
        case .learningCards: return "卡片"
        case .quizQuestions: return "考題"
        case .generatedArticles: return "AI 文章"
        }
    }

    private static func prettyJSON(_ data: Data) -> String {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return "<無法解析>"
        }
        return str
    }

    private func stringBinding(get: @escaping (AppSettings) -> String, set: @escaping (inout AppSettings, String) -> Void) -> Binding<String> {
        Binding {
            get(viewModel.snapshot.settings)
        } set: { value in
            var settings = viewModel.snapshot.settings
            set(&settings, value)
            viewModel.updateSettings(settings)
        }
    }

    private func providerPresetBinding() -> Binding<ProviderPreset> {
        Binding {
            viewModel.activeProviderProfile?.config.preset ?? .openAI
        } set: { preset in
            viewModel.applyProviderPreset(preset)
            syncAIDraftsFromSettings()
        }
    }

    private func ttsProviderPresetBinding() -> Binding<TTSProviderPreset> {
        Binding {
            viewModel.snapshot.settings.openAITtsProviderPreset
        } set: { preset in
            viewModel.applyTTSProviderPreset(preset)
        }
    }

    /// 目前 active TTS profile 的 baseURL/model/voice 綁定。跟主 provider 一樣,
    /// 寫入時一定要透過 `updateActiveTTSProviderProfileConfig` 改進 profile 陣列,
    /// 不能直接改 `openAITts*` 純量欄位 —— 那些欄位只是 active profile 的鏡射,
    /// 下次 normalize 就會被 profile 裡的舊值蓋回去,等於改了也白改。
    private func ttsBaseURLBinding() -> Binding<String> {
        Binding {
            viewModel.snapshot.settings.openAITtsBaseURL
        } set: { value in
            viewModel.updateActiveTTSProviderProfileConfig { $0.baseURL = value }
        }
    }

    private func ttsModelBinding() -> Binding<String> {
        Binding {
            viewModel.snapshot.settings.openAITtsModel
        } set: { value in
            viewModel.updateActiveTTSProviderProfileConfig { $0.model = value }
        }
    }

    private func ttsVoiceBinding() -> Binding<String> {
        Binding {
            viewModel.snapshot.settings.openAITtsVoice
        } set: { value in
            viewModel.updateActiveTTSProviderProfileConfig { $0.voice = value }
        }
    }

    private func activeProviderModelBinding() -> Binding<String> {
        Binding {
            viewModel.activeProviderProfile?.config.model ?? viewModel.snapshot.settings.providerConfig.model
        } set: { model in
            viewModel.updateActiveProviderProfileConfig(resetVerification: false) { config in
                config.model = model
            }
        }
    }

    private func activeProviderFastModelBinding() -> Binding<String> {
        Binding {
            viewModel.activeProviderProfile?.config.fastModel ?? viewModel.snapshot.settings.providerConfig.fastModel
        } set: { fastModel in
            viewModel.updateActiveProviderProfileConfig(resetVerification: false) { config in
                config.fastModel = fastModel
            }
        }
    }

    private func structuredOutputBinding() -> Binding<StructuredOutputMode> {
        Binding {
            viewModel.activeProviderProfile?.config.structuredOutput ?? viewModel.snapshot.settings.providerConfig.structuredOutput
        } set: { mode in
            viewModel.updateActiveProviderProfileConfig(resetVerification: false) { config in
                config.structuredOutput = mode
            }
        }
    }

    private func toggleBinding(_ source: Source) -> Binding<Bool> {
        Binding {
            viewModel.snapshot.sources.first(where: { $0.id == source.id })?.isEnabled ?? false
        } set: { _ in
            viewModel.toggleSource(source)
        }
    }
}

struct HistoryView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var mode: HistoryMode = .articles
    @State private var selectedArticle: GeneratedArticle?

    enum HistoryMode: String, CaseIterable, Identifiable {
        case articles = "AI 文章與短文"
        case cards = "複習卡片"
        case quizzes = "考試紀錄"
        case database = "資料庫"
        var id: String { rawValue }
    }

    // 只顯示曾經被展示過的卡片，依最近複習時間排序，做為「複習紀錄」。
    // 全部卡片的瀏覽請改用「資料庫」分頁。
    private var reviewedCards: [LearningCard] {
        viewModel.snapshot.cards
            .filter { $0.lastShownAt != nil }
            .sorted { ($0.lastShownAt ?? .distantPast) > ($1.lastShownAt ?? .distantPast) }
    }

    private var completedQuizzes: [QuizQuestion] {
        viewModel.snapshot.quizzes
            .filter { $0.status != .pending }
            .sorted { ($0.answeredAt ?? $0.createdAt) > ($1.answeredAt ?? $1.createdAt) }
    }

    private var quizCorrectCount: Int {
        completedQuizzes.filter { $0.status == .correct }.count
    }

    private var quizIncorrectCount: Int {
        completedQuizzes.filter { $0.status == .incorrect }.count
    }

    private var quizAccuracyText: String {
        let answeredCount = quizCorrectCount + quizIncorrectCount
        guard answeredCount > 0 else { return "尚無答題結果" }
        let accuracy = Double(quizCorrectCount) / Double(answeredCount) * 100
        return "\(Int(accuracy.rounded()))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(HistoryMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            switch mode {
            case .articles:
                articleList
            case .cards:
                cardList
            case .quizzes:
                quizList
            case .database:
                DatabaseView(viewModel: viewModel)
            }
        }
        .sheet(item: $selectedArticle) { article in
            AIArticleDetailView(article: article, viewModel: viewModel)
        }
        .background(Color.designCanvas)
    }

    private var articleList: some View {
        List(viewModel.snapshot.generatedArticles) { article in
            HStack(alignment: .top, spacing: 8) {
                Button {
                    selectedArticle = article
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 6) {
                            if article.kind == .essay {
                                Label("AI 短文", systemImage: "doc.text")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(Color.blue)
                                    .cornerRadius(4)
                            } else {
                                Label("AI 擷取", systemImage: "sparkles.rectangle.stack")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12))
                                    .foregroundStyle(Color.green)
                                    .cornerRadius(4)
                            }
                            
                            Text(article.title.isEmpty ? article.theme : article.title)
                                .font(.headline)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(article.generatedAt.formatted(date: .numeric, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(article.plainText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.copyArticle(article)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("複製整篇文章")
            }
            .padding(.vertical, 2)
        }
        .overlay {
            if viewModel.snapshot.generatedArticles.isEmpty {
                ContentUnavailableView("還沒有 AI 文章與短文", systemImage: "doc.text")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.designCanvas)
    }

    private var cardList: some View {
        List(reviewedCards) { card in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(card.word).font(.headline)
                    Text(card.reading).foregroundStyle(.secondary)
                    Spacer()
                    Text(card.status.rawValue).font(.caption)
                }
                if let lastShownAt = card.lastShownAt {
                    Text("複習：\(lastShownAt.formatted()) · 出現 \(card.shownCount) 次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(card.meaningZh).lineLimit(2)
                Text(card.exampleJa).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if reviewedCards.isEmpty {
                ContentUnavailableView("還沒有複習紀錄", systemImage: "clock")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.designCanvas)
    }

    private var quizList: some View {
        List {
            if !completedQuizzes.isEmpty {
                Section {
                    HStack {
                        QuizSummaryTile(title: "累積", value: "\(completedQuizzes.count)")
                        QuizSummaryTile(title: "答對", value: "\(quizCorrectCount)")
                        QuizSummaryTile(title: "答錯", value: "\(quizIncorrectCount)")
                        QuizSummaryTile(title: "正確率", value: quizAccuracyText)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ForEach(completedQuizzes) { quiz in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            if let selectedAnswer = quiz.selectedAnswer {
                                LabeledContent("你的答案", value: selectedAnswer)
                            }
                            LabeledContent("正解", value: quiz.correctAnswer)
                            Text(quiz.explanationZh)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.caption)
                        .padding(.top, 6)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(quizResultText(quiz), systemImage: quizResultIcon(quiz))
                                    .foregroundStyle(quizResultColor(quiz))
                                Spacer()
                                Text((quiz.answeredAt ?? quiz.createdAt).formatted(date: .numeric, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(quiz.sourceWord)
                                .font(.headline)
                            Text(quiz.question)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(quizResultBackground(quiz))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, -8)
                }
            }
        }
        .overlay {
            if completedQuizzes.isEmpty {
                ContentUnavailableView("還沒有考試紀錄", systemImage: "checkmark.seal")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.designCanvas)
    }

    private func quizResultText(_ quiz: QuizQuestion) -> String {
        switch quiz.status {
        case .correct:
            return "答對"
        case .incorrect:
            return "答錯"
        case .skipped:
            return "略過"
        case .pending:
            return "未作答"
        }
    }

    private func quizResultIcon(_ quiz: QuizQuestion) -> String {
        switch quiz.status {
        case .correct:
            return "checkmark.circle.fill"
        case .incorrect:
            return "xmark.circle.fill"
        case .skipped:
            return "forward.circle"
        case .pending:
            return "circle"
        }
    }

    private func quizResultColor(_ quiz: QuizQuestion) -> Color {
        switch quiz.status {
        case .correct:
            return .quizCorrect
        case .incorrect:
            return .quizIncorrect
        case .skipped:
            return .secondary
        case .pending:
            return .secondary
        }
    }

    private func quizResultBackground(_ quiz: QuizQuestion) -> Color {
        switch quiz.status {
        case .correct:
            return .quizCorrectBg
        case .incorrect:
            return .quizIncorrectBg
        case .skipped:
            return .secondary.opacity(0.08)
        case .pending:
            return .clear
        }
    }
}

private struct QuizSummaryTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 造卡頁：把「AI 擷取」、「AI 短文」與「貼上造卡」收進同一個頁籤，用上方分段切換。
struct CardMakerView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var mode: Mode = .aiArticle

    enum Mode: Hashable { case aiArticle, aiEssay, manual }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Label("AI 擷取", systemImage: "sparkles.rectangle.stack").tag(Mode.aiArticle)
                Label("AI 短文", systemImage: "doc.text").tag(Mode.aiEssay)
                Label("貼上造卡", systemImage: "doc.text.magnifyingglass").tag(Mode.manual)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .padding(.bottom, 4)

            switch mode {
            case .aiArticle:
                AIArticleView(viewModel: viewModel)
            case .aiEssay:
                AIEssayView(viewModel: viewModel)
            case .manual:
                ManualCardView(viewModel: viewModel)
            }
        }
        .background(Color.designCanvas)
        .groupBoxStyle(OpenDesignGroupBoxStyle())
    }
}

/// 造卡頁專用的柔和內容卡片，避免 macOS 預設 GroupBox 的深灰底堆在一起。
private struct OpenDesignGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.cardBlue)

            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.designSurface, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.designBorder.opacity(0.58), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 3, y: 1)
    }
}

struct AIEssayView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("利用你庫存的單字產生貼近生活或工作實務的日文短文與中文段落對照。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                GroupBox("1. 選擇單字來源") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: Binding(
                            get: { viewModel.selectedVocabularySource },
                            set: { viewModel.setSelectedVocabularySource($0) }
                        )) {
                            ForEach(VocabularySourceType.allCases, id: \.self) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("預計融入的單字 (最多 5 個)：")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    viewModel.shufflePreviewVocabulary()
                                } label: {
                                    Label("換一批", systemImage: "shuffle")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                            
                            if viewModel.previewVocabularyCards.isEmpty {
                                Text("目前此分類沒有單字，請先新增卡片。")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            } else {
                                FlowLayout(spacing: 6) {
                                    ForEach(viewModel.previewVocabularyCards) { card in
                                        Text(card.word)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    .background(Color.cardBlue.opacity(0.10))
                                    .overlay {
                                        Capsule()
                                            .stroke(Color.cardBlue.opacity(0.18), lineWidth: 1)
                                    }
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                
                GroupBox("2. 附加提示詞 (與日文或日常生活/工作相關)") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("例如：寫一篇居酒屋點餐的對話，或留空隨機生成", text: $viewModel.userEssayPrompt)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("請勿輸入無關或違反規定（如寫程式、算數學、問無關常識）的提示。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack {
                    Spacer()
                    if viewModel.isGeneratingEssay {
                        VStack(spacing: 16) {
                            if let currentStep = viewModel.essayCurrentStep {
                                HStack(spacing: 8) {
                                    ForEach(EssayGenerationStep.allCases, id: \.self) { step in
                                        let isCurrent = step == currentStep
                                        let isCompleted = step.rawValue < currentStep.rawValue
                                        
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle()
                                                    .fill(isCompleted ? Color.green : (isCurrent ? Color.accentColor : Color.secondary.opacity(0.2)))
                                                    .frame(width: 24, height: 24)
                                                
                                                if isCompleted {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundStyle(.white)
                                                } else {
                                                    Text("\(step.rawValue + 1)")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundStyle(isCurrent ? .white : .secondary)
                                                }
                                            }
                                            
                                            Text(step.title)
                                                .font(.caption2)
                                                .foregroundStyle(isCurrent ? .primary : .secondary)
                                        }
                                        
                                        if step != .done {
                                            Rectangle()
                                                .fill(isCompleted ? Color.green : Color.secondary.opacity(0.2))
                                                .frame(height: 2)
                                                .frame(maxWidth: .infinity)
                                                .padding(.bottom, 22)
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                            
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(viewModel.essayGenerationProgress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Button("取消產生") {
                                viewModel.cancelEssayGeneration()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(12)
                        .frame(maxWidth: .infinity)
                    } else {
                        Button {
                            viewModel.generateAIEssayNow()
                        } label: {
                            Label("開始產生短文", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.previewVocabularyCards.isEmpty)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                
                if let valError = viewModel.essayValidationError {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("提示詞無效", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(valError)
                            .font(.body)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                if let genError = viewModel.essayGenerationError {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("產生失敗", systemImage: "xmark.octagon.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(genError)
                            .font(.body)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                if let article = viewModel.lastGeneratedEssay {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        
                        HStack {
                            Text("產生的短文結果")
                                .font(.headline)
                            Spacer()
                            if viewModel.articleNeedsRubyAnnotation(article) {
                                Button {
                                    viewModel.annotateArticleRuby(articleId: article.id)
                                } label: {
                                    if viewModel.isAnnotatingArticleRuby {
                                        Label("標註中...", systemImage: "hourglass")
                                    } else {
                                        Label("重新標註注音", systemImage: "character.phonetic")
                                    }
                                }
                                .disabled(viewModel.isAnnotatingArticleRuby)
                                .help("注音產生失敗時，可重新標註漢字讀音")
                            }
                            Menu {
                                Button("匯出為 PDF (.pdf)") {
                                    viewModel.exportEssay(article: article, format: "pdf")
                                }
                                Button("匯出為 PNG 圖片 (.png)") {
                                    viewModel.exportEssay(article: article, format: "png")
                                }
                                Button("匯出為 Word 文檔 (.docx)") {
                                    viewModel.exportEssay(article: article, format: "word")
                                }
                            } label: {
                                Label("匯出檔案", systemImage: "square.and.arrow.up")
                            }
                            #if !os(macOS)
                            .sheet(isPresented: Binding(
                                get: { viewModel.exportedEssayURL != nil },
                                set: { if !$0 { viewModel.exportedEssayURL = nil } }
                            )) {
                                if let url = viewModel.exportedEssayURL {
                                    ShareLink(item: url, message: Text("AI 產生日文短文：\(article.title)"))
                                }
                            }
                            #endif
                        }
                        
                        GroupBox(content: {
                            VStack(alignment: .leading, spacing: 14) {
                                let paras = article.resolvedParagraphs
                                if paras.isEmpty {
                                    Text(article.plainText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    ForEach(Array(paras.enumerated()), id: \.offset) { _, para in
                                        VStack(alignment: .leading, spacing: 6) {
                                            RubyText(
                                                segments: para.ruby,
                                                fallback: para.japanese,
                                                baseFont: .system(size: 15),
                                                rubyFont: .system(size: 8),
                                                baseColor: .primary,
                                                rubyColor: .secondary,
                                                highlightWords: article.vocabularyWords ?? []
                                            )
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                            Text(para.translation)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }, label: {
                            RubyText(
                                segments: article.titleRuby ?? [],
                                fallback: article.title.isEmpty ? "日文短文" : article.title,
                                baseFont: .headline,
                                rubyFont: .caption2,
                                baseColor: .primary,
                                rubyColor: .secondary
                            )
                        })
                    }
                    .transition(.opacity)
                }
            }
            .padding()
        }
    }
}


struct AIArticleView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedArticle: GeneratedArticle?

    private let levelOrder: [JLPTLevel] = [.n1, .n2, .n3, .n4, .n5, .unknown]

    // Calendar 慣例：1 = 週日 … 7 = 週六。從週一開始排列較符合習慣。
    private let weekdayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]

    private func weekdaySymbol(_ weekday: Int) -> String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let index = max(1, min(7, weekday)) - 1
        return "週" + symbols[index]
    }

    private var scheduleTimeBinding: Binding<Date> {
        Binding(
            get: {
                let settings = viewModel.snapshot.settings
                return Calendar.current.date(
                    bySettingHour: settings.aiArticleScheduleHour,
                    minute: settings.aiArticleScheduleMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                viewModel.setAIArticleScheduleTime(
                    hour: components.hour ?? 9,
                    minute: components.minute ?? 0
                )
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            Text("由 AI 撰寫指定 JLPT 等級的日文短文，再自動從中擷取單字卡。")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("自動排程") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("啟用排程產生", isOn: Binding(
                        get: { viewModel.snapshot.settings.aiArticleEnabled },
                        set: { viewModel.setAIArticleEnabled($0) }
                    ))

                    HStack {
                        Text("時間")
                            .foregroundStyle(.secondary)
                        DatePicker(
                            "",
                            selection: scheduleTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        #if os(macOS)
                        .datePickerStyle(.stepperField)
                        #else
                        .datePickerStyle(.compact)
                        #endif
                    }
                    .disabled(!viewModel.snapshot.settings.aiArticleEnabled)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("星期")
                            .foregroundStyle(.secondary)
                        let selectedWeekdays = Set(viewModel.snapshot.settings.aiArticleWeekdays)
                        FlowLayout(spacing: 6) {
                            ForEach(weekdayOrder, id: \.self) { weekday in
                                WeekdayChip(
                                    title: weekdaySymbol(weekday),
                                    isSelected: selectedWeekdays.contains(weekday)
                                ) {
                                    viewModel.toggleAIArticleWeekday(weekday)
                                }
                            }
                        }
                    }
                    .disabled(!viewModel.snapshot.settings.aiArticleEnabled)

                    if viewModel.snapshot.settings.aiArticleWeekdays.isEmpty {
                        Text("尚未選擇任何星期，排程不會觸發。")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            GroupBox("目標 JLPT 等級") {
                let selectedLevels = Set(viewModel.snapshot.settings.aiArticleLevels)
                FlowLayout(spacing: 6) {
                    ForEach(levelOrder) { level in
                        LevelChip(
                            level: level,
                            isSelected: selectedLevels.contains(level)
                        ) {
                            viewModel.toggleAIArticleLevel(level)
                        }
                    }
                }
                .padding(.vertical, 2)
                Text("至少會選一個等級。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GroupBox("主題") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("留空 = 隨機主題", text: Binding(
                        get: { viewModel.aiArticleCustomTheme },
                        set: { viewModel.setAIArticleCustomTheme($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text("輸入主題 (例如「旅行-京都」)；留空則由 AI 隨機挑選生活化主題。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button {
                            viewModel.generateAIArticleNow()
                        } label: {
                            Label(
                                viewModel.isGeneratingAIArticle ? "生成中..." : "立即產生文章",
                                systemImage: "sparkles"
                            )
                        }
                        .disabled(viewModel.isGeneratingAIArticle)
                    }
                }
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("已產生文章 \(viewModel.snapshot.generatedArticles.count) 篇")
                .font(.subheadline.weight(.semibold))

            if viewModel.snapshot.generatedArticles.isEmpty {
                ContentUnavailableView(
                    "還沒有 AI 文章",
                    systemImage: "doc.text",
                    description: Text("按「立即產生文章」開始，或開啟自動排程。")
                )
            } else {
                ForEach(viewModel.snapshot.generatedArticles) { article in
                    Button {
                        selectedArticle = article
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(article.title.isEmpty ? article.theme : article.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text(article.generatedAt.formatted(date: .numeric, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                ForEach(article.jlptLevels, id: \.self) { level in
                                    CardBadge(text: level.rawValue)
                                }
                                Spacer()
                                Text("\(article.cardCount) 張卡")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(article.plainText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $selectedArticle) { article in
            AIArticleDetailView(article: article, viewModel: viewModel)
        }
    }
}

struct ManualCardView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("貼上一段日文文章，或一份單字／片語清單，AI 會理解內容後幫你產生單字卡。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GroupBox("文章或單字清單") {
                    TextEditor(text: $viewModel.manualCardInput)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 180)
                        .background(Color.platformTextBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.platformSeparator, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                GroupBox("額外指示（選填）") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("例如：只挑動詞、解說偏商業情境", text: $viewModel.manualCardInstruction)
                            .textFieldStyle(.roundedBorder)
                        Text("可指定挑選範圍或解說風格；留空則由 AI 自行判斷。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    if !viewModel.statusMessage.isEmpty {
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.generateManualCards()
                    } label: {
                        Label(
                            viewModel.isGeneratingManualCards ? "產生中..." : "產生單字卡",
                            systemImage: "sparkles"
                        )
                    }
                    .disabled(viewModel.isGeneratingManualCards || !viewModel.canGenerateManualCards)
                }
            }
            .padding()
        }
    }
}

struct LevelChip: View {
    let level: JLPTLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(level.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.cardBlue.opacity(0.14) : Color.designCanvas)
                .foregroundColor(isSelected ? Color.cardBlue : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.cardBlue.opacity(0.65) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct WeekdayChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.cardBlue.opacity(0.14) : Color.designCanvas)
                .foregroundColor(isSelected ? Color.cardBlue : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.cardBlue.opacity(0.65) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct AIArticleDetailView: View {
    let article: GeneratedArticle
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    /// 補標注音後 snapshot 會更新，這裡改讀最新版本，讓畫面立即反映。
    private var liveArticle: GeneratedArticle {
        viewModel.snapshot.generatedArticles.first(where: { $0.id == article.id }) ?? article
    }

    private var relatedCards: [LearningCard] {
        viewModel.snapshot.cards.filter { $0.sourceUrl.absoluteString.contains(article.contentHash.prefix(12).description) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    RubyText(
                        segments: liveArticle.titleRuby ?? [],
                        fallback: liveArticle.title,
                        baseFont: .title2.weight(.semibold),
                        rubyFont: .caption2,
                        baseColor: .primary,
                        rubyColor: .secondary
                    )
                    Text("主題：\(liveArticle.theme)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.articleNeedsRubyAnnotation(liveArticle) {
                    Button {
                        viewModel.annotateArticleRuby(articleId: article.id)
                    } label: {
                        if viewModel.isAnnotatingArticleRuby {
                            Label("標註中...", systemImage: "hourglass")
                        } else {
                            Label("重新標註注音", systemImage: "character.phonetic")
                        }
                    }
                    .disabled(viewModel.isAnnotatingArticleRuby)
                    .help("為缺少注音的段落重新標註漢字讀音")
                }
                Menu {
                    Button("匯出為 PDF (.pdf)") {
                        viewModel.exportEssay(article: liveArticle, format: "pdf")
                    }
                    Button("匯出為 PNG 圖片 (.png)") {
                        viewModel.exportEssay(article: liveArticle, format: "png")
                    }
                    Button("匯出為 Word 文檔 (.docx)") {
                        viewModel.exportEssay(article: liveArticle, format: "word")
                    }
                } label: {
                    Label("匯出", systemImage: "square.and.arrow.up")
                }
                #if !os(macOS)
                .sheet(isPresented: Binding(
                    get: { viewModel.exportedEssayURL != nil },
                    set: { if !$0 { viewModel.exportedEssayURL = nil } }
                )) {
                    if let url = viewModel.exportedEssayURL {
                        ShareLink(item: url, message: Text("AI 產生日文文章：\(article.title)"))
                    }
                }
                #endif
                Button {
                    viewModel.copyArticle(article)
                } label: {
                    Label("複製", systemImage: "doc.on.doc")
                }
                .help("複製整篇文章到剪貼簿")
                Button("關閉") { dismiss() }
            }

            HStack(spacing: 6) {
                ForEach(article.jlptLevels, id: \.self) { level in
                    CardBadge(text: level.rawValue)
                }
                CardBadge(text: "\(article.cardCount) 張卡")
                CardBadge(text: article.generatedAt.formatted(date: .numeric, time: .shortened))
            }

            GroupBox("文章本文") {
                ScrollView {
                    let paras = liveArticle.resolvedParagraphs
                    if paras.isEmpty {
                        Text(liveArticle.plainText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(paras.enumerated()), id: \.offset) { _, para in
                                VStack(alignment: .leading, spacing: 6) {
                                    RubyText(
                                        segments: para.ruby,
                                        fallback: para.japanese,
                                        baseFont: .system(size: 15),
                                        rubyFont: .system(size: 8),
                                        baseColor: .primary,
                                        rubyColor: .secondary,
                                        highlightWords: liveArticle.vocabularyWords ?? []
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    if !para.translation.isEmpty {
                                        Text(para.translation)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }


            if !relatedCards.isEmpty {
                GroupBox("從本文擷取的學習卡") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(relatedCards) { card in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(card.word).font(.headline)
                                        Text(card.reading).foregroundStyle(.secondary).font(.caption)
                                        Spacer()
                                        Text(card.jlptLevel.rawValue).font(.caption2)
                                    }
                                    Text(card.meaningZh).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .padding(.vertical, 2)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }

            Spacer()
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct QuizChoiceButtonStyle: ButtonStyle {
    var bgColor: Color
    var borderColor: Color
    var borderLineWidth: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? bgColor.opacity(0.8) : bgColor)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: borderLineWidth)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
