import SwiftUI
import RopeCore

struct WorkoutScreen: View {
    @Bindable var store: WorkoutStore
    @State private var showEndDialog = false

    var body: some View {
        if let workout = store.workout {
            ZStack {
                Color.black.ignoresSafeArea()
                if store.replayDir == nil && store.cameraDenied {
                    Text("没有摄像头权限，请在系统设置中允许后重试。")
                        .foregroundStyle(.white).multilineTextAlignment(.center).padding(32)
                } else if store.showPreview {
                    if let image = store.replayProgress?.image {
                        GeometryReader { geo in
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height).clipped()
                        }
                        .ignoresSafeArea()
                    } else if store.replayDir == nil {
                        CameraPreview(session: store.camera.session, mirrored: store.lens == .front).ignoresSafeArea()
                    }
                }
                PoseOverlay(frame: store.poseFrame, mirrorHorizontally: store.replayDir == nil && store.lens == .front).ignoresSafeArea()

                VStack {
                    hud(workout)
                    if let p = store.replayProgress {
                        Text("回放 \(String(p.fed))/\(String(p.total)) · 已分析 \(String(p.analyzed)) · \(store.delegateName)")
                            .font(.caption).foregroundStyle(.white.opacity(0.8)).padding(.top, 4)
                    }
                    Spacer()
                    if workout.phase != .complete {
                        bottomControls(workout)
                    }
                }

                if workout.phase == .complete {
                    completionCard(workout)
                }
            }
            .alert("结束本次训练？", isPresented: $showEndDialog) {
                Button("结束", role: .destructive) { store.finishWorkout() }
                Button("继续", role: .cancel) {}
            } message: {
                Text("当前计数和训练时长会保存到本地记录。")
            }
            .alert("提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.dismissError() } })) {
                Button("好") { store.dismissError() }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    // Count and clock side by side so both are readable from a distance while jumping.
    private func hud(_ workout: WorkoutSnapshot) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text(hudClockText(workout)).font(.system(size: 44, weight: .bold)).monospacedDigit()
                Text(hudClockLabel(workout)).font(.caption).opacity(0.8)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(workout.totalCount)").font(.system(size: 72, weight: .black)).foregroundStyle(Color.accentColor).monospacedDigit()
                Text("次").font(.caption).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.85), radius: 5, y: 3)
        .padding(.horizontal, 20).padding(.top, 10)
    }

    private func bottomControls(_ workout: WorkoutSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    let status = statusText(workout, store.detection?.guidance)
                    Text(status)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(workout.phase == .active && status == "计数中" ? Color.accentColor : Color.white)
                    Text(detailText(workout)).font(.caption2).foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
                HStack(spacing: 6) {
                    controlButton(store.showPreview ? "eye.fill" : "eye.slash.fill", store.showPreview ? "隐藏画面" : "显示画面") {
                        store.setShowPreview(!store.showPreview)
                    }
                    if store.replayDir == nil {
                        controlButton("arrow.triangle.2.circlepath.camera", "切换摄像头", action: store.switchCamera)
                    }
                    controlButton(workout.phase == .paused ? "play.fill" : "pause.fill", workout.phase == .paused ? "继续" : "暂停", action: store.togglePause)
                        .disabled(workout.phase == .preparing)
                    controlButton("xmark", "结束训练") { showEndDialog = true }
                }
            }
            if let progress = progress(workout) {
                ProgressView(value: progress).tint(Color.accentColor)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 18))
        .padding(12)
    }

    private func controlButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 42, height: 42)
                .background(Color.white.opacity(0.18), in: Circle()).foregroundStyle(.white)
        }
        .accessibilityLabel(label)
    }

    private func completionCard(_ workout: WorkoutSnapshot) -> some View {
        VStack(spacing: 0) {
            Text(workout.endedEarly ? "训练已结束" : "训练完成").font(.system(size: 26, weight: .bold))
            Spacer().frame(height: 14)
            Text("\(workout.totalCount)").font(.system(size: 60, weight: .black)).foregroundStyle(Color.accentColor)
            Text("累计次数 · \(formatClock(workout.totalActiveMs))")
            Spacer().frame(height: 22)
            Button(action: store.returnToSetup) { Text("完成").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
        }
        .padding(28)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28))
        .padding(28)
    }

    /// Big clock: remaining time for timed groups, otherwise elapsed active time. Pause freezes it.
    private func hudClockText(_ workout: WorkoutSnapshot) -> String {
        let timing = workout.phase == .active || (workout.phase == .paused && workout.pausedFrom == .active)
        if workout.config.mode == .fixedTime {
            let remaining = timing ? (workout.phaseRemainingSec ?? workout.config.durationPerGroupSec) : workout.config.durationPerGroupSec
            return formatClock(Int64(remaining) * 1_000)
        }
        return formatClock(workout.totalActiveMs)
    }

    private func hudClockLabel(_ workout: WorkoutSnapshot) -> String {
        workout.config.mode == .fixedTime ? "本组剩余" : "已跳时间"
    }

    private func statusText(_ workout: WorkoutSnapshot, _ guidance: String?) -> String {
        switch workout.phase {
        case .preparing: return guidance ?? "请全身入镜并站稳"
        case .armed: return "跳起来就开始计数"
        case .active: return (guidance?.hasPrefix("请") == true ? guidance : nil) ?? "计数中"
        case .rest: return "休息 \(workout.phaseRemainingSec ?? 0) 秒"
        case .paused: return "已暂停"
        case .complete: return "训练完成"
        }
    }

    private func detailText(_ workout: WorkoutSnapshot) -> String {
        let group = workout.config.mode == .free ? "" : "第 \(workout.currentGroup)/\(workout.config.groups) 组 · "
        let target: String
        switch workout.config.mode {
        case .fixedCount:
            target = "本组 \(workout.groupCount)/\(workout.config.targetCountPerGroup) · "
        case .fixedTime:
            let timing = workout.phase == .active || (workout.phase == .paused && workout.pausedFrom == .active)
            let remaining = timing ? (workout.phaseRemainingSec ?? workout.config.durationPerGroupSec) : workout.config.durationPerGroupSec
            target = "本组剩余 \(remaining) 秒 · "
        case .free:
            target = ""
        }
        return "\(group)\(target)\(formatClock(workout.totalActiveMs))"
    }

    private func progress(_ workout: WorkoutSnapshot) -> Double? {
        let value: Double
        switch workout.config.mode {
        case .fixedCount: value = Double(workout.groupCount) / Double(workout.config.targetCountPerGroup)
        case .fixedTime: value = Double(workout.groupElapsedMs) / (Double(workout.config.durationPerGroupSec) * 1_000)
        case .free: return nil
        }
        return min(max(value, 0), 1)
    }
}
