import 'package:flutter/material.dart';

/// Palette e tipografia. Tutti i valori estetici vivono qui.
abstract final class Palette {
  static const Color ink = Color(0xFF04060B);
  static const Color night = Color(0xFF080C16);
  static const Color deep = Color(0xFF0D1424);

  static const Color textPrimary = Color(0xF5FFFFFF);
  static const Color textSecondary = Color(0xC7E6ECF7);
  static const Color textTertiary = Color(0x94D5DEEE);

  /// Accento freddo, usato con parsimonia: focus, avanzamento, "ORA".
  static const Color accent = Color(0xFF8AC6FF);
  static const Color accentDeep = Color(0xFF3D7BFF);
  static const Color warm = Color(0xFFFFC27A);
  static const Color danger = Color(0xFFFF7A7A);

  /// Vetro: riempimento e bordo.
  static const Color glassFill = Color(0x1AFFFFFF);
  static const Color glassFillStrong = Color(0x29FFFFFF);
  static const Color glassStroke = Color(0x2EFFFFFF);

  /// Vetro "solido" per il profilo light (nessun blur).
  static const Color frostedSolid = Color(0xE5121A2B);
  static const Color frostedSolidStrong = Color(0xF0182238);

  static const LinearGradient progress = LinearGradient(
    colors: [accentDeep, accent],
  );
}

abstract final class AppText {
  static const _tab = [FontFeature.tabularFigures()];

  static const TextStyle channelNumber = TextStyle(
    fontFamily: 'InterDisplay',
    fontWeight: FontWeight.w300,
    fontSize: 64,
    height: 1,
    letterSpacing: -2,
    color: Palette.textPrimary,
    fontFeatures: _tab,
  );

  static const TextStyle display = TextStyle(
    fontFamily: 'InterDisplay',
    fontWeight: FontWeight.w600,
    fontSize: 30,
    height: 1.1,
    letterSpacing: -0.6,
    color: Palette.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontFamily: 'InterDisplay',
    fontWeight: FontWeight.w600,
    fontSize: 22,
    height: 1.2,
    letterSpacing: -0.3,
    color: Palette.textPrimary,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w600,
    fontSize: 17,
    height: 1.25,
    letterSpacing: -0.2,
    color: Palette.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w400,
    fontSize: 14.5,
    height: 1.45,
    color: Palette.textSecondary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 1.2,
    color: Palette.textSecondary,
    fontFeatures: _tab,
  );

  /// Etichette maiuscole spaziate ("ORA", "DOPO").
  static const TextStyle overline = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w700,
    fontSize: 11,
    height: 1,
    letterSpacing: 1.6,
    color: Palette.textTertiary,
  );

  static const TextStyle clock = TextStyle(
    fontFamily: 'InterDisplay',
    fontWeight: FontWeight.w500,
    fontSize: 30,
    height: 1,
    letterSpacing: -0.5,
    color: Palette.textPrimary,
    fontFeatures: _tab,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: Palette.textSecondary,
    fontFeatures: _tab,
  );
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: Palette.ink,
    colorScheme: const ColorScheme.dark(
      primary: Palette.accent,
      secondary: Palette.accent,
      surface: Palette.night,
      error: Palette.danger,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    focusColor: Colors.transparent,
    hoverColor: Colors.transparent,
  );
  return base.copyWith(
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Palette.accent,
      selectionColor: Color(0x553D7BFF),
      selectionHandleColor: Palette.accent,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
