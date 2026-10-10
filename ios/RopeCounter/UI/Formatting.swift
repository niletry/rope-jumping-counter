import Foundation

func formatClock(_ milliseconds: Int64) -> String {
    let totalSeconds = max(milliseconds / 1_000, 0)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
}

func formatShortDuration(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds) 秒" }
    if seconds % 60 == 0 { return "\(seconds / 60) 分钟" }
    return "\(seconds / 60)分\(seconds % 60)秒"
}
