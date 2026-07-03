/// Màu nền tảng ShotMate — seed color theo `main.dart` gốc (0xFF1B6EF3),
/// dark-first vì camera screen luôn nền tối (spec FR-S1-1, FR-S1-4).
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const seed = Color(0xFF1B6EF3);

  /// Nền camera preview khi chưa có frame (placeholder, xem camera_screen.dart).
  static const cameraPlaceholder = Color(0xFF101418);

  /// Overlay: grid rule-of-thirds (spec FR-S1-4).
  static const gridLine = Colors.white24;

  /// Hint chip — nền theo severity (spec Business Rule 1).
  static const hintCritical = Color(0xD9E53935); // red, alpha ~0.85
  static const hintDefault = Colors.black54;

  static const ratingStar = Colors.amber;
}
