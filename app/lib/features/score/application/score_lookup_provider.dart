/// Data loading cho Score Screen (spec-sprint-1 FR-S1-5) — photoId → photo +
/// score mới nhất (null nếu hết quota, EC-5).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../history/data/app_database.dart';
import '../../history/data/photos_repository.dart';
import '../data/scores_repository.dart';

/// Kết quả lookup cho Score Screen — photo null nghĩa là id không tồn tại
/// (vd deep link hỏng); score null nghĩa là ảnh chưa được chấm (EC-5).
class ScoreLookupResult {
  const ScoreLookupResult({required this.photo, required this.score});

  final Photo? photo;
  final Score? score;
}

final scoreLookupProvider =
    FutureProvider.family<ScoreLookupResult, String>((ref, photoId) async {
  final photosRepo = ref.watch(photosRepositoryProvider);
  final scoresRepo = ref.watch(scoresRepositoryProvider);

  final photo = await photosRepo.getById(photoId);
  if (photo == null) {
    return const ScoreLookupResult(photo: null, score: null);
  }
  final score = await scoresRepo.getLatestForPhoto(photoId);
  return ScoreLookupResult(photo: photo, score: score);
});
