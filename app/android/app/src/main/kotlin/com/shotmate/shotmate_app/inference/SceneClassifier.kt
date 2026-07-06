package com.shotmate.shotmate_app.inference

import android.util.Log
import androidx.camera.core.ImageProxy
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabeler
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions

/**
 * Scene classifier (spec-sprint-2 FR-S2-2): ML Kit image labeling → 3 class V1
 * (landscape / portrait / food) + confidence. Chạy 1fps (NFR-2).
 *
 * Mapping label → scene nằm ở đây (native), một chỗ (BR: native chỉ detect,
 * KHÔNG logic nghiệp vụ — mapping label sang scene là chuẩn hoá output, không
 * phải quyết định hint). Rule 6 (ổn định 3 mẫu) do Dart lo.
 */
class SceneClassifier {
    private val labeler: ImageLabeler =
        ImageLabeling.getClient(
            ImageLabelerOptions.Builder()
                .setConfidenceThreshold(0.5f)
                .build()
        )

    /** Kết quả: scene name (khớp SceneType.name Dart) + confidence [0,1]. */
    data class Result(val scene: String, val confidence: Float)

    fun classify(image: ImageProxy, rotation: Int): Result? {
        val media = image.image ?: return null
        return try {
            val input = InputImage.fromMediaImage(media, rotation)
            val labels = Tasks.await(labeler.process(input))
            // Duyệt label theo độ tin cậy giảm dần, chọn scene khớp đầu tiên.
            for (label in labels.sortedByDescending { it.confidence }) {
                val scene = mapLabel(label.text) ?: continue
                return Result(scene, label.confidence)
            }
            Result("unknown", 0f)
        } catch (t: Throwable) {
            Log.w(TAG, "scene classify error: ${t.message}")
            null
        }
    }

    fun close() = labeler.close()

    private fun mapLabel(label: String): String? {
        val l = label.lowercase()
        return when {
            l in FOOD_LABELS -> "food"
            l in PORTRAIT_LABELS -> "portrait"
            l in LANDSCAPE_LABELS -> "landscape"
            else -> null
        }
    }

    companion object {
        private const val TAG = "SceneClassifier"

        // Nhãn ML Kit base model (447 label) map sang 3 scene V1. Danh sách khởi
        // điểm — tuning bằng test set 150 ảnh (spec Rule 8).
        private val FOOD_LABELS = setOf(
            "food", "dish", "cuisine", "dessert", "meal", "breakfast",
            "brunch", "lunch", "baked goods", "fruit", "drink", "coffee",
        )
        private val PORTRAIT_LABELS = setOf(
            "person", "selfie", "face", "smile", "hair", "skin", "people",
        )
        private val LANDSCAPE_LABELS = setOf(
            "sky", "mountain", "beach", "landscape", "nature", "tree",
            "cloud", "sunset", "sunrise", "horizon", "sea", "lake", "field",
            "building", "cityscape", "street",
        )
    }
}
