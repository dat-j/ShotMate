import 'package:go_router/go_router.dart';

import '../../features/camera/presentation/camera_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/score/presentation/score_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

/// Routes theo spec-sprint-1 "Frontend Changes".
///
/// Camera (`/`) là màn gốc; score/history/settings là **sub-route** của nó nên
/// điều hướng vào (qua `context.push`) giữ camera dưới stack — back hệ thống
/// pop về camera thay vì thoát app. (Route phẳng top-level khiến back thoát app.)
final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const CameraScreen(),
      routes: [
        GoRoute(
          path: 'score/:photoId',
          builder: (_, state) =>
              ScoreScreen(photoId: state.pathParameters['photoId']!),
        ),
        GoRoute(path: 'history', builder: (_, __) => const HistoryScreen()),
        GoRoute(path: 'settings', builder: (_, __) => const SettingsScreen()),
      ],
    ),
  ],
);
