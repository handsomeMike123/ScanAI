import 'package:ai_scan/app/data/models/mood_enum.dart';
import 'package:ai_scan/app/modules/native_realtime_mood/controllers/native_realtime_mood_controller.dart';
import 'package:ai_scan/app/services/native_camera_channel_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ============================================================
// 原生实时心情检测页面
//
// 【MVVM - View 层】
// 纯 UI 渲染，所有业务逻辑由 Controller 处理。
//
// 【布局结构】
// 1. AppBar：状态点 + 标题（🟢🟢 实时检测）
// 2. 中间：摄像头预览区域
//    - Texture（60fps 零拷贝）
//    - CustomPainter 人脸框叠加
// 3. 底部：控制栏（[开始/停止]  😊 开心 85%）
//
// 【v3 技术要点】
// - 预览：Texture(textureId) → GPU 零拷贝，60fps
// - 人脸框：EventChannel(faceBounds) → CustomPainter 绘制
// - TFLite 推理：EventChannel(detection) → 每3秒推理
// ============================================================
class NativeRealtimeMoodPage extends StatelessWidget {
  const NativeRealtimeMoodPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<NativeRealtimeMoodController>();

    return Scaffold(
      appBar: _buildAppBar(context, controller),
      body: Column(
        children: <Widget>[
          // 预览区域（占据剩余空间）
          Expanded(child: _buildPreviewArea(context, controller)),
          // 底部控制栏
          _buildBottomBar(context, controller),
        ],
      ),
    );
  }

  // ============================================================
  // AppBar：状态点 + 标题
  // ============================================================

  PreferredSizeWidget _buildAppBar(BuildContext context, NativeRealtimeMoodController controller) {
    return AppBar(
      title: Obx(() {
        final hasPermission = controller.hasCameraPermission.value;
        final modelLoaded = controller.modelLoaded.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _StatusDot(active: hasPermission, label: '相机'),
            const SizedBox(width: 10),
            _StatusDot(active: modelLoaded, label: '模型'),
            const SizedBox(width: 14),
            const Text('实时检测'),
          ],
        );
      }),
      centerTitle: true,
    );
  }

  // ============================================================
  // 预览区域
  // ============================================================

  Widget _buildPreviewArea(BuildContext context, NativeRealtimeMoodController controller) {
    return Obx(() {
      final hasPermission = controller.hasCameraPermission.value;
      final isCapturing = controller.isCapturing.value;
      final tid = controller.textureId.value;
      final statusText = controller.statusText.value;
      final errorText = controller.errorMessage.value;

      // 无权限 → 占位提示
      if (!hasPermission) {
        return _buildPermissionPlaceholder(context, controller);
      }

      // 有权限但未开始/等待纹理/出错 → 状态提示
      if (!isCapturing || tid == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  isCapturing
                      ? Icons.videocam_outlined
                      : (errorText.isNotEmpty ? Icons.error_outline : Icons.videocam_outlined),
                  size: 64,
                  color: errorText.isNotEmpty ? Colors.orange[400] : Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  isCapturing ? '等待摄像头画面...' : '点击下方按钮开始检测',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (statusText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: errorText.isNotEmpty ? Colors.red[400] : Colors.grey[500],
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red[300]),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            errorText,
                            style: TextStyle(color: Colors.red[300], fontSize: 12),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }

      // 显示 Texture 预览 + 人脸框叠加
      return _buildTextureWithFaceBoxes(context, controller);
    });
  }

  /// 无权限时的占位提示
  Widget _buildPermissionPlaceholder(BuildContext context, NativeRealtimeMoodController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.videocam_off_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '请开启相机权限',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              '需要访问相机才能进行实时心情检测',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: controller.requestPermission,
              icon: const Icon(Icons.videocam, color: Colors.white),
              label: const Text('授权相机', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Texture 预览 + 人脸框叠加
  ///
  /// Texture widget 渲染 GPU 纹理（60fps 零拷贝），
  /// CustomPainter 在上层绘制人脸框。
  Widget _buildTextureWithFaceBoxes(BuildContext context, NativeRealtimeMoodController controller) {
    final int? tid = controller.textureId.value;
    if (tid == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size displaySize = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Texture 预览（GPU 零拷贝，60fps）
            // 使用原生端报告的实际纹理尺寸，动态适配不同手机
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.textureSize.value.width,
                  height: controller.textureSize.value.height,
                  child: Texture(textureId: tid),
                ),
              ),
            ),
            // 人脸框叠加
            Obx(() => CustomPaint(
              size: displaySize,
              painter: _FaceBoxPainter(
                faceBounds: controller.faceBounds.toList(),
                displaySize: displaySize,
                textureSize: controller.textureSize.value,
                mood: controller.latestResult.value?.mood,
              ),
            )),
          ],
        );
      },
    );
  }

  // ============================================================
  // 底部控制栏
  // ============================================================

  Widget _buildBottomBar(BuildContext context, NativeRealtimeMoodController controller) {
    return Obx(() {
      final isCapturing = controller.isCapturing.value;
      final hasPermission = controller.hasCameraPermission.value;
      final result = controller.latestResult.value;

      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: <Widget>[
              // 开始/停止按钮
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: hasPermission
                      ? (isCapturing ? controller.stopCapture : controller.startCapture)
                      : null,
                  icon: Icon(
                    isCapturing ? Icons.stop : Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                  ),
                  label: Text(
                    isCapturing ? '停止' : '开始检测',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCapturing ? Colors.red : Colors.blue,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),

              // 检测结果
              if (result != null) ...<Widget>[
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color(result.mood.colorValue).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        result.mood.displayName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(result.mood.colorValue),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(result.confidence * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(result.mood.colorValue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              // 帧计数
              if (isCapturing)
                Text(
                  '#${controller.frameCount.value}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500], fontFamily: 'monospace'),
                ),
            ],
          ),
        ),
      );
    });
  }
}

