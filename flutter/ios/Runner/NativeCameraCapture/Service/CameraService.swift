import AVFoundation
import Vision
import UIKit
import Flutter

// ============================================================
// 相机采集单例服务
//
// 【MVVM - Service 层】
// 职责：AVCaptureSession 管理、Texture 预览、人脸检测、图像裁剪编码
//
// 【v3 架构 — Texture + 双频 EventChannel】
//
// 1. 预览画面: Texture（60fps 零拷贝）
//    (a) CameraTexture.copyPixelBuffer() → Flutter Texture
//    (b) CIImage oriented(.leftMirrored) → 前置摄像头修正
//
// 2. 人脸框: EventChannel(faceBounds) ~10fps
//    (a) VNDetectFaceRectanglesRequest → 归一化坐标
//    (b) Flutter CustomPainter 画框
//
// 3. 推理帧: EventChannel(detection) 每3秒
//    (a) 原生裁剪人脸区域 → JPEG
//    (b) Flutter TFLite 推理
//
// 【线程安全】
// - captureSession 配置在 sessionQueue（串行队列）上
// - 帧回调在 bufferQueue 上，仅做缓存
// - Texture 更新在 bufferQueue 上
// - 人脸检测在 global(qos: .userInitiated) 上
// - EventChannel 推送在主线程
// ============================================================
class CameraService: NSObject {

    // MARK: - 单例

    static let shared = CameraService()
    private override init() { super.init() }

    // MARK: - 相机属性

    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let bufferQueue = DispatchQueue(label: "com.ai_scan.camera.buffer")
    private let sessionQueue = DispatchQueue(label: "com.ai_scan.camera.session")

    /// 最新帧缓存（用于人脸检测和裁剪）
    private var latestPixelBuffer: CVPixelBuffer?

    /// 是否正在运行
    private(set) var isRunning: Bool = false

    // MARK: - Texture 属性

    /// Flutter 纹理注册表
    private var textureRegistry: FlutterTextureRegistry?

    /// 相机纹理提供者
    private var cameraTexture: CameraTexture?

    /// 纹理 ID（传递给 Flutter 端）
    private(set) var textureId: Int64?

    /// 纹理尺寸（由 CameraTexture 在首帧更新时设置）
    private(set) var textureWidth: Int = 0
    private(set) var textureHeight: Int = 0

    /// 是否已推送过纹理尺寸
    private var hasPushedTextureSize: Bool = false

    // MARK: - 帧推送回调

    /// 结构化帧数据回调（由 CameraChannelHandler 设置）
    /// 推送 [String: Any] 数据，通过 type 区分 faceBounds / detection
    var onFrameReady: (([String: Any]) -> Void)?

    // MARK: - 人脸坐标缓存

    /// 最近一次人脸检测结果（归一化坐标 0~1）
    private var cachedFaceBounds: [[String: Float]] = []

    // MARK: - 检测控制

    private var isProcessing: Bool = false
    private var isDetectingFace: Bool = false
    private var faceDetectionTimer: Timer?
    private var detectionTimer: Timer?
    private var frameIndex: Int = 0
    private let detectionInterval: TimeInterval = 3.0
    private let faceDetectionInterval: TimeInterval = 0.1 // ~10fps

    private var sessionStartTime: Date?
    private var faceDetectedCount: Int = 0

    // MARK: - 权限

