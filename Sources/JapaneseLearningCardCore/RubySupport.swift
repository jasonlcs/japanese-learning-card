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
