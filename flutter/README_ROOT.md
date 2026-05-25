# AI 心情检测

基于端侧 AI 模型的人脸表情识别项目，提供 **iOS 原生** 和 **Flutter 跨平台** 两种实现方案。

## 项目结构

```
├── ios-native/     ← iOS 原生 Swift 实现
├── flutter/        ← Flutter 跨平台实现
└── README.md
```

## 功能

| 功能 | 说明 |
|------|------|
| 人脸检测 | 基于 ML Kit，自动定位图片中的人脸 |
| 表情分类 | TFLite 端侧推理，识别 7 种情绪（愤怒、厌恶、恐惧、开心、悲伤、惊讶、中性） |
| 多脸识别 | 同时检测并标注多张人脸的心情 |
| 拍照 / 相册 | 支持相机实时拍照和从相册选择图片 |
| 离线运行 | 所有推理在设备端完成，无需网络 |

## 两种实现对比

| | iOS 原生 (`ios-native/`) | Flutter (`flutter/`) |
|---|---|---|
| 语言 | Swift | Dart |
| 框架 | UIKit / SwiftUI | Flutter + GetX |
| 推理引擎 | Core ML / TFLite | tflite_flutter |
| 人脸检测 | Vision Framework | google_mlkit_face_detection |
| 平台 | 仅 iOS | iOS + Android |
| 适用场景 | 追求原生性能和集成 | 快速跨平台交付 |

## 快速开始

### Flutter 版本

```bash
cd flutter/
flutter pub get
flutter run
```

> 详见 [flutter/README.md](flutter/README.md)

### iOS 原生版本

```bash
cd ios-native/
open *.xcodeproj   # 或 *.xcworkspace
# Xcode 中选择模拟器/真机，Cmd+R 运行
```

> 详见 [ios-native/README.md](ios-native/README.md)

## 技术架构

```
输入图片 → EXIF 归一化 → 人脸检测 → 裁剪人脸(+40% margin) → TFLite 推理 → 结果展示
```

## 模型

使用 [EmotiEffNet](https://github.com/HSE-asavchenko/face-emotion-recognition) 的 enet_b2_7 模型（FP32 TFLite 格式），支持 7 类情绪分类。

## License

MIT
