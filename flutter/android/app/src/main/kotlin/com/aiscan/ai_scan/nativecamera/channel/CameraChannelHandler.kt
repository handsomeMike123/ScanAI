package com.aiscan.ai_scan.nativecamera.channel

import android.app.Activity
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.lifecycle.LifecycleOwner
import com.aiscan.ai_scan.nativecamera.service.CameraService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

// ============================================================
// 相机通道处理器
//
// 【MVVM - Channel 层（桥梁层）】
// 负责 MethodChannel 和 EventChannel 的注册与分发，
// 是原生端与 Flutter 端通信的唯一入口。
//
// 【v3 通信架构 — Texture + 双频 EventChannel】
//
// 1. MethodChannel.startCapture → 启动相机 + 创建 SurfaceTexture
// 2. ← {textureId: long} 返回纹理 ID
// 3. Texture(textureId) → GPU 纹理预览（60fps 零拷贝）
// 4. ← EventChannel(faceBounds) → ~10fps 人脸坐标 → CustomPainter 画框
// 5. ← EventChannel(detection) → 每3秒裁剪人脸 JPEG → TFLite 推理
// 6. MethodChannel.reportDetectionResult → 回传推理结果
// 7. MethodChannel.stopCapture → 停止相机 + 释放 SurfaceTexture
// ============================================================
class CameraChannelHandler : FlutterPlugin, ActivityAware,
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val TAG = "CameraChannel"
        private const val METHOD_CHANNEL = "com.ai_scan.native_camera"
        private const val EVENT_CHANNEL = "com.ai_scan.native_camera_frames"
        private const val CAMERA_PERMISSION_REQUEST_CODE = 1001
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private val cameraService = CameraService.getInstance()
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pluginBinding: ActivityPluginBinding? = null

    /// Flutter 纹理注册表
    private var textureRegistry: io.flutter.view.TextureRegistry? = null

    // MARK: - FlutterPlugin 生命周期

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(this)

        // 保存纹理注册表
        textureRegistry = binding.textureRegistry

        Log.d(TAG, "✅ 通道已注册（含 TextureRegistry）")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        textureRegistry = null
        Log.d(TAG, "通道已注销")
    }

    // MARK: - ActivityAware 生命周期

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        pluginBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        cameraService.stopCapture()
        pluginBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        pluginBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        pluginBinding = null
        activity = null
    }

    // MARK: - MethodCall 处理

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkPermission" -> handleCheckPermission(result)
            "requestPermission" -> handleRequestPermission(result)
            "startCapture" -> handleStartCapture(result)
            "stopCapture" -> handleStopCapture(result)
            "reportDetectionResult" -> handleReportDetectionResult(call, result)
            else -> result.notImplemented()
        }
    }

    // MARK: - 权限

    private fun handleCheckPermission(result: MethodChannel.Result) {
        val authorized = activity?.let { cameraService.isAuthorized(it) } ?: false
        result.success(mapOf("authorized" to authorized))
    }

    private fun handleRequestPermission(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "无法获取 Activity", null)
            return
        }
        if (cameraService.isAuthorized(act)) {
            result.success(mapOf("authorized" to true))
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            act,
            arrayOf(android.Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST_CODE) return false
        val authorized = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(mapOf("authorized" to authorized))
        pendingPermissionResult = null
        return true
    }

    // MARK: - 采集控制

    private fun handleStartCapture(result: MethodChannel.Result) {
        val context = activity
        if (context == null) {
            result.error("NO_ACTIVITY", "无法获取 Activity", null)
            return
        }
        if (!cameraService.isAuthorized(context)) {
            result.error("NO_PERMISSION", "相机权限未授权", null)
            return
        }

        // 创建 SurfaceTexture，获取 textureId
        val registry = textureRegistry
        if (registry == null) {
            result.error("NO_TEXTURE_REGISTRY", "纹理注册表不可用", null)
            return
        }

        val surfaceTextureEntry = registry.createSurfaceTexture()
        cameraService.setSurfaceTextureEntry(surfaceTextureEntry)

        // 设置结构化帧数据回调
        cameraService.onFrameReady = { frameData ->
            sendFrameData(frameData)
        }

        val lifecycleOwner = activity as? LifecycleOwner
        if (lifecycleOwner == null) {
            result.error("NO_LIFECYCLE", "Activity 未实现 LifecycleOwner", null)
            return
        }

        cameraService.startCapture(context, lifecycleOwner)

        // 返回 textureId 给 Flutter
        // 纹理尺寸通过 EventChannel 的 textureSize 事件动态推送
        val textureId = surfaceTextureEntry.id()
        result.success(mapOf("textureId" to textureId))
    }

    private fun handleStopCapture(result: MethodChannel.Result) {
        cameraService.onFrameReady = null
        cameraService.stopCapture()
        result.success(null)
    }

    // MARK: - 接收推理结果

    private fun handleReportDetectionResult(call: MethodCall, result: MethodChannel.Result) {
        val frameIndex = call.argument<Int>("frameIndex") ?: -1
        val mood = call.argument<String>("mood") ?: "Unknown"
        val confidence = call.argument<Double>("confidence") ?: 0.0
        val displayName = call.argument<String>("displayName") ?: ""
        @Suppress("UNCHECKED_CAST")
        val emotionProbs = call.argument<Map<String, Double>>("emotionProbs") ?: emptyMap()

        val pct = "%.0f%%".format(confidence * 100)
        Log.d(TAG, "📋 帧 #$frameIndex 推理结果: $displayName $pct")

        if (emotionProbs.isNotEmpty()) {
            val top3 = emotionProbs.entries
                .sortedByDescending { it.value }
                .take(3)
                .joinToString(", ") { "${it.key}: ${"%.1f%%".format(it.value * 100)}" }
            Log.d(TAG, "📊 Top3: $top3")
        }

        result.success(null)
    }

    // MARK: - EventChannel 推送

    /**
     * 推送结构化帧数据给 Flutter
     *
     * frameData 是 Map<String, Any?>，包含：
     * - type: "faceBounds" | "detection"
     * - faceBounds 类型: faceBounds 坐标列表
     * - detection 类型: data (JPEG), frameIndex
     */
    private fun sendFrameData(frameData: Map<String, Any?>) {
        activity?.runOnUiThread {
            eventSink?.success(frameData)
        }
    }

    // MARK: - EventChannel.StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        Log.d(TAG, "EventChannel: Flutter 开始监听")
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        Log.d(TAG, "EventChannel: Flutter 取消监听")
    }
}
