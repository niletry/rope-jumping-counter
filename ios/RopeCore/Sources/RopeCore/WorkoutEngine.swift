import Foundation

/// Drives the workout phases from a monotonic millisecond clock. Port of the Android `WorkoutEngine.kt`.
public final class WorkoutEngine {
    private let config: WorkoutConfig
    private var phase = WorkoutPhase.preparing
    private var phaseStartMs: Int64
    private var pausedAtMs: Int64 = 0
    private var pausedFrom: WorkoutPhase?
    private var activeBeforeCurrentPhaseMs: Int64 = 0
    private var currentGroup = 1
    private var totalCount = 0
    private var groupCount = 0
    private var endedEarly = false

    public init(config: WorkoutConfig, startedAtMs: Int64) {
        self.config = config.normalized()
        self.phaseStartMs = startedAtMs
    }

    @discardableResult
    public func tick(_ nowMs: Int64) -> WorkoutSnapshot {
        switch phase {
        case .preparing, .armed, .paused, .complete:
            // ARMED has no timer: the group starts on the first jump (see recordJump).
            break
        case .active:
            if config.mode == .fixedTime && nowMs - phaseStartMs >= Int64(config.durationPerGroupSec) * 1_000 {
                finishGroup(nowMs)
            }
        case .rest:
            if nowMs - phaseStartMs >= Int64(config.restSec) * 1_000 {
                phase = .armed
                phaseStartMs = nowMs
            }
        }
        return snapshot(nowMs)
    }

    @discardableResult
    public func markPoseReady(_ nowMs: Int64) -> WorkoutSnapshot {
        if phase == .preparing {
            phase = .armed
            phaseStartMs = nowMs
        }
        return snapshot(nowMs)
    }

    @discardableResult
    public func requirePosePreparation(_ nowMs: Int64) -> WorkoutSnapshot {
        if phase == .armed {
            phase = .preparing
            phaseStartMs = nowMs
        }
        return snapshot(nowMs)
    }

    @discardableResult
    public func recordJump(_ nowMs: Int64) -> WorkoutSnapshot {
        tick(nowMs)
        if phase == .armed {
            // The first jump starts the clock and is itself counted.
            phase = .active
            phaseStartMs = nowMs
        }
        if phase != .active { return snapshot(nowMs) }

        totalCount += 1
        groupCount += 1
        if config.mode == .fixedCount && groupCount >= config.targetCountPerGroup {
            finishGroup(nowMs)
        }
        return snapshot(nowMs)
    }

    @discardableResult
    public func togglePause(_ nowMs: Int64) -> WorkoutSnapshot {
        if phase == .paused {
            let restored = pausedFrom ?? .armed
            phaseStartMs += max(nowMs - pausedAtMs, 0)
            phase = restored
            pausedFrom = nil
        } else if phase != .complete {
            pausedFrom = phase
            pausedAtMs = nowMs
            phase = .paused
        }
        return snapshot(nowMs)
    }

    @discardableResult
    public func finishEarly(_ nowMs: Int64) -> WorkoutSnapshot {
        if phase != .complete {
            let effectivePhase = phase == .paused ? pausedFrom : phase
            let effectiveNow = phase == .paused ? pausedAtMs : nowMs
            if effectivePhase == .active {
                activeBeforeCurrentPhaseMs += max(effectiveNow - phaseStartMs, 0)
            }
            phase = .complete
            phaseStartMs = nowMs
            endedEarly = true
            pausedFrom = nil
        }
        return snapshot(nowMs)
    }

    private func finishGroup(_ nowMs: Int64) {
        activeBeforeCurrentPhaseMs += max(nowMs - phaseStartMs, 0)
        if currentGroup >= config.groups || config.mode == .free {
            phase = .complete
            phaseStartMs = nowMs
            return
        }

        currentGroup += 1
        groupCount = 0
        phase = config.restSec == 0 ? .armed : .rest
        phaseStartMs = nowMs
    }

    private func snapshot(_ nowMs: Int64) -> WorkoutSnapshot {
        let referenceNow = phase == .paused ? pausedAtMs : nowMs
        let effectivePhase = phase == .paused ? pausedFrom : phase
        let groupElapsed: Int64 = effectivePhase == .active ? max(referenceNow - phaseStartMs, 0) : 0
        let totalActive = activeBeforeCurrentPhaseMs + groupElapsed

        let remainingSec: Int?
        switch effectivePhase {
        case .rest:
            remainingSec = remainingSeconds(Int64(config.restSec) * 1_000 - (referenceNow - phaseStartMs))
        case .active:
            remainingSec = config.mode == .fixedTime
                ? remainingSeconds(Int64(config.durationPerGroupSec) * 1_000 - groupElapsed)
                : nil
        case .preparing, .armed, .paused, .complete, nil:
            remainingSec = nil
        }

        return WorkoutSnapshot(
            config: config,
            phase: phase,
            currentGroup: currentGroup,
            totalCount: totalCount,
            groupCount: groupCount,
            totalActiveMs: totalActive,
            groupElapsedMs: groupElapsed,
            phaseRemainingSec: remainingSec,
            pausedFrom: pausedFrom,
            endedEarly: endedEarly
        )
    }

    private func remainingSeconds(_ milliseconds: Int64) -> Int {
        Int((Double(max(milliseconds, 0)) / 1_000.0).rounded(.up))
    }
}
