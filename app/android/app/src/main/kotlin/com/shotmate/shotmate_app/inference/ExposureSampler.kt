package com.shotmate.shotmate_app.inference

import androidx.camera.core.ImageProxy

/**
 * Lấy thống kê phơi sáng từ Y-plane (luma) của frame YUV_420_888.
 *
 * Subsample (bước [stride]) để rẻ — không cần từng pixel cho mean/clipping.
 * KHÔNG copy pixel ra khỏi native (Business Rule 3): chỉ đọc để tính số thống kê.
 */
object ExposureSampler {
    private const val HIGHLIGHT_THRESHOLD = 250
    private const val SHADOW_THRESHOLD = 5
    private const val STRIDE = 8

    fun sample(image: ImageProxy): ExposurePayload {
        val yPlane = image.planes[0]
        val buffer = yPlane.buffer
        val rowStride = yPlane.rowStride
        val pixelStride = yPlane.pixelStride
        val width = image.width
        val height = image.height

        var sum = 0L
        var count = 0
        var highlights = 0
        var shadows = 0

        var row = 0
        while (row < height) {
            val rowStart = row * rowStride
            var col = 0
            while (col < width) {
                val index = rowStart + col * pixelStride
                if (index >= buffer.limit()) break
                val luma = buffer.get(index).toInt() and 0xFF
                sum += luma
                count++
                if (luma >= HIGHLIGHT_THRESHOLD) highlights++
                if (luma <= SHADOW_THRESHOLD) shadows++
                col += STRIDE
            }
            row += STRIDE
        }

        if (count == 0) return ExposurePayload(0f, 0f, 0f)
        return ExposurePayload(
            meanLuma = sum.toFloat() / count,
            clippedHighlightsPct = 100f * highlights / count,
            clippedShadowsPct = 100f * shadows / count,
        )
    }
}
