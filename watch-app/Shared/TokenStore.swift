import Foundation

/// Holds the CalProTrack session token locally on the Watch. No App Group
/// or iPhone-side storage — you paste the token directly into the Watch
/// app's Settings tab, so this is deliberately just UserDefaults.standard,
/// which needs no extra entitlements or capabilities.
///
/// Marked `@unchecked Sendable`: it's read from the CalProTrackAPI actor,
/// and UserDefaults itself is already thread-safe, so this is an accurate
/// annotation rather than a workaround — needed under Swift 6's stricter
/// concurrency checking (the default in newer Xcode), harmless otherwise.
final class TokenStore: @unchecked Sendable {
    static let shared = TokenStore()
    private let key = "calprotrack.session_token"

    var token: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    var hasToken: Bool {
        guard let t = token else { return false }
        return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
