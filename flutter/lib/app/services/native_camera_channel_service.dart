import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ai_scan/app/data/models/mood_enum.dart';

// ============================================================
// 原生相机通道服务
//
// 【架构定位】
// Flutter ↔ 原生 的通信桥梁。
// 封装 MethodChannel（控制指令 + 结果回传）和 EventChannel（数据流），
// 实现完整的双向通信闭环。
//
// 【v3 通信架构 — Texture + 双频 EventChannel】
//
// 1. MethodChannel.startCapture → 启动相机 + 注册 Texture
// 2. ← {textureId: int} 返回纹理 ID
// 3. Texture(textureId) → GPU 纹理预览（60fps 零拷贝）
// 4. ← EventChannel(faceBounds) → ~10fps 人脸坐标 → CustomPainter 画框
// 5. ← EventChannel(detection) → 每3秒裁剪人脸 JPEG → TFLite 推理
// 6. MethodChannel.reportDetectionResult → 回传推理结果
// 7. MethodChannel.stopCapture → 停止相机 + 注销 Texture
//
// 【EventChannel 数据格式（v3）】
//
// 人脸框（~10fps，仅坐标，极低带宽）：
// {
//   'type': 'faceBounds',
//   'faceBounds': [
//     {'left': 0.3, 'top': 0.2, 'right': 0.7, 'bottom': 0.8},
//   ],
// }
//
// 检测帧（每3秒，裁剪人脸 JPEG，供 TFLite 推理）：
// {
//   'type': 'detection',
//   'data': Uint8List,
//   'frameIndex': int,
// }
// ============================================================
class NativeCameraChannelService {
  NativeCameraChannelService._();
  static final NativeCameraChannelService instance = NativeCameraChannelService._();

  // ============================================================
  // 通道定义
  // ============================================================

  static const MethodChannel _methodChannel =
      MethodChannel('com.ai_scan.native_camera');

  static const EventChannel _eventChannel =
      EventChannel('com.ai_scan.native_camera_frames');

  // ============================================================
  // 纹理 ID（由原生端 startCapture 返回）
  // ============================================================

  /// 当前纹理 ID，用于 Texture widget 渲染
  int? textureId;

  /// 纹理尺寸（由原生端报告，用于正确显示比例）
  int textureWidth = 3;
  int textureHeight = 4;

  // ============================================================
  // EventChannel 事件流管理
  // ============================================================

  Stream<Map<String, dynamic>>? _frameStream;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  /// 获取结构化帧数据流
  Stream<Map<String, dynamic>> get frameStream {
    _frameStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((dynamic event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      // 降级：当作检测帧处理
      return <String, dynamic>{
        'type': 'detection',
        'data': event,
        'frameIndex': 0,
      };
    });
    return _frameStream!;
  }

  // ============================================================
  // MethodChannel 方法
  // ============================================================

  /// 检查相机权限
  Future<bool> checkPermission() async {
    final Map<dynamic, dynamic> result =
        await _methodChannel.invokeMethod('checkPermission');
    return result['authorized'] as bool? ?? false;
  }

  /// 请求相机权限
  Future<bool> requestPermission() async {
    final Map<dynamic, dynamic> result =
        await _methodChannel.invokeMethod('requestPermission');
    return result['authorized'] as bool? ?? false;
  }

  /// 开始采集
  ///
  /// 返回 textureId，用于创建 Texture widget 实现零拷贝预览
  Future<int?> startCapture() async {
    final Map<dynamic, dynamic> result =
        await _methodChannel.invokeMethod('startCapture');
    final int? id = result['textureId'] as int?;
    textureId = id;
    return id;
  }

  /// 停止采集
  Future<void> stopCapture() async {
    await _methodChannel.invokeMethod('stopCapture');
    textureId = null;
  }

  /// 回传推理结果给原生端
  Future<void> reportDetectionResult({
    required int frameIndex,
    required String mood,
    required double confidence,
    required String displayName,
    Map<String, double>? emotionProbs,
  }) async {
    await _methodChannel.invokeMethod('reportDetectionResult', {
      'frameIndex': frameIndex,
      'mood': mood,
      'confidence': confidence,
      'displayName': displayName,
      'emotionProbs': emotionProbs,
    });
  }

  // ============================================================
  // 事件监听控制
  // ============================================================

  /// 开始监听帧数据
  void startListening({
    required void Function(List<FaceBounds>) onFaceBounds,
    required void Function(DetectionFrameData) onDetectionFrame,
    required void Function(Object) onError,
    void Function(int width, int height)? onTextureSize,
  }) {
    _subscription?.cancel();
    _subscription = frameStream.listen(
      (Map<String, dynamic> data) {
        final String type = data['type'] as String? ?? 'detection';

        if (type == 'faceBounds') {
          // 解析人脸坐标
          final List<FaceBounds> faces = [];
          final rawFaces = data['faceBounds'];
          if (rawFaces is List) {
            for (final f in rawFaces) {
              if (f is Map) {
                faces.add(FaceBounds.fromMap(f));
              }
            }
          }
          onFaceBounds(faces);
        } else if (type == 'textureSize') {
          // 纹理尺寸更新
          final int w = (data['width'] as num?)?.toInt() ?? 3;
          final int h = (data['height'] as num?)?.toInt() ?? 4;
          textureWidth = w;
          textureHeight = h;
          onTextureSize?.call(w, h);
        } else if (type == 'detection') {
          // 检测帧
          onDetectionFrame(DetectionFrameData.fromMap(data));
        }
      },
      onError: onError,
    );
  }

  /// 停止监听帧数据
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// 释放资源
  void dispose() {
    stopListening();
    _frameStream = null;
    textureId = null;
  }
}

// ============================================================
// 人脸边界框（归一化坐标 0~1）
// ============================================================

class FaceBounds {
  /// 左边界 (0~1)
  final double left;

  /// 上边界 (0~1)
  final double top;

  /// 右边界 (0~1)
  final double right;

  /// 下边界 (0~1)
  final double bottom;

  const FaceBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory FaceBounds.fromMap(Map<dynamic, dynamic> map) {
    return FaceBounds(
      left: (map['left'] as num?)?.toDouble() ?? 0,
      top: (map['top'] as num?)?.toDouble() ?? 0,
      right: (map['right'] as num?)?.toDouble() ?? 0,
      bottom: (map['bottom'] as num?)?.toDouble() ?? 0,
    );
  }
}

// ============================================================
// 检测帧数据（裁剪人脸，每3秒）
// ============================================================

class DetectionFrameData {
  /// JPEG 图像数据（裁剪后的人脸）
  final Uint8List jpegBytes;

  /// 帧序号
  final int frameIndex;

  const DetectionFrameData({
    required this.jpegBytes,
    required this.frameIndex,
  });

  factory DetectionFrameData.fromMap(Map<dynamic, dynamic> map) {
    return DetectionFrameData(
      jpegBytes: map['data'] as Uint8List,
      frameIndex: (map['frameIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

// ============================================================
// 帧检测结果（TFLite 推理后）
// ============================================================

class FrameDetectionResult {
  final int frameIndex;
  final Uint8List jpegBytes;
  final Mood mood;
  final double confidence;
  final List<double> emotionProbs;
  final DateTime timestamp;

  const FrameDetectionResult({
    required this.frameIndex,
    required this.jpegBytes,
    required this.mood,
    required this.confidence,
    required this.emotionProbs,
    required this.timestamp,
  });
}
