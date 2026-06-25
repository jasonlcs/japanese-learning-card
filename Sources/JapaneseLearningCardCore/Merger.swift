import Foundation

/// 一筆 3-way merge 衝突的描述, 給 UI 顯示或讓使用者手動解。
public struct ConflictRecord: Codable, Sendable, Equatable, Identifiable {
    public enum Table: String, Sendable, Codable, CaseIterable {
        case settings
        case sources
        case crawledDocuments
        case learningCards
        case quizQuestions
        case generatedArticles
    }

    public enum Resolution: String, Sendable, Codable {
        case tookLocal
        case tookRemote
    }

    public let id: UUID
    public let table: Table
    public let recordId: String
    public var resolution: Resolution
    /// 衝突時 local 的 record JSON (給 UI 顯示 side-by-side 比較)
    public let localValue: Data
    /// 衝突時 remote 的 record JSON
    public let remoteValue: Data
    /// 衝突時 base 的 record JSON (nil = 新加入的 record 還沒在 base)
    public let baseValue: Data?
    public let createdAt: Date
    /// user 是否已手動處理 (LWW 自動解掉的話預設 false, 點過「選 local/remote」就 true)
    public var isResolved: Bool

    public init(
        id: UUID = UUID(),
        table: Table,
        recordId: String,
        resolution: Resolution,
        localValue: Data,
        remoteValue: Data,
        baseValue: Data?,
        createdAt: Date = Date(),
        isResolved: Bool = false
    ) {
        self.id = id
        self.table = table
        self.recordId = recordId
        self.resolution = resolution
        self.localValue = localValue
        self.remoteValue = remoteValue
        self.baseValue = baseValue
        self.createdAt = createdAt
        self.isResolved = isResolved
    }
}

public struct MergeResult: Sendable {
    public let snapshot: AppSnapshot
    public let conflicts: [ConflictRecord]

    public init(snapshot: AppSnapshot, conflicts: [ConflictRecord]) {
        self.snapshot = snapshot
        self.conflicts = conflicts
    }
}

