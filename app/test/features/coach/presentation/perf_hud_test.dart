import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/coach/application/perf_tracker_provider.dart';
import 'package:shotmate_app/features/coach/domain/perf_tracker.dart';
import 'package:shotmate_app/features/coach/presentation/perf_hud.dart';

Widget _wrap(Widget child, {PerfTracker? tracker}) {
  return ProviderScope(
    overrides: [
      if (tracker != null) perfTrackerProvider.overrideWithValue(tracker),
    ],
    child: MaterialApp(
      home: Scaffold(body: Stack(children: [child])),
    ),
  );
}

void main() {
  testWidgets('hiển thị "no data" khi tracker rỗng', (tester) async {
    await tester.pumpWidget(_wrap(const PerfHud(), tracker: PerfTracker()));

    expect(find.textContaining('no data'), findsOneWidget);
  });

  testWidgets('hiển thị số liệu latency khi tracker có sample', (tester) async {
    final tracker = PerfTracker();
    final now = DateTime.now();
    tracker.record(PerfSample(
      detector: 'pose',
      latencyMs: 25,
      timestampMs: now.millisecondsSinceEpoch,
    ));
    tracker.record(PerfSample(
      detector: 'end_to_end',
      latencyMs: 80,
      timestampMs: now.millisecondsSinceEpoch,
    ));

    await tester.pumpWidget(_wrap(const PerfHud(), tracker: tracker));

    expect(find.textContaining('pose'), findsOneWidget);
    expect(find.textContaining('frame→hint'), findsOneWidget);
    expect(find.textContaining('no data'), findsNothing);
  });
}
