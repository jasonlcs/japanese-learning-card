import Foundation

public enum RubySupport {
    public static let migrationId = "ruby-v1"

    public static func normalizedBase(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isUsable(_ segments: [RubySegment], for text: String) -> Bool {
        guard !segments.isEmpty else { return false }
        let reconstructed = segments.map(\.base).joined()
        return normalizedBase(reconstructed) == normalizedBase(text)
    }

    public static func validated(_ segments: [RubySegment]?, for text: String) -> [RubySegment] {
        guard let segments, isUsable(segments, for: text) else { return [] }
        return segments
    }

    /// 移除 LLM 沿用 Markdown 習慣輸出的 **強調** 標記。
    /// App 沒有任何地方渲染 Markdown，星號會原樣顯示在畫面與匯出檔，
    /// 也會讓注音 base 拼接與原文對不上而整段被丟棄。
    public static func strippingEmphasis(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }

    /// 嘗試修復模型偶爾漏掉標點/空白造成的 base 拼接誤差：
    /// 只在「原文比拼接多出的字元全部是標點、空白等非文字字元，且缺漏位置
    /// 恰好落在既有 segment 邊界」時才補上一個無 ruby 的 segment；
    /// 只要牽涉到漢字/假名等實際內容不符，一律回傳 nil，交由呼叫端做原文錨定重建。
    public static func repaired(_ segments: [RubySegment], toMatch text: String) -> [RubySegment]? {
        guard !segments.isEmpty else { return nil }
        let joined = segments.map(\.base).joined()
        guard joined != text else { return segments }

        let origChars = Array(text)
        let joinedChars = Array(joined)
        var insertionsByPosition: [Int: [Character]] = [:]
        var i = 0, j = 0
        while i < origChars.count && j < joinedChars.count {
            if origChars[i] == joinedChars[j] {
                i += 1
                j += 1
            } else if isRepairableGap(origChars[i]) {
                insertionsByPosition[j, default: []].append(origChars[i])
                i += 1
            } else {
                return nil
            }
        }
        while i < origChars.count {
            guard isRepairableGap(origChars[i]) else { return nil }
            insertionsByPosition[j, default: []].append(origChars[i])
            i += 1
        }
        guard j == joinedChars.count, !insertionsByPosition.isEmpty else { return nil }

        var result: [RubySegment] = []
        var pos = 0
        for segment in segments {
            if let toInsert = insertionsByPosition[pos] {
                result.append(contentsOf: toInsert.map { RubySegment(base: String($0)) })
            }
            result.append(segment)
            pos += segment.base.count
        }
        if let trailing = insertionsByPosition[pos] {
            result.append(contentsOf: trailing.map { RubySegment(base: String($0)) })
        }

        guard isUsable(result, for: text) else { return nil }
        return result
    }

    /// 以原文為唯一可信來源重建 ruby segments。
    /// 模型回覆的 base 只用來定位可保留的 ruby；任何缺漏、改寫或多餘內容都不會進入結果。
    /// 回傳值對非空原文一律可拼回原文，避免呼叫端因拼接不符而丟掉整段。
    public static func reconciled(_ segments: [RubySegment], toMatch text: String) -> [RubySegment] {
        let original = normalizedBase(text)
        guard !original.isEmpty else { return [] }
        guard !isUsable(segments, for: original) else { return segments }

        var result: [RubySegment] = []
        var searchStart = original.startIndex

        for segment in segments {
            let base = normalizedBase(segment.base)
            guard !base.isEmpty,
                  let range = original.range(of: base, range: searchStart..<original.endIndex)
            else {
                continue
            }

            appendPlain(original[searchStart..<range.lowerBound], to: &result)
            appendSegment(RubySegment(base: String(original[range]), ruby: segment.ruby), to: &result)
            searchStart = range.upperBound
        }

        appendPlain(original[searchStart..<original.endIndex], to: &result)

        guard isUsable(result, for: original) else {
            return [RubySegment(base: original, ruby: "")]
        }
        return result
    }

    private static func appendPlain(_ substring: Substring, to result: inout [RubySegment]) {
        guard !substring.isEmpty else { return }
        appendSegment(RubySegment(base: String(substring), ruby: ""), to: &result)
    }

    private static func appendSegment(_ segment: RubySegment, to result: inout [RubySegment]) {
        guard !segment.base.isEmpty else { return }
        result.append(segment)
    }

    /// 缺漏的字元必須是標點/空白等不需要注音的字元，漢字、假名、英數字一律不修復。
    private static func isRepairableGap(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber
    }

    /// 找出 words 在 text 中所有出現位置（以 Character 為單位的 offset 區間），
    /// 供 UI 高亮融入的單字。相鄰或重疊的命中會合併成一個區間。
    public static func highlightRanges(in text: String, words: [String]) -> [Range<Int>] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        var flags = [Bool](repeating: false, count: characters.count)
        for word in words {
            let target = Array(word.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !target.isEmpty, target.count <= characters.count else { continue }
            var start = 0
            while start <= characters.count - target.count {
                if Array(characters[start..<(start + target.count)]) == target {
                    for index in start..<(start + target.count) { flags[index] = true }
                    start += target.count
                } else {
                    start += 1
                }
            }
        }

        var ranges: [Range<Int>] = []
        var runStart: Int?
        for (index, isHit) in flags.enumerated() {
            if isHit {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                ranges.append(start..<index)
                runStart = nil
            }
        }
        if let start = runStart {
            ranges.append(start..<flags.count)
        }
        return ranges
    }

    /// 依 segments 的 base 串接位置，回傳每個 segment 是否落在高亮範圍內。
    /// 單字跨越多個 segment 時，覆蓋到的 segment 全部標記。
    public static func highlightFlags(for segments: [RubySegment], words: [String]) -> [Bool] {
        guard !segments.isEmpty, !words.isEmpty else {
            return [Bool](repeating: false, count: segments.count)
        }
        let text = segments.map(\.base).joined()
        let ranges = highlightRanges(in: text, words: words)
        guard !ranges.isEmpty else {
            return [Bool](repeating: false, count: segments.count)
        }
        var flags: [Bool] = []
        var offset = 0
        for segment in segments {
            let segmentRange = offset..<(offset + segment.base.count)
            flags.append(ranges.contains { $0.overlaps(segmentRange) })
            offset = segmentRange.upperBound
        }
        return flags
    }
}
