package com.shotmate.shotmate_app.inference

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * Góc nghiêng đường chân trời từ vector trọng lực (accelerometer), độ, [-45,45].
 * Dương = máy nghiêng phải (spec frame_analysis.dart).
 *
 * Dùng gravity vector thay vì edge-detect ảnh: rẻ, ổn định, đủ cho Sprint 1
 * (NATIVE_MODULE.md ghi rõ có thể bổ sung edge-detect khi cần đường chân trời thực).
 */
class HorizonSensor(context: Context) : SensorEventListener {
    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    @Volatile
    private var lastAngle: Float? = null

    @Volatile
    private var lastPitch: Float? = null

    fun start() {
        accelerometer?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
    }

    fun stop() {
        sensorManager.unregisterListener(this)
        lastAngle = null
        lastPitch = null
    }

    /** Góc nghiêng ngang gần nhất, hoặc null nếu chưa có mẫu / không có sensor. */
    fun currentAngleDeg(): Float? = lastAngle

    /**
     * Góc chúc/ngửa (pitch) [-90,90], spec-sprint-2: 0° = máy dựng đứng vuông
     * mặt đất, dương = ngửa lên, 90° ≈ úp xuống (top-down).
     */
    fun currentPitchDeg(): Float? = lastPitch

    override fun onSensorChanged(event: SensorEvent) {
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        // Roll (nghiêng ngang) — chỉ tin cậy khi máy gần thẳng đứng
        val magnitudeXy = sqrt(x * x + y * y)
        if (magnitudeXy >= 1.5f) {
            val deg = Math.toDegrees(atan2(x.toDouble(), y.toDouble())).toFloat()
            lastAngle = deg.coerceIn(-45f, 45f)
        }
        // Pitch: khi dựng đứng gravity dồn vào y (z≈0) → 0°; úp xuống z≈-g → 90°.
        // atan2(-z, y): 0 khi dựng, +90 khi camera hướng xuống đất.
        val pitch = Math.toDegrees(atan2(-z.toDouble(), y.toDouble())).toFloat()
        lastPitch = pitch.coerceIn(-90f, 90f)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
