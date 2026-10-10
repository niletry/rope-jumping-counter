import Foundation
import RopeCore

/// A milestone prompt the user can hear as the bundled default or replace with their own recording.
struct VoicePrompt: Identifiable, Hashable {
    let kind: VoicePromptKind

    var id: VoicePromptKind { kind }

    static let all = VoicePromptKind.allCases.map(VoicePrompt.init)

    /// Shown as the row title in settings: how often it plays.
    var label: String {
        switch kind {
        case .cheer: return "每 \(PromptSchedule.cheerEvery) 次"
        case .bravo: return "每 \(PromptSchedule.bravoEvery) 次"
        }
    }

    /// The default voice line, shown under the title.
    var hint: String {
        switch kind {
        case .cheer: return "默认“加油”"
        case .bravo: return "默认“真棒”"
        }
    }

    var defaultResource: String {
        switch kind {
        case .cheer: return "prompt_cheer"
        case .bravo: return "prompt_bravo"
        }
    }

    /// Where the user's own recording lives when it exists.
    var customFileURL: URL {
        let name = kind == .cheer ? "voice_cheer.m4a" : "voice_bravo.m4a"
        return AppDirectories.documents.appendingPathComponent(name)
    }

    var hasCustomRecording: Bool {
        FileManager.default.fileExists(atPath: customFileURL.path)
    }
}

enum AppDirectories {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