/// 3-way merge: 拿 local, remote, base 三份 `AppSnapshot`, 對每張表的每筆 record
/// 做 diff, 產出 merged snapshot 與衝突清單。
///
/// 規則:
/// - **Settings** (單筆): 兩邊都改且不同 → 衝突, LWW by `updatedAt`.
/// - **Sources**: 兩邊都改且內容不同 → 衝突, LWW by `updatedAt`. 只其中一邊
///   改過 (另一邊跟 base 相同) → 採改過的那邊, 無衝突.
/// - **CrawledDocuments**: 以 `contentHash` 為 key, 兩邊都有的話
///   `fetchedAt` 取較新的 (monotonic, 通常不會衝突). 內容不同 (同 hash 不可
///   能, 但 defensive) → LWW.
/// - **LearningCards**: 兩邊都改 → 先看是不是「shallow diff」(只有
///   `lastShownAt` / `status` 不同, 多半是兩台各自複習了同一張卡), 這種
///   視為非衝突, 取 `lastShownAt` 較新者. 內容欄位真的不同 → 衝突, LWW.
/// - **QuizQuestions**: 同上, shallow diff 為 `selectedAnswer` /
///   `status` / `answeredAt` 三個欄位的差異.
/// - **GeneratedArticles**: 兩邊都改且內容不同 → 衝突, LWW. 兩邊的
///   `contentHash` 一樣就視為同一篇, 取 `cardCount` 較新者.
///
/// **刪除同步**: PR 1 不處理. 如果 local 刪了某 record, remote 還有,
/// merge 結果會保留 remote 那份; 反之亦然. 真正的刪除同步需要 tombstone,
/// 之後再加.
public enum Merger {
    public static func merge3Way(
        local: AppSnapshot,
        remote: AppSnapshot,
        base: AppSnapshot?
    ) -> MergeResult {
        var conflicts: [ConflictRecord] = []
        let base = base ?? AppSnapshot()

        let mergedSettings = mergeSettings(local: local.settings, remote: remote.settings, base: base.settings, conflicts: &conflicts)
        let mergedSources = mergeSources(local: local.sources, remote: remote.sources, base: base.sources, conflicts: &conflicts)
        let mergedDocuments = mergeDocuments(local: local.documents, remote: remote.documents, base: base.documents, conflicts: &conflicts)
        let mergedCards = mergeCards(local: local.cards, remote: remote.cards, base: base.cards, conflicts: &conflicts)
        let mergedQuizzes = mergeQuizzes(local: local.quizzes, remote: remote.quizzes, base: base.quizzes, conflicts: &conflicts)
        let mergedArticles = mergeArticles(local: local.generatedArticles, remote: remote.generatedArticles, base: base.generatedArticles, conflicts: &conflicts)

        // 軟刪除 tombstones: 三方聯集後, 把出現在任何一方 deleted 清單裡
        // 的 record 從合併結果拿掉。records 陣列在 AppStore 端已經是 live 狀態
        // (被刪的已經不在裡面), 所以這層只負責把遠端 / 別台 Mac 的刪除套
        // 過來。
        let deletedSourceIDs = unionDeleted(local.deletedSources, remote.deletedSources, base.deletedSources)
        let deletedDocHashes = unionDeleted(local.deletedDocuments, remote.deletedDocuments, base.deletedDocuments)
        let deletedCardIDs = unionDeleted(local.deletedCards, remote.deletedCards, base.deletedCards)
        let deletedQuizIDs = unionDeleted(local.deletedQuizzes, remote.deletedQuizzes, base.deletedQuizzes)
        let deletedArticleIDs = unionDeleted(local.deletedArticles, remote.deletedArticles, base.deletedArticles)

        return MergeResult(
            snapshot: AppSnapshot(
                settings: mergedSettings,
                sources: mergedSources.filter { !deletedSourceIDs.contains($0.id) },
                documents: mergedDocuments.filter { !deletedDocHashes.contains($0.contentHash) },
                cards: mergedCards.filter { !deletedCardIDs.contains($0.id) },
                quizzes: mergedQuizzes.filter { !deletedQuizIDs.contains($0.id) },
                generatedArticles: mergedArticles.filter { !deletedArticleIDs.contains($0.id) },
                deletedSources: Array(deletedSourceIDs),
                deletedDocuments: Array(deletedDocHashes),
                deletedCards: Array(deletedCardIDs),
                deletedQuizzes: Array(deletedQuizIDs),
                deletedArticles: Array(deletedArticleIDs)
            ),
            conflicts: conflicts
        )
    }

    private static func unionDeleted<ID: Hashable>(_ a: [ID], _ b: [ID], _ c: [ID]) -> Set<ID> {
        Set(a).union(b).union(c)
    }

