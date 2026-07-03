/// Riverpod wiring cho [PerfTracker] (spec-sprint-1 FR-S1-7).
///
/// Sprint 1: chưa có nguồn sample thật — native FrameAnalysis
/// `inferenceLatencyMs` per-detector + timestamp chưa chạy qua EventChannel
/// (FR-S1-2 native module chưa tồn tại trong repo này). Khi wired, caller
/// (vd. `coach_state_provider` hoặc frame_analysis_channel) sẽ gọi
/// `ref.read(perfTrackerProvider).record(PerfSample(...))` mỗi frame nhận
/// được, cho từng detector (pose/composition/exposure), channel latency,
/// rule engine time, và tổng frame→hint ('end_to_end').
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/perf_tracker.dart';

/// Instance duy nhất — sống suốt vòng đời app (giữ history 10s rolling).
final perfTrackerProvider = Provider<PerfTracker>((ref) => PerfTracker());
