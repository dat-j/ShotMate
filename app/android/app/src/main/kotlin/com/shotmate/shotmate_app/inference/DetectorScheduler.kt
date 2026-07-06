package com.shotmate.shotmate_app.inference

/**
 * Throttle mỗi detector theo tần suất mục tiêu (spec: pose 15fps, composition/exposure 5fps).
 *
 * Không tự chạy detector — chỉ trả lời "frame ở thời điểm này có nên chạy detector X không".
 * Thread-safe không cần: ImageAnalysis analyzer chạy trên 1 executor đơn luồng.
 */
class DetectorScheduler(private val targetFps: Int) {
    private var lastRunMs = 0L
    private val intervalMs: Long = if (targetFps <= 0) Long.MAX_VALUE else 1000L / targetFps

    /** true nếu đã đủ khoảng thời gian kể từ lần chạy trước (đồng thời cập nhật mốc). */
    fun shouldRun(nowMs: Long): Boolean {
        if (nowMs - lastRunMs < intervalMs) return false
        lastRunMs = nowMs
        return true
    }

    fun reset() {
        lastRunMs = 0L
    }
}
