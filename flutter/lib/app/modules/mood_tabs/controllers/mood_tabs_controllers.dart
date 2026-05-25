import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:ai_scan/app/core/constants/app_constants.dart';
import 'package:ai_scan/app/data/models/classification_result.dart';
import 'package:ai_scan/app/data/models/face_detection_result.dart';
import 'package:ai_scan/app/data/services/face_detection_service.dart';
import 'package:ai_scan/app/data/services/image_picker_service.dart';
import 'package:ai_scan/app/data/services/tflite_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 心情检测控制器
///
/// 检测流程：
/// 选图/拍照 → 归一化 EXIF 方向 → 人脸检测 → 裁剪人脸(+40% margin) → TFLite 推理 → 结果展示
class MoodDetectionController extends GetxController {
  final TfliteService _tfliteService = Get.find<TfliteService>();
  final FaceDetectionService _faceService = Get.find<FaceDetectionService>();
  final ImagePickerService _pickerService = Get.find<ImagePickerService>();

  /// 选中的图片
  final Rx<File?> selectedImage = Rx<File?>(null);

  /// 人脸检测结果
  final RxList<FaceDetectionResult> faceResults = <FaceDetectionResult>[].obs;

  /// 心情分类结果
  final RxList<ClassificationResult> classificationResults = <ClassificationResult>[].obs;

  /// 是否正在分析
  final RxBool isProcessing = false.obs;

  /// 状态文本
  final RxString statusText = '选择或拍摄一张包含人脸的图片\n开始心情分析'.obs;

  /// 归一化后的图片尺寸（用于人脸框坐标映射）
  final Rx<Size> normalizedImageSize = Size.zero.obs;

  /// 是否正在初始化模型
  final RxBool isInitializing = true.obs;

  /// 初始化状态文本
  final RxString initStatusText = '正在加载模型...'.obs;

  @override
  void onInit() {
    super.onInit();
    _initServices();
  }

  /// 初始化服务（加载 TFLite 模型 + 人脸检测器）
  Future<void> _initServices() async {
    try {
      _faceService.initializeDetector();
      initStatusText.value = '正在加载推理模型...';

      final bool loaded = await _tfliteService.loadModel();
      if (!loaded) {
        initStatusText.value = '模型加载失败，仅人脸检测可用';
      } else {
        initStatusText.value = '初始化完成';
      }
    } catch (e) {
      initStatusText.value = '初始化出错: $e';
    } finally {
      isInitializing.value = false;
    }
  }

  /// 从相册选图
  Future<void> pickFromAlbum() async {
    final File? image = await _pickerService.pickImageFromGallery();
    if (image != null) {
      selectedImage.value = image;
      await _analyzeImage();
    }
  }

  /// 拍照
  Future<void> pickFromCamera() async {
    final File? image = await _pickerService.pickImageFromCamera();
    if (image != null) {
      selectedImage.value = image;
      await _analyzeImage();
    }
  }

  /// 分析图片
  Future<void> _analyzeImage() async {
    if (selectedImage.value == null) return;
    isProcessing.value = true;
    statusText.value = '正在分析...';
    faceResults.clear();
    classificationResults.clear();

    try {
      // 关键步骤：归一化图片文件的 EXIF 方向
      //
      // image_picker 在 iOS 上 resize 图片时，UIImage 已按 EXIF 方向旋转像素，
      // 但保存的临时文件仍可能携带原始 EXIF orientation 标记。
      // ML Kit 的 fromFilePath() 会再读 EXIF 再旋转 → 双重旋转 → 人脸检测失败。
      //
      // 解决方案：bakeOrientation 将旋转"烧录"到像素中，encodeJpg 不写 EXIF 标记，
      // 这样 ML Kit 看到的就是正确方向的图片，不会再二次旋转。
      final File normalizedFile = await _normalizeImageFile(selectedImage.value!);
      selectedImage.value = normalizedFile;

      // Step 1: 人脸检测
      final InputImage inputImage = InputImage.fromFilePath(normalizedFile.path);
      final List<Face> faces = await _faceService.detectFaces(inputImage);

      if (faces.isEmpty) {
        statusText.value = '未检测到人脸';
        await _classifyFullImage();
        return;
      }

      faceResults.value = faces.map((Face f) => FaceDetectionResult.fromFace(f)).toList();
      statusText.value = '检测到 ${faces.length} 张人脸';

      // Step 2: 裁剪 + 分类每张人脸
      await _classifyFaces(faces);
    } catch (e) {
      statusText.value = '分析失败: $e';
    } finally {
      isProcessing.value = false;
    }
  }

