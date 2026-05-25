//
//  ImageClassificationViewController.swift
//  coreML_iOS_test
//
//  表情分类 Demo（MVC - Controller 层）
//  使用 EmotiEffLib enet_b2_7 模型
//

import UIKit
import CoreML
import Vision
import QuartzCore

class ImageClassificationViewController: UIViewController {

    // MARK: - View

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.layer.borderColor = UIColor.systemGray4.cgColor
        iv.layer.borderWidth = 1
        iv.layer.cornerRadius = 12
        iv.clipsToBounds = true
        iv.backgroundColor = .secondarySystemBackground
        return iv
    }()

    private let resultLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15)
        label.textAlignment = .center
        label.text = "选择或拍摄一张包含人脸的图片\n开始表情分类"
        label.textColor = .secondaryLabel
        return label
    }()

    private let benchmarkLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .tertiaryLabel
        label.numberOfLines = 0
        return label
    }()

    private let selectButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("选择图片分类", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.backgroundColor = .systemBlue
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 8
        return btn
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private var cachedModel: MLModel?

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "表情分类"
        view.backgroundColor = .systemBackground

        view.addSubview(imageView)
        view.addSubview(resultLabel)
        view.addSubview(benchmarkLabel)
        view.addSubview(selectButton)
        view.addSubview(activityIndicator)

        selectButton.addTarget(self, action: #selector(selectImage), for: .touchUpInside)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let safe = view.safeAreaInsets
        let w = view.bounds.width
        let h = view.bounds.height
        let padding: CGFloat = 16
        let contentW = w - padding * 2

        let imgY = safe.top + padding
        let imgH = (h - safe.top - safe.bottom - padding * 5) * 0.4
        imageView.frame = CGRect(x: padding, y: imgY, width: contentW, height: imgH)
        activityIndicator.center = CGPoint(x: imageView.frame.midX, y: imageView.frame.midY)

        let resultY = imageView.frame.maxY + padding
        resultLabel.frame = CGRect(x: padding, y: resultY, width: contentW, height: 120)

        let benchY = resultLabel.frame.maxY + padding / 2
        benchmarkLabel.frame = CGRect(x: padding, y: benchY, width: contentW, height: 30)

        let btnY = benchmarkLabel.frame.maxY + padding
        selectButton.frame = CGRect(x: padding, y: btnY, width: contentW, height: 44)
    }

    // MARK: - 选图

    @objc private func selectImage() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - 核心逻辑

    private func classifyImage(image: UIImage) {
        imageView.image = image
        resultLabel.text = "正在分析表情..."
        activityIndicator.startAnimating()
        benchmarkLabel.text = ""

        // 使用 MoodDetector 统一 Pipeline
        MoodDetector.shared.detectMood(in: image) { [weak self] result in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                switch result {
                case .success(let moodResults):
                    self?.handleResults(moodResults)
                case .failure(let error):
                    self?.resultLabel.text = error.errorDescription
                }
            }
        }
    }

    private func handleResults(_ results: [MoodResult]) {
        guard let result = results.first else {
            resultLabel.text = "未检测到人脸\n请选择包含清晰人脸的图片"
            return
        }

        let mood = result.mood
        var text = "识别结果: \(mood.rawValue)\n置信度: \(String(format: "%.1f%%", result.confidence * 100))\n"

        if let probs = result.emotionProbs {
            let sorted = probs.sorted { $0.value > $1.value }
            text += "\n"
            for (label, prob) in sorted {
                let bar = String(repeating: "█", count: Int(prob * 20))
                let m = Mood.fromAffectNetLabel(label)
                text += String(format: "%@ %@  %.1f%%  %@\n", m.rawValue, label, prob * 100, bar)
            }
        }

        resultLabel.text = text
        benchmarkLabel.text = "模型: EmotiEff enet_b2_7 (AffectNet)"
    }
}

// MARK: - UIImagePickerControllerDelegate

extension ImageClassificationViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        classifyImage(image: image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
