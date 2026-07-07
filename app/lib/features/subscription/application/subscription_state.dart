/// State machine cho `subscriptionProvider` (spec-sprint-4 FR-S4-9):
/// idle → loadingOffer → offerReady(offer) → purchasing → purchased/failed.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../domain/subscription_offer.dart';

part 'subscription_state.freezed.dart';

@freezed
sealed class SubscriptionState with _$SubscriptionState {
  const factory SubscriptionState.idle() = SubscriptionIdle;
  const factory SubscriptionState.loadingOffer() = SubscriptionLoadingOffer;
  const factory SubscriptionState.offerReady(SubscriptionOffer offer) =
      SubscriptionOfferReady;
  const factory SubscriptionState.purchasing(SubscriptionOffer offer) =
      SubscriptionPurchasing;
  const factory SubscriptionState.purchased() = SubscriptionPurchased;
  const factory SubscriptionState.failed(String reason) = SubscriptionFailed;
}
