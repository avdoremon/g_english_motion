import 'package:flutter/material.dart';

/// Space Puppy palette, Fredoka type scale and dark theme.
///
/// Fredoka is bundled under `assets/fonts/` (SIL OFL); no network font loader
/// is used (privacy rule). If the asset fails to load the fallbacks apply.
class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF1B1F4B); // night
  static const Color ink = Color(0xFF0E1033);
  static const Color surface = Color(0xFF262B6B); // panel
  static const Color surfaceLight = Color(0xFF323896); // panel-light
  static const Color purple = Color(0xFF6C4DFF);
  static const Color accent = Color(0xFF35D0FF); // sky
  static const Color yellow = Color(0xFFFFD23F); // star
  static const Color coral = Color(0xFFFF6B6B);
  static const Color green = Color(0xFF3DDC97); // correct
  static const Color orange = Color(0xFFFFB84D);
  static const Color muted = Color(0xFFC9CCF5);
  static const Color text = Color(0xFFFFFFFF);

  /// Alias of [coral] kept so existing screens compile.
  static const Color pink = coral;

  /// Scrims drawn over the playing area (background colour, translucent).
  static const Color pauseScrim = Color(0xCC1B1F4B);
  static const Color breakScrim = Color(0xEE1B1F4B);

  /// Translucent overlays and fills (alpha baked in).
  static const Color shade40 = Color(0x40000000); // HUD pill
  static const Color shade38 = Color(0x38000000); // ring backing
  static const Color shade4d = Color(0x4D000000); // result panel
  static const Color shadow = Color(0x47000000); // sticker drop shadow
  static const Color trackWhite = Color(0x29FFFFFF); // empty star / ring track
  static const Color glassWhite = Color(0x24FFFFFF); // round icon button fill
  static const Color cardFill = Color(0xFFFFFFFF); // sticker card default
  static const Color selectedFill = Color(0xFF3A36A0); // chosen tile

  static const String fontFamily = 'Fredoka';
  static const List<String> fontFallback = ['Roboto', 'sans-serif'];

  /// Minimum touch target (dp).
  static const double minTarget = 56;

  /// The five-size type scale. Play text never goes below 28 sp.
  static const AppTextStyles textStyles = AppTextStyles._();

  static TextStyle _s(double size, {FontWeight? w, Color color = text}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
        fontSize: size,
        fontWeight: w,
        color: color,
      );

  static ThemeData dark() {
    const st = textStyles;
    final textTheme = TextTheme(
      displayLarge: st.display,
      headlineLarge: st.heading,
      // Instruction text: readable from 2-3 m.
      bodyLarge: st.play,
      labelLarge: st.label,
    );
    // Buttons are play-sized (>= 28 sp), dark text on the bright fill.
    final buttonText = st.play.copyWith(color: background);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: background,
        secondary: yellow,
        onSecondary: background,
        surface: surface,
        onSurface: text,
        error: coral,
      ),
      textTheme: textTheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          minimumSize: const Size(minTarget * 2, minTarget),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          textStyle: buttonText,
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
          textStyle: buttonText.copyWith(color: text),
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

/// The five type sizes: Display 56/700, Title 48/700, Heading 36/700,
/// Play text 28/600, Label 24/500.
class AppTextStyles {
  const AppTextStyles._();

  TextStyle get display => AppTheme._s(56, w: FontWeight.w700);
  TextStyle get title => AppTheme._s(48, w: FontWeight.w700);
  TextStyle get heading => AppTheme._s(36, w: FontWeight.w700);
  TextStyle get play => AppTheme._s(28, w: FontWeight.w600);
  TextStyle get label => AppTheme._s(24, w: FontWeight.w500);
}
