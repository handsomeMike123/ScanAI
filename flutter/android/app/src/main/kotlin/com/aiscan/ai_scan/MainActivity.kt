package com.aiscan.ai_scan

import com.aiscan.ai_scan.nativecamera.channel.CameraChannelHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

// ============================================================
// MainActivity
//
// 【Android 入口 — 对比 iOS AppDelegate】
//
// iOS: AppDelegate.swift 中注册 MethodChannel
// Android: MainActivity 中注册 FlutterPlugin
//
// 【FlutterPlugin 注册方式】
// 在 configureFlutterEngine 中调用 addPlugin，
// 插件的 onAttachedToEngine 会被自动调用，
// 完成通道注册。
// ============================================================
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册原生相机通道插件
        //
        // 【关键步骤】
        // 必须在 configureFlutterEngine 中注册，
        // 否则 Flutter 端调用 MethodChannel 时找不到 Handler。
        // 类似 iOS AppDelegate 中的 cameraChannelHandler.register()
        flutterEngine.plugins.add(CameraChannelHandler())
    }
}
