//
//  RealTimeMoodViewController.swift
//  coreML_iOS_test
//
//  实时心情检测 — 前置摄像头 + Vision 人脸检测 + CoreML 心情推理
//  每3秒检测一次，心情变化时弹出 Alert
//
//  【架构设计】
//  AVCaptureSession → CVPixelBuffer（逐帧缓存）
//      ↓ 每3秒触发
//  VNImageRequestHandler(cvPixelBuffer:) → VNDetectFaceRectanglesRequest → 人脸坐标
//      ↓
//  CVPixelBuffer 裁剪人脸区域 → UIImage(.leftMirrored) → MoodDetector.classifyFaceImage()
//      ↓
//  心情变化 → UIAlertController
//

import UIKit
import AVFoundation
import Vision

class RealTimeMoodViewController: UIViewController {

    // MARK: - 摄像头

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let bufferQueue = DispatchQueue(label: "com.mood.realtime.buffer")
    private var latestPixelBuffer: CVPixelBuffer?

    // MARK: - 人脸框

    private let faceBoxLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.systemGreen.cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 3
        return layer
    }()

    // MARK: - UI 控件

    private let moodLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 26, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 16
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "👀 正在寻找人脸..."
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        return label
    }()

    // MARK: - 检测控制

    private var detectionTimer: Timer?
    private var lastMood: Mood?
    private var isProcessing = false
    private let detectionInterval: TimeInterval = 3.0

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "实时心情"
        view.backgroundColor = .systemBackground
        checkCameraAuthorization()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRunning()
        startTimer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopTimer()
        stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds

        let w = view.bounds.width
        let safe = view.safeAreaInsets

        moodLabel.frame = CGRect(x: (w - 220) / 2, y: safe.top + 20, width: 220, height: 50)
        statusLabel.frame = CGRect(x: (w - 200) / 2, y: view.bounds.height - safe.bottom - 60, width: 200, height: 36)
    }

    // MARK: - 相机权限

    private func checkCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
            setupUI()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                        self?.setupUI()
                    } else {
                        self?.showNoCameraView()
                    }
                }
            }
        default:
            showNoCameraView()
        }
    }

    private func showNoCameraView() {
        let label = UILabel()
        label.text = "⚠️ 需要相机权限才能使用实时检测\n请在设置中开启相机权限"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.frame = CGRect(x: 40, y: view.bounds.midY - 40, width: view.bounds.width - 80, height: 80)
        label.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
        view.addSubview(label)
    }

    // MARK: - 摄像头配置

    private func setupCamera() {
        captureSession.sessionPreset = .high

        // 前置摄像头
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            statusLabel.text = "⚠️ 无法访问前置摄像头"
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // 视频数据输出（获取每一帧 CVPixelBuffer）
        videoDataOutput.setSampleBufferDelegate(self, queue: bufferQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }

        // 预览层
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)

        // 人脸框层
        previewLayer.addSublayer(faceBoxLayer)
    }

    // MARK: - UI 布局

    private func setupUI() {
        view.addSubview(moodLabel)
        view.addSubview(statusLabel)
    }

    // MARK: - Session 控制

    private func startRunning() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard !(self?.captureSession.isRunning ?? true) else { return }
            self?.captureSession.startRunning()
        }
    }

    private func stopRunning() {
        guard captureSession.isRunning else { return }
        captureSession.stopRunning()
    }

    // MARK: - 定时检测（每3秒）

    private func startTimer() {
        // 先立即检测一次
        detectCurrentFrame()
        detectionTimer = Timer.scheduledTimer(withTimeInterval: detectionInterval, repeats: true) { [weak self] _ in
            self?.detectCurrentFrame()
        }
    }

    private func stopTimer() {
        detectionTimer?.invalidate()
        detectionTimer = nil
    }

    // MARK: - 帧检测核心

    private func detectCurrentFrame() {
        guard !isProcessing, let pixelBuffer = latestPixelBuffer else {
            statusLabel.text = "👀 正在寻找人脸..."
            return
        }

        isProcessing = true
        statusLabel.text = "🔍 正在检测..."

        // Vision 人脸检测（在 CVPixelBuffer 上直接运行）
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }

            guard let observations = request.results as? [VNFaceObservation],
                  let firstFace = observations.first else {
                DispatchQueue.main.async {
                    self.faceBoxLayer.path = nil
                    self.moodLabel.isHidden = true
                    self.statusLabel.text = "👀 未检测到人脸"
                    self.isProcessing = false
                }
                return
            }

            // 绘制人脸框（主线程）
            DispatchQueue.main.async {
                self.drawFaceBox(boundingBox: firstFace.boundingBox)
            }

            // 裁剪人脸 + 分类
            self.cropAndClassifyFace(pixelBuffer: pixelBuffer, faceObservation: firstFace)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])
            // 如果 perform 之后没有进入回调，释放 isProcessing
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if self?.isProcessing == true {
                    self?.isProcessing = false
                }
            }
        }
    }

    // MARK: - 人脸框绘制

    /// Vision 坐标（归一化，左下原点）→ 预览层坐标
    /// layerRectConverted 会自动处理前置摄像头镜像和旋转
    private func drawFaceBox(boundingBox: CGRect) {
        let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: boundingBox)
        let path = UIBezierPath(roundedRect: convertedRect.insetBy(dx: -2, dy: -2), cornerRadius: 8)
        faceBoxLayer.path = path.cgPath
    }

    // MARK: - 裁剪人脸 + CoreML 分类

    private func cropAndClassifyFace(pixelBuffer: CVPixelBuffer, faceObservation: VNFaceObservation) {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let bbox = faceObservation.boundingBox

        // Vision 归一化坐标 → CVPixelBuffer 像素坐标（Y 轴翻转）
        var faceRect = CGRect(
            x: bbox.origin.x * width,
            y: (1 - bbox.origin.y - bbox.height) * height,
            width: bbox.width * width,
            height: bbox.height * height
        )

        // 扩大裁剪区域（留 40% 边距，与 MoodDetector.detectMood 一致）
        let margin = max(faceRect.width, faceRect.height) * 0.4
        faceRect = faceRect.insetBy(dx: -margin, dy: -margin)
        faceRect = faceRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        // CVPixelBuffer → CIImage → 裁剪 → CGImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let croppedCGImage = CIContext().createCGImage(ciImage, from: faceRect) else {
            DispatchQueue.main.async { self.isProcessing = false }
            return
        }

        // 【关键】前置摄像头 CVPixelBuffer 是横屏传感器数据
        // .leftMirrored = 逆时针旋转90° + 水平翻转 = 自拍视角
        // 这样 MoodDetector 内部的 normalizedOrientation() 就能正确摆正人脸
        let faceUIImage = UIImage(cgImage: croppedCGImage, scale: 1.0, orientation: .leftMirrored)

        // 调用 MoodDetector 分类（跳过人脸检测，直接推理）
        MoodDetector.shared.classifyFaceImage(faceUIImage) { [weak self] result in
            DispatchQueue.main.async {
                self?.isProcessing = false

                switch result {
                case .success(let (label, confidence, _)):
                    let mood = Mood.fromAffectNetLabel(label)
                    self?.updateMoodDisplay(mood: mood, confidence: confidence)

                case .failure:
                    self?.statusLabel.text = "⚠️ 分类失败"
                    self?.moodLabel.isHidden = true
                }
            }
        }
    }

    // MARK: - 更新心情显示

    private func updateMoodDisplay(mood: Mood, confidence: Double) {
        moodLabel.isHidden = false
        let pct = String(format: "%.0f%%", confidence * 100)
        moodLabel.text = "  \(mood.rawValue)  \(pct)  "
        statusLabel.text = "✅ 每3秒检测一次"

        // 心情变化 → 弹 Alert
        if let last = lastMood, last != mood {
            showMoodChangeAlert(from: last, to: mood)
        }
        lastMood = mood
    }

    // MARK: - 心情变化 Alert

    private func showMoodChangeAlert(from oldMood: Mood, to newMood: Mood) {
        let alert = UIAlertController(
            title: "心情变化了！",
            message: "\(oldMood.rawValue)  →  \(newMood.rawValue)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension RealTimeMoodViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // 缓存最新帧，等待定时器触发时使用
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestPixelBuffer = pixelBuffer
    }
}
