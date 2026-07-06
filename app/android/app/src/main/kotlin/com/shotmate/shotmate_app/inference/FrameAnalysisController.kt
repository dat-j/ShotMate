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
    private val sceneScheduler = DetectorScheduler(SCENE_FPS)

    private var poseDetector: PoseDetectorWrapper? = null
    private val faceDetector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            // Bật classification để đọc smilingProbability (spec-sprint-2 FR-S2-1)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .build()
    )
    private val sceneClassifier = SceneClassifier()

    private var horizonSensor: HorizonSensor? = null
    private val powerManager =
        context.getSystemService(Context.POWER_SERVICE) as PowerManager

    private val latestPose = AtomicReference<PoseSnapshot?>(null)
    // Scene ổn định gần nhất (native trả raw mỗi 1fps; Dart lo Rule 6 ổn định)
    private val latestScene = AtomicReference<SceneClassifier.Result?>(null)
    // Camera control cho zoom (FR-S2-3) + FOV cho distance (FR-S2-4)
    private var camera: androidx.camera.core.Camera? = null
    @Volatile private var verticalFovDeg: Float? = null
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
        camera = provider.bindToLifecycle(
            lifecycleOwner,
            CameraSelector.DEFAULT_BACK_CAMERA,
            preview,
            analysis,
            capture,
        )
        verticalFovDeg = readVerticalFov()
        Log.i(TAG, "camera bound: preview + analysis + capture (fov=$verticalFovDeg)")
    }

    /** FOV dọc từ CameraCharacteristics (spec-sprint-2 FR-S2-4). Null nếu thiếu. */
    private fun readVerticalFov(): Float? {
        return try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE)
                as android.hardware.camera2.CameraManager
            for (id in cm.cameraIdList) {
                val chars = cm.getCameraCharacteristics(id)
                val facing =
                    chars.get(android.hardware.camera2.CameraCharacteristics.LENS_FACING)
                if (facing != android.hardware.camera2.CameraMetadata.LENS_FACING_BACK) continue
                val sizes = chars.get(
                    android.hardware.camera2.CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE
                ) ?: continue
                val focal = chars.get(
                    android.hardware.camera2.CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS
                )?.firstOrNull() ?: continue
                // FOV dọc = 2·atan(sensorHeight / (2·focalLength))
                val fovRad = 2.0 * kotlin.math.atan((sizes.height / (2.0 * focal)))
                return Math.toDegrees(fovRad).toFloat()
            }
            null
        } catch (t: Throwable) {
            Log.w(TAG, "readVerticalFov failed: ${t.message}")
            null
        }
    }

    /** Đặt zoom (FR-S2-3). Trả về true nếu ra lệnh thành công. */
    fun setZoom(ratio: Float): Boolean {
        val cam = camera ?: return false
        val zoomState = cam.cameraInfo.zoomState.value ?: return false
        val clamped = ratio.coerceIn(zoomState.minZoomRatio, zoomState.maxZoomRatio)
        cam.cameraControl.setZoomRatio(clamped)
        return true
    }

    /** Range zoom thật của thiết bị (FR-S2-3, EC-S2-4). */
    fun zoomRange(): Pair<Float, Float>? {
        val state = camera?.cameraInfo?.zoomState?.value ?: return null
        return state.minZoomRatio to state.maxZoomRatio
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
        camera = null
        imageCapture = null
        poseDetector?.close()
        poseDetector = null
        horizonSensor?.stop()
        horizonSensor = null
        latestPose.set(null)
        latestScene.set(null)
        poseScheduler.reset(); exposureScheduler.reset()
        faceScheduler.reset(); sceneScheduler.reset()
    }

    fun dispose() {
        stop()
        faceDetector.close()
        sceneClassifier.close()
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

            var face: FaceResult? = null
            if (!throttled && faceScheduler.shouldRun(nowMs)) {
                face = detectFace(image, rotation)
            }

            // Scene classifier 1fps (FR-S2-2) — tắt khi throttled (EC-S2-8)
            if (!throttled && sceneScheduler.shouldRun(nowMs)) {
                sceneClassifier.classify(image, rotation)?.let { latestScene.set(it) }
            }

            emitPayload(nowMs, throttled, exposure, exposureLatency, face)
        } catch (t: Throwable) {
            Log.w(TAG, "analyze error: ${t.message}")
        } finally {
            image.close()
        }
    }

    private data class FaceResult(val box: SubjectBoxPayload, val smiling: Float?)

    private fun detectFace(image: ImageProxy, rotation: Int): FaceResult? {
        val media = image.image ?: return null
        return try {
            val input = InputImage.fromMediaImage(media, rotation)
            val faces = Tasks.await(faceDetector.process(input))
            val largest = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
                ?: return null
            val (w, h) = if (rotation == 90 || rotation == 270)
                image.height to image.width else image.width to image.height
            val b = largest.boundingBox
            FaceResult(
                box = SubjectBoxPayload(
                    left = (b.left.toFloat() / w).coerceIn(0f, 1f),
                    top = (b.top.toFloat() / h).coerceIn(0f, 1f),
                    width = (b.width().toFloat() / w).coerceIn(0f, 1f),
                    height = (b.height().toFloat() / h).coerceIn(0f, 1f),
                ),
                smiling = largest.smilingProbability,
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
        face: FaceResult?,
    ) {
        val pose = latestPose.get()
        val poseLandmarks = pose?.landmarks
        val faceBox = face?.box
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

        val scene = latestScene.get()
        val zoom = camera?.cameraInfo?.zoomState?.value?.zoomRatio ?: 1f

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
            sceneType = scene?.scene,
            sceneConfidence = scene?.confidence ?: 0f,
            smilingProbability = face?.smiling,
            pitchDeg = horizonSensor?.currentPitchDeg(),
            zoomRatio = zoom,
            verticalFovDeg = verticalFovDeg,
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
        private const val SCENE_FPS = 1
    }
}
