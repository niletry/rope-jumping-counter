# Rope Counter / 智能跳绳计数

包名：`com.yzrun.ropecounter`

一个完全离线的 Android 跳绳计数 MVP。应用通过 CameraX 获取实时画面，使用 MediaPipe Pose Landmarker 提取人体关键点，再通过可测试的运动状态机识别双脚单摇跳跃。

## 已实现

- 定数跳：每组目标次数、组数、组间休息
- 定时跳：每组时长、组数、组间休息
- 自由跳绳：持续到用户主动结束
- 无需站稳、无需倒计时：校准约 0.7 秒后，检测到第一跳即开始计时并计数（第一跳本身也计入）
- 自动组间休息、暂停和继续
- 后置/前置摄像头切换
- 默认使用前置摄像头
- 实时人体骨架和画面质量提示
- 跳跃提示音、阶段振动提醒、训练时屏幕常亮
- APK 内置“请站稳”“请保持全身入镜”和“三、二、一、开始”普通话音频，不依赖系统 TTS 或网络
- APK 内置接近满幅音量的短促“嘀”声音频，每次有效计数播放一次
- 最近 100 条训练摘要保存在设备本地
- 摄像头帧不保存、不上传

## 技术栈

- Kotlin、Jetpack Compose、Material 3
- CameraX 1.5.3 Preview + ImageAnalysis（保持 compileSdk 35 兼容）
- MediaPipe Tasks Vision 1.0.0 + Pose Landmarker Lite
- 最低 Android 8.0（API 26），编译和目标 API 35
- APK 面向 ARM64 Android 真机
- Java 17、Gradle 8.11.1、Android Gradle Plugin 8.9.2

## 构建

在 Android Studio 中打开仓库根目录，安装 Android SDK 35 后同步项目。命令行构建：

```bash
./gradlew testDebugUnitTest assembleDebug
```

Debug APK 输出到：

```text
app/build/outputs/apk/debug/app-debug.apk
```

## 使用条件

1. 固定手机，竖屏拍摄；默认使用前置摄像头，必要时可切换后置摄像头。
2. 人物与镜头保持约 2–4 米距离，头部和双脚完整入镜。
3. 点击开始后直接跳即可；应用在约 0.7 秒内完成校准，并从检测到的第一跳开始计时计数。校准期间发生的跳跃会在校准完成后补记。
4. 当前算法针对单人、双脚并跳、单摇设计。

## 计数原理

检测器使用肩、髋、膝和脚踝关键点。最近约 0.7 秒内脚踝与髋部的最低点作为地面基线（不要求站立不动），垂直位移使用当前躯干长度归一化；连续跳绳时，每一跳都以最近一次落地低点作为新的局部基准。人物落地点发生较大的横向、纵向或前后偏移时，检测器会吸收累计位移，而不会因为偏离最初站位而重新校准。信号经过指数平滑后进入 `READY → RISING → AIRBORNE → LANDING` 状态机，只有双脚同步上升，并满足相对峰值高度、持续时间和最短间隔的完整周期才会计数。

## 当前限制

- 不识别绳子旋转，因此不支持双摇或三摇按绳圈计数。
- 手持拍摄、多人入镜、身体被遮挡或强逆光会降低可靠性。
- 调试：`adb shell am start -n com.yzrun.ropecounter/.MainActivity --es replay_dir <App 私有目录下的 JPEG 帧序列目录>` 可用录制视频的帧序列代替摄像头回放；关键点会落盘到 `files/replay_landmarks.jsonl`，配合 `ReplayHarnessTest`（`-PreplayCsv=`）可离线回归计数算法。
- `sample1.mp4`、`sample2.mp4` 和 `test.mp4` 是调参与回归素材，不会被打包进 APK；最终阈值仍需在目标 Android 设备上用人工标注结果校准。
- 当前本地历史使用 SharedPreferences 保存训练摘要，不保存视频或人体关键点。

详细设计见 [docs/design.md](docs/design.md)。
