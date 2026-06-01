import 'dart:io';
import 'dart:math';
import 'package:ai_scan/app/core/constants/app_constants.dart';
import 'package:ai_scan/app/data/models/classification_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// TFLite 推理服务
///
/// 模型：EmotiEff enet_b2_7 (EfficientNet-B2, AffectNet 7类)
/// 输入：(1, 224, 224, 3) RGB float32, 像素值 0-255, NHWC 布局
/// 输出：(1, 7) float32 logits → softmax → 7 类概率分布
class TfliteService {
  Interpreter? _interpreter;

  /// 是否已加载模型
  bool get isModelLoaded => _interpreter != null;

  /// 加载模型
  ///
  /// 加载策略：先尝试 fromBuffer（效率最高），失败后降级为 fromFile（写临时文件再加载）。
  /// fromBuffer 在 Android 上稳定可用；iOS 上偶发缓冲区生命周期问题时 fromFile 可兜底。
  Future<bool> loadModel() async {
    // 尝试方式 1：fromBuffer（直接从内存加载，最快）
    try {
      final String assetPath = 'assets/models/${AppConstants.modelFileName}';
      final ByteData byteData = await rootBundle.load(assetPath);
      final Uint8List buffer = byteData.buffer.asUint8List();

      debugPrint('模型资源: $assetPath (${buffer.length} bytes)');

      _interpreter = Interpreter.fromBuffer(buffer);

      debugPrint('TFLite 模型加载成功 (fromBuffer): ${AppConstants.modelFileName}');
      debugPrint('输入 shape: ${_interpreter!.getInputTensor(0).shape}');
      debugPrint('输出 shape: ${_interpreter!.getOutputTensor(0).shape}');
      return true;
    } catch (e, stackTrace) {
      debugPrint('fromBuffer 加载失败: $e');
      debugPrint('尝试 fromFile 降级方案...');
    }

    // 尝试方式 2：fromFile（写临时文件再加载，兼容性更好）
    try {
      final String assetPath = 'assets/models/${AppConstants.modelFileName}';
      final ByteData byteData = await rootBundle.load(assetPath);
      final Uint8List buffer = byteData.buffer.asUint8List();

      final Directory tempDir = await getTemporaryDirectory();
      final File modelFile = File('${tempDir.path}/${AppConstants.modelFileName}');
      await modelFile.writeAsBytes(buffer, flush: true);

      debugPrint('模型临时文件: ${modelFile.path} (${buffer.length} bytes)');

      _interpreter = Interpreter.fromFile(modelFile);

      debugPrint('TFLite 模型加载成功 (fromFile): ${AppConstants.modelFileName}');
      debugPrint('输入 shape: ${_interpreter!.getInputTensor(0).shape}');
      debugPrint('输出 shape: ${_interpreter!.getOutputTensor(0).shape}');
      return true;
    } catch (e) {
      debugPrint('fromFile 加载也失败: $e');
      return false;
    }
  }

  /// 对单张人脸图片进行推理
  ///
  /// 预处理流程：
  /// 1. 解码图片
  /// 2. 归一化 EXIF 方向（bakeOrientation）
  /// 3. 缩放到 224×224
  /// 4. 构建 NHWC 输入张量 [1][224][224][3]，像素值 0-255
  /// 5. 执行推理 → 输出 [1][7] logits
  /// 6. 手动 softmax 得到概率分布
  ClassificationResult classifyFaceImage(Uint8List imageBytes) {
    if (_interpreter == null) {
      throw StateError('模型尚未加载');
    }

    // ① 解码图片
    final img.Image? decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      throw Exception('无法解码图片');
    }

    // ② 归一化 EXIF 方向
    // img.decodeImage() 不自动应用 EXIF orientation，像素仍是传感器原始方向。
    // 手机拍摄的照片通常有 EXIF 方向标记（如竖拍标记为 rotation90），
    // 必须先 bakeOrientation 将方向"烧录"到像素中，否则模型看到旋转的人脸，推理不准。
    final img.Image normalizedImage = img.bakeOrientation(decodedImage);

    // ③ 缩放到 224×224
    final img.Image resizedImage = img.copyResize(
      normalizedImage,
      width: AppConstants.modelInputSize,
      height: AppConstants.modelInputSize,
      interpolation: img.Interpolation.linear,
    );

    // ④ 构建 NHWC 输入张量 [1, 224, 224, 3]
    // 模型要求 NHWC 布局（batch-height-width-channel），像素值为 0-255 原始 RGB。
    // 不做 ImageNet 归一化（mean/std），因为模型内部的 Wrapper 已包含归一化层。
    const int h = AppConstants.modelInputSize;
    const int w = AppConstants.modelInputSize;

    final List<List<List<List<double>>>> reshapedInput = [
      List.generate(h, (int y) =>
        List.generate(w, (int x) {
          final img.Pixel pixel = resizedImage.getPixel(x, y);
          return <double>[
            pixel.r.toDouble(),
            pixel.g.toDouble(),
            pixel.b.toDouble(),
          ];
        }),
      ),
    ];

    // ⑤ 输出 buffer 必须严格匹配模型输出 shape [1, 7]
    // 注意：不能写成 Float32List(7)，因为 Interpreter.run() 要求嵌套结构匹配
    final List<List<double>> outputBuffer = [
      List<double>.filled(AppConstants.affectNetLabels.length, 0),
    ];

    _interpreter!.run(reshapedInput, outputBuffer);

    // ⑥ 手动 softmax（模型输出是 logits，不是概率）
    final List<double> logits = outputBuffer[0];
    final List<double> softmaxProbs = _softmax(logits);

    // ⑦ 找最高概率的类别
    int topIdx = 0;
    double topProb = 0;
    for (int i = 0; i < softmaxProbs.length; i++) {
      if (softmaxProbs[i] > topProb) {
        topProb = softmaxProbs[i];
        topIdx = i;
      }
    }

    debugPrint('推理结果: ${AppConstants.affectNetLabelsCN[topIdx]} (${(topProb * 100).toStringAsFixed(1)}%)');

    // ⑧ 保存送入模型的 224×224 调试图片（便于验证预处理是否正确）
    final Uint8List debugPng = Uint8List.fromList(img.encodePng(resizedImage));

    return ClassificationResult.fromInference(topIdx, softmaxProbs, debugFaceBytes: debugPng);
  }

  /// Softmax：将 logits 转换为概率分布
  ///
  /// 减去 maxLogit 保证数值稳定性，避免 exp() 溢出
  List<double> _softmax(List<double> logits) {
    final double maxLogit = logits.reduce(max);
    final List<double> exps =
        logits.map((double v) => exp(v - maxLogit)).toList();
    final double sumExp = exps.fold<double>(0, (double a, double b) => a + b);
    return exps.map((double v) => v / sumExp).toList();
  }

  /// 释放模型
  void release() {
    _interpreter?.close();
    _interpreter = null;
  }
}
