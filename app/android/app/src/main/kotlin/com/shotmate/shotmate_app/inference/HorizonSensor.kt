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

    fun start() {
        accelerometer?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
    }

    fun stop() {
        sensorManager.unregisterListener(this)
        lastAngle = null
    }

    /** Góc gần nhất, hoặc null nếu chưa có mẫu / thiết bị không có accelerometer. */
    fun currentAngleDeg(): Float? = lastAngle

    override fun onSensorChanged(event: SensorEvent) {
        val x = event.values[0]
        val y = event.values[1]
        // Chỉ tin cậy khi máy gần thẳng đứng (không nằm ngửa); tránh nhiễu khi |gravity xy| nhỏ
        val magnitudeXy = sqrt(x * x + y * y)
        if (magnitudeXy < 1.5f) return
        // atan2(x, y): 0° khi cầm dọc thẳng; nghiêng phải → x dương → góc dương
        val deg = Math.toDegrees(atan2(x.toDouble(), y.toDouble())).toFloat()
        lastAngle = deg.coerceIn(-45f, 45f)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
