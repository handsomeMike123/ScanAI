import 'package:ai_scan/app/data/models/mood_result.dart';
import 'package:flutter/material.dart';

/// 心情结果卡片（对应 iOS MoodResultView）
/// 左侧显示人脸缩略图，右侧显示心情分析结果
class MoodResultCard extends StatelessWidget {
  final MoodResult result;

  const MoodResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final Color moodColor = Color(result.mood.colorValue);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildFaceThumbnail(),
          const SizedBox(width: 12),
          Expanded(child: _buildResultInfo(context, moodColor)),
        ],
      ),
    );
  }

  /// 左侧人脸缩略图（对应 iOS faceImageView + faceHintLabel）
  Widget _buildFaceThumbnail() {
    final bool hasImage = result.faceImageBytes != null;
    return Column(
      children: <Widget>[
        if (hasImage)
          Text(
            '模型看到的',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: hasImage
                ? Image.memory(result.faceImageBytes!, fit: BoxFit.cover)
                : const Icon(Icons.face, size: 40, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  /// 右侧心情结果（对应 iOS faceIndexLabel / moodLabel / classLabel 等）
  Widget _buildResultInfo(BuildContext context, Color moodColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '人脸 #${result.faceIndex + 1}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          result.mood.displayName,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: moodColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '分类: ${result.classificationLabel}',
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: result.confidence,
                  color: moodColor,
                  backgroundColor: Colors.grey[200],
                  minHeight: 10,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(result.confidence * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          result.mood.description,
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ],
    );
  }
}
