import 'package:flutter/material.dart';

/// Score 4 chiều sau chụp (spec FR-S1-5).
/// Scaffold: đọc từ Drift theo photoId ở Sprint 1.
class ScoreScreen extends StatelessWidget {
  const ScoreScreen({super.key, required this.photoId});

  final String photoId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Điểm ảnh')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('TODO(sprint-1): PhotoScorer + Drift lookup'),
            Text('photoId: $photoId'),
          ],
        ),
      ),
    );
  }
}
