/// Gọi 3 endpoint auth (spec-sprint-3 FR-S3-1 + API Changes) + DELETE /me
/// (FR-S3-7, dùng chung bởi auth_controller cho "Xoá tài khoản").
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/auth_user.dart';

/// Kết quả từ /auth/verify hoặc /auth/refresh — token pair + user.
class AuthTokenResult {
  const AuthTokenResult({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthTokenResult.fromJson(Map<String, Object?> json) {
    return AuthTokenResult(
      accessToken: json['accessToken']! as String,
      refreshToken: json['refreshToken']! as String,
      user: AuthUser.fromJson(json['user']! as Map<String, Object?>),
    );
  }

  final String accessToken;
  final String refreshToken;
  final AuthUser user;
}

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// `POST /auth/magic-link` — luôn 202 bất kể email tồn tại hay không
  /// (Rule 6, không lộ user tồn tại).
  Future<void> requestMagicLink(String email) async {
    await _dio.post<void>('/auth/magic-link', data: {'email': email});
  }

  /// `POST /auth/verify` — 401 `AUTH_LINK_INVALID` nếu token sai/hết hạn/đã
  /// dùng (ném DioException, caller xử lý).
  Future<AuthTokenResult> verify(String token) async {
    final response = await _dio.post<Map<String, Object?>>(
      '/auth/verify',
      data: {'token': token},
    );
    return AuthTokenResult.fromJson(response.data!);
  }

  /// `POST /auth/refresh` — dùng khi cần chủ động refresh ngoài luồng
  /// interceptor (vd sau khi app resume). Interceptor tự lo refresh 401.
  Future<AuthTokenResult> refresh(String refreshToken) async {
    final response = await _dio.post<Map<String, Object?>>(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    return AuthTokenResult.fromJson(response.data!);
  }

  /// `DELETE /me` (FR-S3-7) — xoá account server-side, 204 khi thành công.
  Future<void> deleteAccount() async {
    await _dio.delete<void>('/me');
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});
