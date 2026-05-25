import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 人脸框覆盖层（对应 iOS FaceOverlayView）
class FaceOverlayPainter extends CustomPainter {
  final List<Rect> faceRects;
  final Size imageSize;

  FaceOverlayPainter({
    required this.faceRects,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size viewSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return;

    // scaleAspectFit 映射
    final double scaleX = viewSize.width / imageSize.width;
    final double scaleY = viewSize.height / imageSize.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;
    final double offsetX = (viewSize.width - imageSize.width * scale) / 2;
    final double offsetY = (viewSize.height - imageSize.height * scale) / 2;

    for (final Rect faceRect in faceRects) {
      final ui.Rect mappedRect = ui.Rect.fromLTWH(
        offsetX + faceRect.left * scale,
        offsetY + faceRect.top * scale,
        faceRect.width * scale,
        faceRect.height * scale,
      );

      final Paint fillPaint = Paint()
        ..color = const Color(0x2600FF00)
        ..style = PaintingStyle.fill;
      canvas.drawRect(mappedRect, fillPaint);

      final Paint strokePaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRect(mappedRect, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) => faceRects != oldDelegate.faceRects;
}
