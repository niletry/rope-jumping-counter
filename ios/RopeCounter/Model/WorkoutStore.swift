import Foundation
import QuartzCore
import SwiftUI
import RopeCore

enum AppScreen {
    case setup, workout, history
}

/// Central state, a port of the Android RopeCounterViewModel. Everything UI-facing is on the
/// main actor; the pose processor calls back from its own thread and hops over.
@MainActor
@Observable
final class WorkoutStore {
    var screen: AppScreen = .setup
    var config = WorkoutConfig()
    var workout: WorkoutSnapshot?
    var poseFrame: PoseFrame?
    var detection: JumpDetection?
    var lens: CameraSession.Lens = .front
    var errorMessage: String?
    var history: [WorkoutRecord] = []
    var customVoices: Set<VoicePromptKind> = []
    var recording: VoicePromptKind?
    var countBeepEnabled = false
    /// Draw the camera picture behind the skeleton; off shows the skeleton alone on black.
    var showPreview = true
    var cameraDenied = false
    /// Debug replay: directory of JPEG frames passed as `-replayDir` on launch.
    let replayDir: URL?
    /// Debug replay: `-replayRuns N` replays the frames N times as back-to-back workouts.
    private var replayRunsLeft: Int
    var replayProgress: ReplaySource.Progress?
    var delegateName = ""

    let camera = CameraSession()
    private let historyStore = SessionHistoryStore(directory: AppDirectories.documents)
    private let feedback = FeedbackPlayer()
    private let recorder = VoiceRecorder()
    private let detector = JumpDetector()
    private var processor: PoseLandmarkerProcessor?
    private var replay: ReplaySource?
    private var engine: WorkoutEngine?
    private var sessionStartedAtEpochMs: Int64 = 0
    private var sessionSaved = false
    private var lastGuidancePrompt: String?
    private var lastGuidancePromptAtMs: Int64 = Int64.min / 2
    private var clock: Timer?
    /// Read from the camera thread; only the main actor writes it.
    nonisolated(unsafe) private var analyzeFrames = false

    private static let guidanceReminderMs: Int64 = 5_000

