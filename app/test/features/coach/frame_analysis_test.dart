import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/coach/domain/frame_analysis.dart';

void main() {
  group('FrameAnalysis.tryParse — inferenceLatencyMs (FR-S1-7 perf feed)', () {
    Map<String, Object?> base() => {
          'schemaVersion': 2,
          'timestampMs': 1730000000000,
        };

    test('parse map latency per-detector từ native', () {
      final fa = FrameAnalysis.tryParse({
        ...base(),
        'inferenceLatencyMs': {'pose': 22, 'composition': 9},
      });
      expect(fa, isNotNull);
      expect(fa!.inferenceLatencyMs, {'pose': 22, 'composition': 9});
    });

    test('latency rỗng khi native không gửi field', () {
      final fa = FrameAnalysis.tryParse(base());
      expect(fa, isNotNull);
      expect(fa!.inferenceLatencyMs, isEmpty);
    });

    test('latency dạng double được ép về int', () {
      final fa = FrameAnalysis.tryParse({
        ...base(),
        'inferenceLatencyMs': {'pose': 22.0},
      });
      expect(fa!.inferenceLatencyMs['pose'], 22);
    });

    test('schema sai vẫn drop (không vì latency mà bỏ qua guard)', () {
      final fa = FrameAnalysis.tryParse({
        'schemaVersion': 99,
        'timestampMs': 1,
        'inferenceLatencyMs': {'pose': 5},
      });
      expect(fa, isNull);
    });
  });

  group('FrameAnalysis.tryParse — schemaVersion 2 fields (FR-S2-8)', () {
    Map<String, Object?> base() => {
          'schemaVersion': 2,
          'timestampMs': 1730000000000,
        };

    test('sceneType parse + coerce unknown khi lạ', () {
      expect(
        FrameAnalysis.tryParse({...base(), 'sceneType': 'food'})!.sceneType,
        SceneType.food,
      );
      expect(
        FrameAnalysis.tryParse({...base(), 'sceneType': 'xyz'})!.sceneType,
        SceneType.unknown,
      );
      expect(
        FrameAnalysis.tryParse(base())!.sceneType,
        SceneType.unknown,
      );
    });

    test('sceneConfidence và smilingProbability clamp [0,1]', () {
      final fa = FrameAnalysis.tryParse({
        ...base(),
        'sceneConfidence': 1.5,
        'smilingProbability': -0.2,
      })!;
      expect(fa.sceneConfidence, 1.0);
      expect(fa.smilingProbability, 0.0);
    });

    test('pitchDeg clamp [-90,90], zoomRatio clamp [0.1,20]', () {
      final fa = FrameAnalysis.tryParse({
        ...base(),
        'pitchDeg': 120.0,
        'zoomRatio': 50.0,
      })!;
      expect(fa.pitchDeg, 90);
      expect(fa.zoomRatio, 20);
    });

    test('field mới null/mặc định khi native không gửi', () {
      final fa = FrameAnalysis.tryParse(base())!;
      expect(fa.smilingProbability, isNull);
      expect(fa.pitchDeg, isNull);
      expect(fa.verticalFovDeg, isNull);
      expect(fa.zoomRatio, 1);
      expect(fa.sceneConfidence, 0);
    });
  });
}
