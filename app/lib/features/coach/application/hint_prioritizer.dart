/// Chọn tối đa 2 hint hiển thị + debounce 500ms
/// (spec-sprint-1 Business Rule 1 & 2).
///
/// Stateful có chủ đích: giữ tập hint đang hiển thị (cấp cho rule engine làm
/// hysteresis) và thời điểm đổi gần nhất (debounce). Nhận `now` từ ngoài để
/// test được không cần clock thật.
library;

import '../domain/coach_hint.dart';

class HintPrioritizer {
  HintPrioritizer({this.maxHints = 2, this.debounce = const Duration(milliseconds: 500)});

  final int maxHints;
  final Duration debounce;

  List<CoachHint> _visible = const [];
  DateTime? _lastChange;

  /// Id các hint đang hiển thị — truyền vào [CoachRuleEngine.evaluate].
  Set<String> get activeHintIds => _visible.map((h) => h.id).toSet();

  List<CoachHint> select(List<CoachHint> candidates, {required DateTime now}) {
    final ranked = [...candidates]
      ..sort((a, b) {
        final bySeverity = a.severity.index.compareTo(b.severity.index);
        if (bySeverity != 0) return bySeverity;
        // Cùng severity: hint đang hiển thị giữ chỗ (Business Rule 1).
        final aVisible = activeHintIds.contains(a.id) ? 0 : 1;
        final bVisible = activeHintIds.contains(b.id) ? 0 : 1;
        return aVisible.compareTo(bVisible);
      });
    final next = ranked.take(maxHints).toList();

    final changed = next.map((h) => h.id).join(',') !=
        _visible.map((h) => h.id).join(',');
    if (!changed) {
      _visible = next; // cập nhật metric/message, tập id không đổi
      return _visible;
    }
    final last = _lastChange;
    if (last != null && now.difference(last) < debounce) {
      return _visible; // trong cửa sổ debounce — giữ nguyên
    }
    _visible = next;
    _lastChange = now;
    return _visible;
  }
}
