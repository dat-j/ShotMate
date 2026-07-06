/// Cấu hình API base URL (spec-sprint-3 "API Changes" — prefix `api/v1`).
///
/// Mặc định trỏ tới Android emulator (`10.0.2.2` là host loopback từ trong
/// emulator) — override lúc build bằng `--dart-define=API_BASE_URL=...` cho
/// staging/prod hoặc thiết bị thật trỏ vào máy dev qua LAN IP.
library;

class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api/v1',
  );

  static const Duration connectTimeout = Duration(seconds: 5);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
