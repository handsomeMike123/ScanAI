import 'package:ai_scan/app/modules/main_tab/bindings/main_tab_binding.dart';
import 'package:ai_scan/app/modules/main_tab/views/main_tab_view.dart';
import 'package:get/get.dart';

// ============================================================
// 路由名称常量
//
// 命名规范：小写 + 下划线，与模块目录名保持一致
// ============================================================
class AppRoutes {
  AppRoutes._();

  /// 主页（Tab 布局：心情检测 + 实时检测）
  static const String mainTab = '/main_tab';
}

// ============================================================
// 路由页面定义
//
// GetPage.binding: 依赖注入绑定器，页面创建时注册 Controller，
// 页面销毁时自动释放
// ============================================================
class AppPages {
  AppPages._();

  static final List<GetPage> pages = <GetPage>[
    GetPage(
      name: AppRoutes.mainTab,
      page: () => MainTabPage(),
      binding: MainTabBinding(),
    ),
  ];
}