  /// 归一化图片文件：bakeOrientation + 写回（不带 EXIF 旋转标记）
  ///
  /// image_picker 在 iOS 上 resize 图片时，像素已经按 EXIF 方向旋转了，
  /// 但保存的文件仍可能携带原始 EXIF orientation 标记。
  /// ML Kit 的 fromFilePath() 会再读 EXIF 再旋转 → 双重旋转 → 检测失败。
  /// bakeOrientation 将旋转"烧录"到像素中，encodeJpg 不写 EXIF 旋转标记，
  /// 这样 ML Kit 看到的就是正确方向的图片。
  Future<File> _normalizeImageFile(File imageFile) async {
    final Uint8List bytes = await imageFile.readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return imageFile;

    // 将 EXIF 方向烧录到像素中
    final img.Image normalized = img.bakeOrientation(decoded);

    // encodeJpg 不写 EXIF orientation，旋转标记被清除
    final Uint8List normalizedBytes = Uint8List.fromList(img.encodeJpg(normalized, quality: 95));

    // 写回临时文件
    final Directory tempDir = await getTemporaryDirectory();
    final String normalizedPath =
        '${tempDir.path}/normalized_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final File normalizedFile = File(normalizedPath);
    await normalizedFile.writeAsBytes(normalizedBytes);

    return normalizedFile;
  }

  /// 对全图分类（无人脸 fallback）
  Future<void> _classifyFullImage() async {
    if (!_tfliteService.isModelLoaded) return;
    final Uint8List bytes = await selectedImage.value!.readAsBytes();
    final ClassificationResult result = _tfliteService.classifyFaceImage(bytes);
    classificationResults.value = [result];
    _updateNormalizedSize(bytes);
  }

  /// 裁剪 + 分类人脸
  ///
  /// 裁剪时在人脸框外加 40% 边距，让模型能看到更多上下文（下巴、额头等），
  /// 提高表情识别的准确率。
  Future<void> _classifyFaces(List<Face> faces) async {
    if (!_tfliteService.isModelLoaded) return;

    final Uint8List originalBytes = await selectedImage.value!.readAsBytes();
    img.Image? originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) return;

    // 归一化 EXIF 方向（防御性编程，文件应该已经归一化过）
    originalImage = img.bakeOrientation(originalImage);
    normalizedImageSize.value = Size(
      originalImage.width.toDouble(),
      originalImage.height.toDouble(),
    );

    final List<ClassificationResult> results = [];

    for (int i = 0; i < faces.length; i++) {
      try {
        final Face face = faces[i];
        final Rect box = face.boundingBox;

        // 人脸框外加 40% 边距，让模型看到更多上下文
        final double margin = max(box.width, box.height) * AppConstants.faceCropMarginRatio;

        int left = (box.left - margin).toInt().clamp(0, originalImage.width);
        int top = (box.top - margin).toInt().clamp(0, originalImage.height);
        int right = (box.right + margin).toInt().clamp(0, originalImage.width);
        int bottom = (box.bottom + margin).toInt().clamp(0, originalImage.height);

        final img.Image faceImg = img.copyCrop(
          originalImage,
          x: left,
          y: top,
          width: right - left,
          height: bottom - top,
        );

        // 编码为 PNG 送入模型
        final Uint8List faceBytes = Uint8List.fromList(img.encodePng(faceImg));
        final ClassificationResult result = _tfliteService.classifyFaceImage(faceBytes);
        results.add(result.copyWithFaceIndex(i));
      } catch (e) {
        debugPrint('人脸 #$i 分类失败: $e');
      }
    }

    classificationResults.value = results;
  }

  void _updateNormalizedSize(Uint8List imageBytes) {
    final img.Image? decoded = img.decodeImage(imageBytes);
    if (decoded != null) {
      final img.Image normalized = img.bakeOrientation(decoded);
      normalizedImageSize.value = Size(
        normalized.width.toDouble(),
        normalized.height.toDouble(),
      );
    }
  }
}
