import 'package:ai_scan/app/modules/native_realtime_mood/controllers/native_realtime_mood_controller.dart';
import 'package:get/get.dart';

/// 原生实时心情检测页面绑定
///
/// GetX Binding 机制：dependencies() 在页面创建时调用，
/// 注册 Controller 到 GetX 容器，页面销毁时自动释放。
class NativeRealtimeMoodBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<NativeRealtimeMoodController>(NativeRealtimeMoodController());
  }
}
