/// `AnalyticsService` (spec-sprint-4 FR-S4-9) — bọc quanh `FirebaseAnalytics`
/// cho toàn bộ event đã liệt kê spec 1–3: `login_completed`,
/// `review_requested`, `review_completed{provider, latencyMs}`,
/// `review_failed`, `paywall_shown`, `purchase_completed`,
/// `sync_completed{count}`.
///
/// **Graceful khi chưa có Firebase project thật**: `main.dart` bọc
/// `Firebase.initializeApp()` trong try/catch vì `google-services.json`/
/// `firebase_options.dart` chưa tồn tại trong môi trường này. Service này
/// PHẢI no-op an toàn (không throw) nếu Firebase chưa init — kiểm tra
/// `Firebase.apps.isNotEmpty` trước khi chạm `FirebaseAnalytics.instance`.
///
/// Sprint 4 chỉ gọi thật 2 event mới code trong sprint này: `paywallShown()`
/// (paywall_screen.dart khi mở màn) và `purchaseCompleted()` (sau khi mua
/// RevenueCat thành công). Các event còn lại (login/review/sync) để code
/// hiện có gọi sau — method đã sẵn sàng dùng.
library;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnalyticsService {
  AnalyticsService();

  /// `true` nếu `Firebase.initializeApp()` đã thành công (ít nhất 1 app) —
  /// tránh chạm `FirebaseAnalytics.instance` khi chưa init (sẽ throw).
  bool get _isAvailable => Firebase.apps.isNotEmpty;

  Future<void> _logEvent(String name, [Map<String, Object>? parameters]) async {
    if (!_isAvailable) return;
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (e) {
      // Không bao giờ để lỗi analytics làm crash flow nghiệp vụ.
      debugPrint('AnalyticsService.logEvent($name) failed: $e');
    }
  }

  Future<void> loginCompleted() => _logEvent('login_completed');

  Future<void> reviewRequested() => _logEvent('review_requested');

  Future<void> reviewCompleted({
    required String provider,
    required int latencyMs,
  }) =>
      _logEvent('review_completed', {
        'provider': provider,
        'latencyMs': latencyMs,
      });

  Future<void> reviewFailed() => _logEvent('review_failed');

  Future<void> paywallShown() => _logEvent('paywall_shown');

  Future<void> purchaseCompleted() => _logEvent('purchase_completed');

  Future<void> syncCompleted({required int count}) =>
      _logEvent('sync_completed', {'count': count});
}

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});
