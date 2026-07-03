/// Cầu nối Native Inference Module → Dart (ADR-0001).
///
/// Native side phải implement EventChannel cùng tên, emit Map JSON đúng schema
/// [FrameAnalysis]. KHÔNG BAO GIỜ gửi pixel data qua channel này
/// (spec-sprint-1 Business Rule 3).
///
/// Contract phía native (Sprint 1):
///   Android: app/android — Kotlin, CameraX ImageAnalysis + MediaPipe/MLKit
///   iOS:     app/ios     — Swift, AVCaptureVideoDataOutput + MediaPipe/MLKit
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/coach/domain/frame_analysis.dart';

const _channelName = 'shotmate/frame_analysis';
const _eventChannel = EventChannel(_channelName);

/// Stream kết quả phân tích frame từ native. Message sai schema bị drop
/// (spec: silent drop; TODO Sprint 1 — đếm số message drop cho perf HUD).
final frameAnalysisStreamProvider = StreamProvider<FrameAnalysis>((ref) {
  return _eventChannel
      .receiveBroadcastStream()
      .map((event) =>
          FrameAnalysis.tryParse(Map<String, Object?>.from(event as Map)))
      .where((analysis) => analysis != null)
      .cast<FrameAnalysis>();
});
