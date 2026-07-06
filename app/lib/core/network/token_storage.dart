/// Lưu access/refresh token trong secure storage (Keychain iOS /
/// EncryptedSharedPreferences Android) — spec-sprint-3 FR-S3-1: "Token lưu
/// secure storage, KHÔNG lưu Drift/SharedPreferences".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _accessKey = 'shotmate_access_token';
  static const _refreshKey = 'shotmate_refresh_token';

  Future<String?> readAccess() => _storage.read(key: _accessKey);

  Future<void> writeAccess(String token) =>
      _storage.write(key: _accessKey, value: token);

  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  Future<void> writeRefresh(String token) =>
      _storage.write(key: _refreshKey, value: token);

  /// Ghi cả 2 token cùng lúc (login/verify/refresh response).
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await writeAccess(accessToken);
    await writeRefresh(refreshToken);
  }

  /// Xoá toàn bộ token (logout, hoặc refresh thất bại — Rule 1: về anonymous).
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage();
});
