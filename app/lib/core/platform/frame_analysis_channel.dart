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

import '../../features/coach/application/perf_tracker_provider.dart';
import '../../features/coach/domain/frame_analysis.dart';
import '../../features/coach/domain/perf_tracker.dart';

const _channelName = 'shotmate/frame_analysis';
const _eventChannel = EventChannel(_channelName);

/// Stream kết quả phân tích frame từ native. Message sai schema bị drop
/// (spec: silent drop).
///
/// Ghi PerfSample mỗi frame vào [perfTrackerProvider] (FR-S1-7, benchmark
/// gate): mỗi detector từ `inferenceLatencyMs`, cộng `end_to_end` = thời gian
/// từ lúc native đóng dấu `timestampMs` tới khi Dart nhận (gần đúng
/// frame→hint, gồm channel transit + parse).
final frameAnalysisStreamProvider = StreamProvider<FrameAnalysis>((ref) {
  final tracker = ref.watch(perfTrackerProvider);
  return _eventChannel
      .receiveBroadcastStream()
      .map((event) =>
          FrameAnalysis.tryParse(Map<String, Object?>.from(event as Map)))
      .where((analysis) => analysis != null)
      .cast<FrameAnalysis>()
      .map((analysis) {
    _recordPerf(tracker, analysis);
    return analysis;
  });
});

void _recordPerf(PerfTracker tracker, FrameAnalysis analysis) {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  analysis.inferenceLatencyMs.forEach((detector, latencyMs) {
    tracker.record(PerfSample(
      detector: detector,
      latencyMs: latencyMs.toDouble(),
      timestampMs: nowMs,
    ));
  });
  final endToEnd = (nowMs - analysis.timestampMs).toDouble();
  // Bảo vệ chống lệch đồng hồ native↔Dart (giá trị âm) — bỏ qua sample bẩn.
  if (endToEnd >= 0) {
    tracker.record(PerfSample(
      detector: 'end_to_end',
      latencyMs: endToEnd,
      timestampMs: nowMs,
    ));
  }
}