// ============================================================
// 状态指示点
// ============================================================

class _StatusDot extends StatelessWidget {
  final bool active;
  final String label;

  const _StatusDot({required this.active, required this.label});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label: ${active ? "就绪" : "未就绪"}',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: active ? Colors.green : Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ============================================================
// 人脸框绘制器
//
// 将归一化坐标（0~1）的人脸边界框映射到 Texture 显示区域，
// 处理 BoxFit.cover 的缩放和裁剪偏移。
// ============================================================

class _FaceBoxPainter extends CustomPainter {
  final List<FaceBounds> faceBounds;
  final Size displaySize;
  final Size textureSize;
  final Mood? mood;

  _FaceBoxPainter({
    required this.faceBounds,
    required this.displaySize,
    required this.textureSize,
    this.mood,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (textureSize == Size.zero || faceBounds.isEmpty) return;

    final Color boxColor = mood != null
        ? Color(mood!.colorValue)
        : const Color(0xFF4CAF50);

    // BoxFit.cover 缩放计算
    final double scaleX = displaySize.width / textureSize.width;
    final double scaleY = displaySize.height / textureSize.height;
    // cover: 取较大的缩放比
    final double scale = scaleX > scaleY ? scaleX : scaleY;
    final double drawWidth = textureSize.width * scale;
    final double drawHeight = textureSize.height * scale;
    final double offsetX = (drawWidth - displaySize.width) / 2;
    final double offsetY = (drawHeight - displaySize.height) / 2;

    final Paint boxPaint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final Paint bgPaint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.fill;

    for (final FaceBounds face in faceBounds) {
      // 归一化坐标 → 像素坐标 → BoxFit.cover 偏移
      final double left = face.left * drawWidth - offsetX;
      final double top = face.top * drawHeight - offsetY;
      final double right = face.right * drawWidth - offsetX;
      final double bottom = face.bottom * drawHeight - offsetY;

      // 绘制人脸框
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, top, right, bottom),
          const Radius.circular(8),
        ),
        boxPaint,
      );

      // 绘制标签背景
      final String label = mood != null
          ? mood!.displayName
          : '人脸';
      final TextSpan span = TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      );
      final TextPainter tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();

      final double labelWidth = tp.width + 10;
      final double labelHeight = tp.height + 6;
      final double labelLeft = left;
      final double labelTop = top - labelHeight - 4;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(labelLeft, labelTop, labelWidth, labelHeight),
          const Radius.circular(4),
        ),
        bgPaint,
      );
      tp.paint(canvas, Offset(labelLeft + 5, labelTop + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _FaceBoxPainter oldDelegate) =>
      faceBounds != oldDelegate.faceBounds || mood != oldDelegate.mood;
}
