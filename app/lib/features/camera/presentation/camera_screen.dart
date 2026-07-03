import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/platform/frame_analysis_channel.dart';
import '../../../core/theme/app_spacing.dart';
import '../../coach/application/coach_state_provider.dart';
import '../../coach/domain/coach_hint.dart';
import '../../coach/presentation/perf_hud.dart';
import '../../settings/application/settings_providers.dart';
import '../application/camera_permission_state.dart';
import '../application/capture_orchestrator_provider.dart';
import '../domain/capture_debouncer.dart';
import 'coach_overlay.dart';

/// Màn hình chính — camera preview + coach overlay (spec FR-S1-1, FR-S1-4,
/// FR-S1-5).
///
/// Preview/capture dùng `camera` plugin; analysis chạy hoàn toàn ở native
/// side qua `frameAnalysisStreamProvider` (ADR-0001) — KHÔNG dùng
/// `startImageStream` ở đây.
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraPermissionStatus _permissionStatus = CameraPermissionStatus.unknown;
  final _captureDebouncer = CaptureDebouncer();
  bool _capturing = false;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissionAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _requestPermissionAndInit();
    }
  }

  Future<void> _requestPermissionAndInit() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      setState(() => _permissionStatus = CameraPermissionStatus.granted);
      await _initCamera();
      return;
    }
    setState(() {
      _permissionStatus = status.isPermanentlyDenied
          ? CameraPermissionStatus.permanentlyDenied
          : CameraPermissionStatus.denied;
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _initError = 'no_camera_available');
        return;
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initError = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  Future<void> _onShutterPressed() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!_captureDebouncer.tryStart()) return; // EC-7: debounce

    setState(() => _capturing = true);
    try {
      final xFile = await controller.takePicture();
      final savedPath = await _saveToAppPrivateStorage(xFile);

      final coachState = ref.read(coachStateProvider);
      final analysis = ref.read(frameAnalysisStreamProvider).valueOrNull;

      final orchestrator = ref.read(captureOrchestratorProvider);
      final result = await orchestrator.capture(
        filePath: savedPath,
        captureMeta: jsonEncode(_captureMeta(coachState)),
        compositionScore: coachState.compositionScore,
        analysis: analysis,
      );

      if (!mounted) return;
      context.go('/score/${result.photoId}');
    } finally {
      _captureDebouncer.finish();
      if (mounted) setState(() => _capturing = false);
    }
  }

  Map<String, Object?> _captureMeta(CoachState state) {
    return {
      'compositionScore': state.compositionScore,
      'hintsShown': state.hints.map((h) => h.id).toList(),
    };
  }

  Future<String> _saveToAppPrivateStorage(XFile xFile) async {
    // App-private picture directory (spec-sprint-1: "gallery app-private") —
    // KHÔNG lưu vào OS Photos/gallery công khai.
    final dir = await getApplicationDocumentsDirectory();
    final picturesDir = Directory(p.join(dir.path, 'photos'));
    if (!picturesDir.existsSync()) {
      picturesDir.createSync(recursive: true);
    }
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destPath = p.join(picturesDir.path, fileName);
    await File(xFile.path).copy(destPath);
    return destPath;
  }

  @override
  Widget build(BuildContext context) {
    switch (_permissionStatus) {
      case CameraPermissionStatus.unknown:
        return const _LoadingScreen();
      case CameraPermissionStatus.denied:
      case CameraPermissionStatus.permanentlyDenied:
        return _PermissionDeniedScreen(
          permanentlyDenied:
              _permissionStatus == CameraPermissionStatus.permanentlyDenied,
          onRetry: _requestPermissionAndInit,
        );
      case CameraPermissionStatus.granted:
        break;
    }

    if (_initError != null) {
      return _CameraErrorScreen(error: _initError!, onRetry: _initCamera);
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const _LoadingScreen();
    }

    final coachState = ref.watch(coachStateProvider);
    final analysis = ref.watch(frameAnalysisStreamProvider).valueOrNull;
    final showGrid = ref.watch(showGridProvider);
    final showSkeleton = ref.watch(showSkeletonProvider);
    final showPerfHud = ref.watch(showPerfHudProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller),
          CoachOverlay(
            state: coachState,
            showGrid: showGrid,
            showSkeleton: showSkeleton,
            poseLandmarks: analysis?.poseLandmarks,
          ),
          if (kDebugMode && showPerfHud) const PerfHud(),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: () => context.go('/history'),
                      icon: const Icon(Icons.photo_library_outlined,
                          color: Colors.white, size: 32),
                    ),
                    _ShutterButton(
                      enabled: !_capturing,
                      onPressed: _onShutterPressed,
                    ),
                    IconButton(
                      onPressed: () => context.go('/settings'),
                      icon: const Icon(Icons.settings_outlined,
                          color: Colors.white, size: 32),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// EC-3: quyền camera bị từ chối → màn giải thích + nút mở Settings, không
/// crash, không tự động loop xin quyền lại.
class _PermissionDeniedScreen extends StatelessWidget {
  const _PermissionDeniedScreen({
    required this.permanentlyDenied,
    required this.onRetry,
  });

  final bool permanentlyDenied;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 56),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'ShotMate cần quyền Camera để hướng dẫn bạn chụp ảnh đẹp '
                'trước khi bấm nút.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (permanentlyDenied)
                FilledButton(
                  onPressed: openAppSettings,
                  child: const Text('Mở Settings'),
                )
              else
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Cấp quyền Camera'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraErrorScreen extends StatelessWidget {
  const _CameraErrorScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 56),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Không mở được camera: $error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: DecoratedBox(
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
