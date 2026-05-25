//
//  MoodDetector.swift
//  coreML_iOS_test
//
//  心情检测 Pipeline 工具类
//  核心流程：图片 → Vision 人脸检测 → 裁剪人脸 → MLMultiArray 224×224 → CoreML EmotiEff 推理 → 心情映射
//
//  【模型】EmotiEffLib enet_b2_7 (EfficientNet-B2, AffectNet 7类)
//  【输入】(1, 3, 224, 224) RGB float32, 像素值 0-255
//  【输出】7类 logits + classLabel + classLabel_probs
//

import UIKit
import CoreML
import Vision

/// 心情检测器
class MoodDetector {

    static let shared = MoodDetector()

    private var cachedModel: MLModel?

    static var debugMode: Bool = true

    private init() {}

    // MARK: - 错误类型

    enum MoodError: Error, LocalizedError {
        case noFaceDetected
        case modelNotFound
        case imageConversionFailed
        case inferenceFailed(String)

        var errorDescription: String? {
            switch self {
            case .noFaceDetected: return "未检测到人脸，请确保图片中包含清晰的人脸"
            case .modelNotFound: return "CoreML 模型未找到"
            case .imageConversionFailed: return "图片格式转换失败"
            case .inferenceFailed(let msg): return "推理失败: \(msg)"
            }
        }
    }

    // AffectNet 7类标签
    private let affectNetLabels = ["Anger", "Disgust", "Fear", "Happiness", "Neutral", "Sadness", "Surprise"]

    /// 预处理方式切换
    /// - false: 方案A — CVPixelBuffer 直接读 ARGB 字节（默认）
    /// - true:  方案B — CoreMLHelpers toByteArrayRGBA（推荐）
    static var useCoreMLHelpers = false

    // MARK: - 核心 Pipeline

    func detectMood(in image: UIImage, completion: @escaping (Result<[MoodResult], MoodError>) -> Void) {
        detectFaces(in: image) { [weak self] result in
            switch result {
            case .success(let faceObservations):
                guard !faceObservations.isEmpty else {
                    completion(.failure(.noFaceDetected))
                    return
                }

                var moodResults: [MoodResult] = []
                let group = DispatchGroup()

                for (index, observation) in faceObservations.enumerated() {
                    group.enter()

                    let boundingBox = observation.boundingBox
                    let imageWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width))
                    let imageHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height))

                    let faceRect = CGRect(
                        x: boundingBox.origin.x * imageWidth,
                        y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
                        width: boundingBox.width * imageWidth,
                        height: boundingBox.height * imageHeight
                    )

                    let margin = max(faceRect.width, faceRect.height) * 0.4
                    let expandedRect = faceRect.insetBy(dx: -margin, dy: -margin)
                    let clampedRect = expandedRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

                    guard let faceImage = image.cgImage?.cropping(to: clampedRect) else {
                        group.leave()
                        continue
                    }

                    let faceUIImage = UIImage(cgImage: faceImage, scale: image.scale, orientation: image.imageOrientation)

