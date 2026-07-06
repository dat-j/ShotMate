/// Cầu điều khiển camera do Native Inference Module sở hữu (ADR-0001, ADR-0007).
///
/// Trên Android, camera vật lý được CameraX (native) sở hữu để tránh tranh chấp
/// với việc đọc frame cho inference. Preview nhúng qua PlatformView
/// (`shotmate/camera_preview`); chụp ảnh qua MethodChannel
/// (`shotmate/camera_control`).
///
/// iOS Sprint 1 chưa có native module → [NativeCamera.isSupported] = false,
/// caller fallback sang `camera` plugin (xem camera_screen.dart).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _controlChannel = MethodChannel('shotmate/camera_control');
const cameraPreviewViewType = 'shotmate/camera_preview';

/// API điều khiển camera native. Chụp ảnh trên chính camera đang chạy inference.
class NativeCamera {
  const NativeCamera();

  /// true khi platform có native module sở hữu camera (hiện: Android).
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Chụp ảnh, lưu vào [filePath] (app-private). Trả về khi ảnh đã ghi xong.
  /// Ném [CameraCaptureException] nếu native báo lỗi.
  Future<void> capture(String filePath) async {
    try {
      await _controlChannel.invokeMethod<bool>('capture', {'path': filePath});
    } on PlatformException catch (e) {
      throw CameraCaptureException(e.message ?? e.code);
    }
  }
}

class CameraCaptureException implements Exception {
  const CameraCaptureException(this.message);
  final String message;
  @override
  String toString() => 'CameraCaptureException: $message';
}

/// Preview camera native nhúng vào cây widget qua PlatformView.
///
/// Việc start/stop camera gắn với vòng đời PlatformView này (native
/// `CameraPreviewView.init/dispose`), nên đặt/gỡ widget = bật/tắt camera.
class NativeCameraPreview extends StatelessWidget {
  const NativeCameraPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const AndroidView(
      viewType: cameraPreviewViewType,
      creationParamsCodec: StandardMessageCodec(),
    );
  }
}
