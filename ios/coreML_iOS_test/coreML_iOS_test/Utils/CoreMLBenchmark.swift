//
//  CoreMLBenchmark.swift
//  coreML_iOS_test
//
//  CoreML 性能基准测试工具
//  核心内容：模型量化对比、计算单元选择、推理性能测量
//

import Foundation
import CoreML
import QuartzCore

/// CoreML 性能基准测试工具
///
/// 【功能说明】
/// 1. measure() — 测量模型推理时间（含 warmup、P50/P99 统计）
/// 2. formatModelSize() — 获取模型文件大小
/// 3. compareModelSizes() — 批量对比多个模型体积
///
/// 【技术要点】
/// - 首次推理较慢（冷启动），需要 warmup 轮次排除
/// - P50/P99 比 Average 更有参考价值（长尾延迟）
/// - NeuralEngine 首次调用需要编译 shader，后续复用
struct CoreMLBenchmark {
    
    // MARK: - 数据模型
    
    /// 基准测试结果
    struct BenchmarkResult {
        let modelName: String        // 模型名称
        let quantization: String     // 量化等级（FP32/FP16/INT8）
        let modelSize: String        // 模型文件大小
        let avgInferenceTime: String // 平均推理时间
        let minInferenceTime: String // 最小推理时间
        let maxInferenceTime: String // 最大推理时间
        let p50InferenceTime: String // P50 推理时间（中位数）
        let p99InferenceTime: String // P99 推理时间（长尾延迟）
    }
    
    // MARK: - 核心测量方法
    
    /// 测量 CoreML 模型推理性能
    ///
    /// - Parameters:
    ///   - model: 要测试的 CoreML 模型
    ///   - inputProvider: 闭包，每次调用返回新的模型输入（避免缓存影响）
    ///   - iterations: 测试轮次（默认30次）
    ///   - warmup: 预热轮次（默认5次，冷启动耗时较长不纳入统计）
    ///   - completion: 返回 BenchmarkResult
    ///
    /// 【技术要点】
    /// - Warmup 必不可少：首次推理时 CoreML Runtime 需要：
    ///   1. 编译 .mlmodel → .mlmodelc
    ///   2. 加载到 NeuralEngine/GPU
    ///   3. 首次执行 shader 编译
    /// - 这些开销在后续推理中不会出现
    static func measure<T: MLFeatureProvider>(
        model: MLModel,
        inputProvider: () -> T,
        iterations: Int = 30,
        warmup: Int = 5,
        completion: (BenchmarkResult) -> Void
    ) {
        // ① Warmup 阶段 — 排除冷启动开销
        for _ in 0..<warmup {
            _ = try? model.prediction(from: inputProvider())
        }
        
        // ② 正式测量
        var times: [Double] = []
        for _ in 0..<iterations {
            let input = inputProvider()
            let start = CACurrentMediaTime()
            _ = try? model.prediction(from: input)
            let end = CACurrentMediaTime()
            times.append((end - start) * 1000) // 转换为毫秒
        }
        
        // ③ 统计计算
        times.sort()
        let avg = times.reduce(0, +) / Double(times.count)
        let p50 = times[times.count / 2]
        let p99 = times[Int(Double(times.count) * 0.99)]
        
        let result = BenchmarkResult(
            modelName: model.modelDescription.metadata[MLModelMetadataKey.description] as? String ?? "Unknown",
            quantization: "—",
            modelSize: formatModelSize(model: model),
            avgInferenceTime: String(format: "%.2f ms", avg),
            minInferenceTime: String(format: "%.2f ms", times.first ?? 0),
            maxInferenceTime: String(format: "%.2f ms", times.last ?? 0),
            p50InferenceTime: String(format: "%.2f ms", p50),
            p99InferenceTime: String(format: "%.2f ms", p99)
        )
        completion(result)
    }
    
    // MARK: - 模型体积工具
    
    /// 获取模型编译后(.mlmodelc)的文件大小
    ///
    /// 【技术要点】
    /// - .mlmodel 是源文件格式，.mlmodelc 是编译后格式
    /// - Xcode 编译时自动将 .mlmodel → .mlmodelc
    /// - .mlmodelc 是目录结构，包含权重、元数据等
    static func formatModelSize(model: MLModel) -> String {
        // 尝试从编译后的 .mlmodelc 路径获取大小
        // MLModel 没有直接的 modelURL，需要外部传入路径或使用 Bundle 查找
        return "N/A — 请使用 compareModelSizes(modelPaths:) 代替"
    }
    
    /// 批量对比多个模型文件的大小
    ///
    /// 用法示例（量化对比实验）：
    /// ```
    /// let sizes = CoreMLBenchmark.compareModelSizes(modelPaths: [
    ///     "MobileNetV2_fp32.mlmodel",
    ///     "MobileNetV2_fp16.mlmodel",
    ///     "MobileNetV2_int8.mlmodel"
    /// ])
    /// ```
    static func compareModelSizes(modelPaths: [String]) -> [(name: String, size: String)] {
        modelPaths.map { path in
            let url = URL(fileURLWithPath: path)
            let name = url.deletingPathExtension().lastPathComponent
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? UInt64 {
                return (name, ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
            return (name, "N/A")
        }
    }
}
