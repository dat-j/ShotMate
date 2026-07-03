/// DI cho [CaptureOrchestrator] — phụ thuộc 4 repository qua provider, đúng
/// convention DI của codebase (xem photos_repository.dart).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../history/data/analyses_repository.dart';
import '../../history/data/credit_repository.dart';
import '../../history/data/photos_repository.dart';
import '../../score/data/scores_repository.dart';
import '../domain/capture_orchestrator.dart';

final captureOrchestratorProvider = Provider<CaptureOrchestrator>((ref) {
  return CaptureOrchestrator(
    photosRepository: ref.watch(photosRepositoryProvider),
    analysesRepository: ref.watch(analysesRepositoryProvider),
    scoresRepository: ref.watch(scoresRepositoryProvider),
    creditRepository: ref.watch(creditRepositoryProvider),
  );
});
