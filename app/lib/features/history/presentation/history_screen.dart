import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../history/data/app_database.dart';
import '../../history/data/photos_repository.dart';
import '../../score/data/scores_repository.dart';

/// State cho history list — trang hiện có, còn trang tiếp theo hay không,
/// loading indicator khi đang fetch (spec FR-S1-6: "phân trang 30/lần").
class HistoryState {
  const HistoryState({
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
  });

  final List<PhotoWithScore> items;
  final int page;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;

  HistoryState copyWith({
    List<PhotoWithScore>? items,
    int? page,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
  }) {
    return HistoryState(
      items: items ?? this.items,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Notifier phân trang cho history list — gọi
/// `ScoresRepository.getPageWithLatestScore(page)` tăng dần, append kết quả
/// (spec FR-S1-6). `hasMore` = false khi trang cuối trả về < 30 item (page
/// size, xem `historyPageSize`).
class HistoryNotifier extends StateNotifier<HistoryState> {
  HistoryNotifier(this._repository) : super(const HistoryState()) {
    _loadFirstPage();
  }

  final ScoresRepository _repository;

  Future<void> _loadFirstPage() async {
    state = state.copyWith(isLoading: true);
    final items = await _repository.getPageWithLatestScore(0);
    state = HistoryState(
      items: items,
      page: 0,
      hasMore: items.length >= historyPageSize,
      isLoading: false,
    );
  }

  /// Load trang kế tiếp và append — no-op nếu đang tải hoặc đã hết trang.
  Future<void> loadNextPage() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    final nextPage = state.page + 1;
    final items = await _repository.getPageWithLatestScore(nextPage);
    state = state.copyWith(
      items: [...state.items, ...items],
      page: nextPage,
      hasMore: items.length >= historyPageSize,
      isLoadingMore: false,
    );
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, HistoryState>((ref) {
  return HistoryNotifier(ref.watch(scoresRepositoryProvider));
});

/// History list (spec FR-S1-6) — thumbnail + 4 score + thời gian, mới nhất
/// trước, phân trang 30/lần từ Drift. Infinite scroll: load trang tiếp theo
/// khi user cuộn gần cuối danh sách.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    // Còn cách đáy < 200px → prefetch trang tiếp theo (infinite scroll).
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(historyProvider.notifier).loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử')),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(HistoryState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty) {
      return const Center(child: Text('Chưa có ảnh nào'));
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _HistoryTile(item: state.items[index]);
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final PhotoWithScore item;

  @override
  Widget build(BuildContext context) {
    final photo = item.photo;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        onTap: () => context.push('/score/${photo.id}'),
        contentPadding: const EdgeInsets.all(AppSpacing.sm),
        leading: _Thumbnail(filePath: photo.filePath),
        title: item.score == null
            ? const Text('Chưa có điểm')
            : _ScoreBadges(score: item.score!),
        subtitle: Text(_formatTakenAt(photo.takenAt)),
      ),
    );
  }

  static String _formatTakenAt(int takenAtEpochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(takenAtEpochMs);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$hh:$mm $dd/$mo';
  }
}

/// Thumbnail từ file local — placeholder icon nếu file thiếu/hỏng, vì đây
/// là list nhiều item và 1 file lỗi không được phép crash cả danh sách.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.xs),
        child: file.existsSync()
            ? Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const _ThumbnailPlaceholder(),
              )
            : const _ThumbnailPlaceholder(),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.cameraPlaceholder,
      child: const Icon(Icons.image_not_supported_outlined,
          color: Colors.white38),
    );
  }
}

/// Hiển thị 4 chiều score (Composition/Lighting/Focus/Background) dạng
/// badge nhỏ — Sprint 1 backbone, chưa polish visual (spec FR-S1-6).
class _ScoreBadges extends StatelessWidget {
  const _ScoreBadges({required this.score});

  final Score score;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        _ScoreBadge(label: 'C', value: score.composition),
        _ScoreBadge(label: 'L', value: score.lighting),
        _ScoreBadge(label: 'F', value: score.focus),
        _ScoreBadge(label: 'B', value: score.background),
      ],
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.xs),
      ),
      child: Text('$label $value', style: const TextStyle(fontSize: 12)),
    );
  }
}
