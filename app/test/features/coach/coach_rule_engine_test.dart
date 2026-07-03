import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/coach/application/hint_prioritizer.dart';
import 'package:shotmate_app/features/coach/domain/coach_hint.dart';
import 'package:shotmate_app/features/coach/domain/coach_rule_engine.dart';
import 'package:shotmate_app/features/coach/domain/frame_analysis.dart';

FrameAnalysis frame({
  double? horizon,
  SubjectBox? box,
  double confidence = 0.9,
  bool hasPerson = false,
}) =>
    FrameAnalysis(
      schemaVersion: 1,
      timestampMs: 0,
      horizonAngleDeg: horizon,
      subjectBox: box,
      subjectConfidence: confidence,
      hasPerson: hasPerson,
    );

void main() {
  const engine = CoachRuleEngine();

  group('horizon_tilt (hysteresis)', () {
    test('bật tại >3°, hướng ngược chiều nghiêng', () {
      final state = engine.evaluate(frame(horizon: 5.0));
      final hint = state.hints.singleWhere((h) => h.id == 'horizon_tilt');
      expect(hint.severity, HintSeverity.important);
      expect(hint.direction, HintDirection.tiltLeft);
      expect(hint.message, 'Nghiêng máy 5°');
    });

    test('critical khi vượt 7°', () {
      final state = engine.evaluate(frame(horizon: -8.0));
      final hint = state.hints.singleWhere((h) => h.id == 'horizon_tilt');
      expect(hint.severity, HintSeverity.critical);
      expect(hint.direction, HintDirection.tiltRight);
    });

    test('2° giữ hint khi đang active (OFF=1.5°), tắt khi không active', () {
      final active = engine
          .evaluate(frame(horizon: 2.0), activeHintIds: {'horizon_tilt'});
      expect(active.hints.map((h) => h.id), contains('horizon_tilt'));

      final inactive = engine.evaluate(frame(horizon: 2.0));
      expect(inactive.hints, isEmpty);
    });
  });

  group('thirds_offset', () {
    test('subject giữa khung → hint di chuyển về giao điểm thirds', () {
      final state = engine.evaluate(frame(
        box: const SubjectBox(left: 0.4, top: 0.4, width: 0.2, height: 0.2),
      ));
      // Tâm (0.5, 0.5) cách giao điểm gần nhất ~0.236 > 0.15.
      final hint = state.hints.singleWhere((h) => h.id == 'thirds_offset');
      expect(hint.severity, HintSeverity.important);
    });

    test('subject đúng giao điểm thirds → không hint, score cao', () {
      final state = engine.evaluate(frame(
        horizon: 0,
        // Center đúng giao điểm (1/3, 1/3) và area 16% (trong "vùng đẹp"
        // 15–60%) — well-composed shot, không chỉ đúng vị trí mà còn đúng size.
        box: const SubjectBox(left: 0.1333, top: 0.1333, width: 0.4, height: 0.4),
      ));
      expect(state.hints.where((h) => h.id == 'thirds_offset'), isEmpty);
      expect(state.compositionScore, greaterThanOrEqualTo(80));
      expect(state.ratingStars, greaterThanOrEqualTo(4));
    });

    test('confidence thấp → bỏ qua subject rules', () {
      final state = engine.evaluate(frame(
        box: const SubjectBox(left: 0.4, top: 0.4, width: 0.2, height: 0.2),
        confidence: 0.2,
      ));
      expect(state.hints, isEmpty);
    });
  });

  group('subject_cut & subject_too_small', () {
    test('box tràn mép → critical', () {
      final state = engine.evaluate(frame(
        box: const SubjectBox(left: -0.1, top: 0.3, width: 0.4, height: 0.5),
      ));
      final hint = state.hints.singleWhere((h) => h.id == 'subject_cut');
      expect(hint.severity, HintSeverity.critical);
    });

    test('người quá nhỏ (<8% khung) → polish hint', () {
      final state = engine.evaluate(frame(
        box: const SubjectBox(left: 0.31, top: 0.31, width: 0.1, height: 0.1),
        hasPerson: true,
      ));
      expect(state.hints.map((h) => h.id), contains('subject_too_small'));
    });
  });

  group('determinism (golden — ADR-0003)', () {
    test('cùng input luôn cho cùng output', () {
      final input = frame(
        horizon: 4.2,
        box: const SubjectBox(left: 0.05, top: 0.1, width: 0.3, height: 0.6),
        hasPerson: true,
      );
      final a = engine.evaluate(input);
      final b = engine.evaluate(input);
      expect(a.hints.map((h) => h.id), b.hints.map((h) => h.id));
      expect(a.compositionScore, b.compositionScore);
    });
  });

  group('HintPrioritizer', () {
    final t0 = DateTime(2026, 7, 3, 12);

    test('tối đa 2 hint, critical thắng', () {
      final prioritizer = HintPrioritizer();
      const hints = [
        CoachHint(id: 'a', severity: HintSeverity.polish, message: 'a'),
        CoachHint(id: 'b', severity: HintSeverity.critical, message: 'b'),
        CoachHint(id: 'c', severity: HintSeverity.important, message: 'c'),
      ];
      final visible = prioritizer.select(hints, now: t0);
      expect(visible.map((h) => h.id), ['b', 'c']);
    });

    test('debounce 500ms: thay đổi trong cửa sổ bị giữ lại', () {
      final prioritizer = HintPrioritizer();
      const first = [
        CoachHint(id: 'a', severity: HintSeverity.important, message: 'a'),
      ];
      const second = [
        CoachHint(id: 'b', severity: HintSeverity.important, message: 'b'),
      ];
      prioritizer.select(first, now: t0);
      // 200ms sau — trong debounce → vẫn 'a'.
      final held = prioritizer.select(second,
          now: t0.add(const Duration(milliseconds: 200)));
      expect(held.map((h) => h.id), ['a']);
      // 600ms sau — ngoài debounce → đổi sang 'b'.
      final switched = prioritizer.select(second,
          now: t0.add(const Duration(milliseconds: 800)));
      expect(switched.map((h) => h.id), ['b']);
    });
  });

  group('FrameAnalysis.tryParse', () {
    test('schema khác version → null (silent drop)', () {
      expect(
        FrameAnalysis.tryParse({'schemaVersion': 2, 'timestampMs': 1}),
        isNull,
      );
    });

    test('horizonAngleDeg ngoài miền bị clamp về [-45,45]', () {
      final parsed = FrameAnalysis.tryParse({
        'schemaVersion': 1,
        'timestampMs': 1,
        'horizonAngleDeg': 90.0,
      });
      expect(parsed!.horizonAngleDeg, 45);
    });
  });
}
