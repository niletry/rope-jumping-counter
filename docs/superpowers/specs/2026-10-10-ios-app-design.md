# iOS 版跳绳计数器 设计文档

日期：2026-10-10
状态：已确认（2026-10-10，识别层由 Vision 改为 MediaPipe）

## 目标

在同一仓库内新增 `ios/` 目录，提供与 Android 版功能一致的 iOS 应用：离线 AI 摄像头跳绳计数。两端共享同一套检测算法、同一套训练流程语义、同一份离线回放测试数据，保证计数结果一致。

## 范围

包含：

- 三种模式：定数跳、定时跳、自由跳绳，组数与休息时长设置。
- 无倒计时。校准完成后进入 ARMED，从第一跳开始计时并计入该跳。校准不要求站立不动，可中途接入。
- 训练界面同时显示计时（定时模式为本组剩余，其余为已跳时间）与计数，并叠加人体骨架。
- 语音鼓励：每 10 次「加油」，每 100 次「真棒」；两者都可由用户录音替换（3 秒上限）、试听、恢复默认。
- 每次计数「嘀」一声做成开关，默认关闭。
- 训练历史（最近 100 条）与清空。
- 前后摄像头切换。
- 调试用帧序列回放模式，并导出关键点 CSV，供离线回归测试。

不包含：

- 中断次数、跳法识别（Android 也没有）。
- 任何网络功能、账号、云同步。
- iPad 专门布局、横屏。

## 技术选型

### 姿态识别：MediaPipe Tasks Vision 1.0.0，与 Android 同一模型

- 使用 CocoaPods 发布的 `MediaPipeTasksVision` + `MediaPipeTasksCommon` 1.0.0 的 xcframework，直接提交到 `ios/Frameworks/`，不走 CocoaPods，避免依赖 dl.google.com 的网络可达性。两者都带 `ios-arm64` 与 `ios-arm64_x86_64-simulator` 切片，模拟器可运行。
- 模型文件复用 Android 工程的 `app/src/main/assets/pose_landmarker_lite.task`，以资源形式打进 iOS 包。
- 同一模型、同样 33 个关键点、同样的 visibility / presence，JumpDetector 的全部阈值原样沿用，两端计数可直接对齐。
- 运行模式 `.liveStream`，GPU 委托失败时退回 CPU（与 Android 相同）。
- 坐标：MediaPipe 输出的归一化坐标原点在左上，与 Android 相同，不需要翻转。前摄不做镜像，和 Android 一致。
- 图像方向：从 `AVCaptureConnection.videoRotationAngle` 推出 `UIImage.Orientation` 传给 `detectAsync(image:timestampInMilliseconds:)`。

### 工程结构

```
ios/
  project.yml                 xcodegen 工程描述（本机已安装 xcodegen）
  Frameworks/                 MediaPipeTasksVision.xcframework、MediaPipeTasksCommon.xcframework
  RopeCore/                   纯 Swift 本地包，无 UIKit 依赖，可在 macOS 上 swift test
    Package.swift
    Sources/RopeCore/
      PoseModels.swift        PosePoint / PoseFrame / MotionState / JumpDetection
      JumpDetector.swift      与 Kotlin 版逐行对应，含 Params
      WorkoutModels.swift     WorkoutMode / WorkoutConfig / WorkoutPhase / WorkoutSnapshot / WorkoutRecord
      WorkoutEngine.swift     与 Kotlin 版逐行对应
      PromptSchedule.swift    promptFor(before:after:)，CHEER_EVERY=10，BRAVO_EVERY=100
      LandmarkCSV.swift       读写 33x5 关键点 CSV，与 Android ReplayHarnessTest 同格式
    Tests/RopeCoreTests/
      JumpDetectorTests.swift   移植 Android 的 9 个用例
      WorkoutEngineTests.swift  移植 Android 的 4 个用例
      ReplayHarnessTests.swift  读 REPLAY_CSV 环境变量，按 5 段打印与真值差
  RopeCounter/                SwiftUI 应用
    App/RopeCounterApp.swift  入口；读取启动参数 -replayDir
    Model/WorkoutStore.swift  @Observable 状态中心，对应 RopeCounterViewModel
    Vision/PoseLandmarkerProcessor.swift  封装 MPPPoseLandmarker（liveStream），isBusy 丢帧，结果 -> PoseFrame
    Camera/CameraSession.swift       AVCaptureSession，前/后摄，输出 CMSampleBuffer
    Camera/CameraPreview.swift       UIViewRepresentable 预览层
    Camera/PoseOverlay.swift         Canvas 骨架叠加
    Camera/ReplaySource.swift        按 30 fps 读目录内 JPEG，忙碌丢帧，导出 CSV
    Audio/FeedbackPlayer.swift       AVAudioPlayer；嘀、加油、真棒、开始、入镜提示
    Audio/VoiceRecorder.swift        AVAudioRecorder AAC m4a，3 秒自动停止
    Audio/VoicePrompt.swift          CHEER / BRAVO，自定义文件路径
    Data/SessionHistoryStore.swift   Documents/workout_history.json，Codable，最多 100 条
    UI/SetupScreen.swift
    UI/WorkoutScreen.swift
    UI/HistoryScreen.swift
    Resources/Sounds/*.wav           从 Android res/raw 复制
    Resources/pose_landmarker_lite.task  从 Android assets 复制
    Info.plist 键：NSCameraUsageDescription、NSMicrophoneUsageDescription
```

