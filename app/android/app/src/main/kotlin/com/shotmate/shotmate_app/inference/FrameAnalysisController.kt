package com.shotmate.shotmate_app.inference

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

/**
 * Điều phối Native Inference Module + sở hữu camera (ADR-0001, ADR-0007).
 *
 * MỘT owner duy nhất của camera vật lý: CameraX bind Preview (PlatformView) +
 * ImageAnalysis + ImageCapture cùng lúc. KHÔNG dùng `camera` plugin song song
 * (tránh tranh camera). KHÔNG startImageStream.
 *
 * Analysis: pose async (MediaPipe LIVE_STREAM); exposure/horizon/face sync.
 * Thermal ≥ SEVERE → throttle (EC-4). KHÔNG logic nghiệp vụ — chỉ detect + serialize.
 */
class FrameAnalysisController(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageCapture: ImageCapture? = null

    val previewView: PreviewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
    }

    private val poseScheduler = DetectorScheduler(POSE_FPS)
    private val exposureScheduler = DetectorScheduler(SLOW_FPS)
    private val faceScheduler = DetectorScheduler(SLOW_FPS)

    private var poseDetector: PoseDetectorWrapper? = null
    private val faceDetector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .build()
    )

    private var horizonSensor: HorizonSensor? = null
    private val powerManager =
        context.getSystemService(Context.POWER_SERVICE) as PowerManager

    private val latestPose = AtomicReference<PoseSnapshot?>(null)
    private var started = false

    // --- EventChannel.StreamHandler (analysis stream) ---

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // --- Camera lifecycle (gọi khi PlatformView tạo) ---

    fun start() {
        if (started) return
        started = true
        horizonSensor = HorizonSensor(context).also { it.start() }
        poseDetector = PoseDetectorWrapper(context) { result, ts ->
            val landmarks = result.landmarks().firstOrNull()?.map { lm ->
                listOf(lm.x(), lm.y())
            }
            latestPose.set(PoseSnapshot(landmarks, System.currentTimeMillis() - ts))
        }

        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            try {
                val provider = future.get()
                cameraProvider = provider
                bindUseCases(provider)
            } catch (t: Throwable) {
                Log.e(TAG, "camera bind failed", t)
                mainHandler.post { eventSink?.error("camera_init", t.message, null) }
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindUseCases(provider: ProcessCameraProvider) {
        val preview = Preview.Builder().build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }
        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
            .build()
        analysis.setAnalyzer(analysisExecutor, ::analyze)
        val capture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .build()
        imageCapture = capture

        provider.unbindAll()
        provider.bindToLifecycle(
            lifecycleOwner,
            CameraSelector.DEFAULT_BACK_CAMERA,
            preview,
            analysis,
            capture,
        )
        Log.i(TAG, "camera bound: preview + analysis + capture")
    }

    /**
     * Chụp ảnh vào [file]. Chạy trên camera của chính module này (không tranh
     * với plugin). Kết quả qua [onSaved]/[onError] trên main thread.
     */
    fun capture(file: File, onSaved: () -> Unit, onError: (String) -> Unit) {
        val capture = imageCapture
        if (capture == null) {
            onError("capture_not_ready")
            return
        }
        val options = ImageCapture.OutputFileOptions.Builder(file).build()
        capture.takePicture(
            options,
            ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) = onSaved()
                override fun onError(exc: ImageCaptureException) {
                    Log.w(TAG, "capture error", exc)
                    onError(exc.message ?: "capture_failed")
                }
            },
        )
    }

    fun stop() {
        if (!started) return
        started = false
        cameraProvider?.unbindAll()
        cameraProvider = null
        imageCapture = null
        poseDetector?.close()
        poseDetector = null
        horizonSensor?.stop()
        horizonSensor = null
        latestPose.set(null)
        poseScheduler.reset(); exposureScheduler.reset(); faceScheduler.reset()
    }

    fun dispose() {
        stop()
        faceDetector.close()
        analysisExecutor.shutdown()
    }

    // --- Per-frame analysis (single-thread executor) ---

    private fun analyze(image: ImageProxy) {
        val nowMs = System.currentTimeMillis()
        val throttled = powerManager.currentThermalStatus >=
            PowerManager.THERMAL_STATUS_SEVERE
        val rotation = image.imageInfo.rotationDegrees

        try {
            // Pose (async) — throttled thì hạ nhịp xuống SLOW_FPS (EC-4)
            val activePoseScheduler = if (throttled) exposureScheduler else poseScheduler
            if (poseDetector != null && activePoseScheduler.shouldRun(nowMs)) {
                val bitmap = image.toRotatedBitmap(rotation)
                if (bitmap != null) poseDetector?.detectAsync(bitmap, nowMs)
            }

            var exposure: ExposurePayload? = null
            var exposureLatency = 0
            if (!throttled && exposureScheduler.shouldRun(nowMs)) {
                val t0 = System.currentTimeMillis()
                exposure = ExposureSampler.sample(image)
                exposureLatency = (System.currentTimeMillis() - t0).toInt()
            }

            var faceBox: SubjectBoxPayload? = null
            if (!throttled && faceScheduler.shouldRun(nowMs)) {
                faceBox = detectFaceBox(image, rotation)
            }

            emitPayload(nowMs, throttled, exposure, exposureLatency, faceBox)
        } catch (t: Throwable) {
            Log.w(TAG, "analyze error: ${t.message}")
        } finally {
            image.close()
        }
    }

    private fun detectFaceBox(image: ImageProxy, rotation: Int): SubjectBoxPayload? {
        val media = image.image ?: return null
        return try {
            val input = InputImage.fromMediaImage(media, rotation)
            val faces = Tasks.await(faceDetector.process(input))
            val largest = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
                ?: return null
            val (w, h) = if (rotation == 90 || rotation == 270)
                image.height to image.width else image.width to image.height
            val b = largest.boundingBox
            SubjectBoxPayload(
                left = (b.left.toFloat() / w).coerceIn(0f, 1f),
                top = (b.top.toFloat() / h).coerceIn(0f, 1f),
                width = (b.width().toFloat() / w).coerceIn(0f, 1f),
                height = (b.height().toFloat() / h).coerceIn(0f, 1f),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "face detect error: ${t.message}")
            null
        }
    }

    private fun emitPayload(
        nowMs: Long,
        throttled: Boolean,
        exposure: ExposurePayload?,
        exposureLatency: Int,
        faceBox: SubjectBoxPayload?,
    ) {
        val pose = latestPose.get()
        val poseLandmarks = pose?.landmarks
        val hasPerson = poseLandmarks != null || faceBox != null
        val subjectBox = poseLandmarks?.let { PoseDetectorWrapper.subjectBoxFrom(it) } ?: faceBox
        val subjectConfidence = when {
            poseLandmarks != null -> 0.9f
            faceBox != null -> 0.7f
            else -> 0f
        }

        val latency = HashMap<String, Int>()
        pose?.let { latency["pose"] = it.latencyMs.toInt().coerceAtLeast(0) }
        if (exposureLatency > 0) latency["composition"] = exposureLatency

        val payload = FrameAnalysisPayload(
            timestampMs = nowMs,
            horizonAngleDeg = horizonSensor?.currentAngleDeg(),
            subjectBox = subjectBox,
            subjectConfidence = subjectConfidence,
            hasPerson = hasPerson,
            poseLandmarks = if (poseLandmarks?.size == 33) poseLandmarks else null,
            exposure = exposure,
            inferenceLatencyMs = latency,
            throttled = throttled,
        )

        val map = payload.toMap()
        mainHandler.post { eventSink?.success(map) }
    }

    private data class PoseSnapshot(val landmarks: List<List<Float>>?, val latencyMs: Long)

    private fun ImageProxy.toRotatedBitmap(rotation: Int): Bitmap? {
        return try {
            val bmp = this.toBitmap()
            if (rotation == 0) return bmp
            val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
            Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
        } catch (t: Throwable) {
            Log.w(TAG, "toBitmap failed: ${t.message}")
            null
        }
    }

    companion object {
        private const val TAG = "FrameAnalysisCtrl"
        private const val POSE_FPS = 15
        private const val SLOW_FPS = 5
    }
}
