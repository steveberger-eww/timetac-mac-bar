import Foundation

public enum TimeTacTime {
    /// TimeTac sends wall-clock timestamps like `2021-05-11 11:37:30` with the zone in a sibling
    /// field, so a bare parse would land in the wrong instant. Zone must be supplied separately.
    public static func parse(_ string: String?, timeZone identifier: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }

        let zone = identifier.flatMap(TimeZone.init(identifier:)) ?? .current

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }

        // Fall back to ISO8601 in case a field ever carries its own offset.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: string)
    }

    /// `yyyy-MM-dd HH:mm:ss` in the given zone — the format TimeTac expects back.
    public static func wallClock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public enum DurationFormat {
    /// `2:14` / `12:05` — what sits in the menu bar. Hours are not zero-padded so the item
    /// doesn't jitter in width more than it has to.
    public static func compact(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }

    /// `2h 14m` / `14m` — for prose inside the dropdown.
    public static func long(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// `08:15` — clock time in the user's locale.
    public static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
