//
//  MoodResultView.swift
//  coreML_iOS_test
//
//  心情结果卡片 — frame 布局
//  左侧显示裁剪后的人脸缩略图，右侧显示心情分析结果
//

import UIKit

class MoodResultView: UIView {

    // MARK: - 左侧：人脸缩略图

    private let faceImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.layer.cornerRadius = 8
        iv.clipsToBounds = true
        iv.backgroundColor = .tertiarySystemBackground
        iv.layer.borderWidth = 1
        iv.layer.borderColor = UIColor.systemGray4.cgColor
        return iv
    }()

    /// 人脸缩略图上方的提示标签
    private let faceHintLabel: UILabel = {
        let label = UILabel()
        label.text = "模型看到的"
        label.font = .systemFont(ofSize: 10)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        return label
    }()

    // MARK: - 右侧：心情结果

    private let faceIndexLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = .secondaryLabel
        return label
    }()

    private let moodLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .bold)
        return label
    }()

    private let classLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .tertiaryLabel
        return label
    }()

    private let confidenceBar: UIProgressView = {
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progressTintColor = .systemBlue
        return bar
    }()

    private let confidenceLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4

        addSubview(faceHintLabel)
        addSubview(faceImageView)
        addSubview(faceIndexLabel)
        addSubview(moodLabel)
        addSubview(classLabel)
        addSubview(confidenceBar)
        addSubview(confidenceLabel)
        addSubview(descriptionLabel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let padding: CGFloat = 12
        let imgSize: CGFloat = 72   // 人脸缩略图大小
        let gap: CGFloat = 12        // 左右间距

        // 左侧：人脸缩略图
        let leftX = padding
        faceHintLabel.frame = CGRect(x: leftX, y: padding, width: imgSize, height: 14)
        faceImageView.frame = CGRect(x: leftX, y: padding + 16, width: imgSize, height: imgSize)

        // 右侧：心情结果
        let rightX = leftX + imgSize + gap
        let rightW = bounds.width - rightX - padding
        var y: CGFloat = padding

        faceIndexLabel.frame = CGRect(x: rightX, y: y, width: rightW, height: 20)
        y += 22

        moodLabel.frame = CGRect(x: rightX, y: y, width: rightW, height: 26)
        y += 28

        classLabel.frame = CGRect(x: rightX, y: y, width: rightW, height: 16)
        y += 20

        confidenceBar.frame = CGRect(x: rightX, y: y, width: rightW, height: 10)
        y += 14

        confidenceLabel.frame = CGRect(x: rightX, y: y, width: rightW, height: 16)
        y += 20

        descriptionLabel.frame = CGRect(x: rightX, y: y, width: rightW, height: max(bounds.height - y - padding, 16))
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 110)
    }

    // MARK: - 配置

    func configure(with result: MoodResult) {
        faceIndexLabel.text = "人脸 #\(result.faceIndex + 1)"
        moodLabel.text = result.mood.rawValue
        classLabel.text = "分类: \(result.classificationLabel)"
        confidenceBar.progress = Float(result.confidence)
        confidenceLabel.text = String(format: "置信度: %.1f%%", result.confidence * 100)
        descriptionLabel.text = result.mood.description

        moodLabel.textColor = colorForMood(result.mood)
        confidenceBar.progressTintColor = colorForMood(result.mood)

        // 设置人脸缩略图
        if let faceImage = result.faceImage {
            faceImageView.image = faceImage
            faceHintLabel.isHidden = false
        } else {
            faceImageView.image = nil
            faceHintLabel.isHidden = true
        }
    }

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
