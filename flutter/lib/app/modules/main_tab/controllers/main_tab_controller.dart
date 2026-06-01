import 'package:get/get.dart';

/// 主页 Tab 控制器
///
/// 管理底部导航栏的当前选中索引，
/// 通过 `RxInt` 驱动 View 层的 IndexedStack 切换。
class MainTabController extends GetxController {
  /// 当前选中的 Tab 索引
  final RxInt currentIndex = 0.obs;

  /// 切换 Tab
  void changeTab(int index) {
    currentIndex.value = index;
  }
}
