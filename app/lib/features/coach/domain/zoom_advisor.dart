/// Gợi ý mức zoom theo scene (spec-sprint-2 FR-S2-3, Business Rule 5).
///
/// Pure function: scene ổn định + zoom hiện tại + range thiết bị → mức zoom gợi
/// ý (hoặc null nếu zoom hiện tại đã trong dải hợp lý). Gợi ý luôn clamp vào
/// range thật của thiết bị (EC-S2-4: không gợi ý ngoài range).
library;

import 'frame_analysis.dart';

/// Dải zoom gợi ý cho mỗi scene: (min, max) bội số.
class _ZoomRange {
  const _ZoomRange(this.min, this.max);
  final double min;
  final double max;
}

class ZoomAdvisor {
  const ZoomAdvisor();

  static const _byScene = {
    SceneType.landscape: _ZoomRange(0.5, 1.0),
    SceneType.portrait: _ZoomRange(1.5, 2.0),
    SceneType.food: _ZoomRange(1.0, 1.5),
  };

  /// Gợi ý mức zoom, hoặc null nếu không cần đổi.
  ///
  /// [currentZoom]: zoom đang áp dụng. [deviceMin]/[deviceMax]: range thật
  /// (từ `getZoomRange`). Nếu zoom hiện tại đã trong dải gợi ý (sau clamp) →
  /// null.
  double? suggest({
    required SceneType scene,
    required double currentZoom,
    double deviceMin = 1.0,
    double deviceMax = 10.0,
  }) {
    final range = _byScene[scene];
    if (range == null) return null; // unknown → không gợi ý

    // Clamp dải gợi ý vào range thiết bị (EC-S2-4).
    final lo = range.min.clamp(deviceMin, deviceMax);
    final hi = range.max.clamp(deviceMin, deviceMax);
    if (lo > hi) return null; // range thiết bị không giao dải gợi ý

    // Zoom hiện tại đã trong dải → không gợi ý.
    if (currentZoom >= lo && currentZoom <= hi) return null;

    // Gợi ý mức gần nhất trong dải: cận dưới nếu đang zoom thấp hơn, cận trên
    // nếu đang cao hơn.
    return currentZoom < lo ? lo : hi;
  }
}
