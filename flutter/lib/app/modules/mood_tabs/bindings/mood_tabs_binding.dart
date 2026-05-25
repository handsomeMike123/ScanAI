import 'package:ai_scan/app/modules/mood_tabs/controllers/mood_tabs_controllers.dart';
import 'package:ai_scan/app/data/services/face_detection_service.dart';
import 'package:ai_scan/app/data/services/tflite_service.dart';
import 'package:ai_scan/app/data/services/image_picker_service.dart';
import 'package:get/get.dart';

/// 心情检测页面绑定
class MoodTabsBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<TfliteService>()) {
      Get.put<TfliteService>(TfliteService(), permanent: true);
    }
    if (!Get.isRegistered<FaceDetectionService>()) {
      Get.put<FaceDetectionService>(FaceDetectionService(), permanent: true);
    }
    if (!Get.isRegistered<ImagePickerService>()) {
      Get.put<ImagePickerService>(ImagePickerService());
    }
    Get.put<MoodDetectionController>(MoodDetectionController());
  }
}
