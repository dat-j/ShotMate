/// `LoginScreen` (spec-sprint-3 FR-S3-1) — nhập email → "kiểm tra hộp thư".
/// Push từ Settings, KHÔNG BAO GIỜ chặn flow camera (Rule 1) — không có
/// logic camera/coach ở đây, chỉ auth.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _linkSent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Email không hợp lệ');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authStateProvider.notifier).requestMagicLink(email);
      if (!mounted) return;
      setState(() {
        _linkSent = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Không gửi được liên kết — kiểm tra kết nối mạng và thử lại';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng nhập')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: _linkSent ? _SentState(email: _emailController.text.trim()) : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Nhập email để nhận liên kết đăng nhập. Đăng nhập giúp bạn review '
          'ảnh bằng AI và đồng bộ lịch sử — camera vẫn dùng được bình '
          'thường nếu bạn bỏ qua bước này.',
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _loading ? null : _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Gửi liên kết đăng nhập'),
        ),
      ],
    );
  }
}

class _SentState extends StatelessWidget {
  const _SentState({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Đã gửi liên kết đăng nhập tới $email.\n'
          'Kiểm tra hộp thư (mailpit ở local) và bấm liên kết để hoàn tất.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