    var authorizationStatus: AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .video)
    }

    var isAuthorized: Bool {
        return authorizationStatus == .authorized
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        switch authorizationStatus {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    // MARK: - Texture 管理

    /// 设置 Flutter 纹理注册表（由 CameraChannelHandler 在注册时调用）
    func setTextureRegistry(_ registry: FlutterTextureRegistry) {
        self.textureRegistry = registry
    }

    /// 注册纹理，返回 textureId（由 CameraChannelHandler 在 startCapture 时调用）
    func registerTexture() -> Int64? {
        let texture = CameraTexture()
        let id = textureRegistry?.register(texture)
        texture.textureId = id
        cameraTexture = texture
        textureId = id
        hasPushedTextureSize = false

        NSLog("[CameraService] Texture 已注册, id = \(id ?? -1)")
        return id
    }

    /// 注销纹理（由 CameraChannelHandler 在 stopCapture 时调用）
    func unregisterTexture() {
        if let id = textureId {
            textureRegistry?.unregisterTexture(id)
            NSLog("[CameraService] Texture 已注销, id = \(id)")
        }
        cameraTexture?.dispose()
        cameraTexture = nil
        textureId = nil
    }

    // MARK: - 相机配置

    @discardableResult
    func configureFrontCamera() -> Bool {
        guard !captureSession.isRunning else { return true }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .high

        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        guard captureSession.canAddInput(input) else { return false }
        captureSession.addInput(input)

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: bufferQueue)
        guard captureSession.canAddOutput(videoDataOutput) else { return false }
        captureSession.addOutput(videoDataOutput)

        return true
    }

    // MARK: - 采集控制

    func startCapture() {
        frameIndex = 0
        faceDetectedCount = 0
        isProcessing = false
        isDetectingFace = false
        latestPixelBuffer = nil
        cachedFaceBounds = []
        sessionStartTime = Date()

        configureFrontCamera()

        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
                DispatchQueue.main.async {
                    self?.isRunning = self?.captureSession.isRunning ?? false
                    NSLog("[CameraService] 相机已启动（Texture 模式）")
                }
            }
        }

        startTimers()
    }

    func stopCapture() {
        stopTimers()

        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        isRunning = false
        latestPixelBuffer = nil
        isProcessing = false
        isDetectingFace = false
        cachedFaceBounds = []

        NSLog("[CameraService] 相机已停止，共推送 \(frameIndex) 帧")
    }

    // MARK: - 定时器

    private func startTimers() {
        // 人脸检测定时器（~10fps，仅推送坐标）
        runFaceDetection()
        faceDetectionTimer = Timer.scheduledTimer(
            withTimeInterval: faceDetectionInterval,
            repeats: true
        ) { [weak self] _ in
            self?.runFaceDetection()
        }

        // 检测定时器（每3秒，推送裁剪人脸 JPEG）
        detectCurrentFrame()
        detectionTimer = Timer.scheduledTimer(
            withTimeInterval: detectionInterval,
            repeats: true
        ) { [weak self] _ in
            self?.detectCurrentFrame()
        }
    }

    private func stopTimers() {
        faceDetectionTimer?.invalidate()
        faceDetectionTimer = nil
        detectionTimer?.invalidate()
        detectionTimer = nil
    }

    // MARK: - 人脸检测（~10fps，仅推送坐标）

    /// 轻量级人脸检测：仅推送归一化坐标给 Flutter，不编码 JPEG
    ///
    /// 对比旧方案：
    /// - 旧：每 200ms 编码全帧 JPEG + 坐标 → 重开销 ~25ms/帧
    /// - 新：每 100ms 仅推送坐标 → 轻开销 <1ms/帧
    private func runFaceDetection() {
        guard !isDetectingFace, let pixelBuffer = latestPixelBuffer else { return }
        isDetectingFace = true

        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }
            self.isDetectingFace = false

            if let error = error {
                NSLog("[CameraService] 人脸检测错误: \(error)")
                return
            }

            let observations = request.results as? [VNFaceObservation] ?? []

            // 转换为归一化坐标（左上角原点，Flutter 习惯）
            //
            // 【坐标变换说明】
            // Vision 返回的是 CVPixelBuffer 原始坐标系（landscape，左下角原点）
            // Texture 显示的是 .leftMirrored 方向（portrait + 水平镜像）
            // 所以需要做 90° 旋转 + 镜像 的坐标变换：
            //   landscape (lx, ly) → portrait (ly, 1-lx)
            //   宽高也互换：landscape 的 width → portrait 的 height
            let newBounds: [[String: Float]] = observations.map { obs in
                let bbox = obs.boundingBox
                return [
                    "left": Float(bbox.origin.y),
                    "top": Float(1 - bbox.origin.x - bbox.width),
                    "right": Float(bbox.origin.y + bbox.height),
                    "bottom": Float(1 - bbox.origin.x),
                ]
            }

            // 仅在人脸框变化时推送（减少 EventChannel 流量）
            if newBounds != self.cachedFaceBounds {
                self.cachedFaceBounds = newBounds

                let faceData: [String: Any] = [
                    "type": "faceBounds",
                    "faceBounds": newBounds,
                ]

                DispatchQueue.main.async {
                    self.onFrameReady?(faceData)
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                NSLog("[CameraService] Vision 执行失败: \(error)")
                DispatchQueue.main.async { self?.isDetectingFace = false }
            }
        }
    }

    // MARK: - 检测帧核心（每3秒，推送裁剪人脸 JPEG）

    private func detectCurrentFrame() {
        guard !isProcessing, let pixelBuffer = latestPixelBuffer else {
            NSLog("[CameraService] 跳过：无可用帧或正在处理")
            return
        }

        isProcessing = true
        NSLog("[CameraService] 开始检测帧 #\(frameIndex + 1)")

        if cachedFaceBounds.isEmpty {
            // 无人脸 → 推送完整帧
            pushDetectionFrame(pixelBuffer: pixelBuffer)
        } else {
            // 有人脸 → 裁剪人脸区域
            cropAndEncodeFace(pixelBuffer: pixelBuffer, normalizedRect: cachedFaceBounds[0])
        }
    }

    // MARK: - 人脸裁剪 + 编码

    /// 根据归一化坐标裁剪人脸区域并编码为 JPEG
    private func cropAndEncodeFace(pixelBuffer: CVPixelBuffer, normalizedRect: [String: Float]) {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // 归一化坐标 → 像素坐标
        // 注意：pixelBuffer 是传感器方向（landscape），人脸坐标是 portrait 方向的
        // 所以需要根据方向做坐标变换
        //
        // 前置摄像头传感器：landscape right
        // portrait 坐标系中的 (left, top, right, bottom) 映射到传感器坐标系：
        //   传感器 x = portrait y (即 top → sensor_x)
        //   传感器 y = portrait width - portrait x (即 width - right → sensor_y)
        let sensorLeft = CGFloat(normalizedRect["top"] ?? 0) * width
        let sensorTop = CGFloat(1.0 - (normalizedRect["right"] ?? 0)) * height
        let sensorRight = CGFloat(normalizedRect["bottom"] ?? 0) * width
        let sensorBottom = CGFloat(1.0 - (normalizedRect["left"] ?? 0)) * height

        var faceRect = CGRect(
            x: sensorLeft,
            y: sensorTop,
            width: sensorRight - sensorLeft,
            height: sensorBottom - sensorTop
        )

        // 添加边距
        let margin = max(faceRect.width, faceRect.height) * 0.4
        faceRect = faceRect.insetBy(dx: -margin, dy: -margin)
        faceRect = faceRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ciContext = CIContext()
        guard let croppedCGImage = ciContext.createCGImage(ciImage, from: faceRect) else {
            pushDetectionFrame(pixelBuffer: pixelBuffer)
            return
        }

        // 前置摄像头修正方向
        let faceUIImage = UIImage(cgImage: croppedCGImage, scale: 1.0, orientation: .leftMirrored)
        guard let jpegData = faceUIImage.jpegData(compressionQuality: 0.8) else {
            self.isProcessing = false
            return
        }

        self.frameIndex += 1
        NSLog("[CameraService] 帧 #\(self.frameIndex) 已裁剪人脸: \(faceUIImage.size)")

        let frameData: [String: Any] = [
            "type": "detection",
            "data": jpegData,
            "frameIndex": self.frameIndex,
        ]

        DispatchQueue.main.async {
            self.onFrameReady?(frameData)
            self.isProcessing = false
        }
    }

    /// 编码完整帧并推送检测帧（无人脸时降级）
    private func pushDetectionFrame(pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ciContext = CIContext()

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            self.isProcessing = false
            return
        }

        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .leftMirrored)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.6) else {
            self.isProcessing = false
            return
        }

        self.frameIndex += 1
        NSLog("[CameraService] 帧 #\(self.frameIndex) 完整帧推送")

        let frameData: [String: Any] = [
            "type": "detection",
            "data": jpegData,
            "frameIndex": self.frameIndex,
        ]

        DispatchQueue.main.async {
            self.onFrameReady?(frameData)
            self.isProcessing = false
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 缓存原始帧（供人脸检测和裁剪使用）
        latestPixelBuffer = pixelBuffer

        // 更新 Texture（GPU 零拷贝预览）
        cameraTexture?.update(with: pixelBuffer)

        // 首帧时推送纹理尺寸给 Flutter
        if !hasPushedTextureSize, let texture = cameraTexture {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            // .leftMirrored 后宽高互换
            let rotatedWidth = height  // portrait 宽 = sensor 高
            let rotatedHeight = width  // portrait 高 = sensor 宽
            textureWidth = rotatedWidth
            textureHeight = rotatedHeight
            hasPushedTextureSize = true

            let sizeData: [String: Any] = [
                "type": "textureSize",
                "width": rotatedWidth,
                "height": rotatedHeight,
            ]
            DispatchQueue.main.async { [weak self] in
                self?.onFrameReady?(sizeData)
            }
            NSLog("[CameraService] 纹理尺寸: \(rotatedWidth)x\(rotatedHeight)")
        }

        // 通知 Flutter 有新帧可用
        if let textureId = textureId {
            textureRegistry?.textureFrameAvailable(textureId)
        }
    }
}
