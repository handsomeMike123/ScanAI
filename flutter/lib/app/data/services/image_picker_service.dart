import 'dart:io';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

/// 图片选择服务
class ImagePickerService extends GetxService {
  final ImagePicker _imagePicker = ImagePicker();

  /// 是否正在选择图片
  final RxBool isPickingImage = false.obs;

  /// 从相册选择图片
  Future<File?> pickImageFromGallery() async {
    isPickingImage.value = true;
    try {
      final XFile? xFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (xFile == null) {
        return null;
      }
      return File(xFile.path);
    } on Exception catch (e) {
      print('选择图片失败: $e');
      return null;
    } finally {
      isPickingImage.value = false;
    }
  }

  /// 拍照获取图片
  Future<File?> pickImageFromCamera() async {
    isPickingImage.value = true;
    try {
      final XFile? xFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (xFile == null) {
        return null;
      }
      return File(xFile.path);
    } on Exception catch (e) {
      print('拍照失败: $e');
      return null;
    } finally {
      isPickingImage.value = false;
    }
  }
}
