import 'package:flutter/material.dart';

/// History list (spec FR-S1-6) — pagination 30/lần từ Drift, mới nhất trước.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử')),
      body: const Center(
        child: Text('TODO(sprint-1): HistoryRepository (Drift) + thumbnails'),
      ),
    );
  }
}
