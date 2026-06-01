import 'package:ai_scan/app/modules/main_tab/controllers/main_tab_controller.dart';
import 'package:ai_scan/app/modules/mood_tabs/views/mood_tabs_view.dart';
import 'package:ai_scan/app/modules/native_realtime_mood/views/native_realtime_mood_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 主页 Tab 布局
///
/// 底部双 Tab 切换：
/// - Tab 0：心情检测（拍照/相册 + TFLite 推理）
/// - Tab 1：实时检测（原生采集 + EventChannel + Flutter TFLite 推理）
///
/// 使用 IndexedStack 保持两个页面状态不丢失。
class MainTabPage extends StatelessWidget {
  MainTabPage({super.key});

  /// 两个 Tab 页面，索引与 BottomNavigationBar 一一对应
  final List<Widget> _pages = <Widget>[
    const MoodDetectionPage(),
    const NativeRealtimeMoodPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final MainTabController controller = Get.find<MainTabController>();

    return Scaffold(
      body: Obx(() => IndexedStack(
        index: controller.currentIndex.value,
        children: _pages,
      )),
      bottomNavigationBar: Obx(() => BottomNavigationBar(
        currentIndex: controller.currentIndex.value,
        onTap: controller.changeTab,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_camera_outlined),
            activeIcon: Icon(Icons.photo_camera),
            label: '心情检测',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.videocam_outlined),
            activeIcon: Icon(Icons.videocam),
            label: '实时检测',
          ),
        ],
      )),
    );
  }
}
