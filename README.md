# ScanAI — AI 心情检测

基于端侧 AI 模型的人脸表情识别项目，提供 iOS 原生和 Flutter 跨平台两种实现方案。

---

## 版本记录

### v1.0.1 — 原生相机实时检测（当前版本）

本版本在 v1.0.0 基础上，新增 Flutter 与原生双端（iOS/Android）的实时相机交互能力，通过 Texture 零拷贝实现流畅的实时预览，并在原生层完成人脸检测与心情推理，结果通过 Event Channel 实时推送到 Flutter 端展示。

**新增功能：**

- Method Channel：Flutter 调用原生方法，包括启动/停止相机、切换前后置摄像头。
- Event Channel：原生端向 Flutter 推送结构化数据，包括纹理尺寸（用于调整 UI 布局）、人脸坐标（用于绘制人脸框）、心情分析结果（用于展示情绪标签）。
- iOS 端 Texture 零拷贝预览：通过 `FlutterTexture` 协议实现，将 `CVPixelBuffer` 直接写入 GPU 纹理，不经过 CPU 拷贝，预览帧率稳定在 30fps。
- iOS 端实时人脸检测：使用 Vision Framework，通过 100ms 定时器低频采样相机帧，检测人脸坐标并实时推送。
- iOS 端实时心情推理：使用 TFLite 端侧模型，每 3 秒定时采样，裁剪人脸区域后推理，识别 7 类情绪（愤怒、厌恶、恐惧、开心、悲伤、惊讶、中性）。
- Android 端同步实现：基于 CameraX 的 Preview + ImageAnalysis 用例，功能与 iOS 端对齐，具体实现细节见源码。
- 双端架构统一：iOS 和 Android 原生模块的文件职责一一对应，Flutter 端业务代码完全复用。

### v1.0.0 — 图片选择检测

本版本支持从相册选择图片或拍照，进行单次人脸检测与心情分析。

- 人脸检测：基于 ML Kit，自动定位图片中的人脸区域。
- 表情分类：TFLite 端侧推理，支持 7 类情绪分类。
- 多脸识别：同时检测并标注多张人脸的心情。
- 拍照 / 相册：支持相机实时拍照和从相册选择图片。
- 离线运行：所有推理在设备端完成，无需网络。

---

## 项目结构

```
ScanAI/
├── MODEL_REFERENCES.md
│   └── 模型参考文档
│
├── ios/
│   └── coreML_iOS_test/
│       └── coreML_iOS_test/
│           ├── Controller/                # 页面控制器
│           ├── Model/
│           │   └── EmotiEff_enet_b2_7_fp32.mlpackage   # CoreML 模型
│           ├── View/                     # 自定义视图
│           ├── Utils/                    # 推理引擎 + 图片预处理
│           ├── AppDelegate.swift
│           └── SceneDelegate.swift
│
└── flutter/
    ├── lib/app/
    │   ├── core/                        # 常量、主题
    │   ├── data/                        # 服务层（TFLite、人脸检测）
    │   ├── modules/
    │   │   ├── mood_tabs/               # v1.0.0 图片选择检测
    │   │   └── native_realtime_mood/    # v1.0.1 原生实时检测
    │   │       ├── controllers/
    │   │       ├── views/
    │   │       └── bindings/
    │   └── routes/                      # 路由
    │
    ├── ios/Runner/
    │   ├── NativeCameraCapture/         # v1.0.1 iOS 原生相机模块
    │   │   ├── Channel/
    │   │   │   └── CameraChannelHandler.swift   # Method + Event Channel
    │   │   ├── Service/
    │   │   │   └── CameraService.swift          # 相机管理 + 人脸检测 + 帧处理
    │   │   ├── Texture/
    │   │   │   └── CameraTexture.swift           # FlutterTexture 协议实现
    │   │   └── Model/
    │   │       └── CameraFrameData.swift         # 帧数据模型
    │   └── Model/
    │       └── EmotiEff_enet_b2_7_fp32.mlpackage
    │
    ├── android/app/src/main/.../nativecamera/   # v1.0.1 Android 原生相机模块
    │   ├── channel/
    │   │   └── CameraChannelHandler.kt
    │   ├── service/
    │   │   └── CameraService.kt
    │   └── model/
    │       └── CameraFrameData.kt
    │
    ├── assets/models/
    │   └── EmotiEff_enet_b2_7_fp32.tflite
    └── pubspec.yaml
```

---

## 功能列表

- **人脸检测**：基于 ML Kit（Flutter）或 Vision Framework（iOS 原生），自动定位人脸区域。
- **表情分类**：TFLite 端侧推理，识别 7 种情绪（愤怒、厌恶、恐惧、开心、悲伤、惊讶、中性）。
- **多脸识别**：同时检测并标注多张人脸的心情。
- **拍照 / 相册**：支持相机实时拍照和从相册选择图片（v1.0.0）。
- **实时相机预览**：Texture 零拷贝渲染，iOS 端通过 `CVPixelBuffer → GPU 纹理` 实现，Android 端通过 CameraX Preview + SurfaceTexture 实现，均达到 30fps 流畅预览（v1.0.1）。
- **实时人脸检测**：前置摄像头持续检测人脸，坐标通过 Event Channel 实时推送到 Flutter 端绘制人脸框（v1.0.1）。
- **实时心情推理**：定时采样相机帧，裁剪人脸区域后调用 TFLite 推理，结果实时展示（v1.0.1）。
- **离线运行**：所有推理在设备端完成，无需网络。