    init(replayDir: URL? = nil, replayRuns: Int = 1) {
        self.replayDir = replayDir
        replayRunsLeft = replayRuns
        history = historyStore.load()
        countBeepEnabled = Settings.countBeepEnabled
        showPreview = Settings.showPreview
        feedback.countBeepEnabled = countBeepEnabled
        refreshCustomVoices()
        clock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateClock() }
        }
        camera.shouldAnalyze = { [weak self] in self?.analyzeFrames ?? false }
        camera.onError = { [weak self] message in self?.showError(message) }
    }

    static func nowMs() -> Int64 { Int64(CACurrentMediaTime() * 1_000) }

    // MARK: - Workout lifecycle

    func startWorkout() {
        let now = Self.nowMs()
        let normalized = config.normalized()
        detector.reset()
        engine = WorkoutEngine(config: normalized, startedAtMs: now)
        sessionStartedAtEpochMs = Int64(Date().timeIntervalSince1970 * 1_000)
        sessionSaved = false
        lastGuidancePrompt = nil
        lastGuidancePromptAtMs = Int64.min / 2
        feedback.stopSpeech()
        screen = .workout
        config = normalized
        workout = engine?.tick(now)
        poseFrame = nil
        detection = nil
        errorMessage = nil
        replayProgress = nil
        analyzeFrames = true
        UIApplication.shared.isIdleTimerDisabled = true
        createProcessor()
        if let replayDir, let processor {
            let source = ReplaySource(directory: replayDir, processor: processor) { [weak self] p in
                self?.replayProgress = p
                if p.finished { self?.replayFinished() }
            }
            replay = source
            source.start()
        } else {
            CameraSession.requestAccess { [weak self] granted in
                guard let self else { return }
                cameraDenied = !granted
                if granted {
                    camera.configure(lens: lens)
                    camera.start()
                }
            }
        }
    }

    /// One landmarker for the whole app, unlike Android: releasing one on iOS blocks the main
    /// thread inside MediaPipe's stats upload, which froze the second workout. The processor
    /// keeps its own timestamps increasing across workouts.
    private func createProcessor() {
        replay?.stop()
        replay = nil
        guard processor == nil else { return }
        do {
            processor = try PoseLandmarkerProcessor(
                onResult: { [weak self] frame in
                    Task { @MainActor in self?.onPoseFrame(frame) }
                },
                onError: { [weak self] message in
                    Task { @MainActor in self?.showError(message) }
                }
            )
            delegateName = processor?.delegateName ?? ""
            camera.processor = processor
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func replayFinished() {
        guard analyzeFrames else { return }
        analyzeFrames = false
        replayRunsLeft -= 1
        NSLog("Replay finished: \(workout?.totalCount ?? 0) jumps, \(replayRunsLeft) runs left")
        guard replayRunsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            finishWorkout()
            returnToSetup()
            startWorkout()
        }
    }

    func onPoseFrame(_ frame: PoseFrame) {
        replay?.record(frame)
        guard let currentWorkout = workout else { return }
        let shouldDetect = currentWorkout.phase == .preparing || currentWorkout.phase == .armed || currentWorkout.phase == .active
        guard shouldDetect else {
            poseFrame = frame
            return
        }

        let detection = detector.process(frame)
        let now = Self.nowMs()
        announceGuidance(detection.guidance, now)
        var snapshot: WorkoutSnapshot? = currentWorkout
        if currentWorkout.phase == .preparing && detection.state == .ready {
            snapshot = engine?.markPoseReady(now)
            feedback.phaseChanged()
        } else if currentWorkout.phase == .armed && (detection.state == .calibrating || detection.state == .lost) {
            snapshot = engine?.requirePosePreparation(now)
        } else if detection.jumpDetected && (currentWorkout.phase == .active || currentWorkout.phase == .armed) {
            // Calibration replay can report more than one jump in a single frame.
            let before = currentWorkout.totalCount
            for _ in 0..<detection.jumpCount { snapshot = engine?.recordJump(now) }
            if currentWorkout.phase == .armed { feedback.speakStart() }
            feedback.jump()
            let after = snapshot?.totalCount ?? before
            if let prompt = PromptSchedule.prompt(before: before, after: after) {
                feedback.speakPrompt(prompt)
            }
        }
        poseFrame = frame
        self.detection = detection
        workout = snapshot
        updateAnalyzeFlag()
        maybeSaveCompleted(snapshot)
    }

    func togglePause() {
        guard let snapshot = engine?.togglePause(Self.nowMs()) else { return }
        workout = snapshot
        updateAnalyzeFlag()
    }

    func finishWorkout() {
        guard let snapshot = engine?.finishEarly(Self.nowMs()) else { return }
        workout = snapshot
        updateAnalyzeFlag()
        maybeSaveCompleted(snapshot)
    }

    func returnToSetup() {
        engine = nil
        detector.reset()
        feedback.stopSpeech()
        analyzeFrames = false
        replay?.stop()
        replay = nil
        camera.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        screen = .setup
        workout = nil
        poseFrame = nil
        detection = nil
        errorMessage = nil
        history = historyStore.load()
    }

    func openHistory() {
        history = historyStore.load()
        screen = .history
    }

    func closeHistory() {
        screen = .setup
    }

    func clearHistory() {
        historyStore.clear()
        history = []
    }

    func switchCamera() {
        lens = lens == .front ? .back : .front
        poseFrame = nil
        detection = nil
        detector.reset()
        camera.switchLens()
    }

    // MARK: - Voice prompts and settings

    private func refreshCustomVoices() {
        customVoices = Set(VoicePrompt.all.filter(\.hasCustomRecording).map(\.kind))
    }

    func startRecording(_ kind: VoicePromptKind) {
        let prompt = VoicePrompt(kind: kind)
        feedback.suspendForRecording()
        do {
            try recorder.start(file: prompt.customFileURL) { [weak self] in self?.onRecordingFinished() }
        } catch {
            feedback.resumeAfterRecording()
            showError("无法开始录音：\(error.localizedDescription)")
            return
        }
        recording = kind
    }

    func stopRecording() {
        recorder.stop()
    }

    private func onRecordingFinished() {
        feedback.resumeAfterRecording()
        feedback.reloadPrompts()
        recording = nil
        refreshCustomVoices()
    }

    func resetVoice(_ kind: VoicePromptKind) {
        if recorder.isRecording { recorder.stop(discard: true) }
        try? FileManager.default.removeItem(at: VoicePrompt(kind: kind).customFileURL)
        feedback.reloadPrompts()
        recording = nil
        refreshCustomVoices()
    }

    func previewVoice(_ kind: VoicePromptKind) {
        feedback.speakPrompt(kind)
    }

    func setCountBeepEnabled(_ enabled: Bool) {
        Settings.countBeepEnabled = enabled
        feedback.countBeepEnabled = enabled
        countBeepEnabled = enabled
        if enabled { feedback.jump() }
    }

    func setShowPreview(_ enabled: Bool) {
        Settings.showPreview = enabled
        showPreview = enabled
    }

    func showError(_ message: String) {
        errorMessage = message
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Internals

    private func updateAnalyzeFlag() {
        let phase = workout?.phase
        analyzeFrames = phase != nil && phase != .complete && phase != .paused && phase != .rest
    }

    private func updateClock() {
        guard let engine else { return }
        let previous = workout
        let updated = engine.tick(Self.nowMs())
        if previous?.phase != updated.phase, [.active, .rest, .complete].contains(updated.phase) {
            feedback.phaseChanged()
        }
        workout = updated
        updateAnalyzeFlag()
        maybeSaveCompleted(updated)
    }

    private func announceGuidance(_ guidance: String, _ nowMs: Int64) {
        let prompt: String
        if guidance.hasPrefix("请保持全身入镜") {
            prompt = "请保持全身入镜"
        } else if guidance.hasPrefix("请站稳") {
            prompt = "请站稳"
        } else {
            return
        }
        let changed = prompt != lastGuidancePrompt
        let reminderDue = nowMs - lastGuidancePromptAtMs >= Self.guidanceReminderMs
        if changed || reminderDue {
            feedback.speakGuidance(prompt)
            lastGuidancePrompt = prompt
            lastGuidancePromptAtMs = nowMs
        }
    }

    private func maybeSaveCompleted(_ snapshot: WorkoutSnapshot?) {
        guard let snapshot, snapshot.phase == .complete, !sessionSaved else { return }
        sessionSaved = true
        let completedGroups = snapshot.endedEarly ? max(snapshot.currentGroup - 1, 0) : snapshot.config.groups
        historyStore.prepend(WorkoutRecord(
            id: sessionStartedAtEpochMs,
            startedAtEpochMs: sessionStartedAtEpochMs,
            mode: snapshot.config.mode,
            totalCount: snapshot.totalCount,
            completedGroups: completedGroups,
            plannedGroups: snapshot.config.groups,
            activeDurationMs: snapshot.totalActiveMs,
            completed: !snapshot.endedEarly || snapshot.config.mode == .free
        ))
        history = historyStore.load()
    }
}
