import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/coach/domain/frame_analysis.dart';

void main() {
  group('FrameAnalysis.tryParse — inferenceLatencyMs (FR-S1-7 perf feed)', () {
    Map<String, Object?> base() => {
          'schemaVersion': 1,
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
}
