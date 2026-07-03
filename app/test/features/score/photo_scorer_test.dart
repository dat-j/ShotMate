import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/coach/domain/frame_analysis.dart';
import 'package:shotmate_app/features/score/domain/photo_scorer.dart';

ExposureInfo exposure({
  double meanLuma = 135,
  double clippedHighlightsPct = 0,
  double clippedShadowsPct = 0,
}) =>
    ExposureInfo(
      meanLuma: meanLuma,
      clippedHighlightsPct: clippedHighlightsPct,
      clippedShadowsPct: clippedShadowsPct,
    );

void main() {
  const scorer = PhotoScorer();

  group('lighting', () {
    test('midtone well-exposed image scores well', () {
      final score = scorer.score(
        compositionScore: 80,
        exposure: exposure(meanLuma: 135),
        sharpnessVariance: 200,
        backgroundEdgeDensity: 0.1,
      );
      expect(score.lighting, 100);
    });

    test('blown highlights penalized', () {
      final clean = scorer.score(
        compositionScore: 80,
        exposure: exposure(meanLuma: 135),
        sharpnessVariance: 200,
        backgroundEdgeDensity: 0.1,
      );
      final blown = scorer.score(
        compositionScore: 80,
        exposure: exposure(meanLuma: 135, clippedHighlightsPct: 0.2),
        sharpnessVariance: 200,
        backgroundEdgeDensity: 0.1,
      );
      expect(blown.lighting, lessThan(clean.lighting));
      expect(blown.lighting, 0);
    });

    test('crushed shadows penalized', () {
      final clean = scorer.score(
        compositionScore: 80,
        exposure: exposure(meanLuma: 135),
        sharpnessVariance: 200,
        backgroundEdgeDensity: 0.1,
      );
      final crushed = scorer.score(
        compositionScore: 80,
        exposure: exposure(meanLuma: 135, clippedShadowsPct: 0.1),
        sharpnessVariance: 200,
        backgroundEdgeDensity: 0.1,
      );
      expect(crushed.lighting, lessThan(clean.lighting));
    });

    test('missing exposure data → neutral score', () {
      final score = scorer.score(
        compositionScore: 80,
        sharpnessVariance: 200,
        backgroundEdgeDensity: 0.1,
      );
      expect(score.lighting, 70);
    });

    test('extreme underexposure scores low', () {
      final score = scorer.score(
        compositionScore: 80,
        exposure: exposure(meanLuma: 5),
        sharpnessVariance: 200,
        backgroundEdgeDensity: 0.1,
      );
      expect(score.lighting, 0);
    });

    test('extreme overexposure scores low', () {
      final score = scorer.score(
        compositionScore: 80,
        exposure: exposure(meanLuma: 255),
        sharpnessVariance: 200,
        backgroundEdgeDensity: 0.1,
      );
      expect(score.lighting, 0);
    });
  });

  group('focus', () {
    test('sharp image (high variance) scores well', () {
      final score = scorer.score(
        compositionScore: 80,
        exposure: exposure(),
        sharpnessVariance: 150,
        backgroundEdgeDensity: 0.1,
      );
      expect(score.focus, 100);
    });

    test('blurry image (low variance) scores low', () {
      final score = scorer.score(
        compositionScore: 80,
        exposure: exposure(),
        sharpnessVariance: 5,
        backgroundEdgeDensity: 0.1,
      );
      expect(score.focus, 0);
    });

    test('mid variance scores between blur and sharp', () {
      final score = scorer.score(
        compositionScore: 80,
        exposure: exposure(),
        sharpnessVariance: 30,
        backgroundEdgeDensity: 0.1,
      );
      expect(score.focus, greaterThan(0));
      expect(score.focus, lessThan(100));
    });

    test('negative variance clamps to 0 without throwing', () {
      final score = scorer.score(
        compositionScore: 80,
        exposure: exposure(),
        sharpnessVariance: -10,
        backgroundEdgeDensity: 0.1,
      );
      expect(score.focus, 0);
    });
  });

  group('background', () {
    test('clean background (low edge density) scores well', () {
      final score = scorer.score(
        compositionScore: 80,
        exposure: exposure(),
        sharpnessVariance: 150,
        backgroundEdgeDensity: 0.0,
      );
      expect(score.background, 100);
    });

    test('busy background (high edge density) scores low', () {
      final score = scorer.score(
        compositionScore: 80,
        exposure: exposure(),
        sharpnessVariance: 150,
        backgroundEdgeDensity: 1.0,
      );
      expect(score.background, 0);
    });

    test('mid busyness scores between clean and busy', () {
      final score = scorer.score(
        compositionScore: 80,
        exposure: exposure(),
        sharpnessVariance: 150,
        backgroundEdgeDensity: 0.25,
      );
      expect(score.background, greaterThan(0));
      expect(score.background, lessThan(100));
    });
  });

  group('composition passthrough', () {
    test('uses provided compositionScore as-is (not recomputed)', () {
      final score = scorer.score(
        compositionScore: 42,
        exposure: exposure(),
        sharpnessVariance: 150,
        backgroundEdgeDensity: 0.1,
      );
      expect(score.composition, 42);
    });

    test('clamps out-of-range compositionScore input', () {
      final over = scorer.score(
        compositionScore: 150,
        exposure: exposure(),
        sharpnessVariance: 150,
        backgroundEdgeDensity: 0.1,
      );
      final under = scorer.score(
        compositionScore: -10,
        exposure: exposure(),
        sharpnessVariance: 150,
        backgroundEdgeDensity: 0.1,
      );
      expect(over.composition, 100);
      expect(under.composition, 0);
    });
  });

  group('clamping invariants', () {
    test('all dimensions stay within [0,100] across varied inputs', () {
      const variances = [-100.0, 0.0, 5.0, 50.0, 100.0, 1000.0];
      const densities = [-1.0, 0.0, 0.5, 1.0, 2.0];
      const lumas = [-10.0, 0.0, 135.0, 255.0, 400.0];

      for (final variance in variances) {
        for (final density in densities) {
          for (final luma in lumas) {
            final score = scorer.score(
              compositionScore: 80,
              exposure: exposure(meanLuma: luma),
              sharpnessVariance: variance,
              backgroundEdgeDensity: density,
            );
            expect(score.lighting, inInclusiveRange(0, 100));
            expect(score.focus, inInclusiveRange(0, 100));
            expect(score.background, inInclusiveRange(0, 100));
            expect(score.composition, inInclusiveRange(0, 100));
          }
        }
      }
    });
  });

  group('determinism', () {
    test('same input → same output', () {
      final input = exposure(
        meanLuma: 120,
        clippedHighlightsPct: 0.05,
        clippedShadowsPct: 0.02,
      );
      final a = scorer.score(
        compositionScore: 65,
        exposure: input,
        sharpnessVariance: 45,
        backgroundEdgeDensity: 0.3,
      );
      final b = scorer.score(
        compositionScore: 65,
        exposure: input,
        sharpnessVariance: 45,
        backgroundEdgeDensity: 0.3,
      );
      expect(a.composition, b.composition);
      expect(a.lighting, b.lighting);
      expect(a.focus, b.focus);
      expect(a.background, b.background);
    });
  });
}
