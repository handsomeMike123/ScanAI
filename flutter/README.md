# AI 心情检测 (ai_scan)

基于 Flutter + TFLite 的端侧人脸表情识别应用，支持拍照和相册选图两种方式检测人脸心情。

## 功能特性

- **人脸检测** — 基于 Google ML Kit，自动定位图片中的人脸
- **表情分类** — 使用 TFLite 端侧推理（EmotiEff_enet_b2_7 模型），识别 7 种情绪类别
- **多脸支持** — 可同时检测并标注多张人脸的心情
- **拍照 / 相册** — 支持相机拍照和从相册选择图片
- **EXIF 归一化** — 自动处理图片 EXIF 方向，避免 iOS 上双重旋转导致检测失败

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.x + Dart |
| 状态管理 | GetX |
| 端侧推理 | tflite_flutter |
| 人脸检测 | google_mlkit_face_detection |
| 相机 / 选图 | camera + image_picker |
| 图片处理 | image (Dart) |

## 项目结构

```
lib/
├── main.dart                          # 应用入口
└── app/
    ├── core/                          # 主题、常量等基础配置
    ├── data/
    │   ├── models/                    # 数据模型（分类结果、人脸检测结果）
    │   └── services/                  # 服务层（TFLite、人脸检测、图片选择）
    ├── modules/
    │   └── mood_tabs/                 # 主功能模块（心情检测页面）
    │       ├── bindings/
    │       ├── controllers/
    │       └── views/
    └── routes/                        # 路由配置
assets/
└── models/
    └── EmotiEff_enet_b2_7_fp32.tflite # 表情识别模型
```

## 运行项目

### 前置要求

- Flutter SDK >= 3.7.2
- Android Studio / Xcode
- iOS 13+ / Android API 21+

### 启动步骤

```bash
# 克隆项目
git clone https://github.com/<your-repo>/ai_scan.git
cd ai_scan

# 安装依赖
flutter pub get

# 运行（连接设备或模拟器）
flutter run
```

> **注意**：TFLite 模型文件 (`EmotiEff_enet_b2_7_fp32.tflite`) 已包含在 `assets/models/` 中，无需额外下载。

## 检测流程

```
选图/拍照 → EXIF 方向归一化 → ML Kit 人脸检测 → 裁剪人脸(+40% margin) → TFLite 推理 → 结果展示
```

## License

MIT
