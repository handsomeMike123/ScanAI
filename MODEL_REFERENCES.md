# 模型转换参考资料

> 本文档记录了项目中使用的模型、工具、数据集的出处，以及**完整的可复现环境搭建步骤**。
> 目标：在任何 Mac 电脑上，按步骤操作即可生成 CoreML 和 TFLite 模型。

---

## 一、模型来源

### EmotiEffLib (enet_b2_7)

- **项目地址**：https://github.com/sb-ai-lab/EmotiEffLib
- **说明**：EmotiEffLib（原名 HSEmotion）是一个轻量级面部情绪识别库，
  基于 EfficientNet 系列骨干网络，在 AffectNet 数据集上训练。
  本项目使用的是 `enet_b2_7`，即 EfficientNet-B2 骨干 + AffectNet 7 类分类。

### EfficientNet（骨干网络）

- **论文**：EfficientNet: Rethinking Model Scaling for Convolutional Neural Networks
- **作者**：Mingxing Tan, Quoc V. Le (Google Brain)
- **链接**：https://arxiv.org/abs/1905.11946
- **发表**：ICML 2019

### AffectNet（训练数据集）

- **论文**：AffectNet: A Database for Facial Expression, Valence, and Arousal Computing in the Wild
- **作者**：Mollahosseini, Hasani, Mahoor
- **链接**：https://ieeexplore.ieee.org/abstract/document/8013713
- **发表**：IEEE Transactions on Affective Computing, 2017

---

## 二、已生成的模型文件

### CoreML（iOS 专用）

| 文件 | 说明 | 体积 |
|------|------|------|
| `EmotiEff_enet_b2_7_fp32.mlpackage` | 全精度，Xcode 直接使用 | ~30 MB |

### TFLite（跨平台：iOS / Android / Flutter）

| 文件 | 说明 | 体积 | 推荐场景 |
|------|------|------|---------|
| `EmotiEff_enet_b2_7_fp32.tflite` | 全精度 | 29.4 MB | 精度验证基准 |
| `EmotiEff_enet_b2_7_fp16.tflite` | 半精度 | 14.8 MB | **Flutter 推荐使用** |

> **Flutter 推荐 FP16**：体积减半，精度几乎不掉，Android GPU Delegate 和 tflite_flutter 都支持。
> INT8 不推荐：表情分类中 Fear↔Surprise、Sad↔Neutral 边界容易压坏。

---

## 三、CoreML 模型生成（环境 1）

### 环境信息

| 项目 | 值 |
|------|-----|
| Conda 环境名 | `coreml_convert` |
| Python | 3.10 |
| 转换脚本 | `Scripts/convert_emotiefflib_to_coreml.py` |

### 核心依赖

| 包 | 版本 | 说明 |
|----|------|------|
| torch | 2.7.0 | PyTorch |
| torchvision | 0.22.0 | 视觉模型工具 |
| coremltools | 6.3.0 | Apple 模型转换工具 |
| onnx | 1.17.0 | ONNX 格式（备选转换路径） |
| numpy | 1.26.4 | 数值计算 |
| emotiefflib | 1.1.1 | 模型源 |
| opencv-python | 4.13.0.92 | 图片处理 |
| pillow | 12.2.0 | 图片读取 |

### 环境搭建（一键复制）

```bash
conda create -n coreml_convert python=3.10 -y
conda activate coreml_convert
pip install torch==2.7.0 torchvision==0.22.0
pip install coremltools==6.3.0
pip install onnx==1.17.0 onnxruntime onnxsim
pip install numpy==1.26.4 opencv-python pillow
pip install emotiefflib==1.1.1
```

### 验证

```bash
python -c "import torch; print('torch', torch.__version__)"
python -c "import coremltools; print('coremltools', coremltools.__version__)"
python -c "import emotiefflib; print('emotiefflib OK')"
```

### 运行转换

```bash
conda activate coreml_convert
python Scripts/convert_emotiefflib_to_coreml.py
```

### 转换流程

```
PyTorch 模型 (emotiefflib)
  │
  ├─ 方法A: torch.jit.trace → coremltools.convert（推荐）
  │
  └─ 方法B: torch.onnx.export → ONNX → coremltools.convert（备选）
  │
  ▼
EmotiEff_enet_b2_7_fp32.mlpackage
  │
  ▼  拖入 Xcode 项目
.mlmodelc（运行时格式）
```

### 注意事项

- **不要在此环境中安装 tensorflow**，两者有依赖冲突
- coremltools 6.3 + torch 2.7.0 组合已验证可行
- `coreml_env/` 目录是空 venv，可忽略，实际使用 conda 环境

---

## 四、TFLite 模型生成（环境 2）

### 环境信息

| 项目 | 值 |
|------|-----|
| Conda 环境名 | `tflite_convert` |
| Python | 3.10 |
| 转换脚本 | `Scripts/convert_emotiefflib_to_tflite.py`（自动调用子脚本） |

### 核心依赖

| 包 | 版本 | 说明 |
|----|------|------|
| tensorflow | 2.15.0 | **必须 2.15.x，不能升级** |
| tensorflow-macos | 2.15.0 | macOS ARM 适配 |
| onnx-tf | 1.10.0 | ONNX → TensorFlow 转换 |
| onnx | 1.16.1 | ONNX 格式（**不能升级**，1.17+ 与 ml-dtypes 冲突） |
| tf2onnx | 1.17.0 | TF ↔ ONNX 工具 |
| numpy | 1.26.4 | **必须 <2.0**，TF 2.15 不兼容 numpy 2.x |
| ml-dtypes | 0.2.0 | TF 2.15 依赖 |
| protobuf | 4.25.9 | |
| tensorflow-probability | 0.23.0 | onnx-tf 依赖 |
| tensorflow-addons | 0.23.0 | onnx-tf 依赖 |
| opencv-python | 4.13.0.92 | 图片处理 |
| pillow | 12.2.0 | 图片读取 |

