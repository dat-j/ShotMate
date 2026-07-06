package com.shotmate.shotmate_app.inference

/**
 * Mirror của `app/lib/features/coach/domain/frame_analysis.dart` (source of truth).
 *
 * Serialize sang [Map] để đẩy qua EventChannel `shotmate/frame_analysis`.
 * BUSINESS RULE 3 (spec-sprint-1): KHÔNG BAO GIỜ chứa pixel/bitmap; payload ≤ 2KB.
 * Đổi field → tăng schemaVersion cả hai phía + cập nhật Dart tryParse.
 */
data class SubjectBoxPayload(
    val left: Float,
    val top: Float,
    val width: Float,
    val height: Float,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "left" to left.toDouble(),
        "top" to top.toDouble(),
        "width" to width.toDouble(),
        "height" to height.toDouble(),
    )
}

data class ExposurePayload(
    /** [0,255] */
    val meanLuma: Float,
    val clippedHighlightsPct: Float,
    val clippedShadowsPct: Float,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "meanLuma" to meanLuma.toDouble(),
        "clippedHighlightsPct" to clippedHighlightsPct.toDouble(),
        "clippedShadowsPct" to clippedShadowsPct.toDouble(),
    )
}

data class FrameAnalysisPayload(
    val timestampMs: Long,
    val horizonAngleDeg: Float?,
    val subjectBox: SubjectBoxPayload?,
    val subjectConfidence: Float,
    val hasPerson: Boolean,
    /** 33 điểm MediaPipe, mỗi điểm [x,y] normalized [0,1]. Null nếu không có người. */
    val poseLandmarks: List<List<Float>>?,
    val exposure: ExposurePayload?,
    val inferenceLatencyMs: Map<String, Int>,
    val throttled: Boolean,
    // --- schemaVersion 2 (spec-sprint-2 FR-S2-8) ---
    val sceneType: String? = null,
    val sceneConfidence: Float = 0f,
    val smilingProbability: Float? = null,
    val pitchDeg: Float? = null,
    val zoomRatio: Float = 1f,
    val verticalFovDeg: Float? = null,
) {
    fun toMap(): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        map["schemaVersion"] = SCHEMA_VERSION
        map["timestampMs"] = timestampMs
        horizonAngleDeg?.let { map["horizonAngleDeg"] = it.toDouble() }
        subjectBox?.let { map["subjectBox"] = it.toMap() }
        map["subjectConfidence"] = subjectConfidence.toDouble()
        map["hasPerson"] = hasPerson
        // Landmark [x,y] normalized — clamp phòng model trả ngoài [0,1] (Dart drop cả frame nếu lệch)
        poseLandmarks?.let { landmarks ->
            map["poseLandmarks"] = landmarks.map { pt ->
                listOf(
                    pt[0].coerceIn(0f, 1f).toDouble(),
                    pt[1].coerceIn(0f, 1f).toDouble(),
                )
            }
        }
        exposure?.let { map["exposure"] = it.toMap() }
        if (inferenceLatencyMs.isNotEmpty()) map["inferenceLatencyMs"] = inferenceLatencyMs
        if (throttled) map["throttled"] = true
        // v2 fields — chỉ gửi khi có giá trị (payload gọn, Dart parse optional)
        sceneType?.let {
            map["sceneType"] = it
            map["sceneConfidence"] = sceneConfidence.toDouble()
        }
        smilingProbability?.let { map["smilingProbability"] = it.toDouble() }
        pitchDeg?.let { map["pitchDeg"] = it.toDouble() }
        map["zoomRatio"] = zoomRatio.toDouble()
        verticalFovDeg?.let { map["verticalFovDeg"] = it.toDouble() }
        return map
    }

    companion object {
        // schemaVersion 2 (spec-sprint-2 FR-S2-8) — mirror frame_analysis.dart.
        // Field v2 (sceneType, smilingProbability, pitchDeg, zoomRatio,
        // verticalFovDeg) sẽ được thêm vào payload khi detector tương ứng xong;
        // Dart parse chúng optional nên bump version an toàn ngay cả khi native
        // chưa emit đủ (tránh drop toàn bộ frame do version mismatch).
        const val SCHEMA_VERSION = 2
    }
}
