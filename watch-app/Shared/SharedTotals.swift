import Foundation

/// Snapshot of today's totals, written by the main app after every
/// meal load/save and read by the CalProTrackWidget complication. The two
/// targets run in separate sandboxes and can't share `UserDefaults.standard`
/// — this goes through the shared App Group container instead.
///
/// Add this file to BOTH the "CalProWatch Watch App" and "CalProTrackWidget"
/// targets (File Inspector → Target Membership) since both read/write it.
struct TodayTotals: Codable {
    var cal: Int
    var pro: Int
    var updatedAt: Date
}

enum SharedTotals {
    private static let appGroupId = "group.bmdahmen.CalProWatch"
    private static let key = "calprotrack.today_totals"

    static func save(_ totals: TodayTotals) {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = try? JSONEncoder().encode(totals) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> TodayTotals? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TodayTotals.self, from: data)
    }
}
