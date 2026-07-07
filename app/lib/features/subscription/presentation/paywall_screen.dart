/// `PaywallScreen` (spec-sprint-4 FR-S4-9) — hiển thị 1 gói tháng (giá từ
/// `Offerings.current.monthly`, KHÔNG hardcode), nút mua, loading/error
/// state. Sau khi mua thành công → pop về màn trước (Settings hoặc Score,
/// tuỳ điểm vào — CTA 402 hết credit + Settings, spec FR-S4-9).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/subscription_controller.dart';
import '../application/subscription_state.dart';
import '../domain/subscription_offer.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  @override
  void initState() {
    super.initState();
    // `paywall_shown` (spec FR-S4-9) — bắn ngay khi mở màn.
    unawaited(ref.read(analyticsServiceProvider).paywallShown());
    unawaited(ref.read(subscriptionProvider.notifier).loadOffer());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(subscriptionProvider);

    ref.listen<SubscriptionState>(subscriptionProvider, (previous, next) {
      if (next is SubscriptionPurchased && context.mounted) {
        Navigator.of(context).pop();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Nâng cấp Premium')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: switch (state) {
          SubscriptionIdle() || SubscriptionLoadingOffer() =>
            const Center(child: CircularProgressIndicator()),
          SubscriptionOfferReady(:final offer) => _OfferCard(offer: offer),
          SubscriptionPurchasing(:final offer) => _OfferCard(
              offer: offer,
              purchasing: true,
            ),
          SubscriptionPurchased() => const Center(
              child: Text('Nâng cấp thành công!'),
            ),
          SubscriptionFailed(:final reason) => _ErrorState(reason: reason),
        },
      ),
    );
  }
}

class _OfferCard extends ConsumerWidget {
  const _OfferCard({required this.offer, this.purchasing = false});

  final SubscriptionOffer offer;
  final bool purchasing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          offer.title,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          offer.priceString,
          style: Theme.of(context).textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: purchasing
              ? null
              : () => ref.read(subscriptionProvider.notifier).purchase(offer),
          child: purchasing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Mua ngay'),
        ),
      ],
    );
  }
}

class _ErrorState extends ConsumerWidget {
  const _ErrorState({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(reason, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => ref.read(subscriptionProvider.notifier).loadOffer(),
          icon: const Icon(Icons.refresh),
          label: const Text('Thử lại'),
        ),
      ],
    );
  }
}
