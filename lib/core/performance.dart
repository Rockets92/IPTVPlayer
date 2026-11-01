import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Livello prestazionale dell'interfaccia.
///
/// `light` è pensato per proiettori/box Android con ~1 GB di RAM:
/// niente blur in tempo reale, animazioni più brevi, finestra EPG ridotta,
/// buffer video più piccolo e cache immagini contenuta.
enum PerformanceTier { full, light }

/// Preferenza utente: `auto` decide in base al dispositivo.
enum PerformanceMode { auto, full, light }

@immutable
class PerformanceProfile {
  const PerformanceProfile(this.tier, {this.reason = ''});

  final PerformanceTier tier;

  /// Perché è stato scelto questo profilo (mostrato nelle impostazioni).
  final String reason;

  bool get isLight => tier == PerformanceTier.light;

  /// Blur reale (BackdropFilter). In light si usa un vetro "opaco" equivalente.
  bool get useBackdropBlur => !isLight;
  double get blurSigma => 20;

  /// Sfondo animato (setup/caricamento).
  bool get animatedBackground => !isLight;

  Duration get fast => Duration(milliseconds: isLight ? 110 : 200);
  Duration get medium => Duration(milliseconds: isLight ? 160 : 320);
  Duration get slow => Duration(milliseconds: isLight ? 220 : 520);

  /// Finestra temporale EPG mantenuta in memoria.
  Duration get epgBehind => Duration(hours: isLight ? 2 : 6);
  Duration get epgAhead => Duration(hours: isLight ? 14 : 48);
  int get epgMaxDescription => isLight ? 220 : 900;

  /// Buffer di demuxing per libmpv.
  String get demuxerMaxBytes => isLight ? '12MiB' : '64MiB';
  int get playerBufferBytes => isLight ? 8 << 20 : 32 << 20;

  /// Cache immagini (loghi) in memoria.
  int get imageCacheBytes => isLight ? 16 << 20 : 96 << 20;
  int get imageCacheCount => isLight ? 160 : 600;

  /// Larghezza di decodifica dei loghi (px fisici).
  int get logoDecodeWidth => isLight ? 128 : 256;

  /// Preferenza qualità quando un canale ha più sorgenti.
  bool get preferLighterStreams => isLight;

  static const _flavor = String.fromEnvironment('FLAVOR', defaultValue: 'full');
  static const _channel = MethodChannel('iptv_player/device');

  /// Risolve il profilo effettivo.
  ///
  /// Ordine: build flavor (`--dart-define=FLAVOR=light`) > scelta utente >
  /// rilevamento automatico della RAM su Android.
  static Future<PerformanceProfile> resolve(PerformanceMode mode) async {
    if (_flavor == 'light') {
      return const PerformanceProfile(
        PerformanceTier.light,
        reason: 'Build light',
      );
    }
    switch (mode) {
      case PerformanceMode.full:
        return const PerformanceProfile(
          PerformanceTier.full,
          reason: 'Scelta manuale',
        );
      case PerformanceMode.light:
        return const PerformanceProfile(
          PerformanceTier.light,
          reason: 'Scelta manuale',
        );
      case PerformanceMode.auto:
        break;
    }
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final info = await _channel.invokeMapMethod<String, Object?>(
          'memoryInfo',
        );
        final total = (info?['totalMem'] as num?)?.toInt() ?? 0;
        final lowRam = info?['isLowRamDevice'] == true;
        final gb = total / (1 << 30);
        if (lowRam || (total > 0 && gb < 1.8)) {
          return PerformanceProfile(
            PerformanceTier.light,
            reason: 'Automatico · ${gb.toStringAsFixed(1)} GB RAM',
          );
        }
        return PerformanceProfile(
          PerformanceTier.full,
          reason: 'Automatico · ${gb.toStringAsFixed(1)} GB RAM',
        );
      } catch (_) {
        // Canale non disponibile: si prosegue con il profilo completo.
      }
    }
    return const PerformanceProfile(PerformanceTier.full, reason: 'Automatico');
  }
}
