import 'package:go_router/go_router.dart';

import '../../features/camera/presentation/camera_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/score/presentation/score_screen.dart';

/// Routes theo spec-sprint-1 "Frontend Changes".
final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const CameraScreen()),
    GoRoute(
      path: '/score/:photoId',
      builder: (_, state) =>
          ScoreScreen(photoId: state.pathParameters['photoId']!),
    ),
    GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
  ],
);
