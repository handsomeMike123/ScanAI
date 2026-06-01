package com.aiscan.ai_scan.nativecamera.service

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.*
import android.media.Image
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

// ============================================================
// 相机采集单例服务
//
// 【MVVM - Service 层】
// 职责：CameraX 相机管理、SurfaceTexture 预览、人脸检测、图像裁剪编码
//
// 【v3 架构 — Texture + 双频 EventChannel】
//
// 1. 预览画面: Texture（60fps 零拷贝）
//    (a) CameraX Preview → SurfaceTexture → Flutter Texture
//    (b) 前置摄像头自动镜像
//
// 2. 人脸框: EventChannel(faceBounds) ~10fps
//    (a) ML Kit fromMediaImage → 归一化坐标
//    (b) Flutter CustomPainter 画框
//
// 3. 推理帧: EventChannel(detection) 每3秒
//    (a) 原生裁剪人脸区域 → JPEG
//    (b) Flutter TFLite 推理
// ============================================================
class CameraService private constructor() {

    companion object {
        const val TAG = "CameraService"

        @Volatile
        private var instance: CameraService? = null

        fun getInstance(): CameraService {
            return instance ?: synchronized(this) {
                instance ?: CameraService().also { instance = it }
            }
        }
    }

    // MARK: - 相机属性

    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var previewUseCase: Preview? = null

    private val cameraSelector = CameraSelector.Builder()
        .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
        .build()

    /// 最新帧缓存（Bitmap），由 ImageAnalysis 回调持续更新
    @Volatile
    private var latestBitmap: Bitmap? = null

    /// 最新帧的旋转角度
    @Volatile
    private var latestRotationDegrees: Int = 0

    @Volatile
    var isRunning: Boolean = false
        private set

    // MARK: - Texture 属性

    /// Flutter SurfaceTexture（用于 Texture 预览）
    private var surfaceTextureEntry: io.flutter.view.TextureRegistry.SurfaceTextureEntry? = null

    /// 纹理 ID（传递给 Flutter 端）
    @Volatile
    var textureId: Long? = null
        private set

    /// 纹理尺寸（旋转后的 portrait 尺寸）
    @Volatile
    var textureWidth: Int = 3
    @Volatile
    var textureHeight: Int = 4

    /// 相机预览用的 Surface
    private var previewSurface: Surface? = null

    // MARK: - 帧推送回调

    /// 结构化帧数据回调（由 CameraChannelHandler 设置）
    var onFrameReady: ((Map<String, Any?>) -> Unit)? = null

    // MARK: - 人脸坐标缓存

    @Volatile
    private var cachedFaceBounds: List<Map<String, Double>> = emptyList()

    // MARK: - 检测控制

    @Volatile
    private var isProcessing: Boolean = false

    @Volatile
    private var isDetectingFace: Boolean = false

    private var frameIndex: Int = 0

    /// 检测间隔（毫秒），3秒
    private val detectionIntervalMs: Long = 3000L

    private var detectionHandler: Handler? = null
    private var handlerThread: HandlerThread? = null

    /// 检测 Runnable（每3秒触发一次人脸裁剪 + TFLite 帧推送）
    private val detectionRunnable = object : Runnable {
        override fun run() {
            detectCurrentFrame()
            detectionHandler?.postDelayed(this, detectionIntervalMs)
        }
    }

    private var sessionStartTime: Long = 0L
    private var faceDetectedCount: Int = 0

    // MARK: - ML Kit 人脸检测器

    private val faceDetector by lazy {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .build()
        FaceDetection.getClient(options)
    }

    private val cameraExecutor by lazy { Executors.newSingleThreadExecutor() }

    // MARK: - 权限检查

