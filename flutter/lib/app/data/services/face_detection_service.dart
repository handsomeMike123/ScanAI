import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:get/get.dart';

/// 人脸检测服务
class FaceDetectionService extends GetxService {
  late final FaceDetector _faceDetector;

  /// 检测到的人脸数量
  final RxInt detectedFaceCount = 0.obs;

  /// 初始化人脸检测器
  void initializeDetector() {
    final FaceDetectorOptions options = FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    );
    _faceDetector = FaceDetector(options: options);
  }

  /// 从 InputImage 检测人脸
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    try {
      final List<Face> faces = await _faceDetector.processImage(inputImage);
      detectedFaceCount.value = faces.length;
      return faces;
    } on Exception catch (e) {
      print('人脸检测失败: $e');
      return [];
    }
  }

  /// 释放资源
  void releaseDetector() {
    _faceDetector.close();
  }

  @override
  void onClose() {
    releaseDetector();
    super.onClose();
  }
}
