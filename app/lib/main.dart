import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebase();
  runApp(const ProviderScope(child: ShotMateApp()));
}

/// Khởi tạo Firebase (Analytics/Crashlytics — spec-sprint-4 FR-S4-9), bọc
/// try/catch vì `google-services.json`/`firebase_options.dart` CHƯA tồn tại
/// trong môi trường này (chưa có Firebase project thật, chờ
/// `flutterfire configure`). `Firebase.initializeApp()` sẽ throw khi thiếu
/// config native — bắt lỗi, log cảnh báo, KHÔNG crash app: `flutter run`/
/// `flutter test` vẫn chạy bình thường không cần Firebase project.
/// `AnalyticsService` (core/analytics) tự kiểm tra `Firebase.apps.isNotEmpty`
/// trước khi gọi bất kỳ API Firebase nào nên mọi lời gọi analytics sau đó
/// vẫn an toàn (no-op) khi khối này fail.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint(
      'Firebase.initializeApp() thất bại — bỏ qua (chưa có '
      'google-services.json/firebase_options.dart, chờ `flutterfire '
      'configure` khi có Firebase project thật, spec-sprint-4 FR-S4-9): $e',
    );
  }
}

/// Deep link `shotmate://auth/verify?token=...` (spec-sprint-3 FR-S3-1) —
/// điều hướng qua GoRouter route `/auth/verify` (đã map query `token`), màn
/// hình đó tự gọi `verifyToken`. Không có deep link nào chặn camera (Rule 1):
/// nếu parse lỗi, im lặng bỏ qua.
class ShotMateApp extends StatefulWidget {
  const ShotMateApp({super.key});

  @override
  State<ShotMateApp> createState() => _ShotMateAppState();
}

class _ShotMateAppState extends State<ShotMateApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (Object _) {},
    );
  }

  void _handleDeepLink(Uri uri) {
    if (uri.host != 'auth' || uri.path != '/verify') return;
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return;
    appRouter.push('/auth/verify?token=$token');
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ShotMate',
      theme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