    fun isAuthorized(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun checkPermission(context: Context): Boolean {
        return isAuthorized(context)
    }

    // MARK: - Texture 管理

    /// 设置 SurfaceTexture（由 CameraChannelHandler 在 startCapture 时调用）
    fun setSurfaceTextureEntry(entry: io.flutter.view.TextureRegistry.SurfaceTextureEntry) {
        this.surfaceTextureEntry = entry
        this.textureId = entry.id()
        Log.d(TAG, "SurfaceTexture 已设置, textureId = ${entry.id()}")
    }

    /// 获取预览用的 Surface
    fun getPreviewSurface(): Surface? {
        val entry = surfaceTextureEntry ?: return null
        val surfaceTexture = entry.surfaceTexture()

        // 不设置固定 buffer 大小，让 CameraX Preview 自动匹配实际分辨率
        // 避免硬编码 1080x1920 导致不同手机画面拉伸

        val surface = Surface(surfaceTexture)
        previewSurface = surface
        return surface
    }

    /// 释放 SurfaceTexture
    fun releaseSurfaceTexture() {
        previewSurface?.release()
        previewSurface = null
        surfaceTextureEntry?.release()
        surfaceTextureEntry = null
        textureId = null
        Log.d(TAG, "SurfaceTexture 已释放")
    }

    // MARK: - 采集控制

    fun startCapture(context: Context, lifecycleOwner: LifecycleOwner) {
        frameIndex = 0
        faceDetectedCount = 0
        isProcessing = false
        isDetectingFace = false
        latestBitmap = null
        cachedFaceBounds = emptyList()
        sessionStartTime = System.currentTimeMillis()

        handlerThread = HandlerThread("DetectionThread").also { it.start() }
        detectionHandler = Handler(handlerThread!!.looper)

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()

                // ImageAnalysis：逐帧分析（用于人脸检测 + 裁剪）
                imageAnalysis = ImageAnalysis.Builder()
                    .setTargetResolution(android.util.Size(1280, 960))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also { analysis ->
                        analysis.setAnalyzer(cameraExecutor) { imageProxy ->
                            processImageProxy(imageProxy)
                        }
                    }

                // Preview：相机预览（用于 Texture 渲染）
                val surface = getPreviewSurface()
                previewUseCase = if (surface != null) {
                    Preview.Builder()
                        .setTargetResolution(android.util.Size(1080, 1920))
                        .build().also { preview ->
                            preview.setSurfaceProvider { request ->
                                val resolution = request.resolution
                                Log.d(TAG, "📐 Preview 实际分辨率: ${resolution.width}x${resolution.height}")

                                // 动态设置 SurfaceTexture buffer 大小
                                surfaceTextureEntry?.surfaceTexture()?.setDefaultBufferSize(
                                    resolution.width, resolution.height
                                )

                                // 推送纹理尺寸给 Flutter（用 Preview 的实际分辨率）
                                // 前置摄像头 Preview 已经自动镜像，宽高就是 portrait 方向
                                textureWidth = resolution.height  // portrait 宽
                                textureHeight = resolution.width  // portrait 高
                                val sizeData: Map<String, Any?> = mapOf(
                                    "type" to "textureSize",
                                    "width" to textureWidth,
                                    "height" to textureHeight,
                                )
                                onFrameReady?.invoke(sizeData)

                                request.provideSurface(surface, cameraExecutor) { }
                            }
                        }
                } else {
                    Log.w(TAG, "⚠️ 无 SurfaceTexture，跳过 Preview 用例")
                    null
                }

                cameraProvider?.unbindAll()

                // 绑定用例：Preview（可选）+ ImageAnalysis
                val useCases = mutableListOf<UseCase>()
                previewUseCase?.let { useCases.add(it) }
                imageAnalysis?.let { useCases.add(it) }

                cameraProvider?.bindToLifecycle(
                    lifecycleOwner,
                    cameraSelector,
                    *useCases.toTypedArray()
                )

                isRunning = true
                Log.d(TAG, "📷 相机已启动（Texture 模式）")

                // 启动定时检测（每3秒）
                detectionHandler?.post(detectionRunnable)

            } catch (e: Exception) {
                Log.e(TAG, "❌ 相机启动失败: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    fun stopCapture() {
        detectionHandler?.removeCallbacks(detectionRunnable)
        handlerThread?.quitSafely()
        handlerThread = null
        detectionHandler = null

        cameraProvider?.unbindAll()
        releaseSurfaceTexture()
        isRunning = false
        latestBitmap = null
        isProcessing = false
        isDetectingFace = false
        cachedFaceBounds = emptyList()

        Log.d(TAG, "📷 相机已停止，共推送 $frameIndex 帧")
    }

    // MARK: - 帧回调处理 + 人脸检测

    @androidx.annotation.OptIn(androidx.camera.core.ExperimentalGetImage::class)
    private fun processImageProxy(imageProxy: ImageProxy) {
        val image = imageProxy.image
        if (image != null) {
            latestRotationDegrees = imageProxy.imageInfo.rotationDegrees

            // 保存旋转+镜像后的 Bitmap（用于裁剪人脸区域）
            val bitmap = imageProxy.toBitmap()
            val matrix = Matrix().apply {
                postScale(-1f, 1f, bitmap.width / 2f, bitmap.height / 2f)
                postRotate(imageProxy.imageInfo.rotationDegrees.toFloat())
            }
            latestBitmap = Bitmap.createBitmap(
                bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true
            )

            // 在 ImageProxy 回调中直接用 fromMediaImage 做人脸检测
            // ML Kit 官方推荐方式：直接传 MediaImage + rotationDegrees
            // 注意：imageProxy.close() 必须在 ML Kit 处理完成后调用
            if (!isDetectingFace) {
                isDetectingFace = true
                val rotationDegrees = imageProxy.imageInfo.rotationDegrees
                val sensorWidth = image.width
                val sensorHeight = image.height
                val inputImage = InputImage.fromMediaImage(image, rotationDegrees)

                faceDetector.process(inputImage)
                    .addOnSuccessListener { faces ->
                        isDetectingFace = false
                        handleFaceDetectionResult(faces, sensorWidth, sensorHeight)
                        imageProxy.close()
                    }
                    .addOnFailureListener { e ->
                        isDetectingFace = false
                        Log.e(TAG, "❌ 人脸检测失败: ${e.message}")
                        imageProxy.close()
                    }
            } else {
                // 跳过检测时也要关闭 imageProxy
                imageProxy.close()
            }
        } else {
            imageProxy.close()
        }
    }

    /// 处理人脸检测结果，转换为 Texture 坐标系并推送
    ///
    /// 【关键说明】
    /// ML Kit fromMediaImage(image, rotationDegrees) 返回的 boundingBox
    /// 已经是旋转后的坐标系！不需要手动做旋转变换。
    ///
    /// 例如 sensor=640x480, rotation=270 时：
    /// - 旋转后图像尺寸：480x640（portrait）
    /// - ML Kit bbox 已经在 480x640 坐标系中
    /// - 只需归一化 + 前置摄像头水平镜像
    ///
    /// CameraX Preview 默认对前置摄像头做镜像渲染（自拍效果），
    /// 所以人脸框也需要水平镜像才能对齐。
    private fun handleFaceDetectionResult(faces: List<com.google.mlkit.vision.face.Face>, sensorWidth: Int, sensorHeight: Int) {
        // 计算旋转后的图像尺寸
        val rotatedWidth: Int
        val rotatedHeight: Int
        when (latestRotationDegrees) {
            90, 270 -> {
                rotatedWidth = sensorHeight  // 旋转后宽度 = 原始高度
                rotatedHeight = sensorWidth  // 旋转后高度 = 原始宽度
            }
            else -> {
                rotatedWidth = sensorWidth
                rotatedHeight = sensorHeight
            }
        }

        val newBounds: List<Map<String, Double>> = if (faces.isNotEmpty()) {
            Log.d(TAG, "🧑 检测到 ${faces.size} 张人脸, sensor=${sensorWidth}x${sensorHeight}, rotated=${rotatedWidth}x${rotatedHeight}, rotation=$latestRotationDegrees")
            faces.mapIndexed { index, f ->
                val bbox = f.boundingBox

                // ML Kit bbox 已在旋转后的坐标系中，直接归一化
                // 前置摄像头需要水平镜像（自拍效果）
                val normalized = mapOf(
                    "left" to 1.0 - bbox.right.toDouble() / rotatedWidth,
                    "top" to bbox.top.toDouble() / rotatedHeight,
                    "right" to 1.0 - bbox.left.toDouble() / rotatedWidth,
                    "bottom" to bbox.bottom.toDouble() / rotatedHeight,
                )
                Log.d(TAG, "🧑 人脸 #$index: raw=$bbox, normalized=$normalized")
                normalized
            }
        } else {
            emptyList()
        }

        cachedFaceBounds = newBounds

        val faceData: Map<String, Any?> = mapOf(
            "type" to "faceBounds",
            "faceBounds" to newBounds,
        )

        onFrameReady?.invoke(faceData)
    }

    // MARK: - 检测帧核心（每3秒，推送裁剪人脸 JPEG）

    private fun detectCurrentFrame() {
        val bitmap = latestBitmap
        if (isProcessing || bitmap == null) {
            Log.d(TAG, "⏭️ 跳过：无可用帧或正在处理")
            return
        }

        isProcessing = true
        Log.d(TAG, "🔍 开始检测帧 #${frameIndex + 1}")

        if (cachedFaceBounds.isEmpty()) {
            // 无人脸 → 推送完整帧
            pushDetectionFrame(encodeFullFrame(bitmap))
        } else {
            // 有人脸 → 裁剪人脸区域
            val faceBounds = cachedFaceBounds[0]
            cropAndEncodeFace(bitmap, faceBounds)
        }
    }

    // MARK: - 人脸裁剪 + 编码

    private fun cropAndEncodeFace(bitmap: Bitmap, normalizedRect: Map<String, Double>) {
        val left = (normalizedRect["left"] ?: 0.0) * bitmap.width
        val top = (normalizedRect["top"] ?: 0.0) * bitmap.height
        val right = (normalizedRect["right"] ?: 0.0) * bitmap.width
        val bottom = (normalizedRect["bottom"] ?: 0.0) * bitmap.height

        val margin = maxOf(right - left, bottom - top) * 0.4

        val cropLeft = maxOf(0.0, left - margin)
        val cropTop = maxOf(0.0, top - margin)
        val cropRight = minOf(bitmap.width.toDouble(), right + margin)
        val cropBottom = minOf(bitmap.height.toDouble(), bottom + margin)

        val cropWidth = cropRight - cropLeft
        val cropHeight = cropBottom - cropTop

        if (cropWidth <= 0 || cropHeight <= 0) {
            pushDetectionFrame(encodeFullFrame(bitmap))
            return
        }

        val croppedBitmap = Bitmap.createBitmap(
            bitmap,
            cropLeft.toInt(), cropTop.toInt(),
            cropWidth.toInt(), cropHeight.toInt()
        )

        val jpegData = compressToJpeg(croppedBitmap, 80)

        frameIndex++
        Log.d(TAG, "✅ 帧 #$frameIndex 已裁剪人脸: ${croppedBitmap.width}x${croppedBitmap.height}")

        pushDetectionFrame(jpegData)
    }

    /// 编码完整帧（无人脸时降级使用）
    private fun encodeFullFrame(bitmap: Bitmap): ByteArray {
        val maxSize = 640
        val scale = minOf(maxSize.toFloat() / bitmap.width, maxSize.toFloat() / bitmap.height, 1f)
        val scaledBitmap = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * scale).toInt(),
                (bitmap.height * scale).toInt(),
                true
            )
        } else {
            bitmap
        }
        return compressToJpeg(scaledBitmap, 60)
    }

    /// 推送检测帧给 Flutter
    private fun pushDetectionFrame(jpegData: ByteArray) {
        val frameData: Map<String, Any?> = mapOf(
            "type" to "detection",
            "data" to jpegData,
            "frameIndex" to frameIndex,
        )

        onFrameReady?.invoke(frameData)
        isProcessing = false
    }

    // MARK: - 工具方法

    private fun compressToJpeg(bitmap: Bitmap, quality: Int): ByteArray {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        return stream.toByteArray()
    }

    @androidx.annotation.OptIn(androidx.camera.core.ExperimentalGetImage::class)
    private fun ImageProxy.toBitmap(): Bitmap {
        val image = this.image ?: return Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
        return image.toBitmap()
    }

    private fun Image.toBitmap(): Bitmap {
        val yBuffer = planes[0].buffer
        val uBuffer = planes[1].buffer
        val vBuffer = planes[2].buffer

        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()

        val nv21 = ByteArray(ySize + uSize + vSize)

        yBuffer.get(nv21, 0, ySize)
        vBuffer.get(nv21, ySize, vSize)
        uBuffer.get(nv21, ySize + vSize, uSize)

        val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, width, height), 100, out)
        val imageBytes = out.toByteArray()

        return BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
    }
}
