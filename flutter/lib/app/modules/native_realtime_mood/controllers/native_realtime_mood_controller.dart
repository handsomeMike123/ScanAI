import 'dart:typed_data';
import 'package:ai_scan/app/data/models/mood_enum.dart';
import 'package:ai_scan/app/data/services/tflite_service.dart';
import 'package:ai_scan/app/services/native_camera_channel_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ============================================================
// 原生实时心情检测控制器
// 参考文章： https://juejin.cn/post/7392066728438054962
//
// 【MVVM - ViewModel 层】
//
// 职责：
// 1. 管理与原生端的通信（通过 NativeCameraChannelService）
// 2. 使用 Texture 预览（60fps 零拷贝）
// 3. 接收人脸坐标（~10fps）→ 驱动人脸框叠加
// 4. 接收检测帧（每3秒）→ TFLite 推理 → 结果通知 View
// 5. 推理结果回传原生端（MethodChannel），形成完整通信闭环
//
// 【v3 双频数据流】
// 预览: 原生 Texture → Flutter Texture widget（60fps GPU 零拷贝）
// 人脸框: 原生 → EventChannel(faceBounds) → Flutter CustomPainter
// 检测帧: 原生 → EventChannel(detection) → TFLite 推理 → UI + 回传原生
// ============================================================
class NativeRealtimeMoodController extends GetxController {

  final NativeCameraChannelService _channelService = NativeCameraChannelService.instance;
  final TfliteService _tfliteService = Get.find<TfliteService>();

  /// 模型是否已加载（响应式，供 AppBar 状态点使用）
  final RxBool modelLoaded = false.obs;

  // ============================================================
  // 响应式状态
  // ============================================================

  /// 是否有相机权限
  final RxBool hasCameraPermission = false.obs;

  /// 是否正在采集中
  final RxBool isCapturing = false.obs;

  /// 是否正在推理中
  final RxBool isProcessing = false.obs;

  /// 状态文本
  final RxString statusText = '准备就绪'.obs;

  /// Texture 纹理 ID（用于 Texture widget 渲染，null 表示未启动）
  final RxnInt textureId = RxnInt();

  /// 纹理尺寸（由原生端报告）
  final Rx<Size> textureSize = const Size(3, 4).obs;

  /// 当前人脸边界框列表（归一化坐标 0~1）
  final RxList<FaceBounds> faceBounds = <FaceBounds>[].obs;

  /// 最新检测结果
  final Rx<FrameDetectionResult?> latestResult = Rx<FrameDetectionResult?>(null);

  /// 检测历史记录
  final RxList<FrameDetectionResult> detectionHistory = <FrameDetectionResult>[].obs;

  /// 帧计数
  final RxInt frameCount = 0.obs;

  /// 错误信息
  final RxString errorMessage = ''.obs;

  /// 最近一次回传原生端的结果摘要
  final RxString nativeReportStatus = ''.obs;

  // ============================================================
  // 生命周期
  // ============================================================

  @override
  void onInit() {
    super.onInit();
    _checkInitialStatus();
    _startEventListening();
  }

  @override
  void onClose() {
    if (isCapturing.value) {
      stopCapture();
    }
    _channelService.dispose();
    super.onClose();
  }

  // ============================================================
  // 初始化
  // ============================================================

  Future<void> _checkInitialStatus() async {
    try {
      // 先检查权限
      hasCameraPermission.value = await _channelService.checkPermission();

      if (!hasCameraPermission.value) {
        statusText.value = '需要相机权限';
      }

      // 加载 TFLite 模型
      await _loadModel();

      // 最终状态
      if (modelLoaded.value && hasCameraPermission.value) {
        statusText.value = '准备就绪';
      }
    } catch (e) {
      debugPrint('初始化检查失败: $e');
      errorMessage.value = '初始化失败: $e';
      statusText.value = '初始化失败';
    }
  }

  /// 加载 TFLite 模型（若已加载则跳过）
  Future<void> _loadModel() async {
    modelLoaded.value = _tfliteService.isModelLoaded;
    if (modelLoaded.value) return;

    statusText.value = '正在加载推理模型...';
    try {
      final bool loaded = await _tfliteService.loadModel();
      modelLoaded.value = loaded;
      if (loaded) {
        statusText.value = '模型加载成功';
      } else {
        errorMessage.value = '模型文件未加载，请检查 assets/models/ 目录是否包含模型文件';
        statusText.value = '模型加载失败';
      }
    } catch (e) {
      modelLoaded.value = false;
      errorMessage.value = '模型加载出错: $e';
      statusText.value = '模型加载失败';
    }
  }

  // ============================================================
  // EventChannel 监听
  // ============================================================

  void _startEventListening() {
    _channelService.startListening(
      onFaceBounds: _onFaceBounds,
      onDetectionFrame: _onDetectionFrame,
      onTextureSize: _onTextureSize,
      onError: (Object error) {
        debugPrint('EventChannel 错误: $error');
        errorMessage.value = '通信异常: $error';
        statusText.value = '通信异常';
      },
    );
  }

