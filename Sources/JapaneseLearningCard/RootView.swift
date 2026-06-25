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
                Label("手動造卡", systemImage: "doc.text.magnifyingglass").tag(6)
                Label("考題", systemImage: "checklist").tag(2)
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
                case 4:
                    SettingsView(viewModel: viewModel)
                case 5:
                    HistoryView(viewModel: viewModel)
                case 6:
                    ManualCardView(viewModel: viewModel)
                default:
                    CardView(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
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
                StyledLearningCard(
                    card: card,
                    isGeneratingExampleReading: viewModel.isGeneratingExampleReading,
                    fillExampleReading: viewModel.fillCurrentExampleReading,
                    skipCard: { viewModel.markCurrentCard(.skipped) },
                    learnCard: { viewModel.markCurrentCard(.learned) },
                    nextCard: viewModel.showNextCard
                )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var kind: LearningCardLayoutKind { LearningCardLayoutKind(card: card) }
    private var noteSections: CardNoteSections { CardNoteSections(note: card.grammarNoteZh) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            cardHeader

            switch kind {
            case .vocabulary:
                vocabularyLayout
            case .grammar:
                grammarLayout
            }

            cardFooter
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.cardBlue.opacity(0.42), lineWidth: 2)
        )
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

            Text("#\(card.id.uuidString.prefix(3))")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.cardBlue)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.cardBlue.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                )
        }
    }

    private var vocabularyLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                wordHero
                    .frame(maxWidth: .infinity, minHeight: 112)

                Divider()
                    .frame(height: 105)

                VStack(alignment: .leading, spacing: 8) {
                    CardInfoPanel(title: "意味", systemImage: "lightbulb", tint: .cardOrange) {
                        Text(card.meaningZh)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                wordHero
                    .frame(maxWidth: .infinity, minHeight: 105)

                CardInfoPanel(title: "意味", systemImage: "lightbulb", tint: .cardOrange) {
                    Text(card.meaningZh)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    if let point = noteSections.point {
                        Divider().overlay(Color.cardOrange.opacity(0.45))
                        Text(point)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 8) {
                CardInfoPanel(title: "接続", systemImage: "gearshape.fill", tint: .cardPink) {
                    Text(connectionText)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                }

                CardInfoPanel(title: "ポイント", systemImage: "exclamationmark.circle.fill", tint: .cardPink) {
                    Text(noteSections.point ?? "注意句型前後的接續與語氣。")
                        .font(.callout)
                        .lineLimit(2)
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
        VStack(spacing: 6) {
            if !card.reading.isEmpty {
                CopyableTextRow(text: card.reading, font: .callout.weight(.bold), color: .cardBlue)
            }
            CopyableTextRow(text: card.word, font: .system(size: kind == .grammar ? 32 : 42, weight: .black, design: .rounded), color: kind == .grammar ? .cardBlue : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
            if !card.reading.isEmpty {
                Text(card.reading.romanizedJapaneseFallback)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            DecorativeStroke()
                .foregroundStyle(Color.cardBlue)
                .padding(.leading, 6)
        }
        .overlay(alignment: .trailing) {
            DecorativeStroke()
                .scaleEffect(x: -1, y: 1)
                .foregroundStyle(Color.cardBlue)
                .padding(.trailing, 6)
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

            Button {
                learnCard()
            } label: {
                Label("已學會", systemImage: "checkmark")
            }

            Button {
                nextCard()
            } label: {
                Label("下一張", systemImage: "arrow.right")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(.top, 2)
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
                CopyableTextRow(text: card.exampleJa, font: .headline)
                    .lineLimit(2)
                if !card.exampleReading.isEmpty {
                    CopyableTextRow(text: card.exampleReading, font: .subheadline, color: .secondary)
                        .lineLimit(1)
                } else {
                    Button {
                        fillExampleReading()
                    } label: {
                        Label(isGeneratingExampleReading ? "補平假名中..." : "補平假名", systemImage: "wand.and.stars")
                    }
                    .disabled(isGeneratingExampleReading)
                }
                Text(card.exampleZh)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .lineLimit(2)
            }
        }
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
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
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
                .lineLimit(1)
        }
    }
}

private struct DecorativeStroke: View {
    var body: some View {
        VStack(spacing: 5) {
            Capsule().frame(width: 13, height: 2.5).rotationEffect(.degrees(28))
            Capsule().frame(width: 16, height: 2.5)
            Capsule().frame(width: 13, height: 2.5).rotationEffect(.degrees(-28))
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
    static let cardBlue = Color(red: 0.05, green: 0.34, blue: 0.68)
    static let cardOrange = Color(red: 0.96, green: 0.61, blue: 0.05)
    static let cardPink = Color(red: 0.93, green: 0.27, blue: 0.45)
    static let cardGreen = Color(red: 0.25, green: 0.68, blue: 0.28)
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
    @State private var isSystemSettingsPresented = false
    @AppStorage(UpdateChecker.autoCheckDefaultsKey) private var autoCheckUpdates = false
    @FocusState private var isSourceURLFocused: Bool
    /// 既有來源網址的編輯緩衝區（key 為 Source.id），送出前不寫回資料。
    @State private var editingSourceURLs: [UUID: String] = [:]

    var body: some View {
        if isSystemSettingsPresented {
            systemSettingsView
        } else {
            sourceSettingsView
        }
    }

    private var sourceSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("來源設定")
                        .font(.headline)
                    Spacer()
                    Button {
                        isSystemSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help("系統設定")
                }

                if !viewModel.statusMessage.isEmpty {
                    Label(viewModel.statusMessage, systemImage: viewModel.isValidatingProvider || viewModel.isRefreshing ? "hourglass" : "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

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
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
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
                            Button {
                                addSourceAndRefocus()
                            } label: {
                                Image(systemName: "plus")
                            }
                            .disabled(!canAddSource)
                            .help("新增網址")
                        }
                    }

                    ForEach(webSources) { source in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: toggleBinding(source))
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 3) {
                                TextField("", text: sourceURLBinding(source))
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { commitSourceURL(source) }
                                if let error = source.lastError {
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
            .padding()
        }
    }

    private var systemSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        isSystemSettingsPresented = false
                    } label: {
                        Label("返回", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Text("系統設定")
                        .font(.headline)
                    Spacer()
                    Button("完成") {
                        isSystemSettingsPresented = false
                    }
                }

                if !viewModel.statusMessage.isEmpty {
                    Label(viewModel.statusMessage, systemImage: viewModel.isValidatingProvider || viewModel.isRefreshing ? "hourglass" : "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                settingsBox("顯示") {
                    Stepper("顯示頻率：\(viewModel.snapshot.settings.displayIntervalMinutes) 分鐘", value: binding(\.displayIntervalMinutes), in: 1...1440)
                    Stepper("停留秒數：\(viewModel.snapshot.settings.visibleDurationSeconds) 秒", value: binding(\.visibleDurationSeconds), in: 3...300)
                    Stepper("爬文頻率：\(viewModel.snapshot.settings.crawlIntervalHours) 小時", value: binding(\.crawlIntervalHours), in: 1...168)
                }

                settingsBox("AI Provider") {
                    labeledRow("Provider") {
                        Picker("", selection: providerPresetBinding()) {
                            ForEach(ProviderPreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .labelsHidden()
                    }

                    labeledRow("Base URL") {
                        TextField("", text: stringBinding(
                            get: { $0.providerConfig.baseURL.absoluteString },
                            set: { settings, value in
                                if let url = URL(string: value) {
                                    settings.providerConfig.baseURL = url
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    labeledRow("Model") {
                        Picker("", selection: stringBinding(
                            get: { $0.providerConfig.model },
                            set: { $0.providerConfig.model = $1 }
                        )) {
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

                    labeledRow("Keychain reference") {
                        TextField("", text: stringBinding(
                            get: { $0.providerConfig.apiKeyKeychainRef },
                            set: { $0.providerConfig.apiKeyKeychainRef = $1 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    labeledRow("API key") {
                        SecureField("", text: $viewModel.apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        viewModel.validateAndSaveProvider()
                    } label: {
                        Label(viewModel.isValidatingProvider ? "驗證中..." : "驗證並儲存", systemImage: "checkmark.seal")
                    }
                    .disabled(viewModel.isValidatingProvider)
                    .help("驗證成功才會把 API key 存入 Keychain；失敗則不變更。")
                }

                settingsBox("資料庫") {
                    Button {
                        viewModel.exportDatabase()
                    } label: {
                        Label("匯出 SQLite DB", systemImage: "square.and.arrow.down")
                    }
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
                        .disabled(viewModel.iCloudIsSyncing)
                        .help("從 iCloud 拉最新一份回來, 跟本機做 3-way merge")
                        Spacer()
                    }
                }

                settingsBox("AI Log") {
                    Button {
                        viewModel.openAIRequestLog()
                    } label: {
                        Label("在 Finder 顯示 AI Log", systemImage: "folder")
                    }
                    Text(AIRequestLogStore.logFileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                settingsBox("更新") {
                    Toggle("自動檢查更新", isOn: $autoCheckUpdates)
                        .help("啟動時若有新版本會跳出提示（每小時最多檢查一次）。")
                    HStack {
                        Button {
                            Task { await UpdateChecker.shared.checkForUpdates(showUpToDate: true) }
                        } label: {
                            Label("立即檢查更新", systemImage: "arrow.down.circle")
                        }
                        Spacer()
                        Text("目前版本 \(UpdateChecker.shared.currentVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Button(role: .destructive) {
                    viewModel.quitApp()
                } label: {
                    Label("結束程式", systemImage: "power")
                }
            }
            .padding()
        }
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

    private func settingsBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Int> {
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
            viewModel.snapshot.settings.providerConfig.preset
        } set: { preset in
            viewModel.applyProviderPreset(preset)
        }
    }

    private func structuredOutputBinding() -> Binding<StructuredOutputMode> {
        Binding {
            viewModel.snapshot.settings.providerConfig.structuredOutput
        } set: { mode in
            var settings = viewModel.snapshot.settings
            settings.providerConfig.structuredOutput = mode
            viewModel.updateSettings(settings)
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
        case articles = "AI 文章"
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
    }

    private var articleList: some View {
        List(viewModel.snapshot.generatedArticles) { article in
            HStack(alignment: .top, spacing: 8) {
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
                ContentUnavailableView("還沒有 AI 文章", systemImage: "doc.text")
            }
        }
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
                }
            }
        }
        .overlay {
            if completedQuizzes.isEmpty {
                ContentUnavailableView("還沒有考試紀錄", systemImage: "checkmark.seal")
            }
        }
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
            return .green
        case .incorrect:
            return .red
        case .skipped:
            return .secondary
        case .pending:
            return .secondary
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
            VStack(alignment: .leading, spacing: 6) {
                Text("AI 文章產生")
                    .font(.title2.weight(.semibold))
                Text("由 AI 撰寫指定 JLPT 等級的日文短文，再自動從中擷取單字卡。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                        .datePickerStyle(.stepperField)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("手動造卡")
                        .font(.title2.weight(.semibold))
                    Text("貼上一段日文文章，或一份單字／片語清單，AI 會理解內容後幫你產生單字卡。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GroupBox("文章或單字清單") {
                    TextEditor(text: $viewModel.manualCardInput)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 180)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
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
