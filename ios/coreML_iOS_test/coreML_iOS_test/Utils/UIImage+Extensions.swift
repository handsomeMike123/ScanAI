//
//  UIImage+Extensions.swift
//  coreML_iOS_test
//
//  UIImage 图片预处理扩展
//  核心内容：CoreML 推理前的图片预处理（缩放、归一化、CVPixelBuffer 转换）
//

import UIKit
import CoreML
import Vision

extension UIImage {
    
    // MARK: - CVPixelBuffer 转换（CoreML 推理核心方法）
    
    /// 将 UIImage 转换为 CVPixelBuffer（ARGB 格式）
    ///
    /// 【关键概念】
    /// - CVPixelBuffer 是 CoreML 底层使用的像素缓冲区格式
    /// - 每个模型有固定输入尺寸，需指定 width/height
    /// - 如果用 VNCoreMLRequest，Vision 会自动处理此转换
    func pixelBuffer(width: Int = 224, height: Int = 224) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          width,
                                          height,
                                          kCVPixelFormatType_32ARGB,
                                          attrs,
                                          &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        
        // Core Graphics 坐标系是左下角为原点，需要翻转
        UIGraphicsPushContext(context)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        self.draw(in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        UIGraphicsPopContext()
        
        return buffer
    }
    
    // MARK: - 图片裁剪（用于人脸区域提取）
    
    /// 裁剪图片指定区域
    func cropped(to rect: CGRect) -> UIImage {
        guard let cgImage = self.cgImage?.cropping(to: rect) else { return self }
        return UIImage(cgImage: cgImage, scale: self.scale, orientation: self.imageOrientation)
    }
    
    // MARK: - 缩放
    
    /// 缩放到指定大小
    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    // MARK: - 方向归一化

    /// 将 UIImage 归一化为 .up 方向
    ///
    /// 【为什么需要？】
    /// 相册选取的图片通常有 orientation 属性（如 .right 表示竖拍），
    /// 但 image.cgImage 是原始传感器数据（横屏），orientation 只是显示标记。
    /// 如果直接用 cgImage 做裁剪或灰度转换，会得到旋转/翻转的图片，
    /// 导致模型看到的是歪的人脸，推理结果完全不准。
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - RGB MLMultiArray 转换（EmotiEffLib 模型专用）

    /// 将 UIImage 转换为 MLMultiArray（RGB，224×224，像素值 0-255）
    ///
    /// 【处理流程】
    /// UIImage → 方向归一化 → CGContext 缩放224×224 ARGB → 分离RGB通道 → MLMultiArray(1,3,224,224)
    ///
    /// 【关键细节】
    /// - 像素值 0-255（模型内部已有 /255.0 + ImageNet 归一化）
    /// - shape=(1,3,224,224) 对应 (batch, channel, height, width)
    /// - ARGB 格式中 R=1, G=2, B=3（offset 从1开始，0是Alpha）
    ///
    /// 【技术要点】
    /// - CoreML 的 MLMultiArray 是列优先（与 NumPy 的行优先不同）
    /// - 通道顺序必须与训练时一致：RGB 而非 BGR
    func rgbMultiArray(width: Int = 224, height: Int = 224) -> MLMultiArray? {
        // ① 方向归一化
        let normalized = self.normalizedOrientation()
        guard let sourceCGImage = normalized.cgImage else { return nil }

        // ② 创建 ARGB CGContext，缩放到 224×224
        // 使用 byteOrder32Big 确保 ARGB 在内存中按 A,R,G,B 字节顺序排列
        // iOS 默认小端序下，noneSkipFirst 的内存布局是 B,G,R,A（与直觉相反！）
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,  // ARGB 每像素4字节
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // ③ CGContext 坐标系翻转
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = context.data else { return nil }

        // ④ 创建 MLMultiArray (1, 3, 224, 224)
        let shape = [1, 3, height, width] as [NSNumber]
        guard let multiArray = try? MLMultiArray(shape: shape, dataType: .float32) else {
            return nil
        }

        // ⑤ 逐像素分离 RGB 通道
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        let bytesPerRow = context.bytesPerRow

        for y in 0..<height {
            for x in 0..<width {
                let pixelOffset = y * bytesPerRow + x * 4
                let a = pixelData.load(fromByteOffset: pixelOffset, as: UInt8.self)
                let r = pixelData.load(fromByteOffset: pixelOffset + 1, as: UInt8.self)
                let g = pixelData.load(fromByteOffset: pixelOffset + 2, as: UInt8.self)
                let b = pixelData.load(fromByteOffset: pixelOffset + 3, as: UInt8.self)

                // MLMultiArray strides for shape [1, 3, H, W]:
                // channel stride = H * W, row stride = W, col stride = 1
                let spatialIdx = y * width + x
                ptr[0 * height * width + spatialIdx] = Float(r)  // R channel
                ptr[1 * height * width + spatialIdx] = Float(g)  // G channel
                ptr[2 * height * width + spatialIdx] = Float(b)  // B channel
            }
        }

        return multiArray
    }