### ⚠️ 绝对不能安装的包

| 包 | 原因 |
|----|------|
| torch / torchvision | 与 tensorflow 共享 libomp，macOS ARM 上 mutex crash |
| onnx2tf | 同上，且依赖 onnxruntime，与 tensorflow 冲突 |
| tensorflow-metal | 触发 macOS ARM mutex crash |
| numpy >= 2.0 | TF 2.15 编译时绑定 numpy 1.x C API |
| onnx >= 1.17 | 依赖 ml-dtypes >= 0.5，与 TF 2.15 的 ml-dtypes 0.2 冲突 |

### 环境搭建（一键复制）

```bash
conda create -n tflite_convert python=3.10 -y
conda activate tflite_convert

# TensorFlow（macOS ARM 直接装，不要指定版本以外的版本）
pip install tensorflow==2.15.0

# ONNX 转换工具
pip install onnx==1.16.1
pip install tf2onnx
pip install onnx-tf

# onnx-tf 的间接依赖
pip install tensorflow-probability==0.23.0

# 其他工具
pip install numpy==1.26.4
pip install opencv-python pillow
```

### 验证

```bash
python -c "import tensorflow as tf; print('tf', tf.__version__)"
python -c "from onnx_tf.backend import prepare; print('onnx-tf OK')"
python -c "import onnx; print('onnx', onnx.__version__)"
```

预期输出：
```
tf 2.15.0
onnx-tf OK    # 可能有一个 TensorFlow Addons 停止维护的警告，可忽略
onnx 1.16.1
```

### 运行转换

```bash
# 任意 conda 环境下运行即可，脚本自动切换环境
python Scripts/convert_emotiefflib_to_tflite.py
```

### 转换架构（双环境隔离）

```
主脚本 convert_emotiefflib_to_tflite.py
  │
  ├─ 子进程1: coreml_convert/bin/python _tflite_phase1.py
  │  │  只有 torch/onnx，没有 tensorflow
  │  └── PyTorch 加载 → ONNX 导出（opset 11）
  │
  └─ 子进程2: tflite_convert/bin/python _tflite_phase2.py
     │  只有 tensorflow，没有 torch
     └── ONNX → onnx-tf → SavedModel → TFLite FP32/FP16
```

### macOS ARM 已踩过的坑

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| mutex crash | torch + tensorflow 共享 libomp | 双环境隔离，永不混装 |
| onnx2tf crash | onnxruntime + tensorflow C++ 冲突 | 改用 onnx-tf |
| onnxsim SIGSEGV | macOS ARM 兼容问题 | 跳过，非必需 |
| Unsqueeze op 不支持 | onnx-tf 不支持 opset 13+ | 降级 opset 到 11 |
| DepthwiseConv2dNative 报错 | TFLite 原生不支持 | 开启 SELECT_TF_OPS |
| numpy 2.x crash | TF 2.15 绑定 numpy 1.x | 锁定 numpy==1.26.4 |
| ml-dtypes 冲突 | onnx 1.17+ 要求 ml-dtypes 0.5+ | 锁定 onnx==1.16.1 |
| tf_keras 缺失 | TF 2.16+ 拆分 keras | 用 TF 2.15（内置 keras） |

---

## 五、常见问题

### Q: 为什么需要两个 conda 环境？

> macOS ARM（M1/M2/M3/M4）上，PyTorch 和 TensorFlow 的 C++ 运行时
> 共享 libomp 库但版本不兼容，同时加载会触发 mutex crash。
> 两个环境完全隔离，永不混装。

### Q: 为什么 TFLite 用 onnx-tf 而不是 onnx2tf？

> onnx2tf 依赖 onnxruntime，与 tensorflow 在 macOS ARM 上 C++ 冲突。
> onnx-tf 直接用 tensorflow 作为后端，不引入 onnxruntime。

### Q: 为什么 TFLite 模型需要 Flex ops？

> EfficientNet-B2 使用了 DepthwiseConv2dNative，
> 标准 TFLite 不支持此算子，需要启用 SELECT_TF_OPS。
> Flutter 端使用 tflite_flutter 时需确保 Flex delegate 可用。

### Q: 可以在 Linux 上转换吗？

> 可以。Linux 上 torch + tensorflow 的冲突较少，
> 可以在同一个环境中安装，但建议仍用双环境保证稳定性。
> Linux 上 tensorflow-metal 不存在，无需担心。

---

## 六、延伸阅读

| 主题 | 链接 |
|------|------|
| CoreML 官方文档 | https://developer.apple.com/documentation/coreml |
| coremltools 转换指南 | https://apple.github.io/coremltools/docs-guides/source/convert-pytorch.html |
| TFLite 官方文档 | https://www.tensorflow.org/lite |
| TFLite Flutter 插件 | https://pub.dev/packages/tflite_flutter |
| onnx-tf 仓库 | https://github.com/onnx/onnx-tensorflow |
| EfficientNet 论文 | https://arxiv.org/abs/1905.11946 |
| AffectNet 论文 | https://ieeexplore.ieee.org/abstract/document/8013713 |
| EmotiEffLib 仓库 | https://github.com/sb-ai-lab/EmotiEffLib |
