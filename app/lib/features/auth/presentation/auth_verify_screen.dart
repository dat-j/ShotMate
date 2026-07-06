/// Route `/auth/verify?token=...` (spec-sprint-3 "Frontend Changes": "deep
/// link handler ... → verify → pop về Settings").
///
/// Dùng làm route thật (không chỉ deep link handler ẩn) để `app_links` và
/// GoRouter đều có nơi điều hướng tới khi app đã chạy (cold start hoặc
/// warm start) — tự verify token trong `initState` rồi tự pop/redirect.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_controller.dart';

class AuthVerifyScreen extends ConsumerStatefulWidget {
  const AuthVerifyScreen({super.key, required this.token});

  final String? token;

  @override
  ConsumerState<AuthVerifyScreen> createState() => _AuthVerifyScreenState();
}

class _AuthVerifyScreenState extends ConsumerState<AuthVerifyScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Liên kết không hợp lệ');
      return;
    }
    try {
      await ref.read(authStateProvider.notifier).verifyToken(token);
      if (!mounted) return;
      // Đăng nhập xong → về Settings (spec: "verify → pop về Settings").
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/settings');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Liên kết đã hết hạn hoặc đã được dùng — '
          'vui lòng yêu cầu liên kết mới');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng nhập')),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go('/settings'),
                      child: const Text('Về Cài đặt'),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
