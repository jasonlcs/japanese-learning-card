import Foundation

public struct HTMLTextExtractor: Sendable {
    public init() {}

    public func extract(html: String) -> (title: String, text: String) {
        let title = firstMatch(in: html, pattern: #"<title[^>]*>(.*?)</title>"#) ?? ""
        var working = html
        working = replace(pattern: #"(?is)<script[^>]*>.*?</script>"#, in: working, with: " ")
        working = replace(pattern: #"(?is)<style[^>]*>.*?</style>"#, in: working, with: " ")
        working = replace(pattern: #"(?is)<[^>]+>"#, in: working, with: " ")
        working = decodeEntities(working)
        working = working
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return (decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines), working)
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    private func replace(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private func decodeEntities(_ text: String) -> String {
        var decoded = text
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " "
        ]
        for (entity, value) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: value)
        }
        return decoded
    }
}
