import 'package:ai_scan/app/data/services/face_detection_service.dart';
import 'package:ai_scan/app/data/services/image_picker_service.dart';
import 'package:ai_scan/app/data/services/tflite_service.dart';
import 'package:ai_scan/app/modules/main_tab/controllers/main_tab_controller.dart';
import 'package:ai_scan/app/modules/mood_tabs/controllers/mood_tabs_controllers.dart';
import 'package:ai_scan/app/modules/native_realtime_mood/controllers/native_realtime_mood_controller.dart';
import 'package:get/get.dart';

/// 主页 Tab 绑定
///
/// 统一注册两个 Tab 页面所需的全部依赖：
/// - 共享服务：TfliteService、FaceDetectionService（permanent，切换 Tab 不释放）
/// - 页面控制器：MoodDetectionController、NativeRealtimeMoodController
/// - Tab 控制器：MainTabController（permanent，随 App 生命周期）
class MainTabBinding extends Bindings {
  @override
  void dependencies() {
    // 共享服务（permanent 确保切换 Tab 时模型不会重新加载）
    if (!Get.isRegistered<TfliteService>()) {
      Get.put<TfliteService>(TfliteService(), permanent: true);
    }
    if (!Get.isRegistered<FaceDetectionService>()) {
      Get.put<FaceDetectionService>(FaceDetectionService(), permanent: true);
    }
    if (!Get.isRegistered<ImagePickerService>()) {
      Get.put<ImagePickerService>(ImagePickerService());
    }

    // Tab 页面控制器
    Get.put<MoodDetectionController>(MoodDetectionController());
    Get.put<NativeRealtimeMoodController>(NativeRealtimeMoodController());

    // Tab 切换控制器
    Get.put<MainTabController>(MainTabController(), permanent: true);
  }
}
