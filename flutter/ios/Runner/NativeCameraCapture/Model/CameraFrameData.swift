import Foundation

// ============================================================
// 原生相机采集数据模型
//
// 【设计原则】
// 数据模型独立于业务逻辑，仅负责数据承载和序列化。
// 通过 toDictionary() 方法将数据转为 Flutter 可识别的 Map，
// 用于 MethodChannel / EventChannel 传输。
//
// 【Flutter 通信数据格式】
// MethodChannel 和 EventChannel 的数据传输使用 Map<String, Any>，
// 原生端的字典会自动序列化为 Flutter 的 Map<String, dynamic>。
// 基本类型（String, Int, Double, Bool, Data/Uint8List）可直接传递。
// ============================================================

// MARK: - 帧数据

/// 单帧采集结果
///
/// 包含原生端采集的图像数据及元信息，
/// 通过 EventChannel 推送给 Flutter
struct CameraFrameData {
    /// JPEG 编码的图像数据
    /// Flutter 端通过 EventChannel 收到的就是这些 bytes
    let jpegData: Data

    /// 帧序号（递增）
    let frameIndex: Int

    /// 采集时间戳
    let timestamp: TimeInterval

    /// 图像宽度（像素）
    let width: Int

    /// 图像高度（像素）
    let height: Int

    /// 是否检测到人脸
    let hasFace: Bool

    /// 人脸区域（归一化坐标，0~1）
    let faceBoundingBox: CGRect?

    /// 转 Flutter 字典格式
    ///
    /// 注意：JPEG 数据通过 EventChannel 直接推送（FlutterEventSink 传 Data），
    /// 不需要手动编码为字典。此方法仅用于调试日志。
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "frameIndex": frameIndex,
            "timestamp": timestamp,
            "width": width,
            "height": height,
            "hasFace": hasFace,
            "dataLength": jpegData.count,
        ]
        if let bbox = faceBoundingBox {
            dict["faceBoundingBox"] = [
                "x": bbox.origin.x,
                "y": bbox.origin.y,
                "width": bbox.width,
                "height": bbox.height,
            ]
        }
        return dict
    }
}

// MARK: - 采集会话统计

/// 采集会话统计
struct CaptureSessionStats {
    /// 推送的帧数
    let frameCount: Int

    /// 检测到人脸的帧数
    let faceDetectedCount: Int

    /// 持续时间（秒）
    let duration: TimeInterval

    func toDictionary() -> [String: Any] {
        return [
            "type": "session_stats",
            "frameCount": frameCount,
            "faceDetectedCount": faceDetectedCount,
            "duration": duration,
        ]
    }
}
