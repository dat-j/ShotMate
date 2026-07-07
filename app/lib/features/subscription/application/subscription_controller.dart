/// `subscriptionProvider` (spec-sprint-3 "Frontend Changes" đặt tên trước,
/// spec-sprint-4 FR-S4-9 implement thật) — wrap RevenueCat SDK:
/// `Purchases.configure`, `Purchases.getOfferings()`, `Purchases.purchase()`
/// (API hiện hành thay `purchasePackage` đã deprecated trong SDK 10.x — cùng
/// hành vi mua 1 `Package`, tránh lint `deprecated_member_use`). Sau khi mua
/// thành công, invalidate `meProvider` để app refresh credit/plan từ backend
/// (webhook RevenueCat đã ghi Subscription — FR-S3-5).
///
/// **RevenueCat public SDK key** đọc từ compile-time flag
/// `REVENUECAT_PUBLIC_KEY` (`--dart-define=REVENUECAT_PUBLIC_KEY=...`). Môi
/// trường này CHƯA có RevenueCat account/Play Console product thật —
/// key rỗng là bình thường. Quan trọng: KHÔNG được throw khi thiếu key lúc
/// khởi động app — chỉ throw khi user thực sự bấm mua (loadOffer/purchase),
/// với message rõ ràng để dev biết cần cấu hình gì.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../auth/application/me_provider.dart';
import '../domain/subscription_offer.dart';
import 'subscription_state.dart';

/// Đọc từ `--dart-define=REVENUECAT_PUBLIC_KEY=...` khi build (Fastlane lane
/// `beta` sẽ truyền key thật — FR-S4-9). Rỗng ở dev/test bình thường.
const _revenueCatPublicKey =
    String.fromEnvironment('REVENUECAT_PUBLIC_KEY', defaultValue: '');

class SubscriptionController extends Notifier<SubscriptionState> {
  bool _configured = false;

  @override
  SubscriptionState build() => const SubscriptionState.idle();

  /// Configure RevenueCat SDK đúng 1 lần (idempotent) — lazy, chỉ chạy khi
  /// thật sự cần offerings/purchase (không ở app startup) để không làm chậm
  /// cold start và không crash nếu thiếu key.
  Future<void> _ensureConfigured() async {
    if (_configured) return;
    if (_revenueCatPublicKey.isEmpty) {
      throw StateError(
        'REVENUECAT_PUBLIC_KEY chưa được cấu hình — build với '
        '--dart-define=REVENUECAT_PUBLIC_KEY=<public_sdk_key> (cần '
        'RevenueCat account + Play Console product thật, xem spec-sprint-4 '
        'FR-S4-9).',
      );
    }
    await Purchases.configure(
      PurchasesConfiguration(_revenueCatPublicKey),
    );
    _configured = true;
  }

  /// Lấy gói tháng hiện có (`Offerings.current.monthly`) — không hardcode
  /// giá, `priceString` đến từ store.
  Future<void> loadOffer() async {
    state = const SubscriptionState.loadingOffer();
    try {
      await _ensureConfigured();
      final offerings = await Purchases.getOfferings();
      final monthly = offerings.current?.monthly;
      if (monthly == null) {
        state = const SubscriptionState.failed(
          'Chưa có gói Premium khả dụng — thử lại sau',
        );
        return;
      }
      final offer = SubscriptionOffer(
        packageIdentifier: monthly.identifier,
        title: monthly.storeProduct.title,
        priceString: monthly.storeProduct.priceString,
      );
      state = SubscriptionState.offerReady(offer);
    } catch (e) {
      state = SubscriptionState.failed(_messageFor(e));
    }
  }

  /// Mua gói đang hiển thị — sau khi thành công, invalidate `meProvider` để
  /// refresh credit/plan (webhook RC backend cập nhật DB, `/me` phản ánh
  /// plan mới — có thể có độ trễ nhỏ do webhook, EC-S4-5 fallback
  /// `POST /subscriptions/verify` đã có ở Sprint 3).
  Future<void> purchase(SubscriptionOffer offer) async {
    state = SubscriptionState.purchasing(offer);
    try {
      await _ensureConfigured();
      final offerings = await Purchases.getOfferings();
      final availablePackages = offerings.current?.availablePackages ?? const [];
      Package? package;
      for (final candidate in availablePackages) {
        if (candidate.identifier == offer.packageIdentifier) {
          package = candidate;
          break;
        }
      }
      if (package == null) {
        state = const SubscriptionState.failed('Không tìm thấy gói — thử lại');
        return;
      }
      await Purchases.purchase(PurchaseParams.package(package));
      ref.invalidate(meProvider);
      await ref.read(analyticsServiceProvider).purchaseCompleted();
      state = const SubscriptionState.purchased();
    } catch (e) {
      if (_isUserCancelled(e)) {
        state = SubscriptionState.offerReady(offer);
        return;
      }
      state = SubscriptionState.failed(_messageFor(e));
    }
  }

  bool _isUserCancelled(Object e) {
    if (e is PlatformException) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      return code == PurchasesErrorCode.purchaseCancelledError;
    }
    return false;
  }

  String _messageFor(Object e) {
    if (e is StateError) return e.message;
    if (kDebugMode) {
      debugPrint('SubscriptionController error: $e');
    }
    return 'Mua gói thất bại — thử lại sau';
  }
}

final subscriptionProvider =
    NotifierProvider<SubscriptionController, SubscriptionState>(
  SubscriptionController.new,
);
