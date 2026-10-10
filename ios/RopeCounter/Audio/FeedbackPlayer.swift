import AVFoundation
import UIKit
import RopeCore

/// Plays the bundled prompts and the user's own recordings. Never uses TTS or the network.
final class FeedbackPlayer {
    private var players: [String: AVAudioPlayer] = [:]
    private var promptPlayers: [VoicePromptKind: AVAudioPlayer] = [:]
    private var activeVoice: AVAudioPlayer?
    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    /// Per-jump beep; off by default because many users find it annoying.
    var countBeepEnabled = false

    init() {
        // Playback category: audible with the ring/silent switch muted and mixes with music,
        // the same role the media stream plays on Android.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        for name in ["count_beep", "prompt_stand", "prompt_full_body", "prompt_start"] {
            players[name] = Self.bundledPlayer(named: name)
        }
        reloadPrompts()
        haptics.prepare()
    }

    func jump() {
        guard countBeepEnabled, let beep = players["count_beep"] else { return }
        beep.currentTime = 0
        beep.play()
    }

    func phaseChanged() {
        haptics.impactOccurred()
    }

    func speakGuidance(_ message: String) {
        switch message {
        case "请站稳": playVoice(players["prompt_stand"])
        case "请保持全身入镜": playVoice(players["prompt_full_body"])
        default: break
        }
    }

    func speakStart() {
        playVoice(players["prompt_start"])
    }

    /// (Re)loads milestone prompts, preferring a user recording over the bundled default.
    /// A recording that cannot be decoded falls back to the default instead of going silent.
    func reloadPrompts() {
        for prompt in VoicePrompt.all {
            let custom = prompt.hasCustomRecording ? try? AVAudioPlayer(contentsOf: prompt.customFileURL) : nil
            let player = custom ?? Self.bundledPlayer(named: prompt.defaultResource)
            player?.prepareToPlay()
            promptPlayers[prompt.kind] = player
        }
    }

    /// Plays a milestone prompt ("加油" every 10, "真棒" every 100, or the user's own recording).
    func speakPrompt(_ kind: VoicePromptKind) {
        playVoice(promptPlayers[kind])
    }

    func stopSpeech() {
        activeVoice?.stop()
        activeVoice = nil
    }

    /// Releases the audio session while recording so the microphone can take over.
    func suspendForRecording() {
        stopSpeech()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func resumeAfterRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func playVoice(_ player: AVAudioPlayer?) {
        guard let player else { return }
        stopSpeech()
        player.currentTime = 0
        player.play()
        activeVoice = player
    }

    private static func bundledPlayer(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }
}
