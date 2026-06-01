import Flutter
import UIKit
import AVFoundation

// ============================================================
// 相机通道处理器
//
// 【MVVM - Channel 层（桥梁层）】
// 负责 MethodChannel 和 EventChannel 的注册与分发，
// 是原生端与 Flutter 端通信的唯一入口。
//
// 【v3 通信架构 — Texture + 双频 EventChannel】
//
// 1. MethodChannel.startCapture → 启动相机 + 注册 Texture
// 2. ← {textureId: int64} 返回纹理 ID
// 3. Texture(textureId) → GPU 纹理预览（60fps 零拷贝）
// 4. ← EventChannel(faceBounds) → ~10fps 人脸坐标 → CustomPainter 画框
// 5. ← EventChannel(detection) → 每3秒裁剪人脸 JPEG → TFLite 推理
// 6. MethodChannel.reportDetectionResult → 回传推理结果
// 7. MethodChannel.stopCapture → 停止相机 + 注销 Texture
// ============================================================
class CameraChannelHandler: NSObject {

    private static let methodChannelName = "com.ai_scan.native_camera"
    private static let eventChannelName = "com.ai_scan.native_camera_frames"

    private var methodChannel: FlutterMethodChannel?
    var eventChannel: FlutterEventChannel?
    var eventSink: FlutterEventSink?

    /// 注册通道（在 AppDelegate 中调用）
    ///
    /// - Parameter binaryMessenger: Flutter 引擎消息传递接口
    /// - Parameter textureRegistry: Flutter 纹理注册表（用于 Texture 预览）
    func register(with binaryMessenger: FlutterBinaryMessenger, textureRegistry: FlutterTextureRegistry) {
        methodChannel = FlutterMethodChannel(
            name: Self.methodChannelName,
            binaryMessenger: binaryMessenger
        )
        methodChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }

        eventChannel = FlutterEventChannel(
            name: Self.eventChannelName,
            binaryMessenger: binaryMessenger
        )
        eventChannel?.setStreamHandler(CameraFrameStreamHandler(handler: self))

        // 将纹理注册表传递给 CameraService
        CameraService.shared.setTextureRegistry(textureRegistry)

        NSLog("[CameraChannel] 通道已注册（含 TextureRegistry）")
    }

    // MARK: - MethodCall 处理

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkPermission":
            let authorized = CameraService.shared.isAuthorized
            result(["authorized": authorized])

        case "requestPermission":
            CameraService.shared.requestPermission { authorized in
                result(["authorized": authorized])
            }

        case "startCapture":
            guard CameraService.shared.isAuthorized else {
                result(FlutterError(code: "NO_PERMISSION", message: "相机权限未授权", details: nil))
                return
            }

            // 注册 Texture，获取 textureId
            let textureId = CameraService.shared.registerTexture()

            // 设置结构化帧数据回调
            CameraService.shared.onFrameReady = { [weak self] frameData in
                self?.sendFrameData(frameData)
            }

            CameraService.shared.startCapture()

            // 返回 textureId 给 Flutter
            // 纹理尺寸通过 EventChannel 的 textureSize 事件动态推送
            if let tid = textureId {
                result(["textureId": tid])
            } else {
                result(FlutterError(code: "TEXTURE_ERROR", message: "纹理创建失败", details: nil))
            }

        case "stopCapture":
            CameraService.shared.onFrameReady = nil
            CameraService.shared.stopCapture()

            // 注销 Texture
            CameraService.shared.unregisterTexture()

            result(nil)

        case "reportDetectionResult":
            handleReportDetectionResult(call: call, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 接收推理结果

    private func handleReportDetectionResult(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "参数格式错误", details: nil))
            return
        }

        let frameIndex = args["frameIndex"] as? Int ?? -1
        let mood = args["mood"] as? String ?? "Unknown"
        let confidence = args["confidence"] as? Double ?? 0
        let displayName = args["displayName"] as? String ?? ""
        let emotionProbs = args["emotionProbs"] as? [String: Double] ?? [:]

        let pct = String(format: "%.0f%%", confidence * 100)
        NSLog("[CameraChannel] 📋 帧 #\(frameIndex) 推理结果: \(displayName) \(pct)")

        if !emotionProbs.isEmpty {
            let sorted = emotionProbs.sorted { $0.value > $1.value }
            let probsStr = sorted.prefix(3).map { "\($0.key): \(String(format: "%.1f%%", $0.value * 100))" }.joined(separator: ", ")
            NSLog("[CameraChannel] 📊 Top3: \(probsStr)")
        }

        result(nil)
    }

    // MARK: - EventChannel 推送

    /// 推送结构化帧数据给 Flutter
    private func sendFrameData(_ frameData: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(frameData)
        }
    }
}

// MARK: - EventChannel StreamHandler

class CameraFrameStreamHandler: NSObject, FlutterStreamHandler {

    private weak var handler: CameraChannelHandler?

    init(handler: CameraChannelHandler) {
        self.handler = handler
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        handler?.eventSink = events
        NSLog("[CameraChannel] EventChannel: Flutter 开始监听")
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        handler?.eventSink = nil
        NSLog("[CameraChannel] EventChannel: Flutter 取消监听")
        return nil
    }
}