    // MARK: - RGB MLMultiArray 转换 — CoreMLHelpers 版本

    /// 使用 CoreMLHelpers 将 UIImage 转为 MLMultiArray（RGB，224×224，像素值 0-255）
    ///
    /// 【处理流程】
    /// UIImage → pixelBufferFromUIImage(ARGB CVPixelBuffer 224×224)
    ///       → CVPixelBuffer → CGImage → toByteArrayRGBA()
    ///       → 从 RGBA 字节数组分离 R/G/B → MLMultiArray(1,3,224,224)
    ///
    /// 【为什么用 CoreMLHelpers？】
    /// 1. pixelBufferFromUIImage() 封装了 CVPixelBuffer 创建 + CGContext 缩放，代码更简洁
    /// 2. toByteArrayRGBA() 返回明确的 [R,G,B,A,R,G,B,A,...] 字节数组，不涉及端序问题
    /// 3. 代码更清晰，CVPixelBuffer 像素格式严格定义，不受 iOS 小端序影响
    ///
    /// 【核心原理】
    /// "图片预处理是 CoreML 推理的关键环节。通过 hollance 的 CoreMLHelpers 库，
    ///  封装了 CVPixelBuffer 的创建和图片缩放，再用 toByteArrayRGBA() 把像素数据
    ///  提取为 RGBA 字节数组，然后手动分离 RGB 通道。这种方式比直接用 CGContext 更可靠，
    ///  因为 CVPixelBuffer 的像素格式是严格定义的，不受 iOS 小端序影响。"
    func rgbMultiArrayCoreMLHelpers(width: Int = 224, height: Int = 224) -> MLMultiArray? {
        // ① 方向归一化
        let normalized = self.normalizedOrientation()

        // ② 用 CoreMLHelpers 创建 ARGB CVPixelBuffer 并缩放
        guard let pixelBuffer = normalized.pixelBufferFromUIImage(width: width, height: height) else {
            return nil
        }

        // ③ CVPixelBuffer → CGImage
        guard let cgImage = CGImage.create(pixelBuffer: pixelBuffer) else {
            return nil
        }

        // ④ CGImage → RGBA 字节数组
        // toByteArrayRGBA() 返回 [R, G, B, A, R, G, B, A, ...]，每像素4字节
        // 不涉及端序问题，R 就是 R，G 就是 G
        let rgbaBytes = cgImage.toByteArrayRGBA()

        // 安全检查
        let expectedSize = width * height * 4
        guard rgbaBytes.count == expectedSize else {
            return nil
        }

        // ⑤ 创建 MLMultiArray (1, 3, H, W)
        let shape = [1, 3, height, width] as [NSNumber]
        guard let multiArray = try? MLMultiArray(shape: shape, dataType: .float32) else {
            return nil
        }

        // ⑥ 从 RGBA 字节数组分离 RGB 通道
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        let hw = height * width

        for i in 0..<hw {
            let byteIndex = i * 4
            // RGBA: [R, G, B, A] 每像素4字节
            ptr[0 * hw + i] = Float(rgbaBytes[byteIndex])       // R channel
            ptr[1 * hw + i] = Float(rgbaBytes[byteIndex + 1])   // G channel
            ptr[2 * hw + i] = Float(rgbaBytes[byteIndex + 2])   // B channel
            // byteIndex + 3 是 Alpha，跳过
        }

        return multiArray
    }

    // MARK: - 灰度 MLMultiArray 转换（旧 FER 模型兼容）

