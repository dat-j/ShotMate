/// `SubscriptionOffer` (spec-sprint-4 FR-S4-9) — gói tháng lấy từ
/// `Offerings.current.monthly` RevenueCat. KHÔNG hardcode giá: `priceString`
/// đến trực tiếp từ `StoreProduct` (Play Console product thật, khi có
/// account). Model đơn giản, không cần freezed (không có union/copyWith
/// phức tạp).
library;

class SubscriptionOffer {
  const SubscriptionOffer({
    required this.packageIdentifier,
    required this.title,
    required this.priceString,
  });

  /// Identifier của `Package` RevenueCat — truyền lại cho `purchasePackage`.
  final String packageIdentifier;

  /// Tiêu đề sản phẩm (từ store, ví dụ "ShotMate Premium (tháng)").
  final String title;

  /// Giá đã format kèm ký hiệu tiền tệ (ví dụ "49.000 ₫", "$4.99") — lấy từ
  /// `StoreProduct.priceString`, KHÔNG hardcode (spec: "giá từ Offerings...
  /// KHÔNG hardcode giá").
  final String priceString;
}
