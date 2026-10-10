import Foundation

public enum WorkoutMode: String, Codable, CaseIterable, Sendable {
    case fixedCount = "FIXED_COUNT"
    case fixedTime = "FIXED_TIME"
    case free = "FREE"

    public var title: String {
        switch self {
        case .fixedCount: return "定数跳"
        case .fixedTime: return "定时跳"
        case .free: return "自由跳绳"
        }
    }

    public var subtitle: String {
        switch self {
        case .fixedCount: return "每组完成指定次数"
        case .fixedTime: return "每组持续指定时间"
        case .free: return "持续到主动结束"
        }
    }
}

public struct WorkoutConfig: Equatable, Sendable {
    public var mode: WorkoutMode
    public var targetCountPerGroup: Int
    public var durationPerGroupSec: Int
    public var groups: Int
    public var restSec: Int

    public init(mode: WorkoutMode = .fixedCount, targetCountPerGroup: Int = 100, durationPerGroupSec: Int = 60, groups: Int = 3, restSec: Int = 60) {
        self.mode = mode
        self.targetCountPerGroup = targetCountPerGroup
        self.durationPerGroupSec = durationPerGroupSec
        self.groups = groups
        self.restSec = restSec
    }

    public func normalized() -> WorkoutConfig {
        var copy = self
        copy.targetCountPerGroup = min(max(targetCountPerGroup, 1), 9_999)
        copy.durationPerGroupSec = min(max(durationPerGroupSec, 5), 3_600)
        copy.groups = mode == .free ? 1 : min(max(groups, 1), 99)
        copy.restSec = mode == .free ? 0 : min(max(restSec, 0), 1_800)
        return copy
    }
}

public enum WorkoutPhase: Sendable {
    case preparing
    /// Calibrated; timing and counting start with the first detected jump.
    case armed
    case active
    case rest
    case paused
    case complete
}

public struct WorkoutSnapshot: Equatable, Sendable {
    public var config: WorkoutConfig
    public var phase: WorkoutPhase
    public var currentGroup: Int
    public var totalCount: Int
    public var groupCount: Int
    public var totalActiveMs: Int64
    public var groupElapsedMs: Int64
    public var phaseRemainingSec: Int?
    public var pausedFrom: WorkoutPhase?
    public var endedEarly: Bool

    public init(config: WorkoutConfig, phase: WorkoutPhase, currentGroup: Int, totalCount: Int, groupCount: Int, totalActiveMs: Int64, groupElapsedMs: Int64, phaseRemainingSec: Int?, pausedFrom: WorkoutPhase? = nil, endedEarly: Bool = false) {
        self.config = config
        self.phase = phase
        self.currentGroup = currentGroup
        self.totalCount = totalCount
        self.groupCount = groupCount
        self.totalActiveMs = totalActiveMs
        self.groupElapsedMs = groupElapsedMs
        self.phaseRemainingSec = phaseRemainingSec
        self.pausedFrom = pausedFrom
        self.endedEarly = endedEarly
    }
}

public struct WorkoutRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64
    public var startedAtEpochMs: Int64
    public var mode: WorkoutMode
    public var totalCount: Int
    public var completedGroups: Int
    public var plannedGroups: Int
    public var activeDurationMs: Int64
    public var completed: Bool

    public init(id: Int64, startedAtEpochMs: Int64, mode: WorkoutMode, totalCount: Int, completedGroups: Int, plannedGroups: Int, activeDurationMs: Int64, completed: Bool) {
        self.id = id
        self.startedAtEpochMs = startedAtEpochMs
        self.mode = mode
        self.totalCount = totalCount
        self.completedGroups = completedGroups
        self.plannedGroups = plannedGroups
        self.activeDurationMs = activeDurationMs
        self.completed = completed
    }
}
