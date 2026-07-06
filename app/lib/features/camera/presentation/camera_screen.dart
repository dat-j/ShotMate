import 'dart:async';
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
import '../../../core/platform/native_camera.dart';
import '../../../core/theme/app_spacing.dart';
import '../../coach/application/coach_state_provider.dart';
import '../../coach/application/countdown_provider.dart';
import '../../coach/domain/coach_hint.dart';
import '../../coach/domain/countdown_controller.dart';
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
  /// Android: camera do native module sở hữu (preview PlatformView + capture
  /// MethodChannel). iOS/khác: `camera` plugin (chưa có native module).
  final bool _useNative = NativeCamera.isSupported;
  final NativeCamera _nativeCamera = const NativeCamera();

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
    // Native path: vòng đời camera gắn với PlatformView (native lo start/stop).
    if (_useNative) return;
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
      if (!_useNative) await _initCamera();
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
    if (!_captureDebouncer.tryStart()) return; // EC-7: debounce

    // Chụp tay thắng countdown đang chạy (EC-S2-2).
    ref.read(countdownProvider.notifier).notifyManual();

    setState(() => _capturing = true);
    try {
      final savedPath = await _capturePhotoToDisk();
      if (savedPath == null) return; // native capture lỗi → không navigate

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
      // push (không go): giữ camera dưới stack để back từ Score quay về camera.
      unawaited(context.push('/score/${result.photoId}'));
    } finally {
      _captureDebouncer.finish();
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Chụp và lưu vào app-private storage; trả đường dẫn hoặc null nếu lỗi.
  Future<String?> _capturePhotoToDisk() async {
    if (_useNative) {
      final destPath = await _appPrivatePhotoPath();
      try {
        await _nativeCamera.capture(destPath);
        return destPath;
      } on CameraCaptureException catch (e) {
        if (mounted) setState(() => _initError = e.message);
        return null;
      }
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    final xFile = await controller.takePicture();
    return _saveToAppPrivateStorage(xFile);
  }

  Map<String, Object?> _captureMeta(CoachState state) {
    return {
      'compositionScore': state.compositionScore,
      'hintsShown': state.hints.map((h) => h.id).toList(),
    };
  }

  /// Đường dẫn đích mới trong app-private picture dir (spec-sprint-1:
  /// "gallery app-private" — KHÔNG lưu vào OS Photos/gallery công khai).
  Future<String> _appPrivatePhotoPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final picturesDir = Directory(p.join(dir.path, 'photos'));
    if (!picturesDir.existsSync()) {
      picturesDir.createSync(recursive: true);
    }
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    return p.join(picturesDir.path, fileName);
  }

  Future<String> _saveToAppPrivateStorage(XFile xFile) async {
    final destPath = await _appPrivatePhotoPath();
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

    // Path plugin (iOS): chờ controller sẵn sàng. Path native (Android): preview
    // là PlatformView, không cần CameraController.
    final controller = _controller;
    if (!_useNative && (controller == null || !controller.value.isInitialized)) {
      return const _LoadingScreen();
    }

    final coachState = ref.watch(coachStateProvider);
    final analysis = ref.watch(frameAnalysisStreamProvider).valueOrNull;
    final showGrid = ref.watch(showGridProvider);
    final showSkeleton = ref.watch(showSkeletonProvider);
    final showPerfHud = ref.watch(showPerfHudProvider);
    final countdown = ref.watch(countdownProvider);

    // Countdown hết đếm → tự chụp (FR-S2-6). Dùng post-frame để không capture
    // trong lúc build.
    if (countdown.phase == CountdownPhase.firing && !_capturing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(countdownProvider.notifier).reset();
        _onShutterPressed();
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_useNative)
            const NativeCameraPreview()
          else
            CameraPreview(controller!),
          CoachOverlay(
            state: coachState,
            showGrid: showGrid,
            showSkeleton: showSkeleton,
            poseLandmarks: analysis?.poseLandmarks,
            throttled: analysis?.throttled ?? false,
          ),
          if (coachState.suggestedZoom != null)
            _ZoomChip(
              zoom: coachState.suggestedZoom!,
              onTap: () => _nativeCamera.setZoom(coachState.suggestedZoom!),
            ),
          if (countdown.phase != CountdownPhase.idle &&
              countdown.phase != CountdownPhase.firing)
            _CountdownBanner(
              state: countdown,
              onStart: () => ref.read(countdownProvider.notifier).start(),
              onCancel: () => ref.read(countdownProvider.notifier).cancel(),
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
                      onPressed: () => context.push('/history'),
                      icon: const Icon(Icons.photo_library_outlined,
                          color: Colors.white, size: 32),
                    ),
                    _ShutterButton(
                      enabled: !_capturing,
                      onPressed: _onShutterPressed,
                    ),
                    IconButton(
                      onPressed: () => context.push('/settings'),
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

/// Chip gợi ý zoom (FR-S2-3) — tap để áp dụng. Nằm ngoài IgnorePointer của
/// overlay để nhận tap.
class _ZoomChip extends StatelessWidget {
  const _ZoomChip({required this.zoom, required this.onTap});

  final double zoom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white70),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.center_focus_strong,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text('Chuyển ${_fmt(zoom)}x',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(double z) =>
      z == z.roundToDouble() ? z.toStringAsFixed(0) : z.toStringAsFixed(1);
}

/// Banner smart countdown (FR-S2-6): đề xuất (tap bắt đầu), số đếm, hoặc lý do
/// huỷ. Không hiển thị khi idle/firing.
class _CountdownBanner extends StatelessWidget {
  const _CountdownBanner({
    required this.state,
    required this.onStart,
    required this.onCancel,
  });

  final CountdownState state;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: switch (state.phase) {
        CountdownPhase.proposed => GestureDetector(
            onTap: onStart,
            child: _banner(
              icon: Icons.timer_outlined,
              text: 'Ánh sáng đang đẹp — chạm để đếm ngược',
            ),
          ),
        CountdownPhase.counting => Text(
            '${state.secondsLeft}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 96,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(blurRadius: 12, color: Colors.black)],
            ),
          ),
        CountdownPhase.cancelled => _banner(
            icon: Icons.info_outline,
            text: state.cancelReason ?? 'Đã huỷ',
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _banner({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
        ],
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
