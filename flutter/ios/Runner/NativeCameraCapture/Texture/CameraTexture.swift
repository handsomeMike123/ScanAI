import Flutter
import AVFoundation

// ============================================================
// 相机纹理提供者
//
// 【FlutterTexture 协议实现】
// 实现 Flutter 的 FlutterTexture 协议，将 CVPixelBuffer
// 通过零拷贝（GPU 纹理）方式传递给 Flutter 渲染引擎。
//
// 【工作原理】
// 1. 原生端在 captureOutput 中收到 CVPixelBuffer
// 2. 通过 CIImage 转换方向（.leftMirrored 适配前置摄像头）
// 3. 渲染到预分配的 CVPixelBuffer
// 4. Flutter 引擎通过 copyPixelBuffer() 获取纹理数据
// 5. Texture widget 在 Flutter 端直接渲染 GPU 纹理
//
// 【对比 JPEG EventChannel 方案】
//
//                  JPEG EventChannel        Texture（本方案）
// 预览帧率         ~5fps                    30fps（跟随相机）
// 传输方式         JPEG编码→跨线程→解码      GPU 纹理零拷贝
// CPU 开销         高（编解码+GC）           低（仅方向转换）
// 画质             低（320px, Q40）          高（原始分辨率）
// 内存占用         每帧 JPEG 分配           预分配 buffer 复用
// ============================================================
class CameraTexture: NSObject, FlutterTexture {

    // MARK: - 属性

    /// 当前可供 Flutter 读取的像素缓冲区
    private var _pixelBuffer: CVPixelBuffer?

    /// 渲染目标缓冲区（预分配，避免每帧 malloc）
    private var _renderBuffer: CVPixelBuffer?

    /// 线程安全锁
    private let lock = NSLock()

    /// CIImage 渲染上下文（复用，GPU 加速）
    private let ciContext = CIContext(options: nil)

    /// 纹理 ID（由 FlutterTextureRegistry 分配）
    var textureId: Int64?

    // MARK: - 更新帧数据

    /// 更新纹理内容（由 CameraService 在相机帧回调中调用）
    ///
    /// 流程：CVPixelBuffer → CIImage → 方向转换 → 渲染到预分配 buffer → 交换引用
    ///
    /// - Parameter pixelBuffer: 相机原始帧（传感器方向，landscape）
    func update(with pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 前置摄像头修正：.leftMirrored = 旋转90° + 水平翻转
        // 效果：传感器landscape → portrait + 镜像（自拍效果）
        let oriented = ciImage.oriented(.leftMirrored)

        let targetWidth = Int(oriented.extent.width)
        let targetHeight = Int(oriented.extent.height)

        // 确保渲染目标 buffer 存在且尺寸匹配
        if _renderBuffer == nil ||
            CVPixelBufferGetWidth(_renderBuffer!) != targetWidth ||
            CVPixelBufferGetHeight(_renderBuffer!) != targetHeight {
            let attrs: [String: Any] = [
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(
                nil,
                targetWidth,
                targetHeight,
                kCVPixelFormatType_32BGRA,
                attrs as CFDictionary,
                &buffer
            )
            _renderBuffer = buffer
        }

        // GPU 加速渲染：CIImage → CVPixelBuffer
        if let renderBuffer = _renderBuffer {
            ciContext.render(oriented, to: renderBuffer)
        }

        // 原子交换引用，供 copyPixelBuffer 读取
        lock.lock()
        _pixelBuffer = _renderBuffer
        lock.unlock()
    }

    // MARK: - FlutterTexture 协议

    /// Flutter 引擎调用此方法获取纹理像素数据
    ///
    /// 此方法在 Flutter 渲染线程上调用，频率与 Flutter 帧率一致（60fps）。
    /// 返回 passRetained 让 Flutter 持有引用，渲染完成后自动释放。
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        let buffer = _pixelBuffer
        lock.unlock()

        guard let buffer = buffer else { return nil }

        // passRetained：增加引用计数，Flutter 渲染完成后 CFRelease
        return Unmanaged.passRetained(buffer)
    }

    // MARK: - 清理

    /// 释放资源
    func dispose() {
        lock.lock()
        _pixelBuffer = nil
        _renderBuffer = nil
        lock.unlock()
    }
}