    /// 将 UIImage 转换为 MLMultiArray（灰度，48×48，像素值 0-255）
    ///
    /// 【处理流程】
    /// UIImage → 方向归一化 → CGContext 直接缩放+灰度化48×48 → 提取像素值(0-255) → MLMultiArray(1,1,48,48)
    ///
    /// 【关键修复 — 之前的问题】
    /// ❌ 旧代码: normalized → resized(to:) → cgImage → 灰度Context
    ///    resized() 使用 UIGraphicsImageRenderer，在 2x/3x 屏幕上 cgImage 是 96×96/144×144
    ///    而非 48×48，导致 CGContext 缩放绘制时出现插值问题
    ///
    /// ✅ 新代码: normalized → 直接在灰度 CGContext 中缩放+绘制，一步到位
    ///    CGContext 不会受屏幕 scale 影响，保证精确的 48×48 像素输出
    ///
    /// 【技术要点】
    /// - MLMultiArray 是 CoreML 的通用输入格式（类似 NumPy 的 ndarray）
    /// - 像素值 0-255 而非 0-1，因为模型内部已有 x/255.0 归一化
    /// - shape=(1,1,48,48) 对应 (batch, channel, height, width)
    func grayscaleMultiArray(width: Int = 48, height: Int = 48) -> MLMultiArray? {
        // ① 方向归一化（竖拍照片必须先修正方向）
        let normalized = self.normalizedOrientation()
        guard let sourceCGImage = normalized.cgImage else { return nil }

        // ② 一步到位：创建 48×48 灰度 CGContext，直接在 Context 中缩放绘制
        //    关键：CGContext 不受屏幕 scale 影响，width/height 就是实际像素尺寸
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,       // 灰度图每行 = width 字节
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // ③ CGContext 坐标系原点在左下角，Y 向上
        //    而像素数据从顶部开始读取，必须翻转 Y 轴
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high  // 高质量缩放插值
        context.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = context.data else { return nil }

        // ④ 创建 MLMultiArray (1, 1, 48, 48)
        let shape = [1, 1, height, width] as [NSNumber]
        guard let multiArray = try? MLMultiArray(shape: shape, dataType: .float32) else {
            return nil
        }

        // ⑤ 逐像素填入值（0-255）
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        let bytesPerRow = context.bytesPerRow
        for y in 0..<height {
            for x in 0..<width {
                let pixelOffset = y * bytesPerRow + x
                let arrayIndex = y * width + x
                let pixelValue = pixelData.load(fromByteOffset: pixelOffset, as: UInt8.self)
                ptr[arrayIndex] = Float(pixelValue)
            }
        }

        return multiArray
    }

    // MARK: - 调试：将 MLMultiArray 转回 UIImage 可视化

    /// 将灰度 MLMultiArray 转换为 UIImage（调试用，验证预处理是否正确）
    ///
    /// 【为什么需要？】
    /// 如果模型结果不对，第一步应该检查送入模型的数据是否正确。
    /// 这个方法可以把 MLMultiArray 转回图片，让你肉眼确认：
    /// 1. 图片是否上下颠倒 → Y 翻转问题
    /// 2. 图片是否全黑/全白 → 像素值范围问题
    /// 3. 图片是否模糊/歪 → 缩放/方向问题
    static func fromGrayscaleMultiArray(_ array: MLMultiArray) -> UIImage? {
        // 预期 shape: (1, 1, H, W) 或 (1, H, W) 或 (H, W)
        let hIdx = array.shape.count >= 3 ? array.shape.count - 2 : 0
        let wIdx = array.shape.count >= 2 ? array.shape.count - 1 : 1
        let height = array.shape[hIdx].intValue
        let width = array.shape[wIdx].intValue

        var pixels = [UInt8](repeating: 0, count: height * width)
        let ptr = array.dataPointer.assumingMemoryBound(to: Float.self)

        // 处理不同 shape 的 stride
        let yStride = array.strides.count > hIdx ? array.strides[hIdx].intValue : width
        let xStride = array.strides.count > wIdx ? array.strides[wIdx].intValue : 1

        for y in 0..<height {
            for x in 0..<width {
                let val = ptr[y * yStride + x * xStride]
                // 将 0-255 范围的 float 值转回 UInt8
                pixels[y * width + x] = UInt8(max(0, min(255, val)))
            }
        }

        return CGImage.fromByteArrayGray(pixels, width: width, height: height).map { UIImage(cgImage: $0) }
    }
    
    // MARK: - VNImageRequestHandler 便捷创建

    /// 创建 Vision 的图片请求处理器
    func visionHandler(orientation: CGImagePropertyOrientation = .up) -> VNImageRequestHandler? {
        guard let cgImage = self.cgImage else { return nil }
        return VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
    }
}
