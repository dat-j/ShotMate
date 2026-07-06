/// `meProvider` (spec-sprint-3 "State Management") — `GET /me`: user +
/// subscription + credits cho UI (Account section, nút Review AI). Cache
/// in-memory per-session (FutureProvider mặc định), invalidate sau
/// review/purchase bằng `ref.invalidate(meProvider)`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/auth_user.dart';

class MeSubscription {
  const MeSubscription({required this.plan, this.expiresAt});

  factory MeSubscription.fromJson(Map<String, Object?> json) {
    final expiresAtRaw = json['expiresAt'] as String?;
    return MeSubscription(
      plan: json['plan']! as String,
      expiresAt: expiresAtRaw == null ? null : DateTime.parse(expiresAtRaw),
    );
  }

  final String plan; // 'free' | 'premium'
  final DateTime? expiresAt;
}

class MeCredits {
  const MeCredits({
    required this.usedToday,
    required this.quota,
    required this.remainingToday,
  });

  factory MeCredits.fromJson(Map<String, Object?> json) {
    return MeCredits(
      usedToday: json['usedToday']! as int,
      quota: json['quota']! as int,
      remainingToday: json['remainingToday']! as int,
    );
  }

  final int usedToday;
  final int quota; // -1 = unlimited (premium)
  final int remainingToday;

  bool get isUnlimited => quota == -1;
}

class MeResult {
  const MeResult({
    required this.user,
    required this.subscription,
    required this.credits,
  });

  factory MeResult.fromJson(Map<String, Object?> json) {
    return MeResult(
      user: AuthUser.fromJson(json['user']! as Map<String, Object?>),
      subscription:
          MeSubscription.fromJson(json['subscription']! as Map<String, Object?>),
      credits: MeCredits.fromJson(json['credits']! as Map<String, Object?>),
    );
  }

  final AuthUser user;
  final MeSubscription subscription;
  final MeCredits credits;
}

final meProvider = FutureProvider<MeResult>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get<Map<String, Object?>>('/me');
  return MeResult.fromJson(response.data!);
});
