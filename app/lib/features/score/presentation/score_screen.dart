import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/auth_controller.dart';
import '../../history/data/app_database.dart';
import '../../review/application/review_controller.dart';
import '../../review/application/review_state.dart';
import '../../review/presentation/review_result_view.dart';
import '../application/score_lookup_provider.dart';

/// Score 4 chiều sau chụp (spec FR-S1-5).
///
/// Nếu score null (hết quota — EC-5) hiển thị message + CTA placeholder
/// thay vì các thanh điểm (spec Business Rule 4: "vẫn chụp được ảnh, không
/// hiển thị score").
class ScoreScreen extends ConsumerWidget {
  const ScoreScreen({super.key, required this.photoId});

  final String photoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookup = ref.watch(scoreLookupProvider(photoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Điểm ảnh')),
      body: lookup.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Không tải được điểm ảnh: $error'),
        ),
        data: (result) {
          final photo = result.photo;
          if (photo == null) {
            return const Center(child: Text('Không tìm thấy ảnh'));
          }
          return _ScoreScreenBody(photo: photo, score: result.score);
        },
      ),
    );
  }
}

class _ScoreScreenBody extends ConsumerWidget {
  const _ScoreScreenBody({required this.photo, required this.score});

  final Photo photo;
  final Score? score;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.md),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: _PhotoThumbnail(filePath: photo.filePath),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (score == null) const _QuotaExhaustedNotice() else _ScoreBreakdown(score: score!),
          if (score != null) _WhySection(captureMeta: photo.captureMeta),
          if (score != null) _ReviewAiSection(photoId: photo.id),
        ],
      ),
    );
  }
}

/// Nút "Review AI ✨" + kết quả cloud (spec-sprint-3 FR-S3-3) — chỉ hiển thị
/// khi đã có score offline (giữ nguyên offline score + "Vì sao" — spec
/// "Keep existing offline score intact").
class _ReviewAiSection extends ConsumerWidget {
  const _ReviewAiSection({required this.photoId});

  final String photoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final isAuthenticated = authState is AuthAuthenticated;
    final reviewState = ref.watch(reviewControllerProvider(photoId));

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReviewAiButton(
            photoId: photoId,
            isAuthenticated: isAuthenticated,
            onLoginPrompt: () => context.push('/login'),
          ),
          reviewState.when(
            data: (value) => value is ReviewDone
                ? ReviewResultView(result: value)
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (error, stack) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// "Vì sao" (spec-sprint-2 FR-S2-7): các hint app đã hiển thị tại thời điểm
/// chụp — đọc từ `captureMeta.hintsShown` (đã lưu từ Sprint 1). Không tính
/// lại, chỉ trình bày. Ẩn nếu không có hint (ảnh đã tốt).
class _WhySection extends StatelessWidget {
  const _WhySection({required this.captureMeta});

  final String captureMeta;

  static const _labels = {
    'horizon_tilt': 'Đường chân trời bị nghiêng',
    'thirds_offset': 'Chủ thể lệch điểm mạnh (rule-of-thirds)',
    'subject_too_small': 'Chủ thể hơi nhỏ trong khung',
    'subject_cut': 'Chủ thể bị cắt ở mép khung',
    'raise_chin': 'Nên nâng cằm người được chụp',
    'smile': 'Người được chụp chưa cười',
    'too_close': 'Máy hơi gần chủ thể',
    'too_far': 'Máy hơi xa chủ thể',
    'tilt_angle': 'Góc máy chưa hợp với cảnh',
  };

  List<String> _hintsShown() {
    try {
      final meta = jsonDecode(captureMeta) as Map<String, Object?>;
      final ids = (meta['hintsShown'] as List<Object?>?) ?? const [];
      return ids.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final hints = _hintsShown();
    if (hints.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Có thể cải thiện',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final id in hints)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.chevron_right, size: 20),
                  Expanded(child: Text(_labels[id] ?? id)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    return ColoredBox(
      color: AppColors.cameraPlaceholder,
      child: file.existsSync()
          ? Image.file(file, fit: BoxFit.cover)
          : const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white38),
            ),
    );
  }
}

class _ScoreBreakdown extends StatelessWidget {
  const _ScoreBreakdown({required this.score});

  final Score score;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScoreDimensionTile(label: 'Composition', value: score.composition),
        const SizedBox(height: AppSpacing.md),
        _ScoreDimensionTile(label: 'Lighting', value: score.lighting),
        const SizedBox(height: AppSpacing.md),
        _ScoreDimensionTile(label: 'Focus', value: score.focus),
        const SizedBox(height: AppSpacing.md),
        _ScoreDimensionTile(label: 'Background', value: score.background),
      ],
    );
  }
}

class _ScoreDimensionTile extends StatelessWidget {
  const _ScoreDimensionTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            Text('$value/100', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.xs),
          child: LinearProgressIndicator(
            value: value.clamp(0, 100) / 100,
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

class _QuotaExhaustedNotice extends StatelessWidget {
  const _QuotaExhaustedNotice();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Hết lượt chấm điểm hôm nay',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Ảnh của bạn đã được lưu. Quay lại vào ngày mai để chấm điểm '
          'tiếp, hoặc nâng cấp để có thêm lượt.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          // TODO(sprint-2+): paywall thật — Sprint 1 chỉ là CTA placeholder
          // (spec Business Rule 4: "Sprint 1 chưa có paywall").
          onPressed: null,
          child: const Text('Nâng cấp (sắp ra mắt)'),
        ),
      ],
    );
  }
}
