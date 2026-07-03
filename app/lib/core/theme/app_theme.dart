/// ThemeData tập trung — trước đây khai báo inline trong main.dart.
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get dark => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );
}
