import Foundation

// MARK: - 日期工具

/// 所有日期处理统一使用用户本地时区，日期归属以"开始时间的本地日期"为准。
enum DateHelper {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f
    }()

    static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "M月d日"
        return f
    }()

    /// Date → "yyyy-MM-dd"（本地时区）
    static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// "yyyy-MM-dd" → Date（当天本地时区 00:00）
    static func date(from dateString: String) -> Date? {
        dateFormatter.date(from: dateString)
    }

    static var todayString: String { dateString(from: Date()) }

    /// 相对今天的天数差：今天 = 0，昨天 = -1
    static func daysFromToday(_ dateString: String) -> Int? {
        guard let date = date(from: dateString) else { return nil }
        let startOfTarget = Calendar.current.startOfDay(for: date)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: startOfToday, to: startOfTarget).day
    }

    /// 列表分组标题：今天 / 昨天 / 8月27日 周三 / 2025年8月27日
    static func groupTitle(for dateString: String) -> String {
        guard let date = date(from: dateString) else { return dateString }
        let days = daysFromToday(dateString) ?? 0
        if days == 0 { return "今天" }
        if days == -1 { return "昨天" }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        let components = Calendar.current.dateComponents([.year], from: date, to: Date())
        let sameYear = components.year == 0
        formatter.dateFormat = sameYear ? "M月d日 EEEE" : "yyyy年M月d日"
        return formatter.string(from: date)
    }

    /// 本周（周一为起点）的日期字符串数组，周一 → 周日
    static func currentWeekDateStrings(reference: Date = Date()) -> [String] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // 周一
        let today = calendar.startOfDay(for: reference)
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return [dateString(from: today)]
        }
        var result: [String] = []
        var cursor = weekInterval.start
        while cursor < weekInterval.end {
            result.append(dateString(from: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// 本周每天的星期简称（周一 → 周日），用于图表 X 轴
    static func weekdaySymbols() -> [String] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let symbols = calendar.shortWeekdaySymbols // ["周日","周一",...] 依 locale
        // shortWeekdaySymbols 以周日为首位，按 firstWeekday=2 重排为周一起始
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[1...6]) + [symbols[0]]
    }

    /// 把 24 小时制的 hour/minute 组合成"下一个"触发日期（若已过则顺延到明天）
    static func nextDate(hour: Int, minute: Int, from now: Date = Date()) -> Date? {
        Calendar.current.nextDate(after: now,
                                  matching: DateComponents(hour: hour, minute: minute),
                                  matchingPolicy: .nextTime)
    }
}

// MARK: - 格式化扩展

extension Int {
    /// 秒 → "12:34" 或 "1:02:03"
    var formattedDuration: String {
        let h = self / 3600
        let m = (self % 3600) / 60
        let s = self % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// 秒 → "20 分钟"
    var minutesText: String { "\(self / 60) 分钟" }
}
