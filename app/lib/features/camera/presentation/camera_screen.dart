import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../coach/application/coach_state_provider.dart';
import 'coach_overlay.dart';

/// Màn hình chính — camera preview + coach overlay (spec FR-S1-1, FR-S1-4).
///
/// Scaffold: preview là placeholder cho tới khi native inference module
/// (Sprint 1) sẵn sàng. Khi tích hợp: dùng `camera` plugin cho preview/capture,
/// analysis chạy hoàn toàn ở native side (ADR-0001) — KHÔNG startImageStream.
class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coachState = ref.watch(coachStateProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // TODO(sprint-1): CameraPreview(controller)
          const ColoredBox(
            color: Color(0xFF101418),
            child: Center(
              child: Text(
                '📷 Camera preview\n(native module — Sprint 1)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ),
          CoachOverlay(state: coachState),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: () => context.go('/history'),
                      icon: const Icon(Icons.photo_library_outlined,
                          color: Colors.white, size: 32),
                    ),
                    // TODO(sprint-1): capture → PhotoScorer → /score/:id (FR-S1-5)
                    const _ShutterButton(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
      ),
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        ),
      ),
    );
  }
}
