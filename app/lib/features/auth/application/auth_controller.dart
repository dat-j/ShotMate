/// `authStateProvider` (spec-sprint-3 "State Management") — quản lý phiên
/// đăng nhập. Login là TUỲ CHỌN (Rule 1): app khởi động luôn dùng được
/// offline dù `build()` chưa xác định xong trạng thái auth.
///
/// `build()` đọc token đã lưu: có access token → optimistic Authenticated
/// ngay (email hiển thị tạm rỗng/placeholder cho tới khi `meProvider` xác
/// nhận qua `/me` — "validated lazily by first /me" theo spec) để UI Settings
/// không nhấp nháy giữa 2 lần mở app.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/token_storage.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';
import 'auth_state.dart';

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restoreSession();
    return const AuthState.anonymous();
  }

  Future<void> _restoreSession() async {
    final tokenStorage = ref.read(tokenStorageProvider);
    final access = await tokenStorage.readAccess();
    if (access == null || access.isEmpty) return;
    // Optimistic: chưa biết email thật, đặt placeholder — meProvider sẽ
    // xác nhận (và AccountSection đọc email từ đó khi cần độ chính xác).
    state = const AuthState.authenticated(
      AuthUser(id: '', email: ''),
    );
  }

  /// `POST /auth/magic-link` — không đổi state (chưa login), chỉ gửi mail.
  Future<void> requestMagicLink(String email) async {
    await ref.read(authRepositoryProvider).requestMagicLink(email);
  }

  /// `POST /auth/verify` — thành công thì lưu token + chuyển Authenticated.
  Future<void> verifyToken(String token) async {
    final result = await ref.read(authRepositoryProvider).verify(token);
    await ref.read(tokenStorageProvider).writeTokens(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
        );
    state = AuthState.authenticated(result.user);
  }

  /// Xoá token + về anonymous (Rule 1: camera/score offline không bị ảnh
  /// hưởng).
  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    state = const AuthState.anonymous();
  }

  /// `DELETE /me` (FR-S3-7) rồi logout — EC-S3-11: data local giữ nguyên.
  Future<void> deleteAccount() async {
    await ref.read(authRepositoryProvider).deleteAccount();
    await logout();
  }
}

final authStateProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