---

## iOS 原生端架构说明（v1.0.1）

### 文件职责

`CameraChannelHandler.swift`：Method Channel 和 Event Channel 的注册与分发。Flutter 端通过 Method Channel 调用 `startCamera`、`stopCamera`、`switchCamera`；原生端通过 Event Channel 向 Flutter 推送 `textureSize`、`faceBounds`、`moodResult` 三类事件。

`CameraService.swift`：核心业务类，采用单例模式。负责 AVCaptureSession 的配置与管理，包括前后置摄像头切换、帧率设置；实现 `AVCaptureVideoDataOutputSampleBufferDelegate` 协议，在 `captureOutput` 回调中缓存最新帧到 `latestPixelBuffer`；通过定时器驱动人脸检测（100ms 间隔）和心情推理（3s 间隔）；人脸检测使用 Vision 的 `VNDetectFaceRectanglesRequest`，心情推理使用 TFLite（`TFLiteService`）。

`CameraTexture.swift`：实现 `FlutterTexture` 协议，是零拷贝预览的关键。核心方法是 `update(with:)`（接收 `CVPixelBuffer`，用 Core Image 做方向校正后渲染到 `_renderBuffer`）和 `copyPixelBuffer()`（引擎读取时返回当前帧）。用 `NSLock` 保护 `_pixelBuffer` 的读写安全。

`CameraFrameData.swift`：帧数据的 Swift 模型，用于结构化封装纹理尺寸、人脸坐标、心情结果，通过 `toDictionary()` 转为 `Dictionary` 后通过 Event Channel 发送。

### 帧数据流

预览链路（GPU 零拷贝）：`captureOutput` 回调 → `CameraTexture.update()` 写入 GPU 纹理 → 调用 `textureFrameAvailable(textureId)` 通知引擎 → 引擎调用 `copyPixelBuffer()` 读取 → Texture widget 渲染。整条链路无 CPU 拷贝。

检测链路（低频采样）：100ms 定时器触发 → 读取 `latestPixelBuffer` → 转为 `CVPixelBuffer` 送入 Vision API → 获取人脸坐标 → 通过 Event Channel 推送 `faceBounds`。用 `isDetectingFace` 布尔锁防止并发。

推理链路（定时推理）：3s 定时器触发 → 读取 `latestPixelBuffer` → 判断是否有人脸 → 有：裁剪人脸区域，编码为 JPEG 字节数组，送入 TFLite 推理；无：缩放整帧为 224×224，编码为 JPEG，送入 TFLite 推理 → 通过 Event Channel 推送 `moodResult`。

---

## Android 原生端说明（v1.0.1）

Android 端功能与 iOS 端对齐，基于 CameraX 实现。主要差异：

- 预览链路：CameraX Preview 用例直接输出到 `SurfaceTexture`，引擎自动感知新帧并渲染，无需手动实现 `FlutterTexture` 协议。
- 检测链路：在 `ImageAnalysis.setAnalyzer` 回调中处理每一帧，使用 ML Kit Face Detection API，通过 `STRATEGY_KEEP_ONLY_LATEST` 策略丢弃积压帧。
- 帧数据格式：CameraX 输出 `YUV_420_888` 格式的 `ImageProxy`，需要先通过 `toBitmap()` 转为 `Bitmap`，再做镜像和旋转变换后缓存到 `latestBitmap`。

具体实现请参考 `CameraChannelHandler.kt`、`CameraService.kt` 源码。

---

## 两种实现方案对比

**iOS 原生方案**（`ios/coreML_iOS_test/`）：使用 Swift + UIKit + Core ML，模型格式为 `.mlpackage`，人脸检测使用 Vision Framework，适合纯 iOS 项目集成。

**Flutter 跨平台方案**（`flutter/`）：使用 Dart + Flutter + GetX，模型格式为 `.tflite`，iOS 端人脸检测使用 Vision Framework，Android 端使用 ML Kit，支持 iOS 和 Android 双平台。实时检测功能在 v1.0.1 中通过原生端实现，Flutter 端只负责 UI 展示和业务逻辑。

---

## 快速开始

### iOS 原生版本

```bash
cd ios/coreML_iOS_test/
open coreML_iOS_test.xcodeproj
# Xcode 中选择模拟器/真机，Cmd+R 运行
```

模型已内嵌在项目中，无需额外下载。

### Flutter 版本

```bash
cd flutter/
flutter pub get
flutter run
```

模型已包含在 `assets/models/` 中，无需额外下载。

iOS 端需在 Xcode 中确认 Runner target 的 Signing & Capabilities 配置正确。Android 端需确保 `minSdkVersion >= 21`。

---

## 模型

使用 [EmotiEffLib](https://github.com/sb-ai-lab/EmotiEffLib) 的 enet_b2_7 模型，在 AffectNet 数据集上训练，支持 7 类情绪分类。

CoreML 格式（`EmotiEff_enet_b2_7_fp32.mlpackage`，约 15MB）：用于 iOS 原生方案，位于 `ios/.../Model/`；Flutter iOS 端备用模型位于 `flutter/ios/Runner/Model/`。

TFLite 格式（`EmotiEff_enet_b2_7_fp32.tflite`，约 29MB）：用于 Flutter 跨平台方案，位于 `flutter/assets/models/`，iOS 和 Android 双端共用。

---

## License

MIT
