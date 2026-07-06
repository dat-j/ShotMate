import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_verify_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/camera/presentation/camera_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/score/presentation/score_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

/// Routes theo spec-sprint-1 "Frontend Changes" (+ spec-sprint-3: `/login`,
/// `/auth/verify`).
///
/// Camera (`/`) là màn gốc; score/history/settings/login/auth-verify là
/// **sub-route** của nó nên điều hướng vào (qua `context.push`) giữ camera
/// dưới stack — back hệ thống pop về camera thay vì thoát app. (Route phẳng
/// top-level khiến back thoát app.)
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
        // Push từ Settings ("Đăng nhập để review AI & sync") — KHÔNG BAO GIỜ
        // chặn flow camera (Rule 1, spec-sprint-3 FR-S3-1).
        GoRoute(path: 'login', builder: (_, __) => const LoginScreen()),
        // Deep link `shotmate://auth/verify?token=...` (app_links) VÀ route
        // GoRouter thật khi app đã chạy (spec-sprint-3 "Frontend Changes").
        GoRoute(
          path: 'auth/verify',
          builder: (_, state) => AuthVerifyScreen(
            token: state.uri.queryParameters['token'],
          ),
        ),
      ],
    ),
  ],
);
