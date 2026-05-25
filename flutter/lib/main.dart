import 'package:ai_scan/app/core/theme/app_theme.dart';
import 'package:ai_scan/app/modules/mood_tabs/bindings/mood_tabs_binding.dart';
import 'package:ai_scan/app/modules/mood_tabs/views/mood_tabs_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AiScanApp());
}

class AiScanApp extends StatelessWidget {
  const AiScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'AI 心情检测',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const MoodDetectionPage(),
      initialBinding: MoodTabsBinding(),
      debugShowCheckedModeBanner: false,
    );
  }
}
