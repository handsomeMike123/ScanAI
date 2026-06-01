import 'dart:typed_data';
import 'package:ai_scan/app/core/constants/app_constants.dart';

/// 分类结果模型
class ClassificationResult {
  /// 人脸索引
  final int faceIndex;

  /// 模型原始标签（AffectNet 英文，如 "Happiness"）
  final String classificationLabel;

  /// 中文展示标签（如 "开心 😊"）
  final String displayLabel;

  /// 分类置信度 (0.0 ~ 1.0)
  final double confidence;

  /// 心情描述
  final String description;

  /// 心情对应颜色
  final int color;

  /// 7类表情的完整概率分布
  final List<double> emotionProbs;

  /// 调试用：送入模型的人脸裁剪图片 PNG bytes
  final Uint8List? debugFaceBytes;

  const ClassificationResult({
    required this.faceIndex,
    required this.classificationLabel,
    required this.displayLabel,
    required this.confidence,
    required this.description,
    required this.color,
    required this.emotionProbs,
    this.debugFaceBytes,
  });

  /// 从 TFLite 推理输出创建分类结果
  /// [topIdx] 最高概率的索引
  /// [softmaxProbs] softmax 后的 7 类概率
  factory ClassificationResult.fromInference(int topIdx, List<double> softmaxProbs, {Uint8List? debugFaceBytes}) {
    return ClassificationResult(
      faceIndex: 0,
      classificationLabel: AppConstants.affectNetLabels[topIdx],
      displayLabel: AppConstants.affectNetLabelsCN[topIdx],
      confidence: softmaxProbs[topIdx],
      description: AppConstants.affectNetDescriptions[topIdx],
      color: AppConstants.affectNetColors[topIdx],
      emotionProbs: softmaxProbs,
      debugFaceBytes: debugFaceBytes,
    );
  }

  /// 创建指定人脸索引的结果
  ClassificationResult copyWithFaceIndex(int index) {
    return ClassificationResult(
      faceIndex: index,
      classificationLabel: classificationLabel,
      displayLabel: displayLabel,
      confidence: confidence,
      description: description,
      color: color,
      emotionProbs: emotionProbs,
      debugFaceBytes: debugFaceBytes,
    );
  }

  /// 获取排序后的概率分布（降序）
  List<MapEntry<String, double>> get sortedProbs {
    final List<MapEntry<String, double>> entries = [];
    for (int i = 0; i < emotionProbs.length; i++) {
      entries.add(MapEntry(AppConstants.affectNetLabelsCN[i], emotionProbs[i]));
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  @override
  String toString() => '$displayLabel (${(confidence * 100).toStringAsFixed(1)}%)';
}
