# ScanAI — AI 心情检测

基于端侧 AI 模型的人脸表情识别项目，提供 **iOS 原生** 和 **Flutter 跨平台** 两种实现方案。

## 项目结构

```
ScanAI/
├── MODEL_REFERENCES.md                    ← 模型参考文档
├── ios/
│   └── coreML_iOS_test/                   ← iOS 原生 Swift 实现
│       ├── coreML_iOS_test/
│       │   ├── Controller/                # 页面控制器
│       │   ├── Model/                     # 数据模型 + CoreML 模型
│       │   │   └── EmotiEff_enet_b2_7_fp32.mlpackage  ← 唯一需要的模型
│       │   ├── View/                      # 自定义视图
│       │   ├── Utils/                     # 推理引擎 + 图片预处理
│       │   ├── AppDelegate.swift
│       │   └── SceneDelegate.swift
│       └── coreML_iOS_test.xcodeproj/
└── flutter/                               ← Flutter 跨平台实现
    ├── lib/
    │   └── app/
    │       ├── core/                      # 常量、主题
    │       ├── data/                      # 服务层（TFLite、人脸检测）
    │       ├── modules/                   # 功能模块
    │       └── routes/                    # 路由
    ├── assets/models/
    │   └── EmotiEff_enet_b2_7_fp32.tflite ← 唯一需要的模型
    └── pubspec.yaml
```

## 功能

| 功能 | 说明 |
|------|------|
| 人脸检测 | 基于 ML Kit，自动定位图片中的人脸 |
| 表情分类 | 端侧推理，识别 7 种情绪（愤怒、厌恶、恐惧、开心、悲伤、惊讶、中性） |
| 多脸识别 | 同时检测并标注多张人脸的心情 |
| 拍照 / 相册 | 支持相机实时拍照和从相册选择图片 |
| 实时检测 | 摄像头实时捕获 + 持续推理（iOS 原生） |
| 离线运行 | 所有推理在设备端完成，无需网络 |

## 两种实现对比

| | iOS 原生 (`ios/`) | Flutter (`flutter/`) |
|---|---|---|
| 语言 | Swift | Dart |
| 框架 | UIKit | Flutter + GetX |
| 推理引擎 | Core ML | tflite_flutter |
| 人脸检测 | Vision Framework | google_mlkit_face_detection |
| 实时检测 | ✅ 支持 | 📋 开发中 |
| 平台 | 仅 iOS | iOS + Android |
| 模型格式 | .mlpackage | .tflite |

## 快速开始

### iOS 原生版本

```bash
cd ios/coreML_iOS_test/
open coreML_iOS_test.xcodeproj
# Xcode 中选择模拟器/真机，Cmd+R 运行
```

> 模型已内嵌在项目中，无需额外下载。

### Flutter 版本

```bash
cd flutter/
flutter pub get
flutter run
```

> 模型已包含在 `assets/models/` 中，无需额外下载。

## 模型

使用 [EmotiEffLib](https://github.com/sb-ai-lab/EmotiEffLib) 的 enet_b2_7 模型，在 AffectNet 数据集上训练，支持 7 类情绪分类。

| 格式 | 路径 | 大小 | 用于 |
|------|------|------|------|
| CoreML | `ios/.../Model/EmotiEff_enet_b2_7_fp32.mlpackage` | ~15 MB | iOS 原生 |
| TFLite | `flutter/assets/models/EmotiEff_enet_b2_7_fp32.tflite` | ~29 MB | Flutter |

> 模型转换文档详见 [MODEL_REFERENCES.md](MODEL_REFERENCES.md)

## License

MIT
