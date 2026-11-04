import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF05060D);
  static const backgroundAlt = Color(0xFF0C0918);
  static const ink = Color(0xFF07070C);
  static const pink = Color(0xFFFF2D6F);
  static const rose = Color(0xFFFF6B9A);
  static const violet = Color(0xFF6D5DFC);
  static const cyan = Color(0xFF22D3EE);
  static const amber = Color(0xFFFFB020);
  static const textPrimary = Color(0xF2FFFFFF);
  static const textSecondary = Color(0xB3FFFFFF);
  static const textTertiary = Color(0x80FFFFFF);
  static const textFaint = Color(0x4DFFFFFF);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.pink,
    onPrimary: Colors.white,
    secondary: AppColors.cyan,
    onSecondary: Colors.black,
    surface: Color(0xFF0B0A14),
    onSurface: Colors.white,
    error: Color(0xFFFF5C7A),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
      fontFamilyFallback: const [
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'PingFang SC',
        'Sans-Serif',
      ],
    ),
    iconTheme: const IconThemeData(color: Colors.white),
    dividerColor: Colors.white12,
  );
}
