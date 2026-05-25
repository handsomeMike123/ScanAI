//
//  FaceOverlayView.swift
//  coreML_iOS_test
//
//  人脸检测框绘制视图（MVC - View 层）
//  用于在图片上绘制人脸检测框和心情标签
//

import UIKit

/// 人脸检测框 + 心情标签 绘制视图
///
/// 【功能说明】
/// 1. drawDetections() — 在图片上绘制人脸框和心情标签
/// 2. clearDetections() — 清除所有绘制内容
///
/// 【技术要点】
/// - 推理结果的可视化是 Demo 的关键部分
/// - 使用 draw() 重绘而非 addSubview，性能更好
/// - 检测框需要映射回 UIImageView 的图片坐标
class FaceOverlayView: UIView {
    
    /// 检测结果数据
    private var detections: [DetectionDrawInfo] = []
    
    // MARK: - 初始化
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }
    
    /// 是否显示置信度
    var showConfidence: Bool = true
    
    /// 检测框线宽
    var lineWidth: CGFloat = 2.0
    
    // MARK: - 数据模型
    
    /// 绘制信息
    struct DetectionDrawInfo {
        let rect: CGRect          // 检测框位置
        let label: String         // 标签文本（如 "开心 😊"）
        let confidence: Double    // 置信度
        let color: UIColor        // 框颜色
    }
    
    // MARK: - 公开方法
    
    /// 设置检测结果并触发重绘
    ///
    /// - Parameter results: MoodResult 数组
    /// - Parameter imageSize: 原始图片尺寸（用于坐标映射）
    /// - Parameter viewSize: imageView 的显示尺寸
    func drawDetections(results: [MoodResult], imageSize: CGSize, viewSize: CGSize) {
        detections = results.map { result in
            // 将原图坐标映射到 View 坐标
            let scaleX = viewSize.width / imageSize.width
            let scaleY = viewSize.height / imageSize.height
            let mappedRect = CGRect(
                x: result.faceRect.origin.x * scaleX,
                y: result.faceRect.origin.y * scaleY,
                width: result.faceRect.width * scaleX,
                height: result.faceRect.height * scaleY
            )
            
            return DetectionDrawInfo(
                rect: mappedRect,
                label: result.mood.rawValue,
                confidence: result.confidence,
                color: colorForMood(result.mood)
            )
        }
        setNeedsDisplay()
    }
    
    /// 清除所有绘制
    func clearDetections() {
        detections = []
        setNeedsDisplay()
    }
    
    // MARK: - 绘制
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        for detection in detections {
            drawSingleDetection(ctx: ctx, detection: detection)
        }
    }
    
    /// 绘制单个检测框
    private func drawSingleDetection(ctx: CGContext, detection: DetectionDrawInfo) {
        let rect = detection.rect
        
        // ① 绘制检测框
        ctx.setStrokeColor(detection.color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.stroke(rect)
        
        // ② 绘制标签背景
        let labelText = showConfidence
            ? String(format: "%@ %.0f%%", detection.label, detection.confidence * 100)
            : detection.label
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.white
        ]
        let labelSize = labelText.size(withAttributes: attrs)
        let labelRect = CGRect(
            x: rect.origin.x,
            y: rect.origin.y - labelSize.height - 6,
            width: labelSize.width + 8,
            height: labelSize.height + 4
        )
        
        // 圆角背景
        let path = UIBezierPath(roundedRect: labelRect, cornerRadius: 3)
        ctx.setFillColor(detection.color.cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
        
        // ③ 绘制标签文字
        labelText.draw(
            at: CGPoint(x: rect.origin.x + 4, y: rect.origin.y - labelSize.height - 4),
            withAttributes: attrs
        )
    }
    
    // MARK: - 颜色映射
    
    /// 根据心情类型返回颜色
    private func colorForMood(_ mood: Mood) -> UIColor {
        switch mood {
        case .anger:     return .systemRed
        case .disgust:   return .systemGreen
        case .fear:      return .systemPurple
        case .happiness: return .systemYellow
        case .neutral:   return .systemGray
        case .sadness:   return .systemCyan
        case .surprise:  return .systemOrange
        }
    }
}
