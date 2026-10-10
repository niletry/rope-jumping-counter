import Foundation

/// Persistent user preferences, mirroring the Android SharedPreferences keys.
enum Settings {
    private static let countBeepKey = "count_beep_enabled"
    private static let showPreviewKey = "show_preview"

    /// Per-jump beep; off by default because many users find it annoying.
    static var countBeepEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: countBeepKey) }
        set { UserDefaults.standard.set(newValue, forKey: countBeepKey) }
    }

    /// Whether the camera picture (or replay frame) is drawn behind the skeleton. Off = skeleton only.
    static var showPreview: Bool {
        get { UserDefaults.standard.object(forKey: showPreviewKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showPreviewKey) }
    }
}
