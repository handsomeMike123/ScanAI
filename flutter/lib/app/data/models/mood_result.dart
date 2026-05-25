import 'dart:typed_data';
import 'package:ai_scan/app/data/models/mood_enum.dart';

/// 单个人脸的心情检测结果（对应 iOS MoodResult）
class MoodResult {
  /// 人脸索引
  final int faceIndex;

  /// 模型原始分类标签
  final String classificationLabel;

  /// 置信度 (0~1)
  final double confidence;

  /// 映射后的心情
  final Mood mood;

  /// 7 类表情概率分布
  final List<double>? emotionProbs;

  /// 裁剪后的人脸图片字节
  final Uint8List? faceImageBytes;

  const MoodResult({
    required this.faceIndex,
    required this.classificationLabel,
    required this.confidence,
    required this.mood,
    this.emotionProbs,
    this.faceImageBytes,
  });
}
