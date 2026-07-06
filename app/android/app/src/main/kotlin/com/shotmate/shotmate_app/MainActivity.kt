package com.shotmate.shotmate_app

import com.shotmate.shotmate_app.inference.CameraPreviewViewFactory
import com.shotmate.shotmate_app.inference.FrameAnalysisController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private var controller: FrameAnalysisController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val ctrl = FrameAnalysisController(applicationContext, this)
        controller = ctrl

        // Analysis stream → Dart (frame_analysis_channel.dart)
        EventChannel(messenger, ANALYSIS_CHANNEL).setStreamHandler(ctrl)

        // Native camera preview PlatformView
        flutterEngine.platformViewsController.registry.registerViewFactory(
            CameraPreviewViewFactory.VIEW_TYPE,
            CameraPreviewViewFactory { controller!! },
        )

        // Capture control (native camera owner chụp ảnh)
        MethodChannel(messenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "capture" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "missing path", null)
                    } else {
                        ctrl.capture(
                            File(path),
                            onSaved = { result.success(true) },
                            onError = { msg -> result.error("capture_failed", msg, null) },
                        )
                    }
                }
                "setZoom" -> {
                    val ratio = (call.argument<Double>("ratio"))?.toFloat()
                    if (ratio == null) {
                        result.error("bad_args", "missing ratio", null)
                    } else {
                        result.success(ctrl.setZoom(ratio))
                    }
                }
                "getZoomRange" -> {
                    val range = ctrl.zoomRange()
                    if (range == null) {
                        result.success(null)
                    } else {
                        result.success(mapOf("min" to range.first, "max" to range.second))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        controller?.dispose()
        controller = null
        super.onDestroy()
    }

    companion object {
        private const val ANALYSIS_CHANNEL = "shotmate/frame_analysis"
        private const val CONTROL_CHANNEL = "shotmate/camera_control"
    }
}
