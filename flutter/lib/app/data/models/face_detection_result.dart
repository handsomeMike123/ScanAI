import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// 人脸检测结果模型
class FaceDetectionResult {
  /// 检测到的人脸
  final Face face;

  /// 边界矩形
  Rect get boundingBox => face.boundingBox;

  /// 是否微笑
  double? get smilingProbability => face.smilingProbability;

  /// 左眼睁开概率
  double? get leftEyeOpenProbability => face.leftEyeOpenProbability;

  /// 右眼睁开概率
  double? get rightEyeOpenProbability => face.rightEyeOpenProbability;

  /// 头部偏转角 (Y轴)
  double? get headEulerAngleY => face.headEulerAngleY;

  /// 头部俯仰角 (X轴)
  double? get headEulerAngleX => face.headEulerAngleX;

  /// 跟踪 ID
  int? get trackingId => face.trackingId;

  const FaceDetectionResult({required this.face});

  /// 从 Face 对象创建
  factory FaceDetectionResult.fromFace(Face face) {
    return FaceDetectionResult(face: face);
  }

  /// 获取简要描述
  String getDescription() {
    final List<String> parts = [];
    parts.add('人脸位置: (${boundingBox.left.toInt()}, ${boundingBox.top.toInt()})');

    if (smilingProbability != null) {
      parts.add('微笑: ${(smilingProbability! * 100).toStringAsFixed(0)}%');
    }
    if (leftEyeOpenProbability != null) {
      parts.add('左眼: ${(leftEyeOpenProbability! * 100).toStringAsFixed(0)}%');
    }
    if (rightEyeOpenProbability != null) {
      parts.add('右眼: ${(rightEyeOpenProbability! * 100).toStringAsFixed(0)}%');
    }

    return parts.join(' | ');
  }
}
