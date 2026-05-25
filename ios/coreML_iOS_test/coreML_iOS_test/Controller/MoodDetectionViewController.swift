//
//  MoodDetectionViewController.swift
//  coreML_iOS_test
//
//  心情检测 Demo — frame 布局
//

import UIKit
import PhotosUI

class MoodDetectionViewController: UIViewController {

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

    private let overlayView = FaceOverlayView()

    private let cameraButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("📷 拍照", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.backgroundColor = .systemBlue
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 8
        return btn
    }()

    private let albumButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("🖼 相册选图", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.backgroundColor = .systemGreen
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 8
        return btn
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "选择或拍摄一张包含人脸的图片\n开始心情分析"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        return label
    }()

    private let resultsScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.isHidden = true
        return sv
    }()

    private let resultsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    /// 当前选中的图片（用于坐标映射）
    private var currentImage: UIImage?

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "心情检测"
        view.backgroundColor = .systemBackground

        view.addSubview(imageView)
        view.addSubview(overlayView)
        view.addSubview(cameraButton)
        view.addSubview(albumButton)
        view.addSubview(statusLabel)
        view.addSubview(resultsScrollView)
        resultsScrollView.addSubview(resultsStack)
        view.addSubview(activityIndicator)

        cameraButton.addTarget(self, action: #selector(openCamera), for: .touchUpInside)
        albumButton.addTarget(self, action: #selector(openAlbum), for: .touchUpInside)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let safe = view.safeAreaInsets
        let w = view.bounds.width
        let h = view.bounds.height
        let padding: CGFloat = 16
        let contentW = w - padding * 2

        // 图片区：顶部安全区 + padding，宽度铺满，高度占 35%
        let imgY = safe.top + padding
        let imgH = (h - safe.top - safe.bottom - padding * 4) * 0.35
        let imgW = contentW
        imageView.frame = CGRect(x: padding, y: imgY, width: imgW, height: imgH)
        overlayView.frame = imageView.frame

        // activityIndicator 居中在图片区
        activityIndicator.center = CGPoint(x: imageView.frame.midX, y: imageView.frame.midY)

        // 状态标签
        let statusY = imageView.frame.maxY + padding
        statusLabel.frame = CGRect(x: padding, y: statusY, width: contentW, height: 40)

        // 按钮区：两个按钮并排
        let btnY = statusLabel.frame.maxY + padding
        let btnH: CGFloat = 44
        let btnSpacing: CGFloat = 12
        let btnW = (contentW - btnSpacing) / 2
        cameraButton.frame = CGRect(x: padding, y: btnY, width: btnW, height: btnH)
        albumButton.frame = CGRect(x: padding + btnW + btnSpacing, y: btnY, width: btnW, height: btnH)

        // 结果区：铺满剩余空间
        let resultY = cameraButton.frame.maxY + padding
        let resultH = h - safe.bottom - resultY - padding
        resultsScrollView.frame = CGRect(x: 0, y: resultY, width: w, height: max(resultH, 0))
        resultsStack.frame = CGRect(x: padding, y: 8, width: contentW, height: resultsStack.frame.height)

        // 如果有人脸检测结果，重新绘制检测框
        if let image = currentImage {
            let imageSize = CGSize(width: image.cgImage?.width ?? Int(image.size.width),
                                   height: image.cgImage?.height ?? Int(image.size.height))
            overlayView.drawDetections(results: lastResults, imageSize: imageSize, viewSize: imageView.frame.size)
        }
    }

    // MARK: - 拍照/选图

    @objc private func openCamera() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func openAlbum() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - 核心逻辑

    private var lastResults: [MoodResult] = []

    private func analyzeMood(image: UIImage) {
        currentImage = image
        imageView.image = image
        overlayView.clearDetections()
        lastResults = []

        statusLabel.text = "正在分析心情..."
        activityIndicator.startAnimating()
        resultsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        resultsScrollView.isHidden = true

        MoodDetector.shared.detectMood(in: image) { [weak self] result in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()

                switch result {
                case .success(let moodResults):
                    self?.handleMoodResults(moodResults, image: image)
                case .failure(let error):
                    self?.handleError(error)
                }
            }
        }
    }

    // MARK: - 结果处理

    private func handleMoodResults(_ results: [MoodResult], image: UIImage) {
        lastResults = results

        if results.isEmpty {
            statusLabel.text = "未检测到人脸\n请选择包含清晰人脸的图片"
            return
        }

        statusLabel.text = "检测到 \(results.count) 张人脸"

        // 绘制人脸检测框
        let imageSize = CGSize(width: image.cgImage?.width ?? Int(image.size.width),
                               height: image.cgImage?.height ?? Int(image.size.height))
        overlayView.drawDetections(results: results, imageSize: imageSize, viewSize: imageView.frame.size)

        // 展示心情结果卡片
        resultsScrollView.isHidden = false
        for result in results {
            let card = MoodResultView()
            card.configure(with: result)
            resultsStack.addArrangedSubview(card)
        }

        // 更新 resultsStack 高度
        view.layoutIfNeeded()
        let stackH = resultsStack.arrangedSubviews.reduce(0) { $0 + $1.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height + 12 }
        resultsStack.frame.size.height = max(stackH, resultsScrollView.frame.height)
        resultsScrollView.contentSize = CGSize(width: view.bounds.width, height: max(stackH, resultsScrollView.frame.height))
    }

    private func handleError(_ error: MoodDetector.MoodError) {
        statusLabel.text = error.errorDescription
    }
}

// MARK: - UIImagePickerControllerDelegate

extension MoodDetectionViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        analyzeMood(image: image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
