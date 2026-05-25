import 'dart:io';
import 'package:ai_scan/app/data/models/classification_result.dart';
import 'package:ai_scan/app/data/models/face_detection_result.dart';
import 'package:ai_scan/app/modules/mood_tabs/controllers/mood_tabs_controllers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// AI 心情检测页面
///
/// 布局：
/// - 图片预览区 + 人脸框叠加
/// - 状态标签
/// - 拍照 + 相册选图按钮
/// - 心情结果卡片列表
class MoodDetectionPage extends StatelessWidget {
  const MoodDetectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final MoodDetectionController controller = Get.put(MoodDetectionController());

    return Scaffold(
      appBar: AppBar(title: const Text('心情检测')),
      body: Obx(() {
        // 模型初始化中：显示加载状态
        if (controller.isInitializing.value) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  controller.initStatusText.value,
                  style: TextStyle(color: Colors.grey[600], fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 图片预览区
              _buildImagePreview(context, controller),
              const SizedBox(height: 16),

              // 状态标签
              Text(
                controller.statusText.value,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),

              // 拍照 + 相册选图按钮
              Row(
                children: <Widget>[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: controller.isProcessing.value ? null : controller.pickFromCamera,
                      icon: const Icon(Icons.camera_alt, color: Colors.white),
                      label: const Text('📷 拍照', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: controller.isProcessing.value ? null : controller.pickFromAlbum,
                      icon: const Icon(Icons.photo_library, color: Colors.white),
                      label: const Text('🖼 相册选图', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),

              // 加载指示器
              if (controller.isProcessing.value) ...<Widget>[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],

              // 心情结果卡片
              if (controller.classificationResults.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                ...controller.classificationResults.map(
                  (ClassificationResult result) => _MoodResultCard(result: result),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }

  /// 图片预览（带人脸框叠加）
  Widget _buildImagePreview(BuildContext context, MoodDetectionController controller) {
    final File? imageFile = controller.selectedImage.value;

    if (imageFile == null) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.35,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.add_photo_alternate_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 8),
              Text('选择或拍摄一张包含人脸的图片\n开始心情分析', style: TextStyle(color: Colors.grey, fontSize: 15), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final bool hasFaces = controller.faceResults.isNotEmpty && controller.normalizedImageSize.value != Size.zero;
    final double previewHeight = MediaQuery.of(context).size.height * 0.35;

    if (hasFaces) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double displayWidth = constraints.maxWidth;
          return SizedBox(
            height: previewHeight,
            width: displayWidth,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(imageFile, width: displayWidth, height: previewHeight, fit: BoxFit.cover),
                ),
                CustomPaint(
                  size: Size(displayWidth, previewHeight),
                  painter: _FaceBoxPainter(
                    faceResults: controller.faceResults,
                    classificationResults: controller.classificationResults,
                    imageSize: controller.normalizedImageSize.value,
                    displaySize: Size(displayWidth, previewHeight),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(imageFile, height: previewHeight, width: double.infinity, fit: BoxFit.cover),
    );
  }
}

// ============================================================
// 心情结果卡片
// ============================================================

class _MoodResultCard extends StatelessWidget {
  final ClassificationResult result;

  const _MoodResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final Color moodColor = Color(result.color);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 缩略图 + 心情标签
          Row(
            children: <Widget>[
              if (result.debugFaceBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(result.debugFaceBytes!, width: 72, height: 72, fit: BoxFit.cover),
                ),
              if (result.debugFaceBytes != null) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      result.faceIndex > 0 ? '人脸 #${result.faceIndex + 1}' : '模型看到的',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(result.displayLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: moodColor)),
                    const SizedBox(height: 2),
                    Text('分类: ${result.classificationLabel}', style: TextStyle(color: Colors.grey[600], fontSize: 13, fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 置信度进度条
          Row(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: result.confidence,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(moodColor),
                    minHeight: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${(result.confidence * 100).toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: moodColor)),
            ],
          ),
          const SizedBox(height: 8),
          Text(result.description, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          const SizedBox(height: 12),

          // 7类概率分布
          ...result.sortedProbs.map((MapEntry<String, double> entry) => _buildProbRow(context, entry)),
        ],
      ),
    );
  }

  Widget _buildProbRow(BuildContext context, MapEntry<String, double> entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: 80, child: Text(entry.key, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: entry.value,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(width: 44, child: Text('${(entry.value * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
        ],
      ),
    );
  }
}

// ============================================================
// 人脸框绘制器
// ============================================================

class _FaceBoxPainter extends CustomPainter {
  final List<FaceDetectionResult> faceResults;
  final List<ClassificationResult> classificationResults;
  final Size imageSize;
  final Size displaySize;

  _FaceBoxPainter({
    required this.faceResults,
    required this.classificationResults,
    required this.imageSize,
    required this.displaySize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == Size.zero) return;

    final List<Color> colors = <Color>[
      const Color(0xFFDC143C), const Color(0xFF556B2F), const Color(0xFF483D8B),
      const Color(0xFFFFD700), const Color(0xFF808080), const Color(0xFF4682B4), const Color(0xFFFF8C00),
    ];

    // BoxFit.cover 缩放
    final double scaleX = displaySize.width / imageSize.width;
    final double scaleY = displaySize.height / imageSize.height;
    final double scale = scaleX > scaleY ? scaleX : scaleY;
    final double offsetX = (imageSize.width * scale - displaySize.width) / 2;
    final double offsetY = (imageSize.height * scale - displaySize.height) / 2;

    for (int i = 0; i < faceResults.length; i++) {
      final FaceDetectionResult result = faceResults[i];
      final Rect box = result.boundingBox;
      final Color color = classificationResults.isNotEmpty && i < classificationResults.length
          ? Color(classificationResults[i].color)
          : colors[i % colors.length];

      // 人脸框
      final Paint boxPaint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5;
      final double left = box.left * scale - offsetX;
      final double top = box.top * scale - offsetY;
      final double right = box.right * scale - offsetX;
      final double bottom = box.bottom * scale - offsetY;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(left, top, right, bottom), const Radius.circular(8)),
        boxPaint,
      );

      // 心情标签
      if (i < classificationResults.length) {
        final String label = '${classificationResults[i].displayLabel} ${(classificationResults[i].confidence * 100).toStringAsFixed(0)}%';
        final TextSpan span = TextSpan(text: label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold));
        final TextPainter tp = TextPainter(text: span, textDirection: TextDirection.ltr);
        tp.layout();

        final double labelWidth = tp.width + 10;
        final double labelHeight = tp.height + 6;
        final double labelLeft = left;
        final double labelTop = top - labelHeight - 4;

        final Paint bgPaint = Paint()..color = color..style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(labelLeft, labelTop, labelWidth, labelHeight), const Radius.circular(4)),
          bgPaint,
        );
        tp.paint(canvas, Offset(labelLeft + 5, labelTop + 3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FaceBoxPainter oldDelegate) =>
      faceResults != oldDelegate.faceResults || imageSize != oldDelegate.imageSize;
}
