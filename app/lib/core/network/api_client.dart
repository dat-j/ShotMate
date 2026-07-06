/// Dio client dùng chung (spec-sprint-3 "State Management": `apiClientProvider`
/// = `Provider<Dio>` với baseUrl + auth interceptor refresh 1 lần).
///
/// Interceptor:
/// - onRequest: gắn `Authorization: Bearer <access>` nếu có token lưu.
/// - onError 401: thử `POST /auth/refresh` ĐÚNG 1 LẦN (cờ trên
///   `RequestOptions.extra` chống lặp vô hạn — "Keep it robust — never
///   loop"); thành công → lưu token mới + retry request gốc; thất bại → xoá
///   token (logout về anonymous, Rule 1 app vẫn dùng offline bình thường) rồi
///   forward lỗi gốc.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_config.dart';
import 'token_storage.dart';

/// Cờ đánh dấu request đã retry sau refresh — tránh loop vô hạn khi refresh
/// thành công nhưng request gốc vẫn 401 (vd token vừa bị revoke).
const _kRetriedKey = 'shotmate_retried_after_refresh';

final apiClientProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ),
  );

  // Dio riêng cho refresh call — không đi qua interceptor này, tránh đệ quy.
  final refreshDio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final access = await tokenStorage.readAccess();
        if (access != null && access.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $access';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final statusCode = error.response?.statusCode;
        final alreadyRetried =
            error.requestOptions.extra[_kRetriedKey] == true;

        if (statusCode != 401 || alreadyRetried) {
          handler.next(error);
          return;
        }

        final refreshToken = await tokenStorage.readRefresh();
        if (refreshToken == null || refreshToken.isEmpty) {
          handler.next(error);
          return;
        }

        try {
          final response = await refreshDio.post<Map<String, Object?>>(
            '/auth/refresh',
            data: {'refreshToken': refreshToken},
          );
          final body = response.data;
          final newAccess = body?['accessToken'] as String?;
          final newRefresh = body?['refreshToken'] as String?;
          if (newAccess == null || newRefresh == null) {
            await tokenStorage.clear();
            handler.next(error);
            return;
          }
          await tokenStorage.writeTokens(
            accessToken: newAccess,
            refreshToken: newRefresh,
          );

          final retryOptions = error.requestOptions;
          retryOptions.extra[_kRetriedKey] = true;
          retryOptions.headers['Authorization'] = 'Bearer $newAccess';
          final retryResponse = await dio.fetch<Object?>(retryOptions);
          handler.resolve(retryResponse);
        } on DioException {
          // Refresh thất bại (token reuse/expired — EC-S3-5) → về anonymous.
          await tokenStorage.clear();
          handler.next(error);
        }
      },
    ),
  );

  return dio;
});
