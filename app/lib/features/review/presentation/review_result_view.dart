/// UI cloud review (spec-sprint-3 FR-S3-3): nút "Review AI ✨" (kèm credit
/// còn lại) + kết quả (explanation + suggestions + provider) hiển thị dưới
/// score offline trên Score Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/application/me_provider.dart';
import '../application/review_controller.dart';
import '../application/review_state.dart';

const _providerLabels = {
  'claude': 'Claude',
  'gemini': 'Gemini',
};

/// Message chính xác từ `review_controller.dart._messageFor` khi 402
/// `CREDITS_EXHAUSTED` — dùng để quyết định hiển thị CTA "Nâng cấp Premium"
/// thay vì "Thử lại" (spec-sprint-4 FR-S4-9: điểm vào paywall từ CTA 402).
const _creditsExhaustedMessage = 'Hết lượt review — nâng cấp';

/// Nút kích hoạt review — vô hiệu hoá + gợi ý đăng nhập khi anonymous
/// (Rule 1: review là tính năng cộng thêm, không chặn app).
class ReviewAiButton extends ConsumerWidget {
  const ReviewAiButton({
    super.key,
    required this.photoId,
    required this.isAuthenticated,
    required this.onLoginPrompt,
  });

  final String photoId;
  final bool isAuthenticated;
  final VoidCallback onLoginPrompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isAuthenticated) {
      return OutlinedButton.icon(
        onPressed: onLoginPrompt,
        icon: const Icon(Icons.auto_awesome_outlined),
        label: const Text('Đăng nhập để Review AI ✨'),
      );
    }

    final reviewState = ref.watch(reviewControllerProvider(photoId));
    final me = ref.watch(meProvider);

    return reviewState.when(
      data: (value) => switch (value) {
        ReviewIdle() => _IdleButton(photoId: photoId, me: me),
        ReviewUploading() => const _BusyButton(label: 'Đang tải ảnh lên...'),
        ReviewQueued() => const _BusyButton(label: 'Đã gửi, đang chờ xử lý...'),
        ReviewPolling() => const _BusyButton(label: 'Đang phân tích...'),
        ReviewDone() => const SizedBox.shrink(),
        ReviewFailed(:final reason) => _RetryButton(photoId: photoId, reason: reason),
        ReviewStillProcessing() => const _StillProcessingNotice(),
      },
      loading: () => const _BusyButton(label: 'Đang xử lý...'),
      error: (error, stack) => _RetryButton(photoId: photoId, reason: '$error'),
    );
  }
}

class _IdleButton extends ConsumerWidget {
  const _IdleButton({required this.photoId, required this.me});

  final String photoId;
  final AsyncValue<MeResult> me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = me.valueOrNull?.credits;
    final label = credits == null
        ? 'Review AI ✨'
        : credits.isUnlimited
            ? 'Review AI ✨ (không giới hạn)'
            : 'Review AI ✨ (còn ${credits.remainingToday})';
    final disabled = credits != null && !credits.isUnlimited && credits.remainingToday <= 0;

    return FilledButton.icon(
      onPressed: disabled
          ? null
          : () => ref.read(reviewControllerProvider(photoId).notifier).startReview(),
      icon: const Icon(Icons.auto_awesome),
      label: Text(disabled ? 'Hết lượt review hôm nay' : label),
    );
  }
}

class _BusyButton extends StatelessWidget {
  const _BusyButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: null,
      icon: const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      label: Text(label),
    );
  }
}

class _RetryButton extends ConsumerWidget {
  const _RetryButton({required this.photoId, required this.reason});

  final String photoId;
  final String reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCreditsExhausted = reason == _creditsExhaustedMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(reason, style: const TextStyle(color: Colors.redAccent)),
        const SizedBox(height: AppSpacing.sm),
        if (isCreditsExhausted)
          FilledButton.icon(
            onPressed: () => context.push('/paywall'),
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('Nâng cấp Premium'),
          )
        else
          OutlinedButton.icon(
            onPressed: () => ref
                .read(reviewControllerProvider(photoId).notifier)
                .startReview(),
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
      ],
    );
  }
}

class _StillProcessingNotice extends StatelessWidget {
  const _StillProcessingNotice();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Đang xử lý — kết quả sẽ có trong Lịch sử, quay lại sau nhé.',
      textAlign: TextAlign.center,
    );
  }
}

/// Hiển thị kết quả done: explanation + suggestions + provider label.
class ReviewResultView extends StatelessWidget {
  const ReviewResultView({super.key, required this.result});

  final ReviewDone result;

  @override
  Widget build(BuildContext context) {
    final review = result.result;
    final providerLabel = _providerLabels[review.provider] ?? review.provider ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Review AI', style: Theme.of(context).textTheme.titleMedium),
              if (providerLabel.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Chip(label: Text(providerLabel)),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (review.explanation != null && review.explanation!.isNotEmpty)
            Text(review.explanation!),
          if (review.suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final suggestion in review.suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.chevron_right, size: 20),
                    Expanded(child: Text(suggestion)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
