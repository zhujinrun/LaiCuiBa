import 'package:flutter/material.dart';

/// Design tokens sampled from BieCuiLe 1.0.6 (Windows, light theme).
abstract final class LcbColors {
  static const page = Color(0xFFF5F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFF7B68EE);
  static const primaryDim = Color(0xFF9186C2);
  static const primaryContainer = Color(0xFFE7E5F0);
  static const onPrimaryContainer = Color(0xFF4B3FA8);
  static const text = Color(0xFF1C1C1E);
  static const textSecondary = Color(0xFF8A8A8F);
  static const textTertiary = Color(0xFFB0B0B6);
  static const divider = Color(0xFFE9E9EC);
  static const searchFill = Color(0xFFEFEFF2);
  static const scoreGreen = Color(0xFF00B51D);
  static const hover = Color(0xFFEDECF2);
}

abstract final class LcbMetrics {
  static const sidebarWidth = 232.0;
  static const topBarHeight = 56.0;
  static const pagePadding = 28.0;
  static const contentMaxWidth = 1600.0;
  static const cardRadius = 12.0;
  static const chipRadius = 6.0;
}

abstract final class LcbText {
  static const display = 'LcbSerif';
  static const body = 'Microsoft YaHei UI';
}

ThemeData buildBclTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: LcbColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: LcbColors.primary,
    onPrimary: Colors.white,
    primaryContainer: LcbColors.primaryContainer,
    onPrimaryContainer: LcbColors.onPrimaryContainer,
    surface: LcbColors.surface,
    onSurface: LcbColors.text,
    outlineVariant: LcbColors.divider,
  );

  TextStyle body(double size, FontWeight weight, Color color, {double? height, double? spacing}) =>
      TextStyle(
        fontFamily: LcbText.body,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LcbColors.surface,
    canvasColor: LcbColors.surface,
    dividerColor: LcbColors.divider,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: LcbColors.hover,
    fontFamily: LcbText.body,
    textTheme: TextTheme(
      displayLarge: body(40, FontWeight.w600, LcbColors.text, height: 1.15),
      displayMedium: body(34, FontWeight.w600, LcbColors.text, height: 1.15),
      displaySmall: body(28, FontWeight.w600, LcbColors.text, height: 1.2),
      titleLarge: body(18, FontWeight.w600, LcbColors.text, height: 1.3),
      titleMedium: body(15, FontWeight.w600, LcbColors.text, height: 1.3),
      titleSmall: body(13, FontWeight.w500, LcbColors.text, height: 1.3),
      bodyLarge: body(14, FontWeight.w400, LcbColors.text, height: 1.45),
      bodyMedium: body(13, FontWeight.w400, LcbColors.text, height: 1.45),
      bodySmall: body(12, FontWeight.w400, LcbColors.textSecondary, height: 1.4),
      labelLarge: body(13, FontWeight.w600, LcbColors.text),
      labelMedium: body(11.5, FontWeight.w500, LcbColors.textSecondary, spacing: 0.2),
      labelSmall: body(11, FontWeight.w500, LcbColors.textSecondary, spacing: 0.4),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.all(const Color(0x33000000)),
      crossAxisMargin: 2,
    ),
  );
}

/// Serif family used by the original for section and hero headlines.
TextStyle serifStyle(
  double size, {
  FontWeight weight = FontWeight.w600,
  Color color = LcbColors.text,
  double? height,
}) =>
    TextStyle(
      fontFamily: LcbText.display,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
