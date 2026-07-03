/// SettingsScreen — toggles grid/skeleton/HUD (spec-sprint-1 FR-S1-4,
/// FR-S1-7; Frontend Changes: `/settings` route, No auth required).
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showGrid = ref.watch(showGridProvider);
    final showSkeleton = ref.watch(showSkeletonProvider);
    final showPerfHud = ref.watch(showPerfHudProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Hiển thị lưới rule-of-thirds'),
            value: showGrid,
            onChanged: (value) =>
                ref.read(showGridProvider.notifier).state = value,
          ),
          SwitchListTile(
            title: const Text('Hiển thị skeleton debug'),
            value: showSkeleton,
            onChanged: (value) =>
                ref.read(showSkeletonProvider.notifier).state = value,
          ),
          // Perf HUD chỉ có ý nghĩa ở debug build (spec FR-S1-7: "Perf HUD
          // (debug builds)") — ẩn toggle hoàn toàn ở release build.
          if (kDebugMode)
            SwitchListTile(
              title: const Text('Hiển thị Perf HUD'),
              subtitle: const Text('fps/latency per-detector, frame→hint p50/p90'),
              value: showPerfHud,
              onChanged: (value) =>
                  ref.read(showPerfHudProvider.notifier).state = value,
            ),
        ],
      ),
    );
  }
}
