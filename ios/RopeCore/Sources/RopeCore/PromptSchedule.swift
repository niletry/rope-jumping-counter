import Foundation

/// The two milestone prompts: "加油" every 10 jumps, "真棒" every 100.
public enum VoicePromptKind: String, CaseIterable, Sendable {
    case cheer
    case bravo
}

public enum PromptSchedule {
    public static let cheerEvery = 10
    public static let bravoEvery = 100

    /// Which prompt, if any, a count change from `before` to `after` should trigger.
    public static func prompt(before: Int, after: Int) -> VoicePromptKind? {
        if after / bravoEvery > before / bravoEvery { return .bravo }
        if after / cheerEvery > before / cheerEvery { return .cheer }
        return nil
    }
}
