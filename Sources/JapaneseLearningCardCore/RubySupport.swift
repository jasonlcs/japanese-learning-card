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
}
