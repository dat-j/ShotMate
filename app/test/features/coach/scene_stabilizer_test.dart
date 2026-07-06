import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/coach/domain/frame_analysis.dart';
import 'package:shotmate_app/features/coach/domain/scene_stabilizer.dart';
import 'package:shotmate_app/features/coach/domain/zoom_advisor.dart';

void main() {
  group('SceneStabilizer (Rule 6 — ổn định 3 mẫu)', () {
    test('chưa đủ streak thì giữ unknown', () {
      final s = SceneStabilizer();
      expect(s.observe(SceneType.portrait), SceneType.unknown);
      expect(s.observe(SceneType.portrait), SceneType.unknown);
    });

    test('công bố scene sau 3 mẫu liên tiếp', () {
      final s = SceneStabilizer();
      s.observe(SceneType.food);
      s.observe(SceneType.food);
      expect(s.observe(SceneType.food), SceneType.food);
    });

    test('flapping không công bố (EC-S2-3)', () {
      final s = SceneStabilizer();
      expect(s.observe(SceneType.portrait), SceneType.unknown);
      expect(s.observe(SceneType.food), SceneType.unknown);
      expect(s.observe(SceneType.portrait), SceneType.unknown);
    });

    test('giữ scene công bố cũ khi gặp unknown', () {
      final s = SceneStabilizer();
      s.observe(SceneType.landscape);
      s.observe(SceneType.landscape);
      s.observe(SceneType.landscape); // published = landscape
      expect(s.observe(SceneType.unknown), SceneType.landscape);
    });

    test('đổi scene mới cần lại đủ streak', () {
      final s = SceneStabilizer();
      for (var i = 0; i < 3; i++) {
        s.observe(SceneType.portrait);
      }
      expect(s.published, SceneType.portrait);
      s.observe(SceneType.food); // streak 1
      s.observe(SceneType.food); // streak 2
      expect(s.published, SceneType.portrait); // chưa đủ, giữ cũ
      s.observe(SceneType.food); // streak 3
      expect(s.published, SceneType.food);
    });
  });

  group('ZoomAdvisor (Rule 5 / FR-S2-3)', () {
    const advisor = ZoomAdvisor();

    test('portrait ở 1x → gợi ý 1.5x (cận dưới dải)', () {
      expect(
        advisor.suggest(scene: SceneType.portrait, currentZoom: 1.0),
        1.5,
      );
    });

    test('portrait đã ở 1.8x (trong dải) → null', () {
      expect(
        advisor.suggest(scene: SceneType.portrait, currentZoom: 1.8),
        isNull,
      );
    });

    test('landscape muốn 0.5x nhưng thiết bị min 1.0 → clamp, không gợi ý (EC-S2-4)', () {
      // dải landscape (0.5–1.0) clamp về (1.0–1.0); current 1.0 đã trong dải
      expect(
        advisor.suggest(
          scene: SceneType.landscape,
          currentZoom: 1.0,
          deviceMin: 1.0,
        ),
        isNull,
      );
    });

    test('food ở 3x (cao hơn dải) → gợi ý về cận trên 1.5x', () {
      expect(
        advisor.suggest(scene: SceneType.food, currentZoom: 3.0),
        1.5,
      );
    });

    test('scene unknown → không gợi ý', () {
      expect(
        advisor.suggest(scene: SceneType.unknown, currentZoom: 1.0),
        isNull,
      );
    });
  });
}
