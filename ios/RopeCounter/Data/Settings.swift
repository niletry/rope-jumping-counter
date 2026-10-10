import Foundation

/// Persistent user preferences, mirroring the Android SharedPreferences keys.
enum Settings {
    private static let countBeepKey = "count_beep_enabled"

    /// Per-jump beep; off by default because many users find it annoying.
    static var countBeepEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: countBeepKey) }
        set { UserDefaults.standard.set(newValue, forKey: countBeepKey) }
    }
}
