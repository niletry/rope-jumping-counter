import SwiftUI
import RopeCore

struct SetupScreen: View {
    @Bindable var store: WorkoutStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("选择训练模式").font(.headline)
                    Spacer().frame(height: 12)
                    ForEach(WorkoutMode.allCases, id: \.self) { mode in
                        ModeCard(mode: mode, selected: store.config.mode == mode) { store.config.mode = mode }
                        Spacer().frame(height: 10)
                    }

                    if store.config.mode != .free {
                        Spacer().frame(height: 8)
                        Text("训练设置").font(.headline)
                        Spacer().frame(height: 10)
                        SectionCard {
                            if store.config.mode == .fixedCount {
                                NumberStepper(label: "每组次数", value: $store.config.targetCountPerGroup, valueText: "\(store.config.targetCountPerGroup) 次", step: 10, range: 10...9_999)
                            } else {
                                NumberStepper(label: "每组时长", value: $store.config.durationPerGroupSec, valueText: formatShortDuration(store.config.durationPerGroupSec), step: 15, range: 15...3_600)
                            }
                            NumberStepper(label: "训练组数", value: $store.config.groups, valueText: "\(store.config.groups) 组", step: 1, range: 1...99)
                            NumberStepper(label: "组间休息", value: $store.config.restSec, valueText: formatShortDuration(store.config.restSec), step: 15, range: 0...1_800)
                        }
                    }

                    Spacer().frame(height: 18)
                    Text("语音鼓励").font(.headline)
                    Spacer().frame(height: 10)
                    VoicePromptCard(store: store)

                    Spacer().frame(height: 18)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("拍摄提示").fontWeight(.semibold)
                        Text("固定手机并让全身进入画面，直接开跳即可，从第一跳开始计时计数。视频只在设备上实时处理，不会保存或上传。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))

                    Spacer().frame(height: 22)
                    Button(action: store.startWorkout) {
                        Text("开始训练").font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).frame(height: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    if store.history.count > 0 {
                        Text("已保存 \(store.history.count) 次本地训练记录")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 10)
                    }
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .navigationTitle("智能跳绳")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: store.openHistory) { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("训练历史")
                }
            }
            .alert("提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.dismissError() } })) {
                Button("好") { store.dismissError() }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

private struct SectionCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ModeCard: View {
    let mode: WorkoutMode
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(mode.title).font(.system(size: 17, weight: .bold))
                Text(mode.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(selected ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : Color(.separator), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct NumberStepper: View {
    let label: String
    @Binding var value: Int
    let valueText: String
    let step: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button { value = max(value - step, range.lowerBound) } label: { Image(systemName: "minus").frame(width: 40, height: 40) }
                .accessibilityLabel("减少\(label)")
            Text(valueText).fontWeight(.semibold).frame(width: 78).multilineTextAlignment(.center)
            Button { value = min(value + step, range.upperBound) } label: { Image(systemName: "plus").frame(width: 40, height: 40) }
                .accessibilityLabel("增加\(label)")
        }
        .padding(.vertical, 8)
    }
}

private struct VoicePromptCard: View {
    @Bindable var store: WorkoutStore

    var body: some View {
        SectionCard {
            Text("可以录一句自己的话代替默认提示音，最长 3 秒。")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(VoicePrompt.all) { prompt in
                let isRecording = store.recording == prompt.kind
                let isCustom = store.customVoices.contains(prompt.kind)
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt.label).fontWeight(.medium)
                        Text(isRecording ? "录音中…" : (isCustom ? "已使用你的录音" : prompt.hint))
                            .font(.caption2).foregroundStyle(isRecording ? Color.red : Color.secondary)
                    }
                    Spacer()
                    Button("试听") { store.previewVoice(prompt.kind) }.disabled(store.recording != nil)
                    if isCustom && !isRecording {
                        Button("恢复默认") { store.resetVoice(prompt.kind) }.disabled(store.recording != nil)
                    }
                    Button(isRecording ? "停止" : "录音") {
                        if isRecording {
                            store.stopRecording()
                        } else {
                            VoiceRecorder.requestPermission { granted in
                                if granted { store.startRecording(prompt.kind) } else { store.showError("没有麦克风权限，请在系统设置中允许。") }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.recording != nil && !isRecording)
                }
                .padding(.vertical, 6)
            }
            Divider().padding(.vertical, 4)
            Toggle(isOn: Binding(get: { store.countBeepEnabled }, set: { store.setCountBeepEnabled($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("每次计数“嘀”一声").fontWeight(.medium)
                    Text("关闭后只保留语音鼓励").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
