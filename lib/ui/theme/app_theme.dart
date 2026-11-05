import 'package:flutter/material.dart';

/// Space Cadets palette and dark theme.
///
/// Font: 'Baloo 2' is declared by family name only. No network font loader is
/// used (privacy rule); the font file can be bundled later under
/// `flutter: fonts:` in pubspec.yaml. Until then the system fallbacks apply.
class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF14123A);
  static const Color surface = Color(0xFF2A2770);
  static const Color accent = Color(0xFF4DE1FF);
  static const Color yellow = Color(0xFFFFD84D);
  static const Color green = Color(0xFF5CF2A0);
  static const Color pink = Color(0xFFFF5CAA);
  static const Color orange = Color(0xFFFF8A5B);
  static const Color purple = Color(0xFF7B61FF);
  static const Color text = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFFC9C6F5);

  /// Scrims drawn over the playing area (background colour, translucent).
  static const Color pauseScrim = Color(0xCC14123A);
  static const Color breakScrim = Color(0xEE14123A);

  static const String fontFamily = 'Baloo 2';
  static const List<String> fontFallback = ['Roboto', 'sans-serif'];

  /// Minimum touch target (dp).
  static const double minTarget = 56;

  static TextStyle _s(double size, {FontWeight? w, Color color = text}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
        fontSize: size,
        fontWeight: w,
        color: color,
      );

  static ThemeData dark() {
    final textTheme = TextTheme(
      displayMedium: _s(56, w: FontWeight.w700),
      headlineMedium: _s(40, w: FontWeight.w700),
      titleLarge: _s(32, w: FontWeight.w700),
      titleMedium: _s(24, w: FontWeight.w600),
      // Instruction text: readable from 2-3 m.
      bodyLarge: _s(28, w: FontWeight.w600),
      bodyMedium: _s(22, color: muted),
      labelLarge: _s(28, w: FontWeight.w700, color: background),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: background,
        secondary: yellow,
        onSecondary: background,
        surface: surface,
        onSurface: text,
        error: pink,
      ),
      textTheme: textTheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          minimumSize: const Size(minTarget * 2, minTarget),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          textStyle: textTheme.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      // The secondary choice on the camera-problem screen is an
      // OutlinedButton: it must be as big and as readable as every other
      // button a child has to hit from an arm's length.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(minTarget * 2, minTarget),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          textStyle: textTheme.labelLarge!.copyWith(color: text),
          side: const BorderSide(color: accent, width: 3),
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minTarget, minTarget),
          foregroundColor: text,
        ),
      ),
    );
  }
}
