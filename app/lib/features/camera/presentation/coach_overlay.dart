import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../coach/domain/coach_hint.dart';

/// Overlay guidance trên camera preview (spec FR-S1-4):
/// grid rule-of-thirds, tối đa 2 hint, rating sao. Hint fade 150ms.
///
/// [showGrid]/[showSkeleton] đến từ settings toggles (spec FR-S1-4:
/// "grid ... bật/tắt được", "skeleton dots ... toggle trong settings") —
/// xem `settings_providers.dart`.
class CoachOverlay extends StatelessWidget {
  const CoachOverlay({
    super.key,
    required this.state,
    this.showGrid = true,
    this.showSkeleton = false,
    this.poseLandmarks,
    this.throttled = false,
  });

  final CoachState state;
  final bool showGrid;
  final bool showSkeleton;

  /// Thiết bị đang throttle vì nhiệt (spec-sprint-2 EC-4/FR-S2-7) — hiện icon
  /// "chế độ tiết kiệm". Đến từ `FrameAnalysis.throttled` (native).
  final bool throttled;

  /// 33 điểm MediaPipe [x,y] normalized — từ `FrameAnalysis.poseLandmarks`
  /// (raw stream, không qua rule engine). Null nếu không detect được người.
  final List<List<double>>? poseLandmarks;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showGrid) CustomPaint(painter: _ThirdsGridPainter()),
          if (showSkeleton && poseLandmarks != null)
            CustomPaint(painter: _SkeletonPainter(poseLandmarks!)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RatingStars(stars: state.ratingStars),
                      if (throttled) ...[
                        const SizedBox(width: 8),
                        const _ThermalBadge(),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Column(
                    key: ValueKey(state.hints.map((h) => h.id).join(',')),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final hint in state.hints) _HintChip(hint: hint),
                    ],
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThirdsGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gridLine
      ..strokeWidth = 1;
    for (final f in [1 / 3, 2 / 3]) {
      canvas.drawLine(
          Offset(size.width * f, 0), Offset(size.width * f, size.height), paint);
      canvas.drawLine(
          Offset(0, size.height * f), Offset(size.width, size.height * f), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Debug visualization: chấm tại mỗi pose landmark (spec FR-S1-4: "skeleton
/// dots khi detect được người"). Vẽ điểm thô, không nối xương — đủ để xác
/// nhận detector hoạt động, không phải sản phẩm cuối.
class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter(this.landmarks);

  final List<List<double>> landmarks;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.ratingStar;
    for (final point in landmarks) {
      if (point.length < 2) continue;
      canvas.drawCircle(
        Offset(point[0] * size.width, point[1] * size.height),
        3,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SkeletonPainter oldDelegate) =>
      oldDelegate.landmarks != landmarks;
}

class _RatingStars extends StatelessWidget {
  const _RatingStars({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= stars ? Icons.star : Icons.star_border,
            color: AppColors.ratingStar,
            size: 22,
          ),
      ],
    );
  }
}

/// Icon "chế độ tiết kiệm" khi thiết bị throttle vì nhiệt (EC-4).
class _ThermalBadge extends StatelessWidget {
  const _ThermalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.hintCritical,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.thermostat, color: Colors.white, size: 14),
          SizedBox(width: 4),
          Text('Tiết kiệm',
              style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.hint});

  final CoachHint hint;

  static const _icons = {
    HintDirection.left: Icons.arrow_back,
    HintDirection.right: Icons.arrow_forward,
    HintDirection.up: Icons.arrow_upward,
    HintDirection.down: Icons.arrow_downward,
    HintDirection.forward: Icons.zoom_in_map,
    HintDirection.backward: Icons.zoom_out_map,
    HintDirection.tiltLeft: Icons.rotate_left,
    HintDirection.tiltRight: Icons.rotate_right,
    HintDirection.none: Icons.tips_and_updates_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final isCritical = hint.severity == HintSeverity.critical;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isCritical ? AppColors.hintCritical : AppColors.hintDefault,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icons[hint.direction], color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(hint.message,
              style: const TextStyle(color: Colors.white, fontSize: 15)),
        ],
      ),
    );
  }
}
