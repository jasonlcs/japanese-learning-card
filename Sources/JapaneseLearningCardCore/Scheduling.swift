import Foundation

public struct SchedulerPolicy: Sendable {
    public init() {}

    public func displayInterval(settings: AppSettings) -> TimeInterval {
        TimeInterval(max(1, settings.displayIntervalMinutes) * 60)
    }

    public func visibleDuration(settings: AppSettings) -> TimeInterval {
        TimeInterval(max(3, settings.visibleDurationSeconds))
    }

    public func crawlInterval(settings: AppSettings) -> TimeInterval {
        TimeInterval(max(1, settings.crawlIntervalHours) * 60 * 60)
    }
}

public struct CardSelector: Sendable {
    public init() {}

    public func nextCard(from cards: [LearningCard], now: Date = Date()) -> LearningCard? {
        let candidates = cards.filter { $0.status != .skipped && $0.status != .learned }
        if let fresh = candidates
            .filter({ $0.status == .new && $0.lastShownAt == nil })
            .sorted(by: { $0.createdAt < $1.createdAt })
            .first {
            return fresh
        }

        if let reviewing = candidates
            .filter({ $0.status == .reviewing || $0.status == .new })
            .sorted(by: { ($0.lastShownAt ?? .distantPast) < ($1.lastShownAt ?? .distantPast) })
            .first {
            return reviewing
        }

        return candidates
            .sorted(by: { ($0.lastShownAt ?? now) < ($1.lastShownAt ?? now) })
            .first
    }
}
