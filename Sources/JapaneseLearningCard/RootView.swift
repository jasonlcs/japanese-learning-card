import AppKit
import JapaneseLearningCardCore
import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $viewModel.selectedTab) {
                Label("卡片", systemImage: "rectangle.stack").tag(0)
                Label("AI 文章", systemImage: "sparkles.rectangle.stack").tag(1)
                Label("考題", systemImage: "checklist").tag(2)
                Label("資料庫", systemImage: "cylinder.split.1x2").tag(3)
                Label("設定", systemImage: "gearshape").tag(4)
                Label("歷史", systemImage: "clock").tag(5)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            Group {
                switch viewModel.selectedTab {
                case 1:
                    AIArticleView(viewModel: viewModel)
                case 2:
                    QuizView(viewModel: viewModel)
                case 3:
                    DatabaseView(viewModel: viewModel)
                case 4:
                    SettingsView(viewModel: viewModel)
                case 5:
                    HistoryView(viewModel: viewModel)
                default:
                    CardView(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .scrollContentBackground(.hidden)
        .onHover { inside in
            if inside {
                viewModel.pauseAutoCloseForInteraction()
            } else {
                viewModel.resumeAutoCloseAfterInteraction()
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("考題")
                        .font(.title2.weight(.semibold))
                    Text("由 AI 根據已產生的學習卡出題，作答後顯示解析。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.generateQuiz()
                } label: {
                    Label(viewModel.isGeneratingQuiz ? "出題中..." : "AI 出題", systemImage: "sparkles")
                }
                .disabled(viewModel.isGeneratingQuiz)
            }

            if let quiz = viewModel.currentQuiz {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(quiz.sourceWord)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(quiz.question)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(quiz.choices, id: \.self) { choice in
                            Button {
                                viewModel.submitQuizAnswer(choice)
                            } label: {
                                HStack {
                                    Text(choice)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if quiz.selectedAnswer == choice {
                                        Image(systemName: choice == quiz.correctAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(buttonTint(choice: choice, quiz: quiz))
                            .disabled(quiz.status != .pending)
                        }

                        if quiz.status != .pending {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Label(
                                    quiz.status == .correct ? "答對了" : "正解：\(quiz.correctAnswer)",
                                    systemImage: quiz.status == .correct ? "checkmark.seal" : "lightbulb"
                                )
                                .font(.subheadline.weight(.semibold))
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
                    description: Text("先按 AI 出題，系統會從已儲存的學習卡產生選擇題。")
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

    private func buttonTint(choice: String, quiz: QuizQuestion) -> Color? {
        guard quiz.status != .pending else { return nil }
        if choice == quiz.correctAnswer { return .green }
        if choice == quiz.selectedAnswer { return .red }
        return nil
    }
}

struct CardView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let card = viewModel.currentCard {
                VStack(alignment: .leading, spacing: 8) {
                    CopyableTextRow(text: card.word, font: .system(size: 36, weight: .bold))
                    CopyableTextRow(text: card.reading, font: .title3, color: .secondary)
                    HStack(spacing: 6) {
                        CardBadge(text: card.partOfSpeech)
                        if card.jlptLevel != .unknown {
                            CardBadge(text: card.jlptLevel.rawValue)
                        }
                        if card.verbFormType != .notVerb && card.verbFormType != .unknown {
                            CardBadge(text: card.verbFormType.rawValue)
                        }
                    }
                }

                GroupBox("中文意思") {
                    Text(card.meaningZh).frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("文法解說") {
                    Text(card.grammarNoteZh).frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("例句") {
                    VStack(alignment: .leading, spacing: 6) {
                        CopyableTextRow(text: card.exampleJa, font: .headline)
                        if !card.exampleReading.isEmpty {
                            CopyableTextRow(text: card.exampleReading, font: .subheadline, color: .secondary)
                        } else {
                            Button {
                                viewModel.fillCurrentExampleReading()
                            } label: {
                                Label(viewModel.isGeneratingExampleReading ? "補平假名中..." : "補平假名", systemImage: "wand.and.stars")
                            }
                            .disabled(viewModel.isGeneratingExampleReading)
                        }
                        Text(card.exampleZh).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Link(card.sourceUrl.host() ?? card.sourceUrl.absoluteString, destination: card.sourceUrl)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    Button("略過") { viewModel.markCurrentCard(.skipped) }
                    Button("已學會") { viewModel.markCurrentCard(.learned) }
                    Spacer()
                    Button {
                        viewModel.showNextCard()
                    } label: {
                        Label("下一張", systemImage: "arrow.right")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
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
                Spacer()
            }
        }
        .padding()
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

struct CopyableTextRow: View {
    var text: String
    var font: Font
    var color: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("複製")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            if !viewModel.statusMessage.isEmpty {
                Section {
                    Label(viewModel.statusMessage, systemImage: viewModel.isValidatingProvider || viewModel.isRefreshing ? "hourglass" : "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("顯示") {
                Stepper("顯示頻率：\(viewModel.snapshot.settings.displayIntervalMinutes) 分鐘", value: binding(\.displayIntervalMinutes), in: 1...1440)
                Stepper("停留秒數：\(viewModel.snapshot.settings.visibleDurationSeconds) 秒", value: binding(\.visibleDurationSeconds), in: 3...300)
                Stepper("爬文頻率：\(viewModel.snapshot.settings.crawlIntervalHours) 小時", value: binding(\.crawlIntervalHours), in: 1...168)
            }

            Section("AI Provider") {
                Picker("Provider", selection: providerPresetBinding()) {
                    ForEach(ProviderPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                TextField("Base URL", text: stringBinding(
                    get: { $0.providerConfig.baseURL.absoluteString },
                    set: { settings, value in
                        if let url = URL(string: value) {
                            settings.providerConfig.baseURL = url
                        }
                    }
                ))

                Picker("Model", selection: stringBinding(
                    get: { $0.providerConfig.model },
                    set: { $0.providerConfig.model = $1 }
                )) {
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                TextField("Keychain reference", text: stringBinding(
                    get: { $0.providerConfig.apiKeyKeychainRef },
                    set: { $0.providerConfig.apiKeyKeychainRef = $1 }
                ))
                SecureField("API key", text: $viewModel.apiKeyInput)

                HStack {
                    Button {
                        viewModel.saveAndValidateProvider()
                    } label: {
                        Label(viewModel.isValidatingProvider ? "驗證中..." : "存 Key 並驗證", systemImage: "checkmark.seal")
                    }
                    .disabled(viewModel.isValidatingProvider)

                    Button {
                        viewModel.saveAPIKey()
                    } label: {
                        Label("只存 Key", systemImage: "key")
                    }
                }

                if !viewModel.statusMessage.isEmpty {
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("內容來源") {
                TextEditor(text: stringBinding(
                    get: { $0.defaultExtractionPrompt },
                    set: { $0.defaultExtractionPrompt = $1 }
                ))
                .frame(height: 72)

                LabeledContent("新增網址") {
                    HStack {
                        TextField("", text: $viewModel.newSourceURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Button {
                            viewModel.addSource()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(viewModel.newSourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .help("例如：https://example.com/article")

                ForEach(viewModel.snapshot.sources) { source in
                    HStack {
                        Toggle("", isOn: toggleBinding(source))
                            .labelsHidden()
                        VStack(alignment: .leading) {
                            Text(source.url.absoluteString).lineLimit(1)
                            if let error = source.lastError {
                                Text(error).font(.caption).foregroundStyle(.red)
                            } else if let date = source.lastFetchedAt {
                                Text(date.formatted()).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            viewModel.removeSource(source)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
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

            Section("資料庫") {
                Button {
                    viewModel.exportDatabase()
                } label: {
                    Label("匯出 SQLite DB", systemImage: "square.and.arrow.down")
                }
            }

            Section {
                Button(role: .destructive) {
                    viewModel.quitApp()
                } label: {
                    Label("結束程式", systemImage: "power")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Int> {
        Binding {
            viewModel.snapshot.settings[keyPath: keyPath]
        } set: { value in
            var settings = viewModel.snapshot.settings
            settings[keyPath: keyPath] = value
            viewModel.updateSettings(settings)
        }
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
            viewModel.snapshot.settings.providerConfig.preset
        } set: { preset in
            viewModel.applyProviderPreset(preset)
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

    var body: some View {
        List(viewModel.snapshot.cards) { card in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(card.word).font(.headline)
                    Text(card.reading).foregroundStyle(.secondary)
                    Spacer()
                    Text(card.status.rawValue).font(.caption)
                }
                Text(card.meaningZh).lineLimit(2)
                Text(card.exampleJa).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if viewModel.snapshot.cards.isEmpty {
                ContentUnavailableView("沒有歷史卡片", systemImage: "clock")
            }
        }
    }
}

struct AIArticleView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedArticle: GeneratedArticle?

    private let levelOrder: [JLPTLevel] = [.n1, .n2, .n3, .n4, .n5, .unknown]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI 文章產生")
                    .font(.title2.weight(.semibold))
                Text("由 AI 撰寫指定 JLPT 等級的日文短文，再自動從中擷取單字卡。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox("自動排程") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("啟用週期產生", isOn: Binding(
                        get: { viewModel.snapshot.settings.aiArticleEnabled },
                        set: { viewModel.setAIArticleEnabled($0) }
                    ))

                    Stepper(
                        "週期：\(viewModel.snapshot.settings.aiArticleIntervalHours) 小時",
                        value: Binding(
                            get: { viewModel.snapshot.settings.aiArticleIntervalHours },
                            set: { viewModel.setAIArticleIntervalHours($0) }
                        ),
                        in: 1...168
                    )
                    .disabled(!viewModel.snapshot.settings.aiArticleEnabled)
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
                List(viewModel.snapshot.generatedArticles) { article in
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
                }
                .listStyle(.plain)
            }

            Spacer()
        }
        .padding()
        .sheet(item: $selectedArticle) { article in
            AIArticleDetailView(article: article, viewModel: viewModel)
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
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct AIArticleDetailView: View {
    let article: GeneratedArticle
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private var relatedCards: [LearningCard] {
        viewModel.snapshot.cards.filter { $0.sourceUrl.absoluteString.contains(article.contentHash.prefix(12).description) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(article.title)
                        .font(.title2.weight(.semibold))
                    Text("主題：\(article.theme)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
                    Text(article.plainText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: 220)
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
        .frame(minWidth: 460, minHeight: 520)
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
