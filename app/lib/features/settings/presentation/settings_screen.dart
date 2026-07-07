/// SettingsScreen — toggles grid/skeleton/HUD (spec-sprint-1 FR-S1-4,
/// FR-S1-7; Frontend Changes: `/settings` route, No auth required) + Account
/// section (spec-sprint-3 FR-S3-7).
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../application/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showGrid = ref.watch(showGridProvider);
    final showSkeleton = ref.watch(showSkeletonProvider);
    final showPerfHud = ref.watch(showPerfHudProvider);
    final smartCountdown = ref.watch(smartCountdownEnabledProvider);

    // DEBUG tạm: canPop cho biết có route dưới stack không.
    debugPrint('SETTINGS canPop=${Navigator.of(context).canPop()} '
        'goRouterCanPop=${GoRouter.of(context).canPop()}');

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Hiển thị lưới rule-of-thirds'),
            value: showGrid,
            onChanged: (value) =>
                ref.read(showGridProvider.notifier).set(value),
          ),
          SwitchListTile(
            title: const Text('Hiển thị skeleton debug'),
            value: showSkeleton,
            onChanged: (value) =>
                ref.read(showSkeletonProvider.notifier).set(value),
          ),
          SwitchListTile(
            title: const Text('Smart Countdown'),
            subtitle: const Text('Tự chụp khi ánh sáng đang đẹp dần'),
            value: smartCountdown,
            onChanged: (value) =>
                ref.read(smartCountdownEnabledProvider.notifier).set(value),
          ),
          // Perf HUD chỉ có ý nghĩa ở debug build (spec FR-S1-7: "Perf HUD
          // (debug builds)") — ẩn toggle hoàn toàn ở release build.
          if (kDebugMode)
            SwitchListTile(
              title: const Text('Hiển thị Perf HUD'),
              subtitle: const Text('fps/latency per-detector, frame→hint p50/p90'),
              value: showPerfHud,
              onChanged: (value) =>
                  ref.read(showPerfHudProvider.notifier).set(value),
            ),
          const Divider(height: 32),
          const _AccountSection(),
        ],
      ),
    );
  }
}

/// Section Account (spec-sprint-3 FR-S3-1, FR-S3-7): anonymous → CTA login;
/// authenticated → email + logout + xoá tài khoản (confirm 2 bước).
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return switch (authState) {
      AuthAnonymous() => ListTile(
          leading: const Icon(Icons.login),
          title: const Text('Đăng nhập để review AI & sync'),
          onTap: () => context.push('/login'),
        ),
      AuthAuthenticated(:final user) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(user.email.isEmpty ? 'Đã đăng nhập' : user.email),
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Nâng cấp Premium'),
              onTap: () => context.push('/paywall'),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Đăng xuất'),
              onTap: () => ref.read(authStateProvider.notifier).logout(),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Xoá tài khoản'),
              textColor: Colors.redAccent,
              iconColor: Colors.redAccent,
              onTap: () => _confirmDeleteAccount(context, ref),
            ),
          ],
        ),
    };
  }

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    // Bước 1: cảnh báo chung.
    final step1 = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá tài khoản?'),
        content: const Text(
          'Toàn bộ dữ liệu trên máy chủ (ảnh đã upload, lịch sử đồng bộ) sẽ '
          'bị xoá vĩnh viễn. Ảnh và điểm số lưu trên máy này vẫn được giữ '
          'nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    if (step1 != true || !context.mounted) return;

    // Bước 2: xác nhận cuối.
    final step2 = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xoá tài khoản'),
        content: const Text('Hành động này không thể hoàn tác. Bạn chắc chắn chứ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Xoá tài khoản'),
          ),
        ],
      ),
    );
    if (step2 != true || !context.mounted) return;

    try {
      await ref.read(authStateProvider.notifier).deleteAccount();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xoá tài khoản')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xoá tài khoản thất bại — thử lại sau')),
      );
    }
  }
}
