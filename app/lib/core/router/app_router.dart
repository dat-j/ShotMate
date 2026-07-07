import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_verify_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/camera/presentation/camera_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/score/presentation/score_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/subscription/presentation/paywall_screen.dart';

/// Routes theo spec-sprint-1 "Frontend Changes" (+ spec-sprint-3: `/login`,
/// `/auth/verify`).
///
/// Camera (`/`) là màn gốc; score/history/settings/login/auth-verify là
/// **sub-route** của nó nên điều hướng vào (qua `context.push`) giữ camera
/// dưới stack — back hệ thống pop về camera thay vì thoát app. (Route phẳng
/// top-level khiến back thoát app.)
final appRouter = GoRouter(
  // Cold start qua deep link (`shotmate://auth/verify?token=...`, app bị
  // kill): Android/Flutter giao nguyên URI đó làm initial route CHO GoRouter
  // TRƯỚC KHI `AppLinks.getInitialLink()` (main.dart) kịp chạy — GoRouter cố
  // match location bằng path pattern thường (`/auth/verify`) nên fail với
  // GoException "no routes for location" trên toàn bộ URI có scheme. Redirect
  // nó về path chuẩn để không phụ thuộc timing của app_links.
  redirect: (context, state) {
    final uri = state.uri;
    if (uri.scheme == 'shotmate' && uri.host == 'auth' && uri.path == '/verify') {
      return Uri(path: '/auth/verify', queryParameters: uri.queryParameters)
          .toString();
    }
    return null;
  },
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
        // Paywall RevenueCat thật (spec-sprint-4 FR-S4-9) — điểm vào: CTA
        // 402 hết credit (review_result_view.dart) + Settings.
        GoRoute(path: 'paywall', builder: (_, __) => const PaywallScreen()),
      ],
    ),
  ],
);