Bundle ID `com.yzrun.ropecounter`，最低 iOS 17，仅竖屏，训练中禁止自动锁屏。

### 数据流

```
AVCaptureVideoDataOutput (BGRA, 前摄镜像关闭)
  -> PoseLandmarkerProcessor（isBusy 时丢帧）
  -> MPPPoseLandmarker liveStream 回调
  -> PoseFrame(33 个 PosePoint)
  -> 主线程 WorkoutStore.onPoseFrame
  -> JumpDetector -> WorkoutEngine -> SwiftUI
```

时间戳用 `CACurrentMediaTime()` 毫秒（单调时钟），对应 Android 的 `elapsedRealtime`。回放模式用帧序号 × 33.3 ms。

### 训练流程（与 Android 一致）

PREPARING（等待全身入镜并校准 20 帧）→ ARMED（等第一跳，不计时）→ ACTIVE → 定数/定时到达 → REST → ARMED → … → COMPLETE。暂停从任意阶段进入并恢复到原阶段。校准窗口在完成后重放，校准期间的跳跃补记。

### 语音与触觉

- `AVAudioSession` 类别 `.playback`，选项 `.mixWithOthers`，静音键不影响、与音乐共存，对应 Android 的媒体流。
- 每个音频预加载一个 `AVAudioPlayer`；加油/真棒优先取 Documents 下用户录音，否则取内置 wav。
- 阶段切换用 `UIImpactFeedbackGenerator(.medium)`。
- 录音：请求麦克风权限，AAC 24 kHz 64 kbps，3 秒 `maxDuration` 自动停，先写 `.tmp` 再改名。

### 回放模式

- 启动参数 `-replayDir <绝对路径>`；目录内 JPEG 按文件名排序，每 33.3 ms 投喂一帧，PoseProcessor 忙时跳过。
- HUD 显示「回放 i/n · 已分析 k · GPU/CPU」。
- 结束时把每帧 33 个关键点写到 `Documents/replay_landmarks.csv`，列格式与 Android 相同：`ts,w,h,` 后接 33 组 `x,y,z,visibility,presence`。
- 模拟器：`xcrun simctl get_app_container booted com.yzrun.ropecounter data` 找到 Documents，拷入帧，`xcrun simctl launch booted com.yzrun.ropecounter -replayDir <path>`。
- 真机：`xcrun devicectl device copy to` 把帧拷进应用 Documents，`devicectl device process launch --start-stopped` 传启动参数。

## 测试与验收

1. `cd ios/RopeCore && swift test`：13 个移植用例全部通过，不需要模拟器。
2. `REPLAY_CSV=<Android 导出的 landmarks.csv> swift test --filter ReplayHarness`：Swift 版 JumpDetector 对同一份 MediaPipe 关键点得到与 Kotlin 版完全相同的逐帧状态和 118 总数。这是两端算法一致的硬性验收。
3. 模拟器回放 60 秒测试视频的 1795 帧：应用不崩溃，导出 CSV，HUD 正常。
4. 模拟器与真机（iPhone 16，iOS 26.6）回放同一视频：记录「已分析/总帧」与计数，与 Android 真机 123/123 比较。
5. 真机摄像头实拍：权限弹窗、前后摄切换、语音可听、录音替换生效、嘀开关生效、历史保存。

## 构建与部署

```
cd ios && xcodegen generate
xcodebuild -project RopeCounter.xcodeproj -scheme RopeCounter \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project RopeCounter.xcodeproj -scheme RopeCounter \
  -destination 'id=00008140-000668E83C87001C' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=DYG78PPG68 build
xcrun devicectl device install app --device BFB52381-CFCA-5D87-8D40-8274629B71AE <path>.app
```

签名用本机已有的 Apple Development 证书与团队 `DYG78PPG68`（本机其他工程使用的团队，若不对请指出）。

## 风险

- Xcode 26.1.1 配 iOS 26.6 设备可能缺少 DeviceSupport，影响调试但不影响 `devicectl` 安装与运行；若安装被拒，需要升级 Xcode。
- MediaPipe iOS 框架是静态库，含 C++ 运行时，包体积增加约 40 MB。
- 模拟器没有摄像头，摄像头路径只能在真机验证。
