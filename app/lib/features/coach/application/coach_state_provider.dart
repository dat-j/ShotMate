import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/frame_analysis_channel.dart';
import '../domain/coach_hint.dart';
import '../domain/coach_rule_engine.dart';
import '../domain/frame_analysis.dart';
import '../domain/scene_stabilizer.dart';
import '../domain/zoom_advisor.dart';
import 'hint_prioritizer.dart';

final _engineProvider = Provider((_) => const CoachRuleEngine());
final _prioritizerProvider = Provider((_) => HintPrioritizer());
final _sceneStabilizerProvider = Provider((_) => SceneStabilizer());
const _zoomAdvisor = ZoomAdvisor();

/// Scene đã ổn định (Rule 6) — dùng cho angle rule + zoom, và UI hiển thị.
/// Provider riêng để widget khác (vd chip scene) đọc mà không rebuild coach.
final stableSceneProvider = Provider<SceneType>((ref) {
  final stabilizer = ref.watch(_sceneStabilizerProvider);
  final analysis = ref.watch(frameAnalysisStreamProvider).valueOrNull;
  if (analysis == null) return SceneType.unknown;
  return stabilizer.observe(analysis.sceneType);
});

/// FrameAnalysis stream → CoachState cho overlay.
///
/// Prioritizer stateful: cấp activeHintIds cho engine (hysteresis) và
/// debounce 500ms mọi thay đổi tập hint (spec Business Rule 1 & 2).
/// Scene ổn định (Rule 6) feed angle rule + zoom suggestion (FR-S2-3/5).
final coachStateProvider = Provider<CoachState>((ref) {
  final engine = ref.watch(_engineProvider);
  final prioritizer = ref.watch(_prioritizerProvider);
  final analysis = ref.watch(frameAnalysisStreamProvider).valueOrNull;
  if (analysis == null) return CoachState.empty;

  final scene = ref.watch(stableSceneProvider);
  final raw = engine.evaluate(
    analysis,
    activeHintIds: prioritizer.activeHintIds,
    stableScene: scene,
  );
  return CoachState(
    hints: prioritizer.select(raw.hints, now: DateTime.now()),
    compositionScore: raw.compositionScore,
    suggestedZoom: _zoomAdvisor.suggest(
      scene: scene,
      currentZoom: analysis.zoomRatio,
    ),
  );
});
