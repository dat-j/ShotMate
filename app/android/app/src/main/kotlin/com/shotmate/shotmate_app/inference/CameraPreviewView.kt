package com.shotmate.shotmate_app.inference

import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec

/**
 * PlatformView bọc [FrameAnalysisController.previewView] để nhúng camera preview
 * (native CameraX) vào cây widget Flutter qua `AndroidView`.
 *
 * Camera start khi view được tạo, stop khi dispose — gắn với vòng đời của
 * CameraScreen phía Dart.
 */
class CameraPreviewView(
    private val controller: FrameAnalysisController,
) : PlatformView {
    init {
        controller.start()
    }

    override fun getView(): View = controller.previewView

    override fun dispose() {
        controller.stop()
    }
}

class CameraPreviewViewFactory(
    private val controllerProvider: () -> FrameAnalysisController,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: android.content.Context, viewId: Int, args: Any?): PlatformView {
        return CameraPreviewView(controllerProvider())
    }

    companion object {
        const val VIEW_TYPE = "shotmate/camera_preview"
        // Giữ chữ ký để tương lai truyền messenger nếu view cần channel riêng
        @Suppress("UNUSED_PARAMETER")
        fun register(messenger: BinaryMessenger) {}
    }
}
