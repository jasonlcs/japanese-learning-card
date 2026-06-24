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

    /// 依排程時間與星期幾，計算下一次 AI 文章產生的時刻。
    /// 回傳 nil 代表沒有任何已選的星期幾（不會觸發）。
    public func nextAIArticleFireDate(
        settings: AppSettings,
        after now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let weekdays = AppSettings.normalizeWeekdays(settings.aiArticleWeekdays)
        guard !weekdays.isEmpty else { return nil }

        let hour = AppSettings.clampHour(settings.aiArticleScheduleHour)
        let minute = AppSettings.clampMinute(settings.aiArticleScheduleMinute)

        // 從今天起最多往後找 7 天，挑出第一個符合星期幾且晚於 now 的時刻。
        for dayOffset in 0...7 {
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                let candidate = calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: day
                )
            else { continue }
            if candidate > now, weekdays.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
        }
        return nil
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
