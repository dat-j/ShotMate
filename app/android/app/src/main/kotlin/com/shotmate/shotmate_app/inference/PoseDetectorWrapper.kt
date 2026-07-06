package com.shotmate.shotmate_app.inference

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult

/**
 * MediaPipe pose_landmarker_lite ở LIVE_STREAM mode (async).
 *
 * Trả 33 landmark normalized + subjectBox suy ra từ bao đóng landmark.
 * GPU delegate; nếu init GPU fail (thiết bị/driver) thì fallback CPU.
 *
 * Kết quả về qua [onResult] trên MediaPipe callback thread — caller tự lo thread-safety.
 */
class PoseDetectorWrapper(
    context: Context,
    private val onResult: (PoseLandmarkerResult, Long) -> Unit,
) {
    private var landmarker: PoseLandmarker? = null

    init {
        landmarker = build(context, useGpu = true) ?: build(context, useGpu = false)
        if (landmarker == null) {
            Log.e(TAG, "PoseLandmarker init failed on both GPU and CPU")
        }
    }

    private fun build(context: Context, useGpu: Boolean): PoseLandmarker? {
        return try {
            val base = BaseOptions.builder()
                .setModelAssetPath(MODEL_ASSET)
                .setDelegate(if (useGpu) Delegate.GPU else Delegate.CPU)
                .build()
            val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setNumPoses(1)
                .setMinPoseDetectionConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setMinPosePresenceConfidence(0.5f)
                .setResultListener { result, _ -> emit(result) }
                .setErrorListener { e -> Log.e(TAG, "PoseLandmarker error", e) }
                .build()
            PoseLandmarker.createFromOptions(context, options).also {
                Log.i(TAG, "PoseLandmarker init OK (delegate=${if (useGpu) "GPU" else "CPU"})")
            }
        } catch (t: Throwable) {
            Log.w(TAG, "PoseLandmarker init failed (gpu=$useGpu): ${t.message}")
            null
        }
    }

    private var lastTimestampMs = 0L

    private fun emit(result: PoseLandmarkerResult) {
        onResult(result, lastTimestampMs)
    }

    /**
     * Gửi 1 frame (bitmap RGB đã xoay đúng chiều) để detect async.
     * [timestampMs] phải tăng đơn điệu (yêu cầu của LIVE_STREAM).
     */
    fun detectAsync(bitmap: Bitmap, timestampMs: Long) {
        val lm = landmarker ?: return
        if (timestampMs <= lastTimestampMs) return
        lastTimestampMs = timestampMs
        try {
            val mpImage = BitmapImageBuilder(bitmap).build()
            lm.detectAsync(mpImage, timestampMs)
        } catch (t: Throwable) {
            Log.w(TAG, "detectAsync failed: ${t.message}")
        }
    }

    fun close() {
        landmarker?.close()
        landmarker = null
    }

    companion object {
        private const val TAG = "PoseDetector"
        private const val MODEL_ASSET = "pose_landmarker_lite.task"

        /** SubjectBox = bounding box của toàn bộ landmark (spec: subject = người). */
        fun subjectBoxFrom(landmarks: List<List<Float>>): SubjectBoxPayload? {
            if (landmarks.isEmpty()) return null
            var minX = 1f; var minY = 1f; var maxX = 0f; var maxY = 0f
            for (pt in landmarks) {
                val x = pt[0]; val y = pt[1]
                if (x < minX) minX = x
                if (y < minY) minY = y
                if (x > maxX) maxX = x
                if (y > maxY) maxY = y
            }
            minX = minX.coerceIn(0f, 1f); minY = minY.coerceIn(0f, 1f)
            maxX = maxX.coerceIn(0f, 1f); maxY = maxY.coerceIn(0f, 1f)
            return SubjectBoxPayload(minX, minY, maxX - minX, maxY - minY)
        }
    }
}