    /// 衝突時把 local/remote/base 序列化進 ConflictRecord,
    /// 給 UI side-by-side 顯示用。encode 失敗就回空 Data, 不會讓 merger 整個失敗。
    private static func encodeValue<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(value)
    }

    // MARK: - Settings (single record)

    private static func mergeSettings(
        local: AppSettings,
        remote: AppSettings,
        base: AppSettings,
        conflicts: inout [ConflictRecord]
    ) -> AppSettings {
        if local == remote { return local }
        if local == base { return remote }
        if remote == base { return local }
        let took: AppSettings = local.updatedAt >= remote.updatedAt ? local : remote
        conflicts.append(ConflictRecord(
            table: .settings,
            recordId: "settings",
            resolution: took == local ? .tookLocal : .tookRemote,
            localValue: Self.encodeValue(local) ?? Data(),
            remoteValue: Self.encodeValue(remote) ?? Data(),
            baseValue: Self.encodeValue(base)
        ))
        return took
    }

    // MARK: - Sources (per-id LWW)

    private static func mergeSources(
        local: [Source],
        remote: [Source],
        base: [Source],
        conflicts: inout [ConflictRecord]
    ) -> [Source] {
        let localById = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteById = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let baseById = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        let allIds = Set(localById.keys).union(remoteById.keys).union(baseById.keys)
        var merged: [Source] = []
        for id in allIds {
            let l = localById[id]
            let r = remoteById[id]
            let b = baseById[id]
            switch (l, r, b) {
            case (nil, nil, _): continue
            case (let only?, nil, _), (nil, let only?, _):
                merged.append(only)
            case (let l?, let r?, _):
                if l == r { merged.append(l) }
                else if l == b { merged.append(r) }
                else if r == b { merged.append(l) }
                else {
                    let took = l.updatedAt >= r.updatedAt ? l : r
                    conflicts.append(ConflictRecord(
                        table: .sources,
                        recordId: id.uuidString,
                        resolution: took == l ? .tookLocal : .tookRemote,
                        localValue: Self.encodeValue(l) ?? Data(),
                        remoteValue: Self.encodeValue(r) ?? Data(),
                        baseValue: b.flatMap { Self.encodeValue($0) }
                    ))
                    merged.append(took)
                }
            }
        }
        merged.sort { $0.url.absoluteString < $1.url.absoluteString }
        return merged
    }

    // MARK: - CrawledDocuments (by contentHash)

    private static func mergeDocuments(
        local: [CrawledDocument],
        remote: [CrawledDocument],
        base: [CrawledDocument],
        conflicts: inout [ConflictRecord]
    ) -> [CrawledDocument] {
        let localByHash = Dictionary(uniqueKeysWithValues: local.map { ($0.contentHash, $0) })
        let remoteByHash = Dictionary(uniqueKeysWithValues: remote.map { ($0.contentHash, $0) })
        let baseByHash = Dictionary(uniqueKeysWithValues: base.map { ($0.contentHash, $0) })
        let allHashes = Set(localByHash.keys).union(remoteByHash.keys).union(baseByHash.keys)
        var merged: [CrawledDocument] = []
        for hash in allHashes {
            let l = localByHash[hash]
            let r = remoteByHash[hash]
            let b = baseByHash[hash]
            switch (l, r, b) {
            case (nil, nil, _): continue
            case (let only?, nil, _), (nil, let only?, _):
                merged.append(only)
            case (let l?, let r?, _):
                if l == r { merged.append(l) }
                else if l == b { merged.append(r) }
                else if r == b { merged.append(l) }
                else {
                    // 同 hash 內容理論上相同, 若 updatedAt 不同視為單邊
                    // 重抓, 取較新者不計衝突.
                    let took = l.updatedAt >= r.updatedAt ? l : r
                    merged.append(took)
                }
            }
        }
        merged.sort { $0.fetchedAt > $1.fetchedAt }
        return merged
    }

    // MARK: - LearningCards (shallow diff detection)

    private static func mergeCards(
        local: [LearningCard],
        remote: [LearningCard],
        base: [LearningCard],
        conflicts: inout [ConflictRecord]
    ) -> [LearningCard] {
        let localById = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteById = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let baseById = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        let allIds = Set(localById.keys).union(remoteById.keys).union(baseById.keys)
        var merged: [LearningCard] = []
        for cardId in allIds {
            let l = localById[cardId]
            let r = remoteById[cardId]
            let b = baseById[cardId]
            if l == nil && r == nil { continue }
            if let only = (l ?? r), l == nil || r == nil {
                merged.append(only)
                continue
            }
            guard let l, let r else { continue }
            if l == r {
                merged.append(l)
                continue
            }
            let bValue = b
            if l == bValue {
                merged.append(r)
                continue
            }
            if r == bValue {
                merged.append(l)
                continue
            }
            // 兩邊都跟 base 不同
            if isShallowCardDiff(l, r) {
                var newer = (l.lastShownAt ?? .distantPast) >= (r.lastShownAt ?? .distantPast) ? l : r
                newer.shownCount = max(l.shownCount, r.shownCount)
                merged.append(newer)
                continue
            }
            let took = l.updatedAt >= r.updatedAt ? l : r
            conflicts.append(ConflictRecord(
                table: .learningCards,
                recordId: cardId.uuidString,
                resolution: took == l ? .tookLocal : .tookRemote,
                localValue: Self.encodeValue(l) ?? Data(),
                remoteValue: Self.encodeValue(r) ?? Data(),
                baseValue: b.flatMap { Self.encodeValue($0) }
            ))
            merged.append(took)
        }
        merged.sort { $0.word < $1.word }
        return merged
    }

    private static func isShallowCardDiff(_ a: LearningCard, _ b: LearningCard) -> Bool {
        // 內容欄位相同, 只有 lastShownAt / shownCount / status / updatedAt 變動 →
        // 視為「兩台各自複習了同一張卡」, 不算衝突.
        return a.word == b.word
            && a.reading == b.reading
            && a.partOfSpeech == b.partOfSpeech
            && a.meaningZh == b.meaningZh
            && a.grammarNoteZh == b.grammarNoteZh
            && a.jlptLevel == b.jlptLevel
            && a.verbFormType == b.verbFormType
            && a.exampleJa == b.exampleJa
            && a.exampleReading == b.exampleReading
            && a.exampleZh == b.exampleZh
            && a.sourceUrl == b.sourceUrl
            && a.createdAt == b.createdAt
    }

    // MARK: - QuizQuestions (shallow diff detection)

    private static func mergeQuizzes(
        local: [QuizQuestion],
        remote: [QuizQuestion],
        base: [QuizQuestion],
        conflicts: inout [ConflictRecord]
    ) -> [QuizQuestion] {
        let localById = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteById = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let baseById = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        let allIds = Set(localById.keys).union(remoteById.keys).union(baseById.keys)
        var merged: [QuizQuestion] = []
        for qid in allIds {
            let l = localById[qid]
            let r = remoteById[qid]
            let b = baseById[qid]
            if l == nil && r == nil { continue }
            if let only = (l ?? r), l == nil || r == nil {
                merged.append(only)
                continue
            }
            guard let l, let r else { continue }
            if l == r {
                merged.append(l)
                continue
            }
            let bValue = b
            if l == bValue {
                merged.append(r)
                continue
            }
            if r == bValue {
                merged.append(l)
                continue
            }
            if isShallowQuizDiff(l, r) {
                let newer = (l.answeredAt ?? .distantPast) >= (r.answeredAt ?? .distantPast) ? l : r
                merged.append(newer)
                continue
            }
            let took = l.updatedAt >= r.updatedAt ? l : r
            conflicts.append(ConflictRecord(
                table: .quizQuestions,
                recordId: qid.uuidString,
                resolution: took == l ? .tookLocal : .tookRemote,
                localValue: Self.encodeValue(l) ?? Data(),
                remoteValue: Self.encodeValue(r) ?? Data(),
                baseValue: b.flatMap { Self.encodeValue($0) }
            ))
            merged.append(took)
        }
        merged.sort { $0.createdAt > $1.createdAt }
        return merged
    }

    private static func isShallowQuizDiff(_ a: QuizQuestion, _ b: QuizQuestion) -> Bool {
        return a.cardId == b.cardId
            && a.sourceWord == b.sourceWord
            && a.question == b.question
            && a.choices == b.choices
            && a.correctAnswer == b.correctAnswer
            && a.explanationZh == b.explanationZh
            && a.createdAt == b.createdAt
    }

    // MARK: - GeneratedArticles

    private static func mergeArticles(
        local: [GeneratedArticle],
        remote: [GeneratedArticle],
        base: [GeneratedArticle],
        conflicts: inout [ConflictRecord]
    ) -> [GeneratedArticle] {
        let localById = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteById = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let baseById = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        let allIds = Set(localById.keys).union(remoteById.keys).union(baseById.keys)
        var merged: [GeneratedArticle] = []
        for aid in allIds {
            let l = localById[aid]
            let r = remoteById[aid]
            let b = baseById[aid]
            if l == nil && r == nil { continue }
            if let only = (l ?? r), l == nil || r == nil {
                merged.append(only)
                continue
            }
            guard let l, let r else { continue }
            if l == r {
                merged.append(l)
                continue
            }
            let bValue = b
            if l == bValue {
                merged.append(r)
                continue
            }
            if r == bValue {
                merged.append(l)
                continue
            }
            // contentHash 相同 → 視為同一篇, 不算衝突, 取較新的 cardCount
            if l.contentHash == r.contentHash {
                let newer = l.generatedAt >= r.generatedAt ? l : r
                merged.append(newer)
                continue
            }
            let took = l.updatedAt >= r.updatedAt ? l : r
            conflicts.append(ConflictRecord(
                table: .generatedArticles,
                recordId: aid.uuidString,
                resolution: took == l ? .tookLocal : .tookRemote,
                localValue: Self.encodeValue(l) ?? Data(),
                remoteValue: Self.encodeValue(r) ?? Data(),
                baseValue: b.flatMap { Self.encodeValue($0) }
            ))
            merged.append(took)
        }
        merged.sort { $0.generatedAt > $1.generatedAt }
        return merged
    }
}
