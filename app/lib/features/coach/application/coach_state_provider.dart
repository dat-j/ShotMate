import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/frame_analysis_channel.dart';
import '../domain/coach_hint.dart';
import '../domain/coach_rule_engine.dart';
import 'hint_prioritizer.dart';

final _engineProvider = Provider((_) => const CoachRuleEngine());
final _prioritizerProvider = Provider((_) => HintPrioritizer());

/// FrameAnalysis stream → CoachState cho overlay.
///
/// Prioritizer stateful: cấp activeHintIds cho engine (hysteresis) và
/// debounce 500ms mọi thay đổi tập hint (spec Business Rule 1 & 2).
final coachStateProvider = Provider<CoachState>((ref) {
  final engine = ref.watch(_engineProvider);
  final prioritizer = ref.watch(_prioritizerProvider);
  final analysis = ref.watch(frameAnalysisStreamProvider).valueOrNull;
  if (analysis == null) return CoachState.empty;

  final raw = engine.evaluate(
    analysis,
    activeHintIds: prioritizer.activeHintIds,
  );
  return CoachState(
    hints: prioritizer.select(raw.hints, now: DateTime.now()),
    compositionScore: raw.compositionScore,
  );
});