  /// 收到人脸坐标更新：刷新人脸框
  void _onFaceBounds(List<FaceBounds> faces) {
    faceBounds.value = faces;
  }

  /// 收到纹理尺寸更新
  void _onTextureSize(int width, int height) {
    textureSize.value = Size(width.toDouble(), height.toDouble());
    debugPrint('📐 [Controller] 纹理尺寸: ${width}x${height}');
  }

  /// 收到检测帧：TFLite 推理
  void _onDetectionFrame(DetectionFrameData data) {
    if (isProcessing.value) {
      debugPrint('⏭️ 跳过检测帧（正在处理中）');
      return;
    }

    isProcessing.value = true;
    frameCount.value = data.frameIndex;
    statusText.value = '🔍 正在推理 #${data.frameIndex}...';

    _processFrame(data.jpegBytes, data.frameIndex);
  }

  // ============================================================
  // 帧推理处理 + 结果回传
  // ============================================================

  Future<void> _processFrame(Uint8List jpegBytes, int index) async {
    try {
      final result = _tfliteService.classifyFaceImage(jpegBytes);
      final mood = Mood.fromAffectNetLabel(result.classificationLabel);

      final frameResult = FrameDetectionResult(
        frameIndex: index,
        jpegBytes: jpegBytes,
        mood: mood,
        confidence: result.confidence,
        emotionProbs: result.emotionProbs,
        timestamp: DateTime.now(),
      );

      latestResult.value = frameResult;
      detectionHistory.insert(0, frameResult);
      if (detectionHistory.length > 50) {
        detectionHistory.removeRange(50, detectionHistory.length);
      }

      statusText.value = '${mood.displayName} ${(result.confidence * 100).toStringAsFixed(0)}%';

      // 回传推理结果给原生端
      await _channelService.reportDetectionResult(
        frameIndex: index,
        mood: mood.affectNetLabel,
        confidence: result.confidence,
        displayName: mood.displayName,
        emotionProbs: Map.fromEntries(
          Mood.values.asMap().entries.map((e) =>
            MapEntry(e.value.affectNetLabel, result.emotionProbs[e.key]),
          ),
        ),
      );

      nativeReportStatus.value = '已回传 #$index: ${mood.displayName}';
    } catch (e) {
      debugPrint('❌ 帧推理失败: $e');
      errorMessage.value = '推理失败: $e';
      statusText.value = '推理失败';
    } finally {
      isProcessing.value = false;
    }
  }

  // ============================================================
  // 用户操作
  // ============================================================

  Future<void> requestPermission() async {
    try {
      final granted = await _channelService.requestPermission();
      hasCameraPermission.value = granted;
      if (!granted) {
        statusText.value = '相机权限被拒绝，请在设置中开启';
      } else {
        statusText.value = '权限已获取';
      }
    } catch (e) {
      statusText.value = '权限请求失败: $e';
    }
  }

  Future<void> startCapture() async {
    if (isCapturing.value) return;

    if (!hasCameraPermission.value) {
      statusText.value = '正在请求相机权限...';
      await requestPermission();
      if (!hasCameraPermission.value) {
        errorMessage.value = '相机权限未授权，请在系统设置中开启';
        statusText.value = '权限被拒绝';
        return;
      }
    }

    if (!modelLoaded.value) {
      errorMessage.value = '模型文件未加载，请检查 assets/models/ 目录是否包含模型文件';
      statusText.value = 'TFLite 模型未加载';
      return;
    }

    try {
      isCapturing.value = true;
      frameCount.value = 0;
      detectionHistory.clear();
      latestResult.value = null;
      textureId.value = null;
      faceBounds.clear();
      errorMessage.value = '';
      nativeReportStatus.value = '';
      statusText.value = '正在启动相机...';

      // 启动采集，获取 textureId
      final int? tid = await _channelService.startCapture();
      textureId.value = tid;

      if (tid != null) {
        statusText.value = '相机已启动，预览就绪';
        debugPrint('📷 开始采集（Texture 模式, textureId=$tid）');
      } else {
        statusText.value = '相机已启动，但纹理创建失败';
        debugPrint('⚠️ Texture ID 为空');
      }
    } catch (e) {
      isCapturing.value = false;
      errorMessage.value = '启动相机失败: $e';
      statusText.value = '启动失败';
      debugPrint('❌ 启动采集失败: $e');
    }
  }

  Future<void> stopCapture() async {
    try {
      await _channelService.stopCapture();
      isCapturing.value = false;
      textureId.value = null;
      statusText.value = '已停止，共 $frameCount 帧';
      debugPrint('📷 停止采集，共 $frameCount 帧');
    } catch (e) {
      statusText.value = '停止失败: $e';
    }
  }
}
