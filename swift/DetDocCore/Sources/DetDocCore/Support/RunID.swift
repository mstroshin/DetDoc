import Foundation

public enum RunID {
    public static func create(mode: RunMode, now: Date = Date(), uuid: UUID = UUID()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let timestamp = formatter.string(from: now)
        let prefix = mode == .run ? "run" : "fix"
        let hex = uuid.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(8)
        return "\(timestamp)-\(prefix)-\(hex)"
    }
}
