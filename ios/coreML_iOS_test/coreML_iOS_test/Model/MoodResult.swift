//
//  MoodResult.swift
//  coreML_iOS_test
//
//  心情检测结果数据模型（MVC - Model 层）
//  适配 EmotiEffLib enet_b2_7 (AffectNet 7类) 标签
//

import Foundation
import UIKit

/// 心情类型枚举
///
/// 【核心概念】
/// - Mood 枚举与 AffectNet 数据集的7类标签一一对应
/// - 这是 Model 层的核心职责：将模型输出转化为业务含义
/// - rawValue 是中文展示名，affectNetLabel 是模型原始输出标签
enum Mood: String, CaseIterable {
    case anger     = "生气 😤"
    case disgust   = "厌恶 🤢"
    case fear      = "恐惧 😨"
    case happiness = "开心 😊"
    case neutral   = "中性 😐"
    case sadness   = "悲伤 😔"
    case surprise  = "惊讶 😲"

    /// EmotiEffLib 模型的原始输出标签（AffectNet 英文，与模型 classLabel 一致）
    var affectNetLabel: String {
        switch self {
        case .anger:     return "Anger"
        case .disgust:   return "Disgust"
        case .fear:      return "Fear"
        case .happiness: return "Happiness"
        case .neutral:   return "Neutral"
        case .sadness:   return "Sadness"
        case .surprise:  return "Surprise"
        }
    }

    /// 心情对应的颜色（用于 UI 展示）
    var color: String {
        switch self {
        case .anger:     return "#DC143C"   // 深红
        case .disgust:   return "#556B2F"   // 暗橄榄绿
        case .fear:      return "#483D8B"   // 暗蓝
        case .happiness: return "#FFD700"   // 金色
        case .neutral:   return "#808080"   // 灰色
        case .sadness:   return "#4682B4"   // 钢蓝
        case .surprise:  return "#FF8C00"   // 深橙
        }
    }

    /// 心情描述
    var description: String {
        switch self {
        case .anger:     return "检测到愤怒情绪，表情紧张"
        case .disgust:   return "检测到厌恶表情，对某事物反感"
        case .fear:      return "检测到恐惧情绪，表情不安"
        case .happiness: return "检测到积极表情，心情愉悦"
        case .neutral:   return "表情中性，情绪平稳"
        case .sadness:   return "检测到悲伤情绪，表情低落"
        case .surprise:  return "表情惊讶，意想不到"
        }
    }

    /// 从 EmotiEffLib 模型标签创建 Mood（AffectNet 格式）
    static func fromAffectNetLabel(_ label: String) -> Mood {
        switch label {
        case "Anger":     return .anger
        case "Disgust":   return .disgust
        case "Fear":      return .fear
        case "Happiness": return .happiness
        case "Neutral":   return .neutral
        case "Sadness":   return .sadness
        case "Surprise":  return .surprise
        default:          return .neutral
        }
    }

    /// 兼容旧版 FER2013 标签（小写英文）
    static func fromFERLabel(_ label: String) -> Mood {
        switch label.lowercased() {
        case "angry":     return .anger
        case "disgust":   return .disgust
        case "fear":      return .fear
        case "happy", "happiness": return .happiness
        case "neutral":   return .neutral
        case "sad", "sadness":     return .sadness
        case "surprise":  return .surprise
        default:          return .neutral
        }
    }
}

/// 单个人脸的心情检测结果
struct MoodResult {
    /// 人脸索引（图片中可能有多个人脸）
    let faceIndex: Int

    /// 人脸在原图中的位置（像素坐标）
    let faceRect: CGRect

    /// CoreML 模型的原始分类标签（AffectNet 英文，如 "Happiness"）
    let classificationLabel: String

    /// 分类置信度 (0~1)
    let confidence: Double

    /// 映射后的心情
    let mood: Mood

    /// 7类表情的概率分布（可选，用于详细展示）
    let emotionProbs: [String: Double]?

    /// 裁剪后的人脸图片（用于用户对比：模型看到的就是这张脸）
    let faceImage: UIImage?

    /// 格式化的结果描述
    var formattedResult: String {
        """
        人脸 #\(faceIndex + 1)
        心情: \(mood.rawValue)
        置信度: \(String(format: "%.1f%%", confidence * 100))
        分类: \(classificationLabel)
        说明: \(mood.description)
        """
    }
}
