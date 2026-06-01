package com.aiscan.ai_scan.nativecamera.model

// ============================================================
// 帧数据模型
//
// 【Kotlin data class 说明】
// data class 自动生成 equals()/hashCode()/toString()/copy()
// 类似 Swift 的 struct + Equatable/Hashable
// ============================================================

/**
 * 单帧采集结果
 *
 * @property jpegData JPEG 编码的图像数据
 * @property frameIndex 帧序号
 * @property width 图像宽度
 * @property height 图像高度
 * @property hasFace 是否检测到人脸
 */
data class CameraFrameData(
    val jpegData: ByteArray,
    val frameIndex: Int,
    val width: Int,
    val height: Int,
    val hasFace: Boolean
) {
    // ByteArray 的 equals 需要手动处理
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as CameraFrameData
        return frameIndex == other.frameIndex
    }

    override fun hashCode(): Int = frameIndex
}

/**
 * 采集会话统计
 */
data class CaptureSessionStats(
    val frameCount: Int,
    val faceDetectedCount: Int,
    val durationSeconds: Double
)
