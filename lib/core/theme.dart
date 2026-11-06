import 'package:flutter/material.dart';

/// Palette e tipografia. Tutti i valori estetici vivono qui.
abstract final class Palette {
  // Fondi: nero con una punta di indaco, come lo sfondo del logo.
  static const Color ink = Color(0xFF05040E);
  static const Color night = Color(0xFF0B0920);
  static const Color deep = Color(0xFF16103A);

  static const Color textPrimary = Color(0xF5FFFFFF);
  static const Color textSecondary = Color(0xC7E6ECF7);
  static const Color textTertiary = Color(0x94D5DEEE);

  /// Colori del logo B&B: blu elettrico, viola, magenta neon e tramonto.
  static const Color accent = Color(0xFF52B8FF);
  static const Color accentDeep = Color(0xFF2E6BFF);
  static const Color violet = Color(0xFF8A3DFF);
  static const Color magenta = Color(0xFFE53DF5);
  static const Color sunset = Color(0xFFFF8A3D);
  static const Color warm = Color(0xFFFFC94A);
  static const Color danger = Color(0xFFFF7A7A);

  /// Vetro: riempimento e bordo.
  static const Color glassFill = Color(0x1AFFFFFF);
  static const Color glassFillStrong = Color(0x29FFFFFF);
  static const Color glassStroke = Color(0x2EFFFFFF);

  /// Vetro "solido" per il profilo light (nessun blur).
  static const Color frostedSolid = Color(0xE5151034);
  static const Color frostedSolidStrong = Color(0xF01C1642);

  /// Avanzamento: dal blu al magenta, come le scritte del logo.
  static const LinearGradient progress = LinearGradient(
    colors: [accent, violet, magenta],
  );

  /// Riflesso del logo (pulsante play): blu, viola, magenta, arancio.
  static const LinearGradient neon = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, violet, magenta, sunset],
    stops: [0, 0.4, 0.75, 1],
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
      secondary: Palette.magenta,
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
      selectionColor: Color(0x558A3DFF),
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
