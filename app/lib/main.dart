import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: ShotMateApp()));
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
