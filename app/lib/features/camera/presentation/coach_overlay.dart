import 'package:flutter/material.dart';

import '../../coach/domain/coach_hint.dart';

/// Overlay guidance trên camera preview (spec FR-S1-4):
/// grid rule-of-thirds, tối đa 2 hint, rating sao. Hint fade 150ms.
class CoachOverlay extends StatelessWidget {
  const CoachOverlay({super.key, required this.state});

  final CoachState state;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _ThirdsGridPainter()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _RatingStars(stars: state.ratingStars),
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
      ..color = Colors.white24
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
            color: Colors.amber,
            size: 22,
          ),
      ],
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
        color: isCritical ? Colors.red.withValues(alpha: 0.85) : Colors.black54,
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
