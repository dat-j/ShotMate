import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/coach/domain/countdown_controller.dart';

void main() {
  // Feed chuỗi luma tăng đủ 15% trải hết cửa sổ 3s → proposed.
  CountdownController proposed() {
    final c = CountdownController();
    c.tick(meanLuma: 100, hasCritical: false, manualCapture: false, nowMs: 0);
    c.tick(
        meanLuma: 110, hasCritical: false, manualCapture: false, nowMs: 1500);
    c.tick(
        meanLuma: 120, hasCritical: false, manualCapture: false, nowMs: 3000);
    assert(c.state.phase == CountdownPhase.proposed);
    return c;
  }

  group('CountdownController — đề xuất (BR-7)', () {
    test('luma tăng ≥15% trong 3s, không critical → proposed', () {
      final c = CountdownController();
      c.tick(meanLuma: 100, hasCritical: false, manualCapture: false, nowMs: 0);
      c.tick(
          meanLuma: 110, hasCritical: false, manualCapture: false, nowMs: 1500);
      final s = c.tick(
          meanLuma: 120, hasCritical: false, manualCapture: false, nowMs: 3000);
      expect(s.phase, CountdownPhase.proposed);
    });

    test('luma tăng nhưng có critical → không đề xuất', () {
      final c = CountdownController();
      c.tick(meanLuma: 100, hasCritical: true, manualCapture: false, nowMs: 0);
      final s = c.tick(
          meanLuma: 120, hasCritical: true, manualCapture: false, nowMs: 3000);
      expect(s.phase, CountdownPhase.idle);
    });

    test('luma không tăng đủ → idle', () {
      final c = CountdownController();
      c.tick(meanLuma: 100, hasCritical: false, manualCapture: false, nowMs: 0);
      final s = c.tick(
          meanLuma: 103, hasCritical: false, manualCapture: false, nowMs: 3000);
      expect(s.phase, CountdownPhase.idle);
    });
  });

  group('CountdownController — đếm & fire', () {
    test('start → đếm 3→2→1 → firing', () {
      final c = proposed();
      expect(c.start(3000).secondsLeft, 3);
      expect(
          c
              .tick(
                  meanLuma: 120,
                  hasCritical: false,
                  manualCapture: false,
                  nowMs: 4000)
              .secondsLeft,
          2);
      expect(
          c
              .tick(
                  meanLuma: 120,
                  hasCritical: false,
                  manualCapture: false,
                  nowMs: 5000)
              .secondsLeft,
          1);
      final fired = c.tick(
          meanLuma: 120, hasCritical: false, manualCapture: false, nowMs: 6000);
      expect(fired.phase, CountdownPhase.firing);
    });

    test('critical xuất hiện giữa đếm → cancelled (EC-S2-1)', () {
      final c = proposed();
      c.start(3000);
      final s = c.tick(
          meanLuma: 120, hasCritical: true, manualCapture: false, nowMs: 4000);
      expect(s.phase, CountdownPhase.cancelled);
      expect(s.cancelReason, isNotNull);
    });

    test('luma tụt >5% so đỉnh giữa đếm → cancelled', () {
      final c = proposed();
      c.start(3000);
      // đỉnh 120, tụt xuống 110 = -8.3%
      final s = c.tick(
          meanLuma: 110, hasCritical: false, manualCapture: false, nowMs: 4000);
      expect(s.phase, CountdownPhase.cancelled);
    });

    test('chụp tay giữa đếm → về idle, không fire (EC-S2-2)', () {
      final c = proposed();
      c.start(3000);
      final s = c.tick(
          meanLuma: 120, hasCritical: false, manualCapture: true, nowMs: 4000);
      expect(s.phase, CountdownPhase.idle);
    });

    test('user huỷ → cancelled', () {
      final c = proposed();
      c.start(3000);
      expect(c.cancelByUser(4000).phase, CountdownPhase.cancelled);
    });
  });

  group('CountdownController — cooldown & disabled', () {
    test('disabled → luôn idle', () {
      final c = CountdownController(config: const CountdownConfig(enabled: false));
      c.tick(meanLuma: 100, hasCritical: false, manualCapture: false, nowMs: 0);
      final s = c.tick(
          meanLuma: 200, hasCritical: false, manualCapture: false, nowMs: 3000);
      expect(s.phase, CountdownPhase.idle);
    });

    test('sau khi fire, cooldown 30s chặn đề xuất mới', () {
      final c = proposed();
      c.start(3000);
      c.tick(meanLuma: 120, hasCritical: false, manualCapture: false, nowMs: 6000); // fire tại 6000
      // ngay sau đó luma lại tăng nhưng trong cooldown
      c.tick(meanLuma: 100, hasCritical: false, manualCapture: false, nowMs: 7000);
      final s = c.tick(
          meanLuma: 130, hasCritical: false, manualCapture: false, nowMs: 10000);
      expect(s.phase, CountdownPhase.idle); // 10000-6000 < 30000
    });
  });
}