                    self?.classifyFace(faceUIImage, faceRect: faceRect) { classificationResult in
                        switch classificationResult {
                        case .success(let (label, confidence, probs)):
                            let mood = Mood.fromAffectNetLabel(label)
                            let result = MoodResult(
                                faceIndex: index,
                                faceRect: faceRect,
                                classificationLabel: label,
                                confidence: confidence,
                                mood: mood,
                                emotionProbs: probs,
                                faceImage: faceUIImage
                            )
                            moodResults.append(result)
                        case .failure:
                            let result = MoodResult(
                                faceIndex: index,
                                faceRect: faceRect,
                                classificationLabel: "未知",
                                confidence: 0,
                                mood: .neutral,
                                emotionProbs: nil,
                                faceImage: faceUIImage
                            )
                            moodResults.append(result)
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    completion(.success(moodResults.sorted { $0.faceIndex < $1.faceIndex }))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - 人脸检测

    private func detectFaces(in image: UIImage, completion: @escaping (Result<[VNFaceObservation], MoodError>) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(.failure(.imageConversionFailed))
            return
        }

        let request = VNDetectFaceRectanglesRequest { request, error in
            if let error = error {
                completion(.failure(.inferenceFailed(error.localizedDescription)))
                return
            }
            let faces = request.results as? [VNFaceObservation] ?? []
            Self.log("👤 Vision 检测到 \(faces.count) 张人脸")
            completion(.success(faces))
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(.inferenceFailed(error.localizedDescription)))
            }
        }
    }

    // MARK: - 单张人脸分类（实时检测用）

    /// 对已裁剪的人脸图片直接进行心情分类
    ///
    /// 与 detectMood(in:) 不同，此方法跳过人脸检测，直接分类，
    /// 适用于实时摄像头场景（人脸检测由 Controller 层的 Vision 完成）。
    func classifyFaceImage(_ faceImage: UIImage, completion: @escaping (Result<(String, Double, [String: Double]?), MoodError>) -> Void) {
        classifyFace(faceImage, faceRect: .zero, completion: completion)
    }

    // MARK: - CoreML 推理

    private func classifyFace(_ faceImage: UIImage, faceRect: CGRect, completion: @escaping (Result<(String, Double, [String: Double]?), MoodError>) -> Void) {
        guard let model = loadModel() else {
            completion(.failure(.modelNotFound))
            return
        }

        // 图片预处理：根据开关选择方案
        let inputArray: MLMultiArray?
        if Self.useCoreMLHelpers {
            // 方案B: CoreMLHelpers（推荐）
            inputArray = faceImage.rgbMultiArrayCoreMLHelpers()
            Self.log("📷 预处理: CoreMLHelpers (toByteArrayRGBA)")
        } else {
            // 方案A: CVPixelBuffer 直接读字节
            let normalized = faceImage.normalizedOrientation()
            guard let pixelBuffer = normalized.pixelBufferFromUIImage(width: 224, height: 224) else {
                completion(.failure(.imageConversionFailed))
                return
            }
            inputArray = multiArrayFromCVPixelBuffer(pixelBuffer)
            Self.log("📷 预处理: CVPixelBuffer (ARGB 直接读)")
        }

        guard let array = inputArray else {
            completion(.failure(.imageConversionFailed))
            return
        }

        Self.log("📊 MLMultiArray shape=\(array.shape), dataType=\(array.dataType)")

        guard let input = try? MLDictionaryFeatureProvider(dictionary: ["image": array]) else {
            completion(.failure(.inferenceFailed("无法构造模型输入")))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let prediction = try model.prediction(from: input)
                let (label, confidence, probs) = self?.parseOutput(prediction) ?? ("Neutral", 0.5, nil)
                Self.log("🎯 推理结果: \(label) (\(String(format: "%.1f%%", confidence * 100)))")
                completion(.success((label, confidence, probs)))
            } catch {
                Self.log("❌ 推理失败: \(error)")
                completion(.failure(.inferenceFailed(error.localizedDescription)))
            }
        }
    }

    // MARK: - CVPixelBuffer → MLMultiArray

    private func multiArrayFromCVPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> MLMultiArray? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32ARGB else {
            return nil
        }

        let shape = [1, 3, height, width] as [NSNumber]
        guard let multiArray = try? MLMultiArray(shape: shape, dataType: .float32) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        let srcPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
        let hw = height * width

        for y in 0..<height {
            for x in 0..<width {
                let pixelOffset = y * bytesPerRow + x * 4
                // ARGB: offset+0=A, offset+1=R, offset+2=G, offset+3=B
                let r = srcPtr[pixelOffset + 1]
                let g = srcPtr[pixelOffset + 2]
                let b = srcPtr[pixelOffset + 3]

                let spatialIdx = y * width + x
                ptr[0 * hw + spatialIdx] = Float(r)
                ptr[1 * hw + spatialIdx] = Float(g)
                ptr[2 * hw + spatialIdx] = Float(b)
            }
        }

        return multiArray
    }

    // MARK: - 解析模型输出

    private func parseOutput(_ prediction: MLFeatureProvider) -> (String, Double, [String: Double]?) {
        if Self.debugMode {
            Self.log("📋 模型输出 features: \(prediction.featureNames)")
            for name in prediction.featureNames {
                if let value = prediction.featureValue(for: name) {
                    if let multiArr = value.multiArrayValue {
                        Self.log("  \(name): MLMultiArray shape=\(multiArr.shape)")
                    } else if !value.stringValue.isEmpty {
                        Self.log("  \(name): String = \(value.stringValue)")
                    } else if let dictVal = value.dictionaryValue as? [String: Double] {
                        Self.log("  \(name): Dictionary = \(dictVal)")
                    }
                }
            }
        }

        var topLabel = "Neutral"
        if let classLabel = prediction.featureValue(for: "classLabel")?.stringValue, !classLabel.isEmpty {
            topLabel = classLabel
        }

        var probs: [String: Double]?

        if let classLabelProbs = prediction.featureValue(for: "classLabel_probs")?.dictionaryValue as? [String: Double] {
            let allInRange = classLabelProbs.values.allSatisfy { $0 >= 0 && $0 <= 1 }
            if allInRange {
                probs = classLabelProbs
            } else {
                Self.log("⚠️ classLabel_probs 包含 logits（非概率），从 logits 手动计算 softmax")
            }
        }

        if probs == nil {
            for name in ["var_736", "logits", "output"] {
                if let logitsArray = prediction.featureValue(for: name)?.multiArrayValue {
                    let (softmaxProbs, topIdx) = softmaxFull(logitsArray)
                    var manualProbs: [String: Double] = [:]
                    for (i, label) in affectNetLabels.enumerated() {
                        manualProbs[label] = softmaxProbs[i]
                    }
                    probs = manualProbs
                    topLabel = affectNetLabels[topIdx]
                    Self.log("📈 手动 softmax from \(name):")
                    break
                }
            }
        }

        if Self.debugMode, let probs = probs {
            for (label, prob) in probs.sorted(by: { $0.value > $1.value }) {
                let bar = String(repeating: "█", count: Int(prob * 30))
                Self.log("  \(label): \(String(format: "%.4f", prob)) \(bar)")
            }
        }

        var confidence = 0.5
        if let probs = probs {
            confidence = probs[topLabel] ?? 0.5
        }

        return (topLabel, confidence, probs)
    }

    private func softmaxFull(_ logits: MLMultiArray) -> ([Double], Int) {
        let count = logits.count
        guard count > 0 else { return ([0.5], 0) }

        let ptr = logits.dataPointer.assumingMemoryBound(to: Float.self)
        var maxLogit: Float = -.greatestFiniteMagnitude
        for i in 0..<count { maxLogit = max(maxLogit, ptr[i]) }

        var expValues = [Double]()
        var sumExp: Double = 0
        var topIdx = 0
        var topExp: Double = 0

        for i in 0..<count {
            let expVal = exp(Double(ptr[i] - maxLogit))
            expValues.append(expVal)
            sumExp += expVal
            if expVal > topExp { topExp = expVal; topIdx = i }
        }

        return (expValues.map { $0 / sumExp }, topIdx)
    }

    // MARK: - 模型加载

    private func loadModel() -> MLModel? {
        if let cached = cachedModel { return cached }

        for name in ["EmotiEff_enet_b2_7_fp32"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = .all
                    let model = try MLModel(contentsOf: url, configuration: config)
                    cachedModel = model
                    Self.log("✅ 模型加载成功: \(name)")
                    return model
                } catch {
                    Self.log("⚠️ 模型加载失败 (\(name)): \(error)")
                }
            }
        }
        return nil
    }

    private static func log(_ message: String) {
        guard debugMode else { return }
        print("[MoodDetector] \(message)")
    }
}
